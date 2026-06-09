// yppm_gpu.cuh — reusable CUDA launch API for the yppm transport kernel.
//
// This is the parallel, multi-column counterpart to the single-column
// yppm_col in yppm.hpp. The columns of a y-PPM sweep are independent, so the
// GPU maps one thread to one column and runs the existing yppm_col verbatim.
//
// Layout: COLUMN-CONTIGUOUS. For ncol independent columns, each column's
// j-values are stored contiguously, so a thread's column is a single slice
// and no per-thread gather/scatter is needed:
//   q,  dya  : length nj_q   = jed - jsd + 1 per column
//   cry, flux: length nj_flux = je  - js  + 2 per column
//   column t occupies [t*len, (t+1)*len).
// ncol = (number of x-columns in the tile) * (number of batched levels).
// js/je/jsd/jed/npx/npy are identical for every column (the j-direction
// south/north boundary treatment applies to every x-column alike), exactly as
// the CPU multi-column wrapper calls yppm_col with the same bounds per column.
//
// Per-column scratch is NOT on the stack: it lives in one device buffer sized
// at runtime (ncol * yppm_scratch_*_words(nj)), so any resolution is supported
// regardless of compile-time constants.
//
// Two entry points:
//   yppm_gpu_launch_device(...)  device pointers only; no alloc, no copy, no
//                                sync. This is what a future device-resident
//                                GPU fv_tp_2d orchestrator should call (data
//                                stays on the GPU across xppm/yppm; only the
//                                kernel launch happens here).
//   yppm_gpu(...)                host convenience: allocates device buffers
//                                (incl. scratch), copies in, launches, syncs,
//                                copies flux back, frees. Used by the unit
//                                test and the standalone driver.
#pragma once

#include <cuda_runtime.h>
#include <cstddef>

#include "yppm.hpp"

