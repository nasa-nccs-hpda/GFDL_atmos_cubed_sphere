#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>

#include <cuda_runtime.h>

namespace {

constexpr int NG = 3;
constexpr float R3 = 1.0f / 3.0f;
constexpr float S11 = 11.0f / 14.0f;
constexpr float S14 = 4.0f / 7.0f;
constexpr float S15 = 3.0f / 14.0f;

inline void check_cuda(cudaError_t status, const char *what) {
  if (status != cudaSuccess) {
    std::fprintf(stderr, "CUDA error in %s: %s\n", what, cudaGetErrorString(status));
    std::exit(EXIT_FAILURE);
  }
}

inline void alloc_device(float **ptr, std::size_t count, const char *name) {
  check_cuda(cudaMalloc(reinterpret_cast<void **>(ptr), count * sizeof(float)), name);
}

__host__ __device__ inline int idx2(int i, int j, int ilo, int jlo, int nx) {
  return (i - ilo) + nx * (j - jlo);
}

__host__ __device__ inline float ppm_limiter(float al, float ar, bool update_ar) {
  if (al * ar < 0.0f) {
    const float da1 = al - ar;
    const float da2 = da1 * da1;
    const float a6da = 3.0f * (al + ar) * da1;
    if (a6da < -da2) {
      return update_ar ? -2.0f * al : al;
    }
    if (a6da > da2) {
      return update_ar ? ar : -2.0f * ar;
    }
    return update_ar ? ar : al;
  }
  return 0.0f;
}

__global__ void copy_corners_kernel(float *q, int npx, int npy, int dir,
                                    int isd, int jsd, int nxq) {
  const int t = blockIdx.x * blockDim.x + threadIdx.x;
  if (t >= NG * NG * 4) return;

  const int corner = t / (NG * NG);
  const int r = t % (NG * NG);
  int i = r % NG;
  int j = r / NG;

  if (corner == 0) {
    i = 1 - NG + i;
    j = 1 - NG + j;
    q[idx2(i, j, isd, jsd, nxq)] = q[idx2(1 - j, 1 - i, isd, jsd, nxq)];
  } else if (corner == 1) {
    i = npx + i;
    j = 1 - NG + j;
    const int src_i = (dir == 1) ? 2 * npx - 1 - i : npx - i;
    const int src_j = (dir == 1) ? 1 - j : npy + j - 1;
    q[idx2(i, j, isd, jsd, nxq)] = q[idx2(src_i, src_j, isd, jsd, nxq)];
  } else if (corner == 2) {
    i = npx + i;
    j = npy + j;
    const int src_i = (dir == 1) ? 2 * npx - 1 - i : i;
    q[idx2(i, j, isd, jsd, nxq)] = q[idx2(src_i, 2 * npy - 1 - j, isd, jsd, nxq)];
  } else {
    i = 1 - NG + i;
    j = npy + j;
    const int src_i = (dir == 1) ? 1 - i : j + 1 - npx;
    const int src_j = (dir == 1) ? 2 * npy - 1 - j : npy - i;
    q[idx2(i, j, isd, jsd, nxq)] = q[idx2(src_i, src_j, isd, jsd, nxq)];
  }
}

__global__ void x_dm_kernel(float *dm, const float *q, int is, int ie,
                            int jfirst, int jlast, int isd, int jsd, int nxq) {
  const int n_i = ie - is + 5;
  const int n_j = jlast - jfirst + 1;
  const int t = blockIdx.x * blockDim.x + threadIdx.x;
  if (t >= n_i * n_j) return;

  const int i = is - 2 + (t % n_i);
  const int j = jfirst + (t / n_i);
  const float qm = q[idx2(i - 1, j, isd, jsd, nxq)];
  const float q0 = q[idx2(i, j, isd, jsd, nxq)];
  const float qp = q[idx2(i + 1, j, isd, jsd, nxq)];
  const float xt = 0.25f * (qp - qm);
  const float lim = fminf(fabsf(xt), fminf(fmaxf(fmaxf(qm, q0), qp) - q0,
                                         q0 - fminf(fminf(qm, q0), qp)));
  dm[idx2(i, j, isd, jsd, nxq)] = copysignf(lim, xt);
}

__global__ void x_al_kernel(float *al, const float *q, const float *dm,
                            int is1, int ie1, int jfirst, int jlast,
                            int isd, int jsd, int nxq) {
  const int n_i = ie1 - is1 + 2;
  const int n_j = jlast - jfirst + 1;
  const int t = blockIdx.x * blockDim.x + threadIdx.x;
  if (t >= n_i * n_j) return;

  const int i = is1 + (t % n_i);
  const int j = jfirst + (t / n_i);
  al[idx2(i, j, isd, jsd, nxq)] = 0.5f * (q[idx2(i - 1, j, isd, jsd, nxq)] +
                                          q[idx2(i, j, isd, jsd, nxq)]) +
                                  R3 * (dm[idx2(i - 1, j, isd, jsd, nxq)] -
                                        dm[idx2(i, j, isd, jsd, nxq)]);
}

__global__ void x_blbr_kernel(float *bl, float *br, const float *q, const float *dm,
                              const float *al, int is1, int ie1, int jfirst,
                              int jlast, int isd, int jsd, int nxq) {
  const int n_i = ie1 - is1 + 1;
  const int n_j = jlast - jfirst + 1;
  const int t = blockIdx.x * blockDim.x + threadIdx.x;
  if (t >= n_i * n_j) return;

  const int i = is1 + (t % n_i);
  const int j = jfirst + (t / n_i);
  const float xt = 2.0f * dm[idx2(i, j, isd, jsd, nxq)];
  bl[idx2(i, j, isd, jsd, nxq)] =
      -copysignf(fminf(fabsf(xt), fabsf(al[idx2(i, j, isd, jsd, nxq)] -
                                        q[idx2(i, j, isd, jsd, nxq)])), xt);
  br[idx2(i, j, isd, jsd, nxq)] =
      copysignf(fminf(fabsf(xt), fabsf(al[idx2(i + 1, j, isd, jsd, nxq)] -
                                       q[idx2(i, j, isd, jsd, nxq)])), xt);
}

__global__ void x_edge_west_kernel(float *bl, float *br, const float *q, const float *dm,
                                   const float *al, const float *dxa, int jfirst,
                                   int jlast, int isd, int jsd, int nxq) {
  const int j = jfirst + blockIdx.x * blockDim.x + threadIdx.x;
  if (j > jlast) return;

  bl[idx2(0, j, isd, jsd, nxq)] = S14 * dm[idx2(-1, j, isd, jsd, nxq)] +
                                  S11 * (q[idx2(-1, j, isd, jsd, nxq)] -
                                         q[idx2(0, j, isd, jsd, nxq)]);
  float xt = 0.5f * (((2.0f * dxa[idx2(0, j, isd, jsd, nxq)] +
                       dxa[idx2(-1, j, isd, jsd, nxq)]) *
                          q[idx2(0, j, isd, jsd, nxq)] -
                      dxa[idx2(0, j, isd, jsd, nxq)] * q[idx2(-1, j, isd, jsd, nxq)]) /
                         (dxa[idx2(-1, j, isd, jsd, nxq)] + dxa[idx2(0, j, isd, jsd, nxq)]) +
                     ((2.0f * dxa[idx2(1, j, isd, jsd, nxq)] +
                       dxa[idx2(2, j, isd, jsd, nxq)]) *
                          q[idx2(1, j, isd, jsd, nxq)] -
                      dxa[idx2(1, j, isd, jsd, nxq)] * q[idx2(2, j, isd, jsd, nxq)]) /
                         (dxa[idx2(1, j, isd, jsd, nxq)] + dxa[idx2(2, j, isd, jsd, nxq)]));
  xt = fmaxf(xt, fminf(fminf(q[idx2(-1, j, isd, jsd, nxq)], q[idx2(0, j, isd, jsd, nxq)]),
                       fminf(q[idx2(1, j, isd, jsd, nxq)], q[idx2(2, j, isd, jsd, nxq)])));
  xt = fminf(xt, fmaxf(fmaxf(q[idx2(-1, j, isd, jsd, nxq)], q[idx2(0, j, isd, jsd, nxq)]),
                       fmaxf(q[idx2(1, j, isd, jsd, nxq)], q[idx2(2, j, isd, jsd, nxq)])));

  br[idx2(0, j, isd, jsd, nxq)] = xt - q[idx2(0, j, isd, jsd, nxq)];
  bl[idx2(1, j, isd, jsd, nxq)] = xt - q[idx2(1, j, isd, jsd, nxq)];
  xt = S15 * q[idx2(1, j, isd, jsd, nxq)] + S11 * q[idx2(2, j, isd, jsd, nxq)] -
       S14 * dm[idx2(2, j, isd, jsd, nxq)];
  br[idx2(1, j, isd, jsd, nxq)] = xt - q[idx2(1, j, isd, jsd, nxq)];
  bl[idx2(2, j, isd, jsd, nxq)] = xt - q[idx2(2, j, isd, jsd, nxq)];
  br[idx2(2, j, isd, jsd, nxq)] = al[idx2(3, j, isd, jsd, nxq)] -
                                  q[idx2(2, j, isd, jsd, nxq)];

  for (int i = 0; i <= 2; ++i) {
    const int p = idx2(i, j, isd, jsd, nxq);
    const float old_bl = bl[p];
    const float old_br = br[p];
    bl[p] = ppm_limiter(old_bl, old_br, false);
    br[p] = ppm_limiter(old_bl, old_br, true);
  }
}

__global__ void x_edge_east_kernel(float *bl, float *br, const float *q, const float *dm,
                                   const float *al, const float *dxa, int jfirst,
                                   int jlast, int npx, int isd, int jsd, int nxq) {
  const int j = jfirst + blockIdx.x * blockDim.x + threadIdx.x;
  if (j > jlast) return;

  bl[idx2(npx - 2, j, isd, jsd, nxq)] = al[idx2(npx - 2, j, isd, jsd, nxq)] -
                                        q[idx2(npx - 2, j, isd, jsd, nxq)];
  float xt = S15 * q[idx2(npx - 1, j, isd, jsd, nxq)] +
             S11 * q[idx2(npx - 2, j, isd, jsd, nxq)] +
             S14 * dm[idx2(npx - 2, j, isd, jsd, nxq)];
  br[idx2(npx - 2, j, isd, jsd, nxq)] = xt - q[idx2(npx - 2, j, isd, jsd, nxq)];
  bl[idx2(npx - 1, j, isd, jsd, nxq)] = xt - q[idx2(npx - 1, j, isd, jsd, nxq)];

  xt = 0.5f * (((2.0f * dxa[idx2(npx - 1, j, isd, jsd, nxq)] +
                 dxa[idx2(npx - 2, j, isd, jsd, nxq)]) * q[idx2(npx - 1, j, isd, jsd, nxq)] -
                dxa[idx2(npx - 1, j, isd, jsd, nxq)] * q[idx2(npx - 2, j, isd, jsd, nxq)]) /
                   (dxa[idx2(npx - 2, j, isd, jsd, nxq)] + dxa[idx2(npx - 1, j, isd, jsd, nxq)]) +
               ((2.0f * dxa[idx2(npx, j, isd, jsd, nxq)] +
                 dxa[idx2(npx + 1, j, isd, jsd, nxq)]) * q[idx2(npx, j, isd, jsd, nxq)] -
                dxa[idx2(npx, j, isd, jsd, nxq)] * q[idx2(npx + 1, j, isd, jsd, nxq)]) /
                   (dxa[idx2(npx, j, isd, jsd, nxq)] + dxa[idx2(npx + 1, j, isd, jsd, nxq)]));
  const float mn = fminf(fminf(q[idx2(npx - 2, j, isd, jsd, nxq)], q[idx2(npx - 1, j, isd, jsd, nxq)]),
                        fminf(q[idx2(npx, j, isd, jsd, nxq)], q[idx2(npx + 1, j, isd, jsd, nxq)]));
  const float mx = fmaxf(fmaxf(q[idx2(npx - 2, j, isd, jsd, nxq)], q[idx2(npx - 1, j, isd, jsd, nxq)]),
                        fmaxf(q[idx2(npx, j, isd, jsd, nxq)], q[idx2(npx + 1, j, isd, jsd, nxq)]));
  xt = fminf(fmaxf(xt, mn), mx);

  br[idx2(npx - 1, j, isd, jsd, nxq)] = xt - q[idx2(npx - 1, j, isd, jsd, nxq)];
  bl[idx2(npx, j, isd, jsd, nxq)] = xt - q[idx2(npx, j, isd, jsd, nxq)];
  br[idx2(npx, j, isd, jsd, nxq)] = S11 * (q[idx2(npx + 1, j, isd, jsd, nxq)] -
                                           q[idx2(npx, j, isd, jsd, nxq)]) -
                                    S14 * dm[idx2(npx + 1, j, isd, jsd, nxq)];

  for (int i = npx - 2; i <= npx; ++i) {
    const int p = idx2(i, j, isd, jsd, nxq);
    const float old_bl = bl[p];
    const float old_br = br[p];
    bl[p] = ppm_limiter(old_bl, old_br, false);
    br[p] = ppm_limiter(old_bl, old_br, true);
  }
}

__global__ void x_flux_kernel(float *flux, const float *q, const float *c,
                              const float *bl, const float *br, int is, int ie,
                              int jfirst, int jlast, int isd, int jsd, int nxq) {
  const int n_i = ie - is + 2;
  const int n_j = jlast - jfirst + 1;
  const int t = blockIdx.x * blockDim.x + threadIdx.x;
  if (t >= n_i * n_j) return;

  const int i = is + (t % n_i);
  const int j = jfirst + (t / n_i);
  const float cc = c[idx2(i, j, isd, jsd, nxq)];
  if (cc > 0.0f) {
    flux[idx2(i, j, isd, jsd, nxq)] =
        q[idx2(i - 1, j, isd, jsd, nxq)] +
        (1.0f - cc) * (br[idx2(i - 1, j, isd, jsd, nxq)] -
                       cc * (bl[idx2(i - 1, j, isd, jsd, nxq)] +
                             br[idx2(i - 1, j, isd, jsd, nxq)]));
  } else {
    flux[idx2(i, j, isd, jsd, nxq)] =
        q[idx2(i, j, isd, jsd, nxq)] +
        (1.0f + cc) * (bl[idx2(i, j, isd, jsd, nxq)] +
                       cc * (bl[idx2(i, j, isd, jsd, nxq)] +
                             br[idx2(i, j, isd, jsd, nxq)]));
  }
}

__global__ void y_dm_kernel(float *dm, const float *q, int ifirst, int ilast,
                            int js, int je, int isd, int jsd, int nxq) {
  const int n_i = ilast - ifirst + 1;
  const int n_j = je - js + 5;
  const int t = blockIdx.x * blockDim.x + threadIdx.x;
  if (t >= n_i * n_j) return;

  const int i = ifirst + (t % n_i);
  const int j = js - 2 + (t / n_i);
  const float qm = q[idx2(i, j - 1, isd, jsd, nxq)];
  const float q0 = q[idx2(i, j, isd, jsd, nxq)];
  const float qp = q[idx2(i, j + 1, isd, jsd, nxq)];
  const float xt = 0.25f * (qp - qm);
  const float lim = fminf(fabsf(xt), fminf(fmaxf(fmaxf(qm, q0), qp) - q0,
                                         q0 - fminf(fminf(qm, q0), qp)));
  dm[idx2(i, j, isd, jsd, nxq)] = copysignf(lim, xt);
}

__global__ void y_al_kernel(float *al, const float *q, const float *dm,
                            int ifirst, int ilast, int js1, int je1,
                            int isd, int jsd, int nxq) {
  const int n_i = ilast - ifirst + 1;
  const int n_j = je1 - js1 + 2;
  const int t = blockIdx.x * blockDim.x + threadIdx.x;
  if (t >= n_i * n_j) return;

  const int i = ifirst + (t % n_i);
  const int j = js1 + (t / n_i);
  al[idx2(i, j, isd, jsd, nxq)] = 0.5f * (q[idx2(i, j - 1, isd, jsd, nxq)] +
                                          q[idx2(i, j, isd, jsd, nxq)]) +
                                  R3 * (dm[idx2(i, j - 1, isd, jsd, nxq)] -
                                        dm[idx2(i, j, isd, jsd, nxq)]);
}

__global__ void y_blbr_kernel(float *bl, float *br, const float *q, const float *dm,
                              const float *al, int ifirst, int ilast, int js1,
                              int je1, int isd, int jsd, int nxq) {
  const int n_i = ilast - ifirst + 1;
  const int n_j = je1 - js1 + 1;
  const int t = blockIdx.x * blockDim.x + threadIdx.x;
  if (t >= n_i * n_j) return;

  const int i = ifirst + (t % n_i);
  const int j = js1 + (t / n_i);
  const float xt = 2.0f * dm[idx2(i, j, isd, jsd, nxq)];
  bl[idx2(i, j, isd, jsd, nxq)] =
      -copysignf(fminf(fabsf(xt), fabsf(al[idx2(i, j, isd, jsd, nxq)] -
                                        q[idx2(i, j, isd, jsd, nxq)])), xt);
  br[idx2(i, j, isd, jsd, nxq)] =
      copysignf(fminf(fabsf(xt), fabsf(al[idx2(i, j + 1, isd, jsd, nxq)] -
                                       q[idx2(i, j, isd, jsd, nxq)])), xt);
}

__global__ void y_edge_south_kernel(float *bl, float *br, const float *q,
                                    const float *dm, const float *al, const float *dya,
                                    int ifirst, int ilast, int isd, int jsd, int nxq) {
  const int i = ifirst + blockIdx.x * blockDim.x + threadIdx.x;
  if (i > ilast) return;

  bl[idx2(i, 0, isd, jsd, nxq)] = S14 * dm[idx2(i, -1, isd, jsd, nxq)] +
                                  S11 * (q[idx2(i, -1, isd, jsd, nxq)] -
                                         q[idx2(i, 0, isd, jsd, nxq)]);
  float xt = 0.5f * (((2.0f * dya[idx2(i, 0, isd, jsd, nxq)] +
                       dya[idx2(i, -1, isd, jsd, nxq)]) * q[idx2(i, 0, isd, jsd, nxq)] -
                      dya[idx2(i, 0, isd, jsd, nxq)] * q[idx2(i, -1, isd, jsd, nxq)]) /
                         (dya[idx2(i, -1, isd, jsd, nxq)] + dya[idx2(i, 0, isd, jsd, nxq)]) +
                     ((2.0f * dya[idx2(i, 1, isd, jsd, nxq)] +
                       dya[idx2(i, 2, isd, jsd, nxq)]) * q[idx2(i, 1, isd, jsd, nxq)] -
                      dya[idx2(i, 1, isd, jsd, nxq)] * q[idx2(i, 2, isd, jsd, nxq)]) /
                         (dya[idx2(i, 1, isd, jsd, nxq)] + dya[idx2(i, 2, isd, jsd, nxq)]));
  const float mn = fminf(fminf(q[idx2(i, -1, isd, jsd, nxq)], q[idx2(i, 0, isd, jsd, nxq)]),
                        fminf(q[idx2(i, 1, isd, jsd, nxq)], q[idx2(i, 2, isd, jsd, nxq)]));
  const float mx = fmaxf(fmaxf(q[idx2(i, -1, isd, jsd, nxq)], q[idx2(i, 0, isd, jsd, nxq)]),
                        fmaxf(q[idx2(i, 1, isd, jsd, nxq)], q[idx2(i, 2, isd, jsd, nxq)]));
  xt = fminf(fmaxf(xt, mn), mx);

  br[idx2(i, 0, isd, jsd, nxq)] = xt - q[idx2(i, 0, isd, jsd, nxq)];
  bl[idx2(i, 1, isd, jsd, nxq)] = xt - q[idx2(i, 1, isd, jsd, nxq)];
  xt = S15 * q[idx2(i, 1, isd, jsd, nxq)] + S11 * q[idx2(i, 2, isd, jsd, nxq)] -
       S14 * dm[idx2(i, 2, isd, jsd, nxq)];
  br[idx2(i, 1, isd, jsd, nxq)] = xt - q[idx2(i, 1, isd, jsd, nxq)];
  bl[idx2(i, 2, isd, jsd, nxq)] = xt - q[idx2(i, 2, isd, jsd, nxq)];
  br[idx2(i, 2, isd, jsd, nxq)] = al[idx2(i, 3, isd, jsd, nxq)] -
                                  q[idx2(i, 2, isd, jsd, nxq)];

  for (int j = 0; j <= 2; ++j) {
    const int p = idx2(i, j, isd, jsd, nxq);
    const float old_bl = bl[p];
    const float old_br = br[p];
    bl[p] = ppm_limiter(old_bl, old_br, false);
    br[p] = ppm_limiter(old_bl, old_br, true);
  }
}

__global__ void y_edge_north_kernel(float *bl, float *br, const float *q,
                                    const float *dm, const float *al, const float *dya,
                                    int ifirst, int ilast, int npy, int isd, int jsd,
                                    int nxq) {
  const int i = ifirst + blockIdx.x * blockDim.x + threadIdx.x;
  if (i > ilast) return;

  bl[idx2(i, npy - 2, isd, jsd, nxq)] = al[idx2(i, npy - 2, isd, jsd, nxq)] -
                                        q[idx2(i, npy - 2, isd, jsd, nxq)];
  float xt = S15 * q[idx2(i, npy - 1, isd, jsd, nxq)] +
             S11 * q[idx2(i, npy - 2, isd, jsd, nxq)] +
             S14 * dm[idx2(i, npy - 2, isd, jsd, nxq)];
  br[idx2(i, npy - 2, isd, jsd, nxq)] = xt - q[idx2(i, npy - 2, isd, jsd, nxq)];
  bl[idx2(i, npy - 1, isd, jsd, nxq)] = xt - q[idx2(i, npy - 1, isd, jsd, nxq)];

  xt = 0.5f * (((2.0f * dya[idx2(i, npy - 1, isd, jsd, nxq)] +
                 dya[idx2(i, npy - 2, isd, jsd, nxq)]) * q[idx2(i, npy - 1, isd, jsd, nxq)] -
                dya[idx2(i, npy - 1, isd, jsd, nxq)] * q[idx2(i, npy - 2, isd, jsd, nxq)]) /
                   (dya[idx2(i, npy - 2, isd, jsd, nxq)] + dya[idx2(i, npy - 1, isd, jsd, nxq)]) +
               ((2.0f * dya[idx2(i, npy, isd, jsd, nxq)] +
                 dya[idx2(i, npy + 1, isd, jsd, nxq)]) * q[idx2(i, npy, isd, jsd, nxq)] -
                dya[idx2(i, npy, isd, jsd, nxq)] * q[idx2(i, npy + 1, isd, jsd, nxq)]) /
                   (dya[idx2(i, npy, isd, jsd, nxq)] + dya[idx2(i, npy + 1, isd, jsd, nxq)]));
  const float mn = fminf(fminf(q[idx2(i, npy - 2, isd, jsd, nxq)], q[idx2(i, npy - 1, isd, jsd, nxq)]),
                        fminf(q[idx2(i, npy, isd, jsd, nxq)], q[idx2(i, npy + 1, isd, jsd, nxq)]));
  const float mx = fmaxf(fmaxf(q[idx2(i, npy - 2, isd, jsd, nxq)], q[idx2(i, npy - 1, isd, jsd, nxq)]),
                        fmaxf(q[idx2(i, npy, isd, jsd, nxq)], q[idx2(i, npy + 1, isd, jsd, nxq)]));
  xt = fminf(fmaxf(xt, mn), mx);

  br[idx2(i, npy - 1, isd, jsd, nxq)] = xt - q[idx2(i, npy - 1, isd, jsd, nxq)];
  bl[idx2(i, npy, isd, jsd, nxq)] = xt - q[idx2(i, npy, isd, jsd, nxq)];
  br[idx2(i, npy, isd, jsd, nxq)] = S11 * (q[idx2(i, npy + 1, isd, jsd, nxq)] -
                                           q[idx2(i, npy, isd, jsd, nxq)]) -
                                    S14 * dm[idx2(i, npy + 1, isd, jsd, nxq)];

  for (int j = npy - 2; j <= npy; ++j) {
    const int p = idx2(i, j, isd, jsd, nxq);
    const float old_bl = bl[p];
    const float old_br = br[p];
    bl[p] = ppm_limiter(old_bl, old_br, false);
    br[p] = ppm_limiter(old_bl, old_br, true);
  }
}

__global__ void y_flux_kernel(float *flux, const float *q, const float *c,
                              const float *bl, const float *br, int ifirst,
                              int ilast, int js, int je, int isd, int jsd, int nxq) {
  const int n_i = ilast - ifirst + 1;
  const int n_j = je - js + 2;
  const int t = blockIdx.x * blockDim.x + threadIdx.x;
  if (t >= n_i * n_j) return;

  const int i = ifirst + (t % n_i);
  const int j = js + (t / n_i);
  const float cc = c[idx2(i, j, isd, jsd, nxq)];
  if (cc > 0.0f) {
    flux[idx2(i, j, isd, jsd, nxq)] =
        q[idx2(i, j - 1, isd, jsd, nxq)] +
        (1.0f - cc) * (br[idx2(i, j - 1, isd, jsd, nxq)] -
                       cc * (bl[idx2(i, j - 1, isd, jsd, nxq)] +
                             br[idx2(i, j - 1, isd, jsd, nxq)]));
  } else {
    flux[idx2(i, j, isd, jsd, nxq)] =
        q[idx2(i, j, isd, jsd, nxq)] +
        (1.0f + cc) * (bl[idx2(i, j, isd, jsd, nxq)] +
                       cc * (bl[idx2(i, j, isd, jsd, nxq)] +
                             br[idx2(i, j, isd, jsd, nxq)]));
  }
}

__global__ void qi_kernel(float *q_i, const float *q, const float *area,
                          const float *yfx, const float *fy2, const float *ra_y,
                          int isd, int ied, int js, int je, int jsd, int nxq) {
  const int n_i = ied - isd + 1;
  const int n_j = je - js + 1;
  const int t = blockIdx.x * blockDim.x + threadIdx.x;
  if (t >= n_i * n_j) return;
  const int i = isd + (t % n_i);
  const int j = js + (t / n_i);
  q_i[idx2(i, j, isd, jsd, nxq)] =
      (q[idx2(i, j, isd, jsd, nxq)] * area[idx2(i, j, isd, jsd, nxq)] +
       yfx[idx2(i, j, isd, jsd, nxq)] * fy2[idx2(i, j, isd, jsd, nxq)] -
       yfx[idx2(i, j + 1, isd, jsd, nxq)] * fy2[idx2(i, j + 1, isd, jsd, nxq)]) /
      ra_y[idx2(i, j, isd, jsd, nxq)];
}

__global__ void qj_kernel(float *q_j, const float *q, const float *area,
                          const float *xfx, const float *fx2, const float *ra_x,
                          int is, int ie, int jsd_loop, int jed, int isd, int jsd,
                          int nxq) {
  const int n_i = ie - is + 1;
  const int n_j = jed - jsd_loop + 1;
  const int t = blockIdx.x * blockDim.x + threadIdx.x;
  if (t >= n_i * n_j) return;
  const int i = is + (t % n_i);
  const int j = jsd_loop + (t / n_i);
  q_j[idx2(i, j, isd, jsd, nxq)] =
      (q[idx2(i, j, isd, jsd, nxq)] * area[idx2(i, j, isd, jsd, nxq)] +
       xfx[idx2(i, j, isd, jsd, nxq)] * fx2[idx2(i, j, isd, jsd, nxq)] -
       xfx[idx2(i + 1, j, isd, jsd, nxq)] * fx2[idx2(i + 1, j, isd, jsd, nxq)]) /
      ra_x[idx2(i, j, isd, jsd, nxq)];
}

__global__ void final_fx_kernel(float *fx_out, const float *fx, const float *fx2,
                                const float *xfx, int is, int ie, int js, int je,
                                int isd, int jsd, int nxq, int nxfx) {
  const int n_i = ie - is + 2;
  const int n_j = je - js + 1;
  const int t = blockIdx.x * blockDim.x + threadIdx.x;
  if (t >= n_i * n_j) return;
  const int i = is + (t % n_i);
  const int j = js + (t / n_i);
  fx_out[(i - is) + nxfx * (j - js)] =
      0.5f * (fx[idx2(i, j, isd, jsd, nxq)] + fx2[idx2(i, j, isd, jsd, nxq)]) *
      xfx[idx2(i, j, isd, jsd, nxq)];
}

__global__ void final_fy_kernel(float *fy_out, const float *fy, const float *fy2,
                                const float *yfx, int is, int ie, int js, int je,
                                int isd, int jsd, int nxq, int nxfy) {
  const int n_i = ie - is + 1;
  const int n_j = je - js + 2;
  const int t = blockIdx.x * blockDim.x + threadIdx.x;
  if (t >= n_i * n_j) return;
  const int i = is + (t % n_i);
  const int j = js + (t / n_i);
  fy_out[(i - is) + nxfy * (j - js)] =
      0.5f * (fy[idx2(i, j, isd, jsd, nxq)] + fy2[idx2(i, j, isd, jsd, nxq)]) *
      yfx[idx2(i, j, isd, jsd, nxq)];
}

void xppm8(float *flux, const float *q, const float *c, const float *dxa,
           float *dm, float *al, float *bl, float *br, int is, int ie,
           int isd, int ied, int jfirst, int jlast, int jsd, int jed, int npx,
           bool nested, int grid_type, int nxq, cudaStream_t stream) {
  const int threads = 256;
  const int is1 = (!nested && grid_type < 3) ? std::max(3, is - 1) : is - 1;
  const int ie1 = (!nested && grid_type < 3) ? std::min(npx - 3, ie + 1) : ie + 1;

  int count = (ie - is + 5) * (jlast - jfirst + 1);
  x_dm_kernel<<<(count + threads - 1) / threads, threads, 0, stream>>>(dm, q, is, ie, jfirst, jlast, isd, jsd, nxq);
  count = (ie1 - is1 + 2) * (jlast - jfirst + 1);
  x_al_kernel<<<(count + threads - 1) / threads, threads, 0, stream>>>(al, q, dm, is1, ie1, jfirst, jlast, isd, jsd, nxq);
  count = (ie1 - is1 + 1) * (jlast - jfirst + 1);
  x_blbr_kernel<<<(count + threads - 1) / threads, threads, 0, stream>>>(bl, br, q, dm, al, is1, ie1, jfirst, jlast,
                                                                         isd, jsd, nxq);
  if (!nested && grid_type < 3) {
    if (is == 1) {
      const int n_j = jlast - jfirst + 1;
      x_edge_west_kernel<<<(n_j + threads - 1) / threads, threads, 0, stream>>>(bl, br, q, dm, al, dxa, jfirst,
                                                                                jlast, isd, jsd, nxq);
    }
    if ((ie + 1) == npx) {
      const int n_j = jlast - jfirst + 1;
      x_edge_east_kernel<<<(n_j + threads - 1) / threads, threads, 0, stream>>>(bl, br, q, dm, al, dxa, jfirst,
                                                                                jlast, npx, isd, jsd, nxq);
    }
  }
  count = (ie - is + 2) * (jlast - jfirst + 1);
  x_flux_kernel<<<(count + threads - 1) / threads, threads, 0, stream>>>(flux, q, c, bl, br, is, ie, jfirst, jlast,
                                                                         isd, jsd, nxq);
}

void yppm8(float *flux, const float *q, const float *c, const float *dya,
           float *dm, float *al, float *bl, float *br, int ifirst, int ilast,
           int isd, int ied, int js, int je, int jsd, int jed, int npy,
           bool nested, int grid_type, int nxq, cudaStream_t stream) {
  const int threads = 256;
  const int js1 = (!nested && grid_type < 3) ? std::max(3, js - 1) : js - 1;
  const int je1 = (!nested && grid_type < 3) ? std::min(npy - 3, je + 1) : je + 1;

  int count = (ilast - ifirst + 1) * (je - js + 5);
  y_dm_kernel<<<(count + threads - 1) / threads, threads, 0, stream>>>(dm, q, ifirst, ilast, js, je, isd, jsd, nxq);
  count = (ilast - ifirst + 1) * (je1 - js1 + 2);
  y_al_kernel<<<(count + threads - 1) / threads, threads, 0, stream>>>(al, q, dm, ifirst, ilast, js1, je1, isd, jsd, nxq);
  count = (ilast - ifirst + 1) * (je1 - js1 + 1);
  y_blbr_kernel<<<(count + threads - 1) / threads, threads, 0, stream>>>(bl, br, q, dm, al, ifirst, ilast, js1, je1,
                                                                         isd, jsd, nxq);
  if (!nested && grid_type < 3) {
    const int n_i = ilast - ifirst + 1;
    if (js == 1) {
      y_edge_south_kernel<<<(n_i + threads - 1) / threads, threads, 0, stream>>>(bl, br, q, dm, al, dya, ifirst, ilast,
                                                                                 isd, jsd, nxq);
    }
    if ((je + 1) == npy) {
      y_edge_north_kernel<<<(n_i + threads - 1) / threads, threads, 0, stream>>>(bl, br, q, dm, al, dya, ifirst, ilast,
                                                                                 npy, isd, jsd, nxq);
    }
  }
  count = (ilast - ifirst + 1) * (je - js + 2);
  y_flux_kernel<<<(count + threads - 1) / threads, threads, 0, stream>>>(flux, q, c, bl, br, ifirst, ilast, js, je,
                                                                         isd, jsd, nxq);
}

void launch_tp_iteration(float *dq, const float *dcrx, const float *dcry,
                         const float *dxfx, const float *dyfx, const float *ddxa,
                         const float *ddya, const float *darea, const float *dra_x,
                         const float *dra_y, float *q_i, float *q_j, float *fx_work,
                         float *fy_work, float *fx2, float *fy2, float *dm, float *al,
                         float *bl, float *br, int npx, int npy, int is, int ie,
                         int js, int je, int isd, int ied, int jsd, int jed, int nxq,
                         int threads, bool nested, int grid_type, cudaStream_t stream) {
  copy_corners_kernel<<<1, 128, 0, stream>>>(dq, npx, npy, 2, isd, jsd, nxq);
  yppm8(fy2, dq, dcry, ddya, dm, al, bl, br, isd, ied, isd, ied, js, je, jsd, jed,
        npy, nested, grid_type, nxq, stream);

  int loop_count = (ied - isd + 1) * (je - js + 1);
  qi_kernel<<<(loop_count + threads - 1) / threads, threads, 0, stream>>>(
      q_i, dq, darea, dyfx, fy2, dra_y, isd, ied, js, je, jsd, nxq);

  xppm8(fx_work, q_i, dcrx, ddxa, dm, al, bl, br, is, ie, isd, ied, js, je, jsd, jed,
        npx, nested, grid_type, nxq, stream);

  copy_corners_kernel<<<1, 128, 0, stream>>>(dq, npx, npy, 1, isd, jsd, nxq);
  xppm8(fx2, dq, dcrx, ddxa, dm, al, bl, br, is, ie, isd, ied, jsd, jed, jsd, jed,
        npx, nested, grid_type, nxq, stream);

  loop_count = (ie - is + 1) * (jed - jsd + 1);
  qj_kernel<<<(loop_count + threads - 1) / threads, threads, 0, stream>>>(
      q_j, dq, darea, dxfx, fx2, dra_x, is, ie, jsd, jed, isd, jsd, nxq);

  yppm8(fy_work, q_j, dcry, ddya, dm, al, bl, br, is, ie, isd, ied, js, je, jsd, jed,
        npy, nested, grid_type, nxq, stream);
}

}  // namespace

