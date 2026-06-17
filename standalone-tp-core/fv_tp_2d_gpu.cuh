// fv_tp_2d_gpu.cuh — device-resident GPU orchestrator for fv_tp_2d.
//
// The payoff of the yppm/xppm GPU ports: run the whole 2-D transport operator
// on the GPU with the fields RESIDENT on the device, launching a sequence of
// kernels on one stream and copying in/out only at the boundary.
//
// Sequence (matches fv_tp_2d.hpp / the Fortran, non-mass path):
//   1. copy_corners(q, dir=2)                       [1-thread kernel]
//   2. fy2 = yppm(q)            over columns isd..ied   [strided 2-D kernel]
//   3. q_i = (q*area + d/dy[yfx*fy2])/ra_y              [elementwise kernel]
//   4. fx  = xppm(q_i)          over rows js..je         [xppm_gpu_launch_device]
//   5. copy_corners(q, dir=1)                       [1-thread kernel]
//   6. fx2 = xppm(q)            over rows jsd..jed        [xppm_gpu_launch_device]
//   7. q_j = (q*area + d/dx[xfx*fx2])/ra_x              [elementwise kernel]
//   8. fy  = yppm(q_j)          over columns is..ie       [strided 2-D kernel]
//   9. fx = 0.5(fx+fx2)xfx ; fy = 0.5(fy+fy2)yfx          [combine kernels]
//
// xppm reuses the verified xppm_gpu_launch_device because rows are contiguous
// (column-major, i fastest). yppm columns are strided, so a thread gathers its
// column into a per-thread line buffer (coalesced across threads), runs the
// verified yppm_col, and scatters. All numerics come from the shared device
// functions, so GPU and CPU agree to FMA tolerance.
#pragma once

#include <cuda_runtime.h>
#include <cstddef>

#include "fv_tp_2d.hpp"   // idx2, fv_copy_corners, fv_cross, fv_avg_flux
#include "xppm_gpu.cuh"   // xppm_gpu_launch_device, scratch helpers

namespace fv3 {

// ---------------------------------------------------------------------------
// 1-thread corner-copy kernel.
// ---------------------------------------------------------------------------
template <typename Real>
__global__ void fv_copy_corners_kernel(Real* q, int isd, int jsd, int niq,
                                       int npx, int npy, int dir,
                                       int sw, int se, int nw, int ne) {
    if (blockIdx.x == 0 && threadIdx.x == 0)
        fv_copy_corners<Real>(q, isd, jsd, niq, npx, npy, dir,
                              sw != 0, se != 0, nw != 0, ne != 0);
}

// ---------------------------------------------------------------------------
// Strided 2-D yppm: one thread per column i in [i0,i1]. Gathers the column
// into a per-thread line buffer, runs yppm_col, scatters.
//   q   : (q_ilo:..,  jsd:jed)   stride q_ni
//   cry : (c_ilo:..,  js:je+1)   stride c_ni      (dya shares c_ilo/c_ni, jlo=jsd)
//   flux: (f_ilo:..,  js:je+1)   stride f_ni
// Per-thread buffers in `lines` (lw words): q_line, dya_line, cry_line, flux_line.
// ---------------------------------------------------------------------------
template <typename Real>
__global__ void yppm_kernel_2d(
    Real* flux, int f_ilo, int f_ni,
    const Real* q, int q_ilo, int q_ni,
    const Real* cry, const Real* dya, int c_ilo, int c_ni,
    int i0, int i1, int js, int je, int jsd, int jed, int npx, int npy,
    int nested_i, int grid_type, Real lim_fac, int iord,
    Real* sreal, bool* sbool, Real* lines, int rw, int bw, int lw)
{
    const int t = blockIdx.x * blockDim.x + threadIdx.x;
    const int ncol = i1 - i0 + 1;
    if (t >= ncol) return;
    const int i = i0 + t;

    const int nj    = je - js + 1;
    const int nj_q  = jed - jsd + 1;
    const int nj_f  = je - js + 2;

    Real* base = lines + static_cast<size_t>(t) * lw;
    Real* q_line   = base;
    Real* dya_line = base + nj_q;
    Real* cry_line = base + 2 * nj_q;
    Real* flux_line= base + 2 * nj_q + nj_f;

    for (int j = jsd; j <= jed; ++j) q_line[j-jsd]   = q  [idx2(i,j,q_ilo,jsd,q_ni)];
    for (int j = jsd; j <= jed; ++j) dya_line[j-jsd] = dya[idx2(i,j,c_ilo,jsd,c_ni)];
    for (int j = js;  j <= je+1; ++j) cry_line[j-js] = cry[idx2(i,j,c_ilo,js, c_ni)];

    ScratchYPPMView<Real> s = yppm_make_scratch_view<Real>(
        sreal + static_cast<size_t>(t) * rw, sbool + static_cast<size_t>(t) * bw, nj);

    yppm_col<Real>(flux_line, q_line, cry_line, iord,
                   js, je, jsd, jed, npx, npy, dya_line,
                   nested_i != 0, grid_type, lim_fac, s);

    for (int j = js; j <= je+1; ++j) flux[idx2(i,j,f_ilo,js,f_ni)] = flux_line[j-js];
}

// ---------------------------------------------------------------------------
// Elementwise kernels.
// ---------------------------------------------------------------------------
template <typename Real>
__global__ void qi_kernel(
    Real* q_i, const Real* q, const Real* area, const Real* yfx,
    const Real* fy2, const Real* ra_y,
    int isd, int jsd, int niq, int js, int je, int ied)
{
    const int ni = ied - isd + 1;            // = niq
    const int total = ni * (je - js + 1);
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= total) return;
    const int i = isd + (idx % ni);
    const int j = js  + (idx / ni);
    const Real a = yfx[idx2(i,j,  isd,js,niq)] * fy2[idx2(i,j,  isd,js,niq)];
    const Real b = yfx[idx2(i,j+1,isd,js,niq)] * fy2[idx2(i,j+1,isd,js,niq)];
    q_i[idx2(i,j,isd,js,niq)] = fv_cross<Real>(
        q[idx2(i,j,isd,jsd,niq)], area[idx2(i,j,isd,jsd,niq)],
        a, b, ra_y[idx2(i,j,isd,js,niq)]);
}

