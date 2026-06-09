// driver_yppm_gpu.cu — standalone command-line GPU benchmark for yppm.
//
// Mirrors the CPU tp-core-driver (model/tp-core-driver/driver_cpu.f90):
//   Usage: tp-core-driver-gpu <resolution> <iterations> [levels]
// It builds a synthetic tile, copies it to the device ONCE, then runs the
// yppm GPU kernel <iterations> times in a timed loop (allocate-once /
// copy-once / loop), exactly as a device-resident model step would. The
// per-iteration launch uses the device-pointer API yppm_gpu_launch_device.
//
// Parallelism: one GPU thread per column. ncol = ni * levels, where
//   ni = (ied - isd + 1)   x-columns of one tile (with a 3-cell halo)
//   levels                 a batch dimension standing in for vertical levels.
// Increasing levels raises occupancy; the default of 1 already yields
// thousands of columns at production resolutions.
//
// Output mirrors the CPU driver: elapsed time and a flux checksum.
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <vector>

#include <cuda_runtime.h>

#include "yppm.hpp"
#include "yppm_gpu.cuh"

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
    const int n          = std::atoi(argv[1]);
    const int n_iter     = std::atoi(argv[2]);
    const int levels     = (argc == 4) ? std::atoi(argv[3]) : 1;
    if (n < 1 || n_iter < 1 || levels < 1) {
        fprintf(stderr, "resolution, iterations, and levels must be >= 1\n");
        return 2;
    }

    // ---- Domain (one cubed-sphere tile, 3-cell halo), matching driver_cpu ----
    const int ng     = 3;
    const int jord   = 8;
    const Real lim_fac = Real(1);
    const bool nested  = false;     // driver_cpu uses fv_grid_type(..., .false., 0)
    const int grid_type = 0;

    const int ifirst = 1,        ilast = n;
    const int isd    = ifirst-ng, ied  = ilast+ng;
    const int js     = 1,        je    = n;
    const int jsd    = js-ng,    jed   = je+ng;
    const int npx    = n+1,      npy   = n+1;

    const int ni      = ied - isd + 1;   // x-columns (with halo)
    const long ncol   = static_cast<long>(ni) * levels;
    const int nj_q    = jed - jsd + 1;   // q/dya per-column length
    const int nj_flux = je  - js  + 2;   // cry/flux per-column length

    printf("yppm GPU driver: resolution=%d iterations=%d levels=%d\n", n, n_iter, levels);
    printf("  ni=%d nj_q=%d nj_flux=%d ncol=%ld jord=%d nested=%d\n",
           ni, nj_q, nj_flux, ncol, jord, (int)nested);

    // ---- Build a synthetic, smooth tile on the host (column-contiguous) ----
    std::vector<Real> h_q   (static_cast<size_t>(ncol) * nj_q);
    std::vector<Real> h_dya (static_cast<size_t>(ncol) * nj_q,  Real(1));
    std::vector<Real> h_cry (static_cast<size_t>(ncol) * nj_flux, Real(0.5));
    std::vector<Real> h_flux(static_cast<size_t>(ncol) * nj_flux, Real(0));

    const double two_pi = 6.283185307179586;
    for (long c = 0; c < ncol; ++c) {
        Real* qc = h_q.data() + c * nj_q;
        for (int j = 0; j < nj_q; ++j)
            qc[j] = Real(1.0 + 0.5 * std::cos(two_pi * double(j) / double(nj_q)));
    }

    // ---- Allocate device buffers ONCE ----
    const size_t n_q    = static_cast<size_t>(ncol) * nj_q;
    const size_t n_flux = static_cast<size_t>(ncol) * nj_flux;
    const size_t n_sr   = fv3::yppm_gpu_scratch_real_count(static_cast<int>(ncol), js, je);
    const size_t n_sb   = fv3::yppm_gpu_scratch_bool_count(static_cast<int>(ncol), js, je);

    Real *d_q, *d_cry, *d_dya, *d_flux, *d_sr;
    bool *d_sb;
    CUDA_CHECK(cudaMalloc(&d_q,    n_q    * sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&d_cry,  n_flux * sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&d_dya,  n_q    * sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&d_flux, n_flux * sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&d_sr,   n_sr   * sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&d_sb,   n_sb   * sizeof(bool)));

    // ---- Copy inputs ONCE ----
    CUDA_CHECK(cudaMemcpy(d_q,   h_q.data(),   n_q    * sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_cry, h_cry.data(), n_flux * sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_dya, h_dya.data(), n_q    * sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemset(d_flux, 0, n_flux * sizeof(Real)));

    // ---- Warm-up launch (excluded from timing) ----
    CUDA_CHECK(fv3::yppm_gpu_launch_device<Real>(
        d_flux, d_q, d_cry, d_dya, d_sr, d_sb,
        static_cast<int>(ncol), jord, js, je, jsd, jed, npx, npy,
        nested, grid_type, lim_fac));
    CUDA_CHECK(cudaDeviceSynchronize());

    // ---- Timed loop ----
    cudaEvent_t start, stop;
    CUDA_CHECK(cudaEventCreate(&start));
    CUDA_CHECK(cudaEventCreate(&stop));
    CUDA_CHECK(cudaEventRecord(start));
    for (int it = 0; it < n_iter; ++it) {
        CUDA_CHECK(fv3::yppm_gpu_launch_device<Real>(
            d_flux, d_q, d_cry, d_dya, d_sr, d_sb,
            static_cast<int>(ncol), jord, js, je, jsd, jed, npx, npy,
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
    cudaFree(d_q); cudaFree(d_cry); cudaFree(d_dya);
    cudaFree(d_flux); cudaFree(d_sr); cudaFree(d_sb);
    return 0;
}
