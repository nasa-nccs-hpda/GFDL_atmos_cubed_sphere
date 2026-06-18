// tracer_2d_gpu.cuh — device-resident GPU tracer transport (nsplt=1, unit grid).
//
// Batches the per-(level,tracer) fv_tp_2d over the full B = npz*nq dimension —
// the tracer-scaling parallelism. The q array layout q(i,j,k,iq) places tile
// b = iq*npz + k at b*TQ, so q feeds the batched orchestrator directly. The
// per-level winds (cx/cy/mfx/mfy) and prepped ra_x/ra_y are replicated across
// the nq tracers into the batch; dp1/dp2 stay per level and are indexed by
// k = b % npz in the update.
//
// Flow:  ra_x/ra_y/dp2 prep (per level) -> replicate winds -> fv_tp_2d_gpu_launch
//        (mass variant, B tiles) -> tracer update kernel.
//
// Reuses fv_tp_2d_gpu.cuh entirely for the transport; the only new kernels are
// the prep and the tracer update. Unit grid: xfx=cx, yfx=cy, area=dxa=dya=1,
// rarea=1. nsplt=1, no MPI halo (host-side seam, deferred).
#pragma once

#include <cuda_runtime.h>
#include <cstddef>

#include "tracer_2d.hpp"     // trc_div, trc_update, TracerTiles
#include "fv_tp_2d_gpu.cuh"  // fv_tp_2d_gpu_launch, FvTpTiles, FvTpGpuScratch