template <typename Real>
__global__ void qj_kernel(
    Real* q_j, const Real* q, const Real* area, const Real* xfx,
    const Real* fx2, const Real* ra_x,
    int is, int isd, int jsd, int niq, int nicrx, int nirax, int ie, int jed)
{
    const int ni = ie - is + 1;              // = nirax
    const int total = ni * (jed - jsd + 1);
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= total) return;
    const int i = is  + (idx % ni);
    const int j = jsd + (idx / ni);
    const Real a = xfx[idx2(i,  j,is,jsd,nicrx)] * fx2[idx2(i,  j,is,jsd,nicrx)];
    const Real b = xfx[idx2(i+1,j,is,jsd,nicrx)] * fx2[idx2(i+1,j,is,jsd,nicrx)];
    q_j[idx2(i,j,is,jsd,nirax)] = fv_cross<Real>(
        q[idx2(i,j,isd,jsd,niq)], area[idx2(i,j,isd,jsd,niq)],
        a, b, ra_x[idx2(i,j,is,jsd,nirax)]);
}

template <typename Real>
__global__ void combine_fx_kernel(
    Real* fx, const Real* fx2, const Real* xfx,
    int is, int js, int jsd, int nicrx, int ie, int je)
{
    const int ni = ie - is + 2;              // = nicrx
    const int total = ni * (je - js + 1);
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= total) return;
    const int i = is + (idx % ni);
    const int j = js + (idx / ni);
    fx[idx2(i,j,is,js,nicrx)] = fv_avg_flux<Real>(
        fx[idx2(i,j,is,js,nicrx)], fx2[idx2(i,j,is,jsd,nicrx)], xfx[idx2(i,j,is,jsd,nicrx)]);
}

template <typename Real>
__global__ void combine_fy_kernel(
    Real* fy, const Real* fy2, const Real* yfx,
    int is, int isd, int js, int niq, int nirax, int ie, int je)
{
    const int ni = ie - is + 1;              // = nirax
    const int total = ni * (je - js + 2);
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= total) return;
    const int i = is + (idx % ni);
    const int j = js + (idx / ni);
    fy[idx2(i,j,is,js,nirax)] = fv_avg_flux<Real>(
        fy[idx2(i,j,is,js,nirax)], fy2[idx2(i,j,isd,js,niq)], yfx[idx2(i,j,isd,js,niq)]);
}

