// fv_tp_2d_gpu.cuh — device-resident, BATCHED GPU orchestrator for fv_tp_2d.
//
// Processes `nbatch` independent tiles (vertical levels / cube faces) per
// launch: every kernel folds the batch dimension in, so each of the ~9
// transport steps is a single launch over all tiles. This moves the
// line-parallel PPM steps (only O(n) parallel for one tile) into the
// saturated regime and amortizes launch overhead across the whole batch.
//
// Tile b's copy of an array A lives at A + b*tileA, where tileA is the
// per-tile element count for that array. All numerics reuse the verified
// yppm_col/xppm_col (per line, via gather) and the shared device cell ops.
//
// Both yppm (columns, strided) and xppm (rows, contiguous) use a gather-based
// 2-D kernel here — uniform, tile-aware, and correct for the row subsets that
// the plain xppm launch could not express across tile boundaries.
#pragma once

#include <cuda_runtime.h>
#include <cstddef>

#include "fv_tp_2d.hpp"   // idx2, fv_copy_corners, fv_cross, fv_avg_flux, yppm_col, xppm_col

namespace fv3 {

// ---------------------------------------------------------------------------
// copy_corners: one thread per tile.
// ---------------------------------------------------------------------------
template <typename Real>
__global__ void fv_copy_corners_kernel(Real* q, int isd, int jsd, int niq,
                                       int npx, int npy, int dir,
                                       int sw, int se, int nw, int ne,
                                       int q_tile, int nbatch) {
    const int b = blockIdx.x * blockDim.x + threadIdx.x;
    if (b >= nbatch) return;
    fv_copy_corners<Real>(q + static_cast<size_t>(b) * q_tile,
                          isd, jsd, niq, npx, npy, dir,
                          sw != 0, se != 0, nw != 0, ne != 0);
}

// ---------------------------------------------------------------------------
// Batched strided yppm: one thread per (column, tile). Columns i in [i0,i1].
// q/flux jlo: q spans jsd:jed (jlo=jsd); flux spans js:je+1 (jlo=js).
// cry spans js:je+1 (c_jlo=js); dya spans jsd:jed (c_jlo=jsd) but shares ni.
// ---------------------------------------------------------------------------
template <typename Real>
__global__ void yppm_batch_kernel(
    Real* flux, int f_ilo, int f_ni, int f_tile,
    const Real* q, int q_ilo, int q_ni, int q_tile,
    const Real* cry, int cry_tile, const Real* dya, int dya_tile, int c_ilo, int c_ni,
    int i0, int i1, int js, int je, int jsd, int jed, int npx, int npy,
    int nested_i, int grid_type, Real lim_fac, int iord, int nbatch,
    Real* sreal, bool* sbool, Real* lines, int rw, int bw, int lw)
{
    const int ncol = i1 - i0 + 1;
    const long t = static_cast<long>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (t >= static_cast<long>(ncol) * nbatch) return;
    const int b = t / ncol;
    const int i = i0 + (t % ncol);

    const int nj   = je - js + 1;
    const int nj_q = jed - jsd + 1;
    const int nj_f = je - js + 2;

    const Real* qb   = q   + static_cast<size_t>(b) * q_tile;
    const Real* cryb = cry + static_cast<size_t>(b) * cry_tile;
    const Real* dyab = dya + static_cast<size_t>(b) * dya_tile;
    Real*       fb   = flux+ static_cast<size_t>(b) * f_tile;

    Real* base = lines + t * lw;
    Real* q_line = base, *dya_line = base + nj_q,
          *cry_line = base + 2*nj_q, *flux_line = base + 2*nj_q + nj_f;

    for (int j = jsd; j <= jed; ++j) q_line[j-jsd]   = qb  [idx2(i,j,q_ilo,jsd,q_ni)];
    for (int j = jsd; j <= jed; ++j) dya_line[j-jsd] = dyab[idx2(i,j,c_ilo,jsd,c_ni)];
    for (int j = js;  j <= je+1; ++j) cry_line[j-js] = cryb[idx2(i,j,c_ilo,js, c_ni)];

    ScratchYPPMView<Real> s = yppm_make_scratch_view<Real>(
        sreal + t * rw, sbool + t * bw, nj);
    yppm_col<Real>(flux_line, q_line, cry_line, iord, js, je, jsd, jed, npx, npy,
                   dya_line, nested_i != 0, grid_type, lim_fac, s);

    for (int j = js; j <= je+1; ++j) fb[idx2(i,j,f_ilo,js,f_ni)] = flux_line[j-js];
}

// ---------------------------------------------------------------------------
// Batched strided xppm: one thread per (row, tile). Rows j in [j0,j1].
// q jlo = j0 (q spans exactly the iterated rows); flux jlo = j0.
// crx/dxa span jsd:jed (c_jlo=jsd).
// ---------------------------------------------------------------------------
template <typename Real>
__global__ void xppm_batch_kernel(
    Real* flux, int f_jlo, int f_ni, int f_tile,
    const Real* q, int q_jlo, int q_ni, int q_tile,
    const Real* crx, int crx_tile, const Real* dxa, int dxa_tile, int c_jlo, int c_ni, int dxa_ni,
    int j0, int j1, int is, int ie, int isd, int ied, int npx, int npy,
    int nested_i, int grid_type, Real lim_fac, int iord, int nbatch,
    Real* sreal, bool* sbool, Real* lines, int rw, int bw, int lw)
{
    const int nrow = j1 - j0 + 1;
    const long t = static_cast<long>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (t >= static_cast<long>(nrow) * nbatch) return;
    const int b = t / nrow;
    const int j = j0 + (t % nrow);

    const int ni   = ie - is + 1;
    const int ni_q = ied - isd + 1;
    const int ni_f = ie - is + 2;

    const Real* qb   = q   + static_cast<size_t>(b) * q_tile;
    const Real* crxb = crx + static_cast<size_t>(b) * crx_tile;
    const Real* dxab = dxa + static_cast<size_t>(b) * dxa_tile;
    Real*       fb   = flux+ static_cast<size_t>(b) * f_tile;

    Real* base = lines + t * lw;
    Real* q_line = base, *dxa_line = base + ni_q,
          *c_line = base + 2*ni_q, *flux_line = base + 2*ni_q + ni_f;

    for (int i = isd; i <= ied; ++i) q_line[i-isd]   = qb  [idx2(i,j,isd,q_jlo,q_ni)];
    for (int i = isd; i <= ied; ++i) dxa_line[i-isd] = dxab[idx2(i,j,isd,c_jlo,dxa_ni)];
    for (int i = is;  i <= ie+1; ++i) c_line[i-is]   = crxb[idx2(i,j,is, c_jlo,c_ni)];

    ScratchYPPMView<Real> s = yppm_make_scratch_view<Real>(
        sreal + t * rw, sbool + t * bw, ni);
    xppm_col<Real>(flux_line, q_line, c_line, iord, is, ie, isd, ied, npx, npy,
                   dxa_line, nested_i != 0, grid_type, lim_fac, s);

    for (int i = is; i <= ie+1; ++i) fb[idx2(i,j,is,f_jlo,f_ni)] = flux_line[i-is];
}

// ---------------------------------------------------------------------------
// Batched elementwise kernels: thread per (cell, tile).
// ---------------------------------------------------------------------------
template <typename Real>
__global__ void qi_batch_kernel(
    Real* q_i, const Real* q, const Real* area, const Real* yfx,
    const Real* fy2, const Real* ra_y,
    int isd, int jsd, int niq, int js, int je, int ied,
    int TQI, int TQ, int TCRY, int TRAY, int nbatch)
{
    const int ni = ied - isd + 1;
    const int per = ni * (je - js + 1);
    const long idx = static_cast<long>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (idx >= static_cast<long>(per) * nbatch) return;
    const int b = idx / per;
    const int loc = idx % per;
    const int i = isd + (loc % ni);
    const int j = js  + (loc / ni);
    const Real* yb=yfx+(size_t)b*TCRY; const Real* f2=fy2+(size_t)b*TCRY;
    const Real* qb=q+(size_t)b*TQ; const Real* ab=area+(size_t)b*TQ; const Real* rb=ra_y+(size_t)b*TRAY;
    const Real a = yb[idx2(i,j,  isd,js,niq)] * f2[idx2(i,j,  isd,js,niq)];
    const Real bb= yb[idx2(i,j+1,isd,js,niq)] * f2[idx2(i,j+1,isd,js,niq)];
    q_i[(size_t)b*TQI + idx2(i,j,isd,js,niq)] = fv_cross<Real>(
        qb[idx2(i,j,isd,jsd,niq)], ab[idx2(i,j,isd,jsd,niq)], a, bb, rb[idx2(i,j,isd,js,niq)]);
}

template <typename Real>
__global__ void qj_batch_kernel(
    Real* q_j, const Real* q, const Real* area, const Real* xfx,
    const Real* fx2, const Real* ra_x,
    int is, int isd, int jsd, int niq, int nicrx, int nirax, int ie, int jed,
    int TQJ, int TQ, int TCRX, int TRAX, int nbatch)
{
    const int ni = ie - is + 1;
    const int per = ni * (jed - jsd + 1);
    const long idx = static_cast<long>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (idx >= static_cast<long>(per) * nbatch) return;
    const int b = idx / per;
    const int loc = idx % per;
    const int i = is  + (loc % ni);
    const int j = jsd + (loc / ni);
    const Real* xb=xfx+(size_t)b*TCRX; const Real* f2=fx2+(size_t)b*TCRX;
    const Real* qb=q+(size_t)b*TQ; const Real* ab=area+(size_t)b*TQ; const Real* rb=ra_x+(size_t)b*TRAX;
    const Real a = xb[idx2(i,  j,is,jsd,nicrx)] * f2[idx2(i,  j,is,jsd,nicrx)];
    const Real bb= xb[idx2(i+1,j,is,jsd,nicrx)] * f2[idx2(i+1,j,is,jsd,nicrx)];
    q_j[(size_t)b*TQJ + idx2(i,j,is,jsd,nirax)] = fv_cross<Real>(
        qb[idx2(i,j,isd,jsd,niq)], ab[idx2(i,j,isd,jsd,niq)], a, bb, rb[idx2(i,j,is,jsd,nirax)]);
}

template <typename Real>
__global__ void combine_fx_batch_kernel(
    Real* fx, const Real* fx2, const Real* xfx,
    int is, int js, int jsd, int nicrx, int ie, int je,
    int TFX, int TCRX, int nbatch,
    int use_mass, const Real* mfx)   // mfx is (is:ie+1,js:je), tile = TFX
{
    const int ni = ie - is + 2;
    const int per = ni * (je - js + 1);
    const long idx = static_cast<long>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (idx >= static_cast<long>(per) * nbatch) return;
    const int b = idx / per;
    const int loc = idx % per;
    const int i = is + (loc % ni);
    const int j = js + (loc / ni);
    Real* fxb = fx + (size_t)b*TFX;
    const Real* f2=fx2+(size_t)b*TCRX;
    const Real wx = use_mass ? (mfx + (size_t)b*TFX)[idx2(i,j,is,js,nicrx)]
                             : (xfx + (size_t)b*TCRX)[idx2(i,j,is,jsd,nicrx)];
    fxb[idx2(i,j,is,js,nicrx)] = fv_avg_flux<Real>(
        fxb[idx2(i,j,is,js,nicrx)], f2[idx2(i,j,is,jsd,nicrx)], wx);
}

template <typename Real>
__global__ void combine_fy_batch_kernel(
    Real* fy, const Real* fy2, const Real* yfx,
    int is, int isd, int js, int niq, int nirax, int ie, int je,
    int TFY, int TCRY, int nbatch,
    int use_mass, const Real* mfy)   // mfy is (is:ie,js:je+1), tile = TFY
{
    const int ni = ie - is + 1;
    const int per = ni * (je - js + 2);
    const long idx = static_cast<long>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (idx >= static_cast<long>(per) * nbatch) return;
    const int b = idx / per;
    const int loc = idx % per;
    const int i = is + (loc % ni);
    const int j = js + (loc / ni);
    Real* fyb = fy + (size_t)b*TFY;
    const Real* f2=fy2+(size_t)b*TCRY;
    const Real wy = use_mass ? (mfy + (size_t)b*TFY)[idx2(i,j,is,js,nirax)]
                             : (yfx + (size_t)b*TCRY)[idx2(i,j,isd,js,niq)];
    fyb[idx2(i,j,is,js,nirax)] = fv_avg_flux<Real>(
        fyb[idx2(i,j,is,js,nirax)], f2[idx2(i,j,isd,js,niq)], wy);
}

// ---------------------------------------------------------------------------
// Per-tile element counts and per-thread scratch sizing (host helpers).
// ---------------------------------------------------------------------------
struct FvTpTiles {
    int TQ, TCRX, TCRY, TRAX, TRAY, TFX, TFY, TQI, TQJ;
};
inline FvTpTiles fv_tp_tiles(int is,int ie,int js,int je,int isd,int ied,int jsd,int jed) {
    const int niq=ied-isd+1, nicrx=ie-is+2, nirax=ie-is+1;
    FvTpTiles t;
    t.TQ  = niq   * (jed-jsd+1);
    t.TCRX= nicrx * (jed-jsd+1);
    t.TCRY= niq   * (je-js+2);
    t.TRAX= nirax * (jed-jsd+1);
    t.TRAY= niq   * (je-js+1);
    t.TFX = nicrx * (je-js+1);
    t.TFY = nirax * (je-js+2);
    t.TQI = niq   * (je-js+1);
    t.TQJ = nirax * (jed-jsd+1);
    return t;
}

struct FvTpGpuScratch {
    size_t sreal_words, sbool_words, line_words;
    int rw, bw, lw;
    long max_threads;   // line-kernel threads = max(cols,rows per tile) * nbatch
};
inline FvTpGpuScratch fv_tp_2d_gpu_scratch(
    int is,int ie,int js,int je,int isd,int ied,int jsd,int jed, int nbatch)
{
    const int nj=je-js+1, ni=ie-is+1, nmax=nj>ni?nj:ni;
    const int lines_per_tile = (ied-isd+1 > jed-jsd+1) ? (ied-isd+1) : (jed-jsd+1);
    const int maxq = (jed-jsd+1 > ied-isd+1) ? (jed-jsd+1) : (ied-isd+1);
    const int maxf = (je-js+2 > ie-is+2) ? (je-js+2) : (ie-is+2);
    FvTpGpuScratch g;
    g.rw = yppm_scratch_real_words(nmax);
    g.bw = yppm_scratch_bool_words(nmax);
    g.lw = 2*maxq + 2*maxf;
    g.max_threads = static_cast<long>(lines_per_tile) * nbatch;
    g.sreal_words = static_cast<size_t>(g.max_threads) * g.rw;
    g.sbool_words = static_cast<size_t>(g.max_threads) * g.bw;
    g.line_words  = static_cast<size_t>(g.max_threads) * g.lw;
    return g;
}

// ---------------------------------------------------------------------------
// Device-pointer batched orchestrator: no alloc/copy/sync. Arrays hold nbatch
// tiles each (tile b at A + b*tileA). Kernels run on `stream` in sequence.
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
    const FvTpGpuScratch& g, const FvTpTiles& T, int nbatch,
    int is, int ie, int js, int je, int isd, int ied, int jsd, int jed,
    int npx, int npy, int hord, Real lim_fac,
    bool nested, int grid_type, bool sw, bool se, bool nw, bool ne,
    // Mass-flux combine variant (tracer transport): when use_mass, the flux
    // average uses mfx/mfy (each nbatch tiles, shapes (is:ie+1,js:je)/(is:ie,js:je+1)).
    bool use_mass = false, const Real* d_mfx = nullptr, const Real* d_mfy = nullptr,
    int tpb = 128, cudaStream_t stream = 0)
{
    const int ord_in = (hord == 10) ? 8 : hord;
    const int ord_ou = hord;
    const int niq = ied-isd+1, nicrx = ie-is+2, nirax = ie-is+1;
    auto nblk = [tpb](long count){ return (int)((count + tpb - 1) / tpb); };

    // 1. copy_corners (y)
    if (!nested)
        fv_copy_corners_kernel<Real><<<nblk(nbatch),tpb,0,stream>>>(
            d_q, isd, jsd, niq, npx, npy, 2, sw,se,nw,ne, T.TQ, nbatch);

    // 2. fy2 = yppm(q), columns isd..ied
    yppm_batch_kernel<Real><<<nblk((long)(ied-isd+1)*nbatch),tpb,0,stream>>>(
        d_fy2, isd, niq, T.TCRY, d_q, isd, niq, T.TQ,
        d_cry, T.TCRY, d_dya, T.TQ, isd, niq,
        isd, ied, js, je, jsd, jed, npx, npy, nested?1:0, grid_type, lim_fac, ord_in, nbatch,
        d_sreal, d_sbool, d_lines, g.rw, g.bw, g.lw);

    // 3. q_i
    qi_batch_kernel<Real><<<nblk((long)niq*(je-js+1)*nbatch),tpb,0,stream>>>(
        d_q_i, d_q, d_area, d_yfx, d_fy2, d_ra_y, isd, jsd, niq, js, je, ied,
        T.TQI, T.TQ, T.TCRY, T.TRAY, nbatch);

    // 4. fx = xppm(q_i), rows js..je
    xppm_batch_kernel<Real><<<nblk((long)(je-js+1)*nbatch),tpb,0,stream>>>(
        d_fx, js, nicrx, T.TFX, d_q_i, js, niq, T.TQI,
        d_crx, T.TCRX, d_dxa, T.TQ, jsd, nicrx, niq,
        js, je, is, ie, isd, ied, npx, npy, nested?1:0, grid_type, lim_fac, ord_ou, nbatch,
        d_sreal, d_sbool, d_lines, g.rw, g.bw, g.lw);

    // 5. copy_corners (x)
    if (!nested)
        fv_copy_corners_kernel<Real><<<nblk(nbatch),tpb,0,stream>>>(
            d_q, isd, jsd, niq, npx, npy, 1, sw,se,nw,ne, T.TQ, nbatch);

    // 6. fx2 = xppm(q), rows jsd..jed
    xppm_batch_kernel<Real><<<nblk((long)(jed-jsd+1)*nbatch),tpb,0,stream>>>(
        d_fx2, jsd, nicrx, T.TCRX, d_q, jsd, niq, T.TQ,
        d_crx, T.TCRX, d_dxa, T.TQ, jsd, nicrx, niq,
        jsd, jed, is, ie, isd, ied, npx, npy, nested?1:0, grid_type, lim_fac, ord_in, nbatch,
        d_sreal, d_sbool, d_lines, g.rw, g.bw, g.lw);

    // 7. q_j
    qj_batch_kernel<Real><<<nblk((long)nirax*(jed-jsd+1)*nbatch),tpb,0,stream>>>(
        d_q_j, d_q, d_area, d_xfx, d_fx2, d_ra_x, is, isd, jsd, niq, nicrx, nirax, ie, jed,
        T.TQJ, T.TQ, T.TCRX, T.TRAX, nbatch);

    // 8. fy = yppm(q_j), columns is..ie
    yppm_batch_kernel<Real><<<nblk((long)(ie-is+1)*nbatch),tpb,0,stream>>>(
        d_fy, is, nirax, T.TFY, d_q_j, is, nirax, T.TQJ,
        d_cry, T.TCRY, d_dya, T.TQ, isd, niq,
        is, ie, js, je, jsd, jed, npx, npy, nested?1:0, grid_type, lim_fac, ord_ou, nbatch,
        d_sreal, d_sbool, d_lines, g.rw, g.bw, g.lw);

    // 9. combine
    combine_fx_batch_kernel<Real><<<nblk((long)nicrx*(je-js+1)*nbatch),tpb,0,stream>>>(
        d_fx, d_fx2, d_xfx, is, js, jsd, nicrx, ie, je, T.TFX, T.TCRX, nbatch,
        use_mass ? 1 : 0, d_mfx);
    combine_fy_batch_kernel<Real><<<nblk((long)nirax*(je-js+2)*nbatch),tpb,0,stream>>>(
        d_fy, d_fy2, d_yfx, is, isd, js, niq, nirax, ie, je, T.TFY, T.TCRY, nbatch,
        use_mass ? 1 : 0, d_mfy);

    return cudaGetLastError();
}