namespace fv3 {

// ---------------------------------------------------------------------------
// Kernel: one thread per column.
// ---------------------------------------------------------------------------
template <typename Real>
__global__ void yppm_kernel(
    Real*       flux,
    const Real* q,
    const Real* cry,
    const Real* dya,
    Real*       sreal,      // scratch real buffer  (ncol * rw)
    bool*       sbool,      // scratch bool buffer  (ncol * bw)
    int ncol,
    int jord,
    int js, int je, int jsd, int jed,
    int npx, int npy,
    int nested_i,           // bool passed as int
    int grid_type,
    Real lim_fac,
    int nj_q, int nj_flux,  // per-column array lengths
    int rw, int bw)         // per-column scratch word counts
{
    const int t = blockIdx.x * blockDim.x + threadIdx.x;
    if (t >= ncol) return;

    const int nj = je - js + 1;
    ScratchYPPMView<Real> s = yppm_make_scratch_view<Real>(
        sreal + static_cast<size_t>(t) * rw,
        sbool + static_cast<size_t>(t) * bw,
        nj);

    yppm_col<Real>(
        flux + static_cast<size_t>(t) * nj_flux,
        q    + static_cast<size_t>(t) * nj_q,
        cry  + static_cast<size_t>(t) * nj_flux,
        jord, js, je, jsd, jed, npx, npy,
        dya  + static_cast<size_t>(t) * nj_q,
        nested_i != 0, grid_type, lim_fac, s);
}

// ---------------------------------------------------------------------------
// Device scratch sizing (host helpers).
// ---------------------------------------------------------------------------
inline size_t yppm_gpu_scratch_real_count(int ncol, int js, int je) {
    return static_cast<size_t>(ncol) * yppm_scratch_real_words(je - js + 1);
}
inline size_t yppm_gpu_scratch_bool_count(int ncol, int js, int je) {
    return static_cast<size_t>(ncol) * yppm_scratch_bool_words(je - js + 1);
}

// ---------------------------------------------------------------------------
// Device-pointer launch: no allocation, no copy, no synchronize.
// Caller owns all device buffers (including the two scratch buffers, sized via
// yppm_gpu_scratch_*_count). Returns the launch error (cudaGetLastError).
// ---------------------------------------------------------------------------
template <typename Real>
inline cudaError_t yppm_gpu_launch_device(
    Real*       d_flux,
    const Real* d_q,
    const Real* d_cry,
    const Real* d_dya,
    Real*       d_sreal,
    bool*       d_sbool,
    int ncol,
    int jord,
    int js, int je, int jsd, int jed,
    int npx, int npy,
    bool nested,
    int grid_type,
    Real lim_fac,
    int threads_per_block = 128,
    cudaStream_t stream = 0)
{
    if (ncol <= 0) return cudaSuccess;

    const int nj      = je  - js  + 1;
    const int nj_q    = jed - jsd + 1;
    const int nj_flux = je  - js  + 2;
    const int rw      = yppm_scratch_real_words(nj);
    const int bw      = yppm_scratch_bool_words(nj);
    const int blocks  = (ncol + threads_per_block - 1) / threads_per_block;

    yppm_kernel<Real><<<blocks, threads_per_block, 0, stream>>>(
        d_flux, d_q, d_cry, d_dya, d_sreal, d_sbool,
        ncol, jord, js, je, jsd, jed, npx, npy,
        nested ? 1 : 0, grid_type, lim_fac, nj_q, nj_flux, rw, bw);

    return cudaGetLastError();
}

// ---------------------------------------------------------------------------
// Host convenience: allocate + copy in + launch + sync + copy out + free.
// h_* are host arrays in the column-contiguous layout described above.
// Returns the first CUDA error encountered, or cudaSuccess.
// ---------------------------------------------------------------------------
template <typename Real>
inline cudaError_t yppm_gpu(
    Real*       h_flux,
    const Real* h_q,
    const Real* h_cry,
    const Real* h_dya,
    int ncol,
    int jord,
    int js, int je, int jsd, int jed,
    int npx, int npy,
    bool nested,
    int grid_type,
    Real lim_fac)
{
    const int    nj_q    = jed - jsd + 1;
    const int    nj_flux = je  - js  + 2;
    const size_t n_q     = static_cast<size_t>(ncol) * nj_q;
    const size_t n_flux  = static_cast<size_t>(ncol) * nj_flux;
    const size_t n_sr    = yppm_gpu_scratch_real_count(ncol, js, je);
    const size_t n_sb    = yppm_gpu_scratch_bool_count(ncol, js, je);

    Real *d_q = nullptr, *d_cry = nullptr, *d_dya = nullptr,
         *d_flux = nullptr, *d_sr = nullptr;
    bool *d_sb = nullptr;
    cudaError_t e = cudaSuccess;

#define YPPM_TRY(call) do { e = (call); if (e != cudaSuccess) goto cleanup; } while (0)
    YPPM_TRY(cudaMalloc(&d_q,    n_q    * sizeof(Real)));
    YPPM_TRY(cudaMalloc(&d_cry,  n_flux * sizeof(Real)));
    YPPM_TRY(cudaMalloc(&d_dya,  n_q    * sizeof(Real)));
    YPPM_TRY(cudaMalloc(&d_flux, n_flux * sizeof(Real)));
    YPPM_TRY(cudaMalloc(&d_sr,   n_sr   * sizeof(Real)));
    YPPM_TRY(cudaMalloc(&d_sb,   n_sb   * sizeof(bool)));

    YPPM_TRY(cudaMemcpy(d_q,   h_q,   n_q    * sizeof(Real), cudaMemcpyHostToDevice));
    YPPM_TRY(cudaMemcpy(d_cry, h_cry, n_flux * sizeof(Real), cudaMemcpyHostToDevice));
    YPPM_TRY(cudaMemcpy(d_dya, h_dya, n_q    * sizeof(Real), cudaMemcpyHostToDevice));
    YPPM_TRY(cudaMemset(d_flux, 0, n_flux * sizeof(Real)));

    e = yppm_gpu_launch_device<Real>(
        d_flux, d_q, d_cry, d_dya, d_sr, d_sb,
        ncol, jord, js, je, jsd, jed, npx, npy,
        nested, grid_type, lim_fac);
    if (e != cudaSuccess) goto cleanup;

    YPPM_TRY(cudaDeviceSynchronize());
    YPPM_TRY(cudaMemcpy(h_flux, d_flux, n_flux * sizeof(Real), cudaMemcpyDeviceToHost));
#undef YPPM_TRY

cleanup:
    cudaFree(d_q);
    cudaFree(d_cry);
    cudaFree(d_dya);
    cudaFree(d_flux);
    cudaFree(d_sr);
    cudaFree(d_sb);
    return e;
}

} // namespace fv3