// ---------------------------------------------------------------------------
// Device scratch sizing for the orchestrator (host helpers).
// ---------------------------------------------------------------------------
struct FvTpGpuScratch {
    size_t sreal_words;   // PPM scratch reals  (shared yppm/xppm)
    size_t sbool_words;   // PPM scratch bools
    size_t line_words;    // yppm line buffer reals
    int    rw, bw, lw;    // per-thread word counts (reals, bools, line reals)
};
inline FvTpGpuScratch fv_tp_2d_gpu_scratch(
    int is, int ie, int js, int je, int isd, int ied, int jsd, int jed)
{
    const int nj = je - js + 1, ni = ie - is + 1;
    const int nmax = nj > ni ? nj : ni;
    const int ncol_y = ied - isd + 1;          // yppm columns (step 2, the most)
    const int ncol_x = jed - jsd + 1;          // xppm rows (step 6)
    const int ncol = ncol_y > ncol_x ? ncol_y : ncol_x;
    FvTpGpuScratch g;
    g.rw = yppm_scratch_real_words(nmax);
    g.bw = yppm_scratch_bool_words(nmax);
    g.lw = 2 * (jed - jsd + 1) + 2 * (je - js + 2);
    g.sreal_words = static_cast<size_t>(ncol) * g.rw;
    g.sbool_words = static_cast<size_t>(ncol) * g.bw;
    g.line_words  = static_cast<size_t>(ncol_y) * g.lw;
    return g;
}

// ---------------------------------------------------------------------------
// Device-pointer orchestrator: no alloc, no copy, no sync. All buffers are
// caller-owned and device-resident; kernels run on `stream` in sequence.
// Internals (q_i, q_j, fx2, fy2) and scratch are also caller-provided.
// ---------------------------------------------------------------------------
template <typename Real>
inline cudaError_t fv_tp_2d_gpu_launch(
    Real* d_q, const Real* d_crx, const Real* d_cry,
    const Real* d_xfx, const Real* d_yfx,
    const Real* d_ra_x, const Real* d_ra_y,
    const Real* d_area, const Real* d_dxa, const Real* d_dya,
    Real* d_fx, Real* d_fy,
    Real* d_q_i, Real* d_q_j, Real* d_fx2, Real* d_fy2,
    Real* d_sreal, bool* d_sbool, Real* d_lines,
    const FvTpGpuScratch& g,
    int is, int ie, int js, int je, int isd, int ied, int jsd, int jed,
    int npx, int npy, int hord, Real lim_fac,
    bool nested, int grid_type, bool sw, bool se, bool nw, bool ne,
    int tpb = 128, cudaStream_t stream = 0)
{
    const int ord_in = (hord == 10) ? 8 : hord;
    const int ord_ou = hord;
    const int niq   = ied - isd + 1;
    const int nicrx = ie  - is  + 2;
    const int nirax = ie  - is  + 1;
    auto nblk = [tpb](int count){ return (count + tpb - 1) / tpb; };
    cudaError_t e;

    // 1. copy_corners (y)
    if (!nested)
        fv_copy_corners_kernel<Real><<<1,1,0,stream>>>(d_q, isd, jsd, niq, npx, npy, 2,
                                                       sw, se, nw, ne);

    // 2. fy2 = yppm(q) over columns isd..ied
    yppm_kernel_2d<Real><<<nblk(ied-isd+1), tpb, 0, stream>>>(
        d_fy2, isd, niq, d_q, isd, niq, d_cry, d_dya, isd, niq,
        isd, ied, js, je, jsd, jed, npx, npy, nested?1:0, grid_type, lim_fac, ord_in,
        d_sreal, d_sbool, d_lines, g.rw, g.bw, g.lw);

    // 3. q_i
    qi_kernel<Real><<<nblk(niq*(je-js+1)), tpb, 0, stream>>>(
        d_q_i, d_q, d_area, d_yfx, d_fy2, d_ra_y, isd, jsd, niq, js, je, ied);

    // 4. fx = xppm(q_i) over rows js..je (rows contiguous -> reuse xppm launch)
    e = xppm_gpu_launch_device<Real>(
        d_fx, d_q_i, d_crx + static_cast<size_t>(nicrx) * (js - jsd),
        d_dxa + static_cast<size_t>(niq) * (js - jsd), d_sreal, d_sbool,
        je - js + 1, ord_ou, is, ie, isd, ied, npx, npy,
        nested, grid_type, lim_fac, tpb, stream);
    if (e != cudaSuccess) return e;

    // 5. copy_corners (x)
    if (!nested)
        fv_copy_corners_kernel<Real><<<1,1,0,stream>>>(d_q, isd, jsd, niq, npx, npy, 1,
                                                       sw, se, nw, ne);

    // 6. fx2 = xppm(q) over rows jsd..jed
    e = xppm_gpu_launch_device<Real>(
        d_fx2, d_q, d_crx, d_dxa, d_sreal, d_sbool,
        jed - jsd + 1, ord_in, is, ie, isd, ied, npx, npy,
        nested, grid_type, lim_fac, tpb, stream);
    if (e != cudaSuccess) return e;

    // 7. q_j
    qj_kernel<Real><<<nblk(nirax*(jed-jsd+1)), tpb, 0, stream>>>(
        d_q_j, d_q, d_area, d_xfx, d_fx2, d_ra_x, is, isd, jsd, niq, nicrx, nirax, ie, jed);

    // 8. fy = yppm(q_j) over columns is..ie
    yppm_kernel_2d<Real><<<nblk(ie-is+1), tpb, 0, stream>>>(
        d_fy, is, nirax, d_q_j, is, nirax, d_cry, d_dya, isd, niq,
        is, ie, js, je, jsd, jed, npx, npy, nested?1:0, grid_type, lim_fac, ord_ou,
        d_sreal, d_sbool, d_lines, g.rw, g.bw, g.lw);

    // 9. combine
    combine_fx_kernel<Real><<<nblk(nicrx*(je-js+1)), tpb, 0, stream>>>(
        d_fx, d_fx2, d_xfx, is, js, jsd, nicrx, ie, je);
    combine_fy_kernel<Real><<<nblk(nirax*(je-js+2)), tpb, 0, stream>>>(
        d_fy, d_fy2, d_yfx, is, isd, js, niq, nirax, ie, je);

    return cudaGetLastError();
}

