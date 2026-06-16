// xppm_gpu.cuh — reusable CUDA launch API for the xppm transport kernel.
//
// The X-direction twin of yppm_gpu.cuh: the rows of an x-PPM sweep are
// independent, so the GPU maps one thread to one j-row and runs xppm_col.
//
// Layout: ROW-CONTIGUOUS. For ncol independent rows, each row's i-values are
// stored contiguously (this is the natural Fortran column-major order, since i
// is the fast dimension), so a thread's row is a single slice:
//   q,  dxa : length nj_q   = ied - isd + 1 per row
//   c,  flux: length nj_flux = ie  - is  + 2 per row
//   row t occupies [t*len, (t+1)*len).
// ncol = (number of j-rows in the tile) * (number of batched levels).
//
// Per-row scratch lives in one runtime-sized device buffer
// (ncol * yppm_scratch_*_words(ni), ni = ie - is + 1), reusing the
// direction-agnostic scratch helpers from yppm.hpp.
//
// Two entry points, mirroring yppm_gpu.cuh:
//   xppm_gpu_launch_device(...)  device pointers only; no alloc/copy/sync.
//   xppm_gpu(...)                host convenience (alloc/H2D/launch/sync/D2H/free).
#pragma once

#include <cuda_runtime.h>
#include <cstddef>

#include "xppm.hpp"   // xppm_col + (via yppm.hpp) the scratch view/helpers