namespace fv3 {

template <typename Real>
__global__ void fill_kernel(Real* p, Real v, size_t n) {
    const size_t i = (size_t)blockIdx.x*blockDim.x + threadIdx.x;
    if (i < n) p[i] = v;
}

// Per-level ra_x = 1 + (cx(i)-cx(i+1))  over (is:ie, jsd:jed), npz levels.
template <typename Real>
__global__ void rax_kernel(Real* rax, const Real* cx, int is,int ie,int jsd,int jed,
                           int nicrx,int nirax,int njq,int npz) {
    const int per = nirax * njq;
    const long idx = (long)blockIdx.x*blockDim.x + threadIdx.x;
    if (idx >= (long)per*npz) return;
    const int k = idx/per, loc = idx%per;
    const int i = is + loc%nirax, j = jsd + loc/nirax;
    const Real* cxk = cx + (size_t)k*(nicrx*njq);
    rax[(size_t)k*per + loc] = Real(1) + (cxk[idx2(i,j,is,jsd,nicrx)] - cxk[idx2(i+1,j,is,jsd,nicrx)]);
}

// Per-level ra_y = 1 + (cy(j)-cy(j+1))  over (isd:ied, js:je), npz levels.
template <typename Real>
__global__ void ray_kernel(Real* ray, const Real* cy, int isd,int ied,int js,int je,
                           int niq,int npz) {
    const int per = niq * (je-js+1);
    const long idx = (long)blockIdx.x*blockDim.x + threadIdx.x;
    if (idx >= (long)per*npz) return;
    const int k = idx/per, loc = idx%per;
    const int i = isd + loc%niq, j = js + loc/niq;
    const Real* cyk = cy + (size_t)k*(niq*(je-js+2));
    ray[(size_t)k*per + loc] = Real(1) + (cyk[idx2(i,j,isd,js,niq)] - cyk[idx2(i,j+1,isd,js,niq)]);
}

// Per-level dp2 = dp1 + div(mfx,mfy)  over (is:ie, js:je), npz levels.
template <typename Real>
__global__ void dp2_kernel(Real* dp2, const Real* dp1, const Real* mfx, const Real* mfy,
                           int is,int ie,int js,int je,int isd,int jsd,
                           int niq,int njq,int nicrx,int nirax,int npz) {
    const int ndp2 = ie-is+1, per = ndp2*(je-js+1);
    const long idx = (long)blockIdx.x*blockDim.x + threadIdx.x;
    if (idx >= (long)per*npz) return;
    const int k = idx/per, loc = idx%per;
    const int i = is + loc%ndp2, j = js + loc/ndp2;
    const Real* dp1k = dp1 + (size_t)k*(niq*njq);
    const Real* mfxk = mfx + (size_t)k*(nicrx*(je-js+1));
    const Real* mfyk = mfy + (size_t)k*(nirax*(je-js+2));
    dp2[(size_t)k*per + loc] = dp1k[idx2(i,j,isd,jsd,niq)] + trc_div<Real>(
        mfxk[idx2(i,j,is,js,nicrx)], mfxk[idx2(i+1,j,is,js,nicrx)],
        mfyk[idx2(i,j,is,js,nirax)], mfyk[idx2(i,j+1,is,js,nirax)]);
}

// Tracer update over B = npz*nq tiles: q = (q*dp1 + div(fx,fy))/dp2.
// fx/fy are per-batch (b); dp1/dp2 per level k = b % npz.
template <typename Real>
__global__ void tracer_update_kernel(
    Real* q, const Real* fx, const Real* fy, const Real* dp1, const Real* dp2,
    int is,int ie,int js,int je,int isd,int jsd,
    int niq,int nicrx,int nirax, int TQ,int TFX,int TFY,int Tdp1,int Tdp2,
    int npz, int B)
{
    const int ndp2 = ie-is+1, per = ndp2*(je-js+1);
    const long idx = (long)blockIdx.x*blockDim.x + threadIdx.x;
    if (idx >= (long)per*B) return;
    const int b = idx/per, loc = idx%per;
    const int k = b % npz;
    const int i = is + loc%ndp2, j = js + loc/ndp2;
    Real*       qb  = q  + (size_t)b*TQ;
    const Real* fxb = fx + (size_t)b*TFX;
    const Real* fyb = fy + (size_t)b*TFY;
    const Real* dp1k= dp1+ (size_t)k*Tdp1;
    const Real* dp2k= dp2+ (size_t)k*Tdp2;
    const Real fd = trc_div<Real>(
        fxb[idx2(i,j,is,js,nicrx)], fxb[idx2(i+1,j,is,js,nicrx)],
        fyb[idx2(i,j,is,js,nirax)], fyb[idx2(i,j+1,is,js,nirax)]);
    qb[idx2(i,j,isd,jsd,niq)] = trc_update<Real>(
        qb[idx2(i,j,isd,jsd,niq)], dp1k[idx2(i,j,isd,jsd,niq)], fd, Real(1),
        dp2k[(i-is) + ndp2*(j-js)]);
}

// ---------------------------------------------------------------------------
// Device-pointer launch: transport + update for B = npz*nq tiles.
// Assumes batch winds (cx/cy/mfx/mfy/ra_x/ra_y, unit metrics) are already
// replicated to B tiles, and per-level dp1/dp2 are computed. No alloc/sync.
// ---------------------------------------------------------------------------
template <typename Real>
inline cudaError_t tracer_2d_gpu_launch(
    Real* d_q, const Real* d_cx_b, const Real* d_cy_b,
    const Real* d_mfx_b, const Real* d_mfy_b,
    const Real* d_rax_b, const Real* d_ray_b,
    const Real* d_area_b, const Real* d_dxa_b, const Real* d_dya_b,
    Real* d_fx, Real* d_fy, Real* d_qi, Real* d_qj, Real* d_fx2, Real* d_fy2,
    Real* d_sr, bool* d_sb, Real* d_lines,
    const Real* d_dp1, const Real* d_dp2,
    const FvTpGpuScratch& g, const FvTpTiles& T, int npz, int nq,
    int is,int ie,int js,int je,int isd,int ied,int jsd,int jed,
    int npx,int npy,int hord,Real lim_fac,bool nested,int grid_type,
    bool sw,bool se,bool nw,bool ne, int tpb=128, cudaStream_t stream=0)
{
    const int B = npz*nq;
    const int niq=ied-isd+1, nicrx=ie-is+2, nirax=ie-is+1;
    const int Tdp1 = niq*(jed-jsd+1), Tdp2 = (ie-is+1)*(je-js+1);

    // Batched mass-flux fv_tp_2d over all (level,tracer) tiles.
    cudaError_t e = fv_tp_2d_gpu_launch<Real>(
        d_q, d_cx_b, d_cy_b, d_cx_b, d_cy_b, d_rax_b, d_ray_b,
        d_area_b, d_dxa_b, d_dya_b, d_fx, d_fy,
        d_qi, d_qj, d_fx2, d_fy2, d_sr, d_sb, d_lines, g, T, B,
        is,ie,js,je,isd,ied,jsd,jed, npx,npy,hord,lim_fac,
        nested,grid_type,sw,se,nw,ne, /*use_mass*/true, d_mfx_b, d_mfy_b, tpb, stream);
    if (e != cudaSuccess) return e;

    const long upd = (long)(ie-is+1)*(je-js+1)*B;
    tracer_update_kernel<Real><<<(int)((upd+tpb-1)/tpb),tpb,0,stream>>>(
        d_q, d_fx, d_fy, d_dp1, d_dp2, is,ie,js,je,isd,jsd,
        niq,nicrx,nirax, T.TQ,T.TFX,T.TFY,Tdp1,Tdp2, npz, B);
    return cudaGetLastError();
}

// Bundle of device buffers for the tracer GPU path (alloc once, reuse).
template <typename Real>
struct TracerGpuBufs {
    Real *cx,*cy,*mfx,*mfy,*dp1,*rax_lev,*ray_lev,*dp2_lev;        // per level (npz)
    Real *cx_b,*cy_b,*mfx_b,*mfy_b,*rax_b,*ray_b,*area_b,*dxa_b,*dya_b; // batch (B)
    Real *q,*fx,*fy,*qi,*qj,*fx2,*fy2,*sr,*lines;                  // batch (B) + scratch
    bool *sb;
};

// Allocate, copy per-level inputs, run prep kernels, and replicate winds to the
// batch. Call once; then time tracer_2d_gpu_launch repeatedly. Free with
// tracer_2d_gpu_free.  Host inputs are per-level arrays (npz tiles).
template <typename Real>
inline cudaError_t tracer_2d_gpu_setup(
    TracerGpuBufs<Real>& B_, const Real* h_q, const Real* h_dp1,
    const Real* h_cx, const Real* h_cy, const Real* h_mfx, const Real* h_mfy,
    const FvTpTiles& T, const FvTpGpuScratch& g, int npz, int nq,
    int is,int ie,int js,int je,int isd,int ied,int jsd,int jed, int tpb=128)
{
    const int niq=ied-isd+1, njq=jed-jsd+1, nicrx=ie-is+2, nirax=ie-is+1;
    const int Tdp2 = (ie-is+1)*(je-js+1);
    const long B = (long)npz*nq;
    cudaError_t e = cudaSuccess;
#define TR_TRY(c) do{ e=(c); if(e!=cudaSuccess) return e; }while(0)
    // per-level
    TR_TRY(cudaMalloc(&B_.cx,  (size_t)npz*T.TCRX*sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.cy,  (size_t)npz*T.TCRY*sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.mfx, (size_t)npz*T.TFX *sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.mfy, (size_t)npz*T.TFY *sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.dp1, (size_t)npz*T.TQ  *sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.rax_lev,(size_t)npz*T.TRAX*sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.ray_lev,(size_t)npz*T.TRAY*sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.dp2_lev,(size_t)npz*Tdp2  *sizeof(Real)));
    // batch
    TR_TRY(cudaMalloc(&B_.cx_b, (size_t)B*T.TCRX*sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.cy_b, (size_t)B*T.TCRY*sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.mfx_b,(size_t)B*T.TFX *sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.mfy_b,(size_t)B*T.TFY *sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.rax_b,(size_t)B*T.TRAX*sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.ray_b,(size_t)B*T.TRAY*sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.area_b,(size_t)B*T.TQ *sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.dxa_b, (size_t)B*T.TQ *sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.dya_b, (size_t)B*T.TQ *sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.q,   (size_t)B*T.TQ  *sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.fx,  (size_t)B*T.TFX *sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.fy,  (size_t)B*T.TFY *sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.qi,  (size_t)B*T.TQI *sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.qj,  (size_t)B*T.TQJ *sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.fx2, (size_t)B*T.TCRX*sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.fy2, (size_t)B*T.TCRY*sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.sr,  g.sreal_words*sizeof(Real)));
    TR_TRY(cudaMalloc(&B_.sb,  g.sbool_words*sizeof(bool)));
    TR_TRY(cudaMalloc(&B_.lines, g.line_words*sizeof(Real)));

    TR_TRY(cudaMemcpy(B_.cx, h_cx, (size_t)npz*T.TCRX*sizeof(Real), cudaMemcpyHostToDevice));
    TR_TRY(cudaMemcpy(B_.cy, h_cy, (size_t)npz*T.TCRY*sizeof(Real), cudaMemcpyHostToDevice));
    TR_TRY(cudaMemcpy(B_.mfx,h_mfx,(size_t)npz*T.TFX *sizeof(Real), cudaMemcpyHostToDevice));
    TR_TRY(cudaMemcpy(B_.mfy,h_mfy,(size_t)npz*T.TFY *sizeof(Real), cudaMemcpyHostToDevice));
    TR_TRY(cudaMemcpy(B_.dp1,h_dp1,(size_t)npz*T.TQ  *sizeof(Real), cudaMemcpyHostToDevice));
    TR_TRY(cudaMemcpy(B_.q,  h_q,  (size_t)B*T.TQ    *sizeof(Real), cudaMemcpyHostToDevice));

    // prep (per level)
    auto nb=[tpb](long c){return (int)((c+tpb-1)/tpb);};
    rax_kernel<Real><<<nb((long)nirax*njq*npz),tpb>>>(B_.rax_lev,B_.cx,is,ie,jsd,jed,nicrx,nirax,njq,npz);
    ray_kernel<Real><<<nb((long)niq*(je-js+1)*npz),tpb>>>(B_.ray_lev,B_.cy,isd,ied,js,je,niq,npz);
    dp2_kernel<Real><<<nb((long)(ie-is+1)*(je-js+1)*npz),tpb>>>(
        B_.dp2_lev,B_.dp1,B_.mfx,B_.mfy,is,ie,js,je,isd,jsd,niq,njq,nicrx,nirax,npz);

    // replicate per-level winds across nq into the batch
    for (int iq=0; iq<nq; ++iq) {
        const size_t o = (size_t)iq*npz;
        TR_TRY(cudaMemcpy(B_.cx_b + o*T.TCRX, B_.cx, (size_t)npz*T.TCRX*sizeof(Real), cudaMemcpyDeviceToDevice));
        TR_TRY(cudaMemcpy(B_.cy_b + o*T.TCRY, B_.cy, (size_t)npz*T.TCRY*sizeof(Real), cudaMemcpyDeviceToDevice));
        TR_TRY(cudaMemcpy(B_.mfx_b+ o*T.TFX,  B_.mfx,(size_t)npz*T.TFX *sizeof(Real), cudaMemcpyDeviceToDevice));
        TR_TRY(cudaMemcpy(B_.mfy_b+ o*T.TFY,  B_.mfy,(size_t)npz*T.TFY *sizeof(Real), cudaMemcpyDeviceToDevice));
        TR_TRY(cudaMemcpy(B_.rax_b+ o*T.TRAX, B_.rax_lev,(size_t)npz*T.TRAX*sizeof(Real), cudaMemcpyDeviceToDevice));
        TR_TRY(cudaMemcpy(B_.ray_b+ o*T.TRAY, B_.ray_lev,(size_t)npz*T.TRAY*sizeof(Real), cudaMemcpyDeviceToDevice));
    }
    fill_kernel<Real><<<nb((long)B*T.TQ),tpb>>>(B_.area_b, Real(1), (size_t)B*T.TQ);
    fill_kernel<Real><<<nb((long)B*T.TQ),tpb>>>(B_.dxa_b,  Real(1), (size_t)B*T.TQ);
    fill_kernel<Real><<<nb((long)B*T.TQ),tpb>>>(B_.dya_b,  Real(1), (size_t)B*T.TQ);
#undef TR_TRY
    return cudaGetLastError();
}

template <typename Real>
inline void tracer_2d_gpu_free(TracerGpuBufs<Real>& B_) {
    cudaFree(B_.cx);cudaFree(B_.cy);cudaFree(B_.mfx);cudaFree(B_.mfy);cudaFree(B_.dp1);
    cudaFree(B_.rax_lev);cudaFree(B_.ray_lev);cudaFree(B_.dp2_lev);
    cudaFree(B_.cx_b);cudaFree(B_.cy_b);cudaFree(B_.mfx_b);cudaFree(B_.mfy_b);
    cudaFree(B_.rax_b);cudaFree(B_.ray_b);cudaFree(B_.area_b);cudaFree(B_.dxa_b);cudaFree(B_.dya_b);
    cudaFree(B_.q);cudaFree(B_.fx);cudaFree(B_.fy);cudaFree(B_.qi);cudaFree(B_.qj);
    cudaFree(B_.fx2);cudaFree(B_.fy2);cudaFree(B_.sr);cudaFree(B_.sb);cudaFree(B_.lines);
}

// One-shot host convenience: setup -> launch -> copy q back -> free.
template <typename Real>
inline cudaError_t tracer_2d_gpu(
    Real* h_q, const Real* h_dp1, const Real* h_cx, const Real* h_cy,
    const Real* h_mfx, const Real* h_mfy,
    int is,int ie,int js,int je,int isd,int ied,int jsd,int jed,
    int npx,int npy,int npz,int nq,int hord,Real lim_fac,
    bool nested,int grid_type,bool sw,bool se,bool nw,bool ne)
{
    const FvTpTiles T = fv_tp_tiles(is,ie,js,je,isd,ied,jsd,jed);
    const FvTpGpuScratch g = fv_tp_2d_gpu_scratch(is,ie,js,je,isd,ied,jsd,jed, npz*nq);
    TracerGpuBufs<Real> B_{};
    cudaError_t e = tracer_2d_gpu_setup<Real>(B_, h_q, h_dp1, h_cx, h_cy, h_mfx, h_mfy,
        T, g, npz, nq, is,ie,js,je,isd,ied,jsd,jed);
    if (e == cudaSuccess)
        e = tracer_2d_gpu_launch<Real>(
            B_.q, B_.cx_b, B_.cy_b, B_.mfx_b, B_.mfy_b, B_.rax_b, B_.ray_b,
            B_.area_b, B_.dxa_b, B_.dya_b, B_.fx, B_.fy, B_.qi, B_.qj, B_.fx2, B_.fy2,
            B_.sr, B_.sb, B_.lines, B_.dp1, B_.dp2_lev, g, T, npz, nq,
            is,ie,js,je,isd,ied,jsd,jed, npx,npy,hord,lim_fac,nested,grid_type,sw,se,nw,ne);
    if (e == cudaSuccess) e = cudaDeviceSynchronize();
    if (e == cudaSuccess)
        e = cudaMemcpy(h_q, B_.q, (size_t)npz*nq*T.TQ*sizeof(Real), cudaMemcpyDeviceToHost);
    tracer_2d_gpu_free<Real>(B_);
    return e;
}

} // namespace fv3