// ---------------------------------------------------------------------------
// Host convenience: allocate device buffers, copy inputs in, run the
// orchestrator once, sync, copy fx/fy out, free. h_* are host arrays in the
// fv_tp_2d.hpp layout.
// ---------------------------------------------------------------------------
template <typename Real>
inline cudaError_t fv_tp_2d_gpu(
    Real*       h_q,
    const Real* h_crx, const Real* h_cry, const Real* h_xfx, const Real* h_yfx,
    const Real* h_ra_x, const Real* h_ra_y,
    const Real* h_area, const Real* h_dxa, const Real* h_dya,
    Real* h_fx, Real* h_fy,
    int is, int ie, int js, int je, int isd, int ied, int jsd, int jed,
    int npx, int npy, int hord, Real lim_fac,
    bool nested, int grid_type, bool sw, bool se, bool nw, bool ne)
{
    const int niq   = ied - isd + 1;
    const int nicrx = ie  - is  + 2;
    const int nirax = ie  - is  + 1;
    const size_t sz_q   = (size_t)niq   * (jed - jsd + 1);
    const size_t sz_crx = (size_t)nicrx * (jed - jsd + 1);
    const size_t sz_cry = (size_t)niq   * (je  - js  + 2);
    const size_t sz_rax = (size_t)nirax * (jed - jsd + 1);
    const size_t sz_ray = (size_t)niq   * (je  - js  + 1);
    const size_t sz_fx  = (size_t)nicrx * (je  - js  + 1);
    const size_t sz_fy  = (size_t)nirax * (je  - js  + 2);
    const size_t sz_qi  = (size_t)niq   * (je  - js  + 1);
    const size_t sz_qj  = (size_t)nirax * (jed - jsd + 1);
    const size_t sz_fx2 = (size_t)nicrx * (jed - jsd + 1);
    const size_t sz_fy2 = (size_t)niq   * (je  - js  + 2);

    const FvTpGpuScratch g = fv_tp_2d_gpu_scratch(is, ie, js, je, isd, ied, jsd, jed);

    Real *q=nullptr,*crx=nullptr,*cry=nullptr,*xfx=nullptr,*yfx=nullptr,
         *ra_x=nullptr,*ra_y=nullptr,*area=nullptr,*dxa=nullptr,*dya=nullptr,
         *fx=nullptr,*fy=nullptr,*qi=nullptr,*qj=nullptr,*fx2=nullptr,*fy2=nullptr,
         *sr=nullptr,*lines=nullptr;
    bool *sb=nullptr;
    cudaError_t e = cudaSuccess;

#define FV_TRY(call) do { e=(call); if(e!=cudaSuccess) goto cleanup; } while(0)
    FV_TRY(cudaMalloc(&q,   sz_q  *sizeof(Real)));
    FV_TRY(cudaMalloc(&crx, sz_crx*sizeof(Real)));
    FV_TRY(cudaMalloc(&cry, sz_cry*sizeof(Real)));
    FV_TRY(cudaMalloc(&xfx, sz_crx*sizeof(Real)));
    FV_TRY(cudaMalloc(&yfx, sz_cry*sizeof(Real)));
    FV_TRY(cudaMalloc(&ra_x,sz_rax*sizeof(Real)));
    FV_TRY(cudaMalloc(&ra_y,sz_ray*sizeof(Real)));
    FV_TRY(cudaMalloc(&area,sz_q  *sizeof(Real)));
    FV_TRY(cudaMalloc(&dxa, sz_q  *sizeof(Real)));
    FV_TRY(cudaMalloc(&dya, sz_q  *sizeof(Real)));
    FV_TRY(cudaMalloc(&fx,  sz_fx *sizeof(Real)));
    FV_TRY(cudaMalloc(&fy,  sz_fy *sizeof(Real)));
    FV_TRY(cudaMalloc(&qi,  sz_qi *sizeof(Real)));
    FV_TRY(cudaMalloc(&qj,  sz_qj *sizeof(Real)));
    FV_TRY(cudaMalloc(&fx2, sz_fx2*sizeof(Real)));
    FV_TRY(cudaMalloc(&fy2, sz_fy2*sizeof(Real)));
    FV_TRY(cudaMalloc(&sr,  g.sreal_words*sizeof(Real)));
    FV_TRY(cudaMalloc(&sb,  g.sbool_words*sizeof(bool)));
    FV_TRY(cudaMalloc(&lines, g.line_words*sizeof(Real)));

    FV_TRY(cudaMemcpy(q,   h_q,   sz_q  *sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(crx, h_crx, sz_crx*sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(cry, h_cry, sz_cry*sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(xfx, h_xfx, sz_crx*sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(yfx, h_yfx, sz_cry*sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(ra_x,h_ra_x,sz_rax*sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(ra_y,h_ra_y,sz_ray*sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(area,h_area,sz_q  *sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(dxa, h_dxa, sz_q  *sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(dya, h_dya, sz_q  *sizeof(Real), cudaMemcpyHostToDevice));

    e = fv_tp_2d_gpu_launch<Real>(
        q, crx, cry, xfx, yfx, ra_x, ra_y, area, dxa, dya, fx, fy,
        qi, qj, fx2, fy2, sr, sb, lines, g,
        is, ie, js, je, isd, ied, jsd, jed, npx, npy, hord, lim_fac,
        nested, grid_type, sw, se, nw, ne);
    if (e != cudaSuccess) goto cleanup;

    FV_TRY(cudaDeviceSynchronize());
    FV_TRY(cudaMemcpy(h_fx, fx, sz_fx*sizeof(Real), cudaMemcpyDeviceToHost));
    FV_TRY(cudaMemcpy(h_fy, fy, sz_fy*sizeof(Real), cudaMemcpyDeviceToHost));
#undef FV_TRY

cleanup:
    cudaFree(q); cudaFree(crx); cudaFree(cry); cudaFree(xfx); cudaFree(yfx);
    cudaFree(ra_x); cudaFree(ra_y); cudaFree(area); cudaFree(dxa); cudaFree(dya);
    cudaFree(fx); cudaFree(fy); cudaFree(qi); cudaFree(qj); cudaFree(fx2); cudaFree(fy2);
    cudaFree(sr); cudaFree(sb); cudaFree(lines);
    return e;
}

} // namespace fv3