namespace fv3 {

// ---------------------------------------------------------------------------
// Kernel: one thread per row.
// ---------------------------------------------------------------------------
template <typename Real>
__global__ void xppm_kernel(
    Real*       flux,
    const Real* q,
    const Real* c,
    const Real* dxa,
    Real*       sreal,      // scratch real buffer  (ncol * rw)
    bool*       sbool,      // scratch bool buffer  (ncol * bw)
    int ncol,
    int iord,
    int is, int ie, int isd, int ied,
    int npx, int npy,
    int nested_i,
    int grid_type,
    Real lim_fac,
    int nj_q, int nj_flux,  // per-row array lengths
    int rw, int bw)         // per-row scratch word counts
{
    const int t = blockIdx.x * blockDim.x + threadIdx.x;
    if (t >= ncol) return;

    const int ni = ie - is + 1;
    ScratchYPPMView<Real> s = yppm_make_scratch_view<Real>(
        sreal + static_cast<size_t>(t) * rw,
        sbool + static_cast<size_t>(t) * bw,
        ni);

    xppm_col<Real>(
        flux + static_cast<size_t>(t) * nj_flux,
        q    + static_cast<size_t>(t) * nj_q,
        c    + static_cast<size_t>(t) * nj_flux,
        iord, is, ie, isd, ied, npx, npy,
        dxa  + static_cast<size_t>(t) * nj_q,
        nested_i != 0, grid_type, lim_fac, s);
}

// ---------------------------------------------------------------------------
// Device scratch sizing (host helpers). ni = ie - is + 1.
// ---------------------------------------------------------------------------
inline size_t xppm_gpu_scratch_real_count(int ncol, int is, int ie) {
    return static_cast<size_t>(ncol) * yppm_scratch_real_words(ie - is + 1);
}
inline size_t xppm_gpu_scratch_bool_count(int ncol, int is, int ie) {
    return static_cast<size_t>(ncol) * yppm_scratch_bool_words(ie - is + 1);
}

// ---------------------------------------------------------------------------
// Device-pointer launch: no allocation, no copy, no synchronize.
// ---------------------------------------------------------------------------
template <typename Real>
inline cudaError_t xppm_gpu_launch_device(
    Real*       d_flux,
    const Real* d_q,
    const Real* d_c,
    const Real* d_dxa,
    Real*       d_sreal,
    bool*       d_sbool,
    int ncol,
    int iord,
    int is, int ie, int isd, int ied,
    int npx, int npy,
    bool nested,
    int grid_type,
    Real lim_fac,
    int threads_per_block = 128,
    cudaStream_t stream = 0)
{
    if (ncol <= 0) return cudaSuccess;

    const int ni      = ie  - is  + 1;
    const int nj_q    = ied - isd + 1;
    const int nj_flux = ie  - is  + 2;
    const int rw      = yppm_scratch_real_words(ni);
    const int bw      = yppm_scratch_bool_words(ni);
    const int blocks  = (ncol + threads_per_block - 1) / threads_per_block;

    xppm_kernel<Real><<<blocks, threads_per_block, 0, stream>>>(
        d_flux, d_q, d_c, d_dxa, d_sreal, d_sbool,
        ncol, iord, is, ie, isd, ied, npx, npy,
        nested ? 1 : 0, grid_type, lim_fac, nj_q, nj_flux, rw, bw);

    return cudaGetLastError();
}

// ---------------------------------------------------------------------------
// Host convenience: allocate + copy in + launch + sync + copy out + free.
// h_* are host arrays in the row-contiguous layout described above.
// ---------------------------------------------------------------------------
template <typename Real>
inline cudaError_t xppm_gpu(
    Real*       h_flux,
    const Real* h_q,
    const Real* h_c,
    const Real* h_dxa,
    int ncol,
    int iord,
    int is, int ie, int isd, int ied,
    int npx, int npy,
    bool nested,
    int grid_type,
    Real lim_fac)
{
    const int    nj_q    = ied - isd + 1;
    const int    nj_flux = ie  - is  + 2;
    const size_t n_q     = static_cast<size_t>(ncol) * nj_q;
    const size_t n_flux  = static_cast<size_t>(ncol) * nj_flux;
    const size_t n_sr    = xppm_gpu_scratch_real_count(ncol, is, ie);
    const size_t n_sb    = xppm_gpu_scratch_bool_count(ncol, is, ie);

    Real *d_q = nullptr, *d_c = nullptr, *d_dxa = nullptr,
         *d_flux = nullptr, *d_sr = nullptr;
    bool *d_sb = nullptr;
    cudaError_t e = cudaSuccess;

#define XPPM_TRY(call) do { e = (call); if (e != cudaSuccess) goto cleanup; } while (0)
    XPPM_TRY(cudaMalloc(&d_q,    n_q    * sizeof(Real)));
    XPPM_TRY(cudaMalloc(&d_c,    n_flux * sizeof(Real)));
    XPPM_TRY(cudaMalloc(&d_dxa,  n_q    * sizeof(Real)));
    XPPM_TRY(cudaMalloc(&d_flux, n_flux * sizeof(Real)));
    XPPM_TRY(cudaMalloc(&d_sr,   n_sr   * sizeof(Real)));
    XPPM_TRY(cudaMalloc(&d_sb,   n_sb   * sizeof(bool)));

    XPPM_TRY(cudaMemcpy(d_q,   h_q,   n_q    * sizeof(Real), cudaMemcpyHostToDevice));
    XPPM_TRY(cudaMemcpy(d_c,   h_c,   n_flux * sizeof(Real), cudaMemcpyHostToDevice));
    XPPM_TRY(cudaMemcpy(d_dxa, h_dxa, n_q    * sizeof(Real), cudaMemcpyHostToDevice));
    XPPM_TRY(cudaMemset(d_flux, 0, n_flux * sizeof(Real)));

    e = xppm_gpu_launch_device<Real>(
        d_flux, d_q, d_c, d_dxa, d_sr, d_sb,
        ncol, iord, is, ie, isd, ied, npx, npy,
        nested, grid_type, lim_fac);
    if (e != cudaSuccess) goto cleanup;

    XPPM_TRY(cudaDeviceSynchronize());
    XPPM_TRY(cudaMemcpy(h_flux, d_flux, n_flux * sizeof(Real), cudaMemcpyDeviceToHost));
#undef XPPM_TRY

cleanup:
    cudaFree(d_q);
    cudaFree(d_c);
    cudaFree(d_dxa);
    cudaFree(d_flux);
    cudaFree(d_sr);
    cudaFree(d_sb);
    return e;
}

} // namespace fv3