extern "C" void fv_tp_2d_cuda_cpp(float *q, const float *crx, const float *cry,
                                  const float *xfx, const float *yfx,
                                  const float *dxa, const float *dya,
                                  const float *area, const float *ra_x,
                                  const float *ra_y, float *fx, float *fy,
                                  int npx, int npy, int is, int ie, int js, int je,
                                  int isd, int ied, int jsd, int jed,
                                  int n_iterations) {
  const int nxq = ied - isd + 1;
  const int nyq = jed - jsd + 1;
  const std::size_t n_full = static_cast<std::size_t>(nxq) * nyq;
  const int nxfx = ie - is + 2;
  const int nyfx = je - js + 1;
  const int nxfy = ie - is + 1;
  const int nyfy = je - js + 2;

  float *dq = nullptr, *dcrx = nullptr, *dcry = nullptr, *dxfx = nullptr, *dyfx = nullptr;
  float *ddxa = nullptr, *ddya = nullptr, *darea = nullptr, *dra_x = nullptr, *dra_y = nullptr;
  float *dfx_out = nullptr, *dfy_out = nullptr;
  float *q_i = nullptr, *q_j = nullptr, *fx_work = nullptr, *fy_work = nullptr;
  float *fx2 = nullptr, *fy2 = nullptr, *dm = nullptr, *al = nullptr, *bl = nullptr, *br = nullptr;

  alloc_device(&dq, n_full, "cudaMalloc dq");
  alloc_device(&dcrx, n_full, "cudaMalloc dcrx");
  alloc_device(&dcry, n_full, "cudaMalloc dcry");
  alloc_device(&dxfx, n_full, "cudaMalloc dxfx");
  alloc_device(&dyfx, n_full, "cudaMalloc dyfx");
  alloc_device(&ddxa, n_full, "cudaMalloc ddxa");
  alloc_device(&ddya, n_full, "cudaMalloc ddya");
  alloc_device(&darea, n_full, "cudaMalloc darea");
  alloc_device(&dra_x, n_full, "cudaMalloc dra_x");
  alloc_device(&dra_y, n_full, "cudaMalloc dra_y");
  alloc_device(&q_i, n_full, "cudaMalloc q_i");
  alloc_device(&q_j, n_full, "cudaMalloc q_j");
  alloc_device(&fx_work, n_full, "cudaMalloc fx_work");
  alloc_device(&fy_work, n_full, "cudaMalloc fy_work");
  alloc_device(&fx2, n_full, "cudaMalloc fx2");
  alloc_device(&fy2, n_full, "cudaMalloc fy2");
  alloc_device(&dm, n_full, "cudaMalloc dm");
  alloc_device(&al, n_full, "cudaMalloc al");
  alloc_device(&bl, n_full, "cudaMalloc bl");
  alloc_device(&br, n_full, "cudaMalloc br");
  alloc_device(&dfx_out, static_cast<std::size_t>(nxfx) * nyfx, "cudaMalloc dfx_out");
  alloc_device(&dfy_out, static_cast<std::size_t>(nxfy) * nyfy, "cudaMalloc dfy_out");

  check_cuda(cudaMemcpy(dq, q, n_full * sizeof(float), cudaMemcpyHostToDevice), "copy q");
  check_cuda(cudaMemcpy(dcrx, crx, n_full * sizeof(float), cudaMemcpyHostToDevice), "copy crx");
  check_cuda(cudaMemcpy(dcry, cry, n_full * sizeof(float), cudaMemcpyHostToDevice), "copy cry");
  check_cuda(cudaMemcpy(dxfx, xfx, n_full * sizeof(float), cudaMemcpyHostToDevice), "copy xfx");
  check_cuda(cudaMemcpy(dyfx, yfx, n_full * sizeof(float), cudaMemcpyHostToDevice), "copy yfx");
  check_cuda(cudaMemcpy(ddxa, dxa, n_full * sizeof(float), cudaMemcpyHostToDevice), "copy dxa");
  check_cuda(cudaMemcpy(ddya, dya, n_full * sizeof(float), cudaMemcpyHostToDevice), "copy dya");
  check_cuda(cudaMemcpy(darea, area, n_full * sizeof(float), cudaMemcpyHostToDevice), "copy area");
  check_cuda(cudaMemcpy(dra_x, ra_x, n_full * sizeof(float), cudaMemcpyHostToDevice), "copy ra_x");
  check_cuda(cudaMemcpy(dra_y, ra_y, n_full * sizeof(float), cudaMemcpyHostToDevice), "copy ra_y");

  const int threads = 256;
  const bool nested = false;
  const int grid_type = 0;
  cudaStream_t stream = nullptr;
  cudaGraph_t graph = nullptr;
  cudaGraphExec_t graph_exec = nullptr;
  check_cuda(cudaStreamCreate(&stream), "cudaStreamCreate");

  if (n_iterations > 0) {
    check_cuda(cudaStreamBeginCapture(stream, cudaStreamCaptureModeGlobal), "cudaStreamBeginCapture");
    launch_tp_iteration(dq, dcrx, dcry, dxfx, dyfx, ddxa, ddya, darea, dra_x, dra_y,
                        q_i, q_j, fx_work, fy_work, fx2, fy2, dm, al, bl, br,
                        npx, npy, is, ie, js, je, isd, ied, jsd, jed, nxq,
                        threads, nested, grid_type, stream);
    check_cuda(cudaStreamEndCapture(stream, &graph), "cudaStreamEndCapture");
    check_cuda(cudaGraphInstantiate(&graph_exec, graph, nullptr, nullptr, 0), "cudaGraphInstantiate");

    for (int iter = 0; iter < n_iterations; ++iter) {
      check_cuda(cudaGraphLaunch(graph_exec, stream), "cudaGraphLaunch");
    }
  }

  int count = nxfx * nyfx;
  final_fx_kernel<<<(count + threads - 1) / threads, threads, 0, stream>>>(
      dfx_out, fx_work, fx2, dxfx, is, ie, js, je, isd, jsd, nxq, nxfx);
  count = nxfy * nyfy;
  final_fy_kernel<<<(count + threads - 1) / threads, threads, 0, stream>>>(
      dfy_out, fy_work, fy2, dyfx, is, ie, js, je, isd, jsd, nxq, nxfy);
  check_cuda(cudaGetLastError(), "launch fv_tp_2d_cuda_cpp");
  check_cuda(cudaStreamSynchronize(stream), "sync fv_tp_2d_cuda_cpp");

  check_cuda(cudaMemcpy(fx, dfx_out, static_cast<std::size_t>(nxfx) * nyfx * sizeof(float),
                        cudaMemcpyDeviceToHost),
             "copy fx");
  check_cuda(cudaMemcpy(fy, dfy_out, static_cast<std::size_t>(nxfy) * nyfy * sizeof(float),
                        cudaMemcpyDeviceToHost),
             "copy fy");

  cudaFree(dq);
  cudaFree(dcrx);
  cudaFree(dcry);
  cudaFree(dxfx);
  cudaFree(dyfx);
  cudaFree(ddxa);
  cudaFree(ddya);
  cudaFree(darea);
  cudaFree(dra_x);
  cudaFree(dra_y);
  cudaFree(dfx_out);
  cudaFree(dfy_out);
  cudaFree(q_i);
  cudaFree(q_j);
  cudaFree(fx_work);
  cudaFree(fy_work);
  cudaFree(fx2);
  cudaFree(fy2);
  cudaFree(dm);
  cudaFree(al);
  cudaFree(bl);
  cudaFree(br);
  if (graph_exec) cudaGraphExecDestroy(graph_exec);
  if (graph) cudaGraphDestroy(graph);
  cudaStreamDestroy(stream);
}

