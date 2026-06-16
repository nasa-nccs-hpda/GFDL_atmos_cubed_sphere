// driver_xppm_gpu.cu — standalone command-line GPU benchmark for xppm.
//
// The X-direction twin of driver_yppm_gpu.cu. Mirrors the CPU tp-core-driver:
//   Usage: tp-core-driver-gpu-x <resolution> <iterations> [levels]
// Builds a synthetic tile, copies it to the device ONCE, then runs the xppm
// GPU kernel <iterations> times in a timed loop (allocate-once / copy-once /
// loop) via the device-pointer API xppm_gpu_launch_device.
//
// Parallelism: one GPU thread per j-row. ncol = nrows * levels, where
//   nrows  = (jlast - jfirst + 1) rows of one tile
//   levels = a batch dimension standing in for vertical levels.
//
// Output mirrors the CPU driver: elapsed time and a flux checksum.
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <vector>

#include <cuda_runtime.h>

#include "xppm.hpp"
#include "xppm_gpu.cuh"

#define CUDA_CHECK(call)                                                       \
    do {                                                                       \
        cudaError_t _e = (call);                                               \
        if (_e != cudaSuccess) {                                               \
            fprintf(stderr, "CUDA error %s:%d: %s\n",                          \
                    __FILE__, __LINE__, cudaGetErrorString(_e));               \
            std::exit(1);                                                      \
        }                                                                      \
    } while (0)

using Real = float;

int main(int argc, char** argv)
{
    if (argc < 3 || argc > 4) {
        fprintf(stderr, "Usage: %s <resolution> <iterations> [levels]\n", argv[0]);
        return 2;
    }
    const int n      = std::atoi(argv[1]);
    const int n_iter = std::atoi(argv[2]);
    const int levels = (argc == 4) ? std::atoi(argv[3]) : 1;
    if (n < 1 || n_iter < 1 || levels < 1) {
        fprintf(stderr, "resolution, iterations, and levels must be >= 1\n");
        return 2;
    }

    // ---- Domain (one cubed-sphere tile, 3-cell halo), matching driver_cpu ----
    const int ng     = 3;
    const int iord   = 8;
    const Real lim_fac = Real(1);
    const bool nested  = false;     // exercise the cubed-sphere boundary path
    const int grid_type = 0;

    const int is     = 1,        ie    = n;
    const int isd    = is-ng,    ied   = ie+ng;
    const int jfirst = 1,        jlast = n;        // rows swept by xppm
    const int npx    = n+1,      npy   = n+1;

    const int nrows   = jlast - jfirst + 1;        // j-rows
    const long ncol   = static_cast<long>(nrows) * levels;
    const int nj_q    = ied - isd + 1;             // q/dxa per-row length
    const int nj_flux = ie  - is  + 2;             // c/flux per-row length

    printf("xppm GPU driver: resolution=%d iterations=%d levels=%d\n", n, n_iter, levels);
    printf("  nrows=%d nj_q=%d nj_flux=%d ncol=%ld iord=%d nested=%d\n",
           nrows, nj_q, nj_flux, ncol, iord, (int)nested);

    // ---- Build a synthetic, smooth tile on the host (row-contiguous) ----
    std::vector<Real> h_q   (static_cast<size_t>(ncol) * nj_q);
    std::vector<Real> h_dxa (static_cast<size_t>(ncol) * nj_q,    Real(1));
    std::vector<Real> h_c   (static_cast<size_t>(ncol) * nj_flux, Real(0.5));
    std::vector<Real> h_flux(static_cast<size_t>(ncol) * nj_flux, Real(0));

    const double two_pi = 6.283185307179586;
    for (long r = 0; r < ncol; ++r) {
        Real* qr = h_q.data() + r * nj_q;
        for (int i = 0; i < nj_q; ++i)
            qr[i] = Real(1.0 + 0.5 * std::cos(two_pi * double(i) / double(nj_q)));
    }

    // ---- Allocate device buffers ONCE ----
    const size_t n_q    = static_cast<size_t>(ncol) * nj_q;
    const size_t n_flux = static_cast<size_t>(ncol) * nj_flux;
    const size_t n_sr   = fv3::xppm_gpu_scratch_real_count(static_cast<int>(ncol), is, ie);
    const size_t n_sb   = fv3::xppm_gpu_scratch_bool_count(static_cast<int>(ncol), is, ie);

    Real *d_q, *d_c, *d_dxa, *d_flux, *d_sr;
    bool *d_sb;
    CUDA_CHECK(cudaMalloc(&d_q,    n_q    * sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&d_c,    n_flux * sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&d_dxa,  n_q    * sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&d_flux, n_flux * sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&d_sr,   n_sr   * sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&d_sb,   n_sb   * sizeof(bool)));

    // ---- Copy inputs ONCE ----
    CUDA_CHECK(cudaMemcpy(d_q,   h_q.data(),   n_q    * sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_c,   h_c.data(),   n_flux * sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_dxa, h_dxa.data(), n_q    * sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemset(d_flux, 0, n_flux * sizeof(Real)));

    // ---- Warm-up launch (excluded from timing) ----
    CUDA_CHECK(fv3::xppm_gpu_launch_device<Real>(
        d_flux, d_q, d_c, d_dxa, d_sr, d_sb,
        static_cast<int>(ncol), iord, is, ie, isd, ied, npx, npy,
        nested, grid_type, lim_fac));
    CUDA_CHECK(cudaDeviceSynchronize());

    // ---- Timed loop ----
    cudaEvent_t start, stop;
    CUDA_CHECK(cudaEventCreate(&start));
    CUDA_CHECK(cudaEventCreate(&stop));
    CUDA_CHECK(cudaEventRecord(start));
    for (int it = 0; it < n_iter; ++it) {
        CUDA_CHECK(fv3::xppm_gpu_launch_device<Real>(
            d_flux, d_q, d_c, d_dxa, d_sr, d_sb,
            static_cast<int>(ncol), iord, is, ie, isd, ied, npx, npy,
            nested, grid_type, lim_fac));
    }
    CUDA_CHECK(cudaEventRecord(stop));
    CUDA_CHECK(cudaEventSynchronize(stop));

    float ms = 0.f;
    CUDA_CHECK(cudaEventElapsedTime(&ms, start, stop));

    // ---- Copy result back and checksum ----
    CUDA_CHECK(cudaMemcpy(h_flux.data(), d_flux, n_flux * sizeof(Real), cudaMemcpyDeviceToHost));
    double sum = 0.0;
    for (size_t i = 0; i < h_flux.size(); ++i) sum += double(h_flux[i]);

    printf("time taken: %.6f s  (%.4f ms/iter over %d iters)\n",
           ms / 1000.0, ms / double(n_iter), n_iter);
    printf("sum(flux): %.10e\n", sum);

    cudaEventDestroy(start);
    cudaEventDestroy(stop);
    cudaFree(d_q); cudaFree(d_c); cudaFree(d_dxa);
    cudaFree(d_flux); cudaFree(d_sr); cudaFree(d_sb);
    return 0;
}