// ---------------------------------------------------------------------------
// Host convenience: allocate device buffers for `nbatch` tiles, copy inputs
// in, run the batched orchestrator once, sync, copy fx/fy out, free. Host
// arrays hold nbatch tiles each (tile b at h_A + b*tileA).
// ---------------------------------------------------------------------------
template <typename Real>
inline cudaError_t fv_tp_2d_gpu(
    Real* h_q,
    const Real* h_crx, const Real* h_cry, const Real* h_xfx, const Real* h_yfx,
    const Real* h_ra_x, const Real* h_ra_y,
    const Real* h_area, const Real* h_dxa, const Real* h_dya,
    Real* h_fx, Real* h_fy, int nbatch,
    int is, int ie, int js, int je, int isd, int ied, int jsd, int jed,
    int npx, int npy, int hord, Real lim_fac,
    bool nested, int grid_type, bool sw, bool se, bool nw, bool ne)
{
    const FvTpTiles T = fv_tp_tiles(is,ie,js,je,isd,ied,jsd,jed);
    const FvTpGpuScratch g = fv_tp_2d_gpu_scratch(is,ie,js,je,isd,ied,jsd,jed,nbatch);
    const size_t B = (size_t)nbatch;

    Real *q=nullptr,*crx=nullptr,*cry=nullptr,*xfx=nullptr,*yfx=nullptr,
         *ra_x=nullptr,*ra_y=nullptr,*area=nullptr,*dxa=nullptr,*dya=nullptr,
         *fx=nullptr,*fy=nullptr,*qi=nullptr,*qj=nullptr,*fx2=nullptr,*fy2=nullptr,
         *sr=nullptr,*lines=nullptr;
    bool *sb=nullptr;
    cudaError_t e = cudaSuccess;

#define FV_TRY(call) do { e=(call); if(e!=cudaSuccess) goto cleanup; } while(0)
    FV_TRY(cudaMalloc(&q,   B*T.TQ  *sizeof(Real)));
    FV_TRY(cudaMalloc(&crx, B*T.TCRX*sizeof(Real)));
    FV_TRY(cudaMalloc(&cry, B*T.TCRY*sizeof(Real)));
    FV_TRY(cudaMalloc(&xfx, B*T.TCRX*sizeof(Real)));
    FV_TRY(cudaMalloc(&yfx, B*T.TCRY*sizeof(Real)));
    FV_TRY(cudaMalloc(&ra_x,B*T.TRAX*sizeof(Real)));
    FV_TRY(cudaMalloc(&ra_y,B*T.TRAY*sizeof(Real)));
    FV_TRY(cudaMalloc(&area,B*T.TQ  *sizeof(Real)));
    FV_TRY(cudaMalloc(&dxa, B*T.TQ  *sizeof(Real)));
    FV_TRY(cudaMalloc(&dya, B*T.TQ  *sizeof(Real)));
    FV_TRY(cudaMalloc(&fx,  B*T.TFX *sizeof(Real)));
    FV_TRY(cudaMalloc(&fy,  B*T.TFY *sizeof(Real)));
    FV_TRY(cudaMalloc(&qi,  B*T.TQI *sizeof(Real)));
    FV_TRY(cudaMalloc(&qj,  B*T.TQJ *sizeof(Real)));
    FV_TRY(cudaMalloc(&fx2, B*T.TCRX*sizeof(Real)));
    FV_TRY(cudaMalloc(&fy2, B*T.TCRY*sizeof(Real)));
    FV_TRY(cudaMalloc(&sr,  g.sreal_words*sizeof(Real)));
    FV_TRY(cudaMalloc(&sb,  g.sbool_words*sizeof(bool)));
    FV_TRY(cudaMalloc(&lines, g.line_words*sizeof(Real)));

    FV_TRY(cudaMemcpy(q,   h_q,   B*T.TQ  *sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(crx, h_crx, B*T.TCRX*sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(cry, h_cry, B*T.TCRY*sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(xfx, h_xfx, B*T.TCRX*sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(yfx, h_yfx, B*T.TCRY*sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(ra_x,h_ra_x,B*T.TRAX*sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(ra_y,h_ra_y,B*T.TRAY*sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(area,h_area,B*T.TQ  *sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(dxa, h_dxa, B*T.TQ  *sizeof(Real), cudaMemcpyHostToDevice));
    FV_TRY(cudaMemcpy(dya, h_dya, B*T.TQ  *sizeof(Real), cudaMemcpyHostToDevice));

    e = fv_tp_2d_gpu_launch<Real>(
        q, crx, cry, xfx, yfx, ra_x, ra_y, area, dxa, dya, fx, fy,
        qi, qj, fx2, fy2, sr, sb, lines, g, T, nbatch,
        is,ie,js,je,isd,ied,jsd,jed, npx,npy, hord, lim_fac,
        nested, grid_type, sw, se, nw, ne);
    if (e != cudaSuccess) goto cleanup;

    FV_TRY(cudaDeviceSynchronize());
    FV_TRY(cudaMemcpy(h_fx, fx, B*T.TFX*sizeof(Real), cudaMemcpyDeviceToHost));
    FV_TRY(cudaMemcpy(h_fy, fy, B*T.TFY*sizeof(Real), cudaMemcpyDeviceToHost));
#undef FV_TRY

cleanup:
    cudaFree(q);cudaFree(crx);cudaFree(cry);cudaFree(xfx);cudaFree(yfx);
    cudaFree(ra_x);cudaFree(ra_y);cudaFree(area);cudaFree(dxa);cudaFree(dya);
    cudaFree(fx);cudaFree(fy);cudaFree(qi);cudaFree(qj);cudaFree(fx2);cudaFree(fy2);
    cudaFree(sr);cudaFree(sb);cudaFree(lines);
    return e;
}

} // namespace fv3
