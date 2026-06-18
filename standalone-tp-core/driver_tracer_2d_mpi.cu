// driver_tracer_2d_mpi.cu — multi-rank / multi-GPU tracer transport (Phase A).
//
// 1-D decomposition in i across MPI ranks (one GPU per rank), doubly-periodic
// flat domain (nested=true: pure interior stencil + halos, no cube corners).
// Each step:  exchange q halo (MPI in i, local periodic in j)  ->
//             tracer_2d_gpu_launch (batched over npz*nq).
// Winds/fluxes are known analytic periodic fields, initialized with correct
// halos, so only q needs runtime exchange (it is updated each step).
//
//   Usage: mpirun -np <N> ./tracer-2d-driver-mpi <GX> <ny> <npz> <nq> <iters>
//     GX = GLOBAL i-extent (must be divisible by N); nx_local = GX/N.
//
// Decomposition-invariance (correctness): run the SAME GX at np=1 and np=N;
// the global sum(q) must match. Strong scaling: fix GX, vary N -> time drops.
// Weak scaling: set GX = nx_base*N, vary N -> time stays flat.
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

#include <cuda_runtime.h>
#include <mpi.h>

#include "tracer_2d_gpu.cuh"
#include "halo_exchange_gpu.cuh"

#define CK(c) do{ cudaError_t _e=(c); if(_e!=cudaSuccess){ \
    std::fprintf(stderr,"[%d] CUDA %s:%d: %s\n",rank,__FILE__,__LINE__,cudaGetErrorString(_e)); \
    MPI_Abort(MPI_COMM_WORLD,1);} }while(0)

using Real = float;

int main(int argc, char** argv) {
    MPI_Init(&argc,&argv);
    int rank=0,nranks=1;
    MPI_Comm_rank(MPI_COMM_WORLD,&rank);
    MPI_Comm_size(MPI_COMM_WORLD,&nranks);

    // one GPU per rank (by node-local rank)
    MPI_Comm loc; MPI_Comm_split_type(MPI_COMM_WORLD,MPI_COMM_TYPE_SHARED,rank,MPI_INFO_NULL,&loc);
    int lrank=0; MPI_Comm_rank(loc,&lrank); MPI_Comm_free(&loc);
    int ndev=0; CK(cudaGetDeviceCount(&ndev));
    if(ndev<1){ if(rank==0) std::fprintf(stderr,"no GPU\n"); MPI_Abort(MPI_COMM_WORLD,1);}
    CK(cudaSetDevice(lrank % ndev));

    if (argc!=6){ if(rank==0) std::fprintf(stderr,"Usage: %s <GX> <ny> <npz> <nq> <iters>\n",argv[0]); MPI_Finalize(); return 2; }
    const int GX=atoi(argv[1]), ny=atoi(argv[2]), npz=atoi(argv[3]), nq=atoi(argv[4]), iters=atoi(argv[5]);
    if (GX % nranks != 0){ if(rank==0) std::fprintf(stderr,"GX (%d) must be divisible by nranks (%d)\n",GX,nranks); MPI_Finalize(); return 2; }
    const int nx = GX / nranks;                 // interior columns per rank
    const int ng=3, hord=8; const Real lim_fac=1;
    const int is=1, ie=nx, js=1, je=ny, isd=is-ng, ied=ie+ng, jsd=js-ng, jed=je+ng;
    const int niq=ied-isd+1, njq=jed-jsd+1, nicrx=ie-is+2, nirax=ie-is+1;
    const int left=(rank-1+nranks)%nranks, right=(rank+1)%nranks;

    const fv3::FvTpTiles T = fv3::fv_tp_tiles(is,ie,js,je,isd,ied,jsd,jed);
    const fv3::FvTpGpuScratch g = fv3::fv_tp_2d_gpu_scratch(is,ie,js,je,isd,ied,jsd,jed, npz*nq);
    const int Tcx=T.TCRX, Tcy=T.TCRY, Tmfx=T.TFX, Tmfy=T.TFY, TQ=T.TQ;
    const long B = (long)npz*nq;

    // ---- host inputs: analytic doubly-periodic; q interior set, halo = 0 ----
    std::vector<Real> q((size_t)B*TQ, 0.f), dp1((size_t)npz*TQ, 1.f);
    std::vector<Real> cx((size_t)npz*Tcx), cy((size_t)npz*Tcy),
                      mfx((size_t)npz*Tmfx,0.5f), mfy((size_t)npz*Tmfy,0.5f);
    const double TP=6.283185307179586;
    auto sgi=[&](int i){ return (double)rank*nx + i; };       // global i (periodic mod GX)
    for (int k=0;k<npz;++k){
        for (int j=jsd;j<=jed;++j) for (int i=is;i<=ie+1;++i)
            cx[(size_t)k*Tcx+fv3::idx2(i,j,is,jsd,nicrx)] = 0.3f + 0.1f*std::sin(TP*sgi(i)/GX);
        for (int j=js;j<=je+1;++j) for (int i=isd;i<=ied;++i)
            cy[(size_t)k*Tcy+fv3::idx2(i,j,isd,js,niq)]   = 0.3f + 0.1f*std::sin(TP*(double)j/ny);
        for (int iq=0;iq<nq;++iq)
            for (int j=js;j<=je;++j) for (int i=is;i<=ie;++i)   // interior only; halo stays 0 -> filled by exchange
                q[((size_t)iq*npz+k)*TQ+fv3::idx2(i,j,isd,jsd,niq)] =
                    1.0f + 0.3f*std::sin(TP*sgi(i)/GX) + 0.2f*std::sin(TP*(double)j/ny) + 0.05f*iq + 0.01f*k;
    }

    fv3::TracerGpuBufs<Real> Bf{};
    CK(fv3::tracer_2d_gpu_setup<Real>(Bf, q.data(), dp1.data(), cx.data(), cy.data(), mfx.data(), mfy.data(),
        T, g, npz, nq, is,ie,js,je,isd,ied,jsd,jed));

    // halo buffers (B tiles, ng*ny each, both directions)
    const long cnt = B*ng*ny;
    Real *ws,*es,*wr,*er;
    CK(cudaMalloc(&ws,cnt*sizeof(Real))); CK(cudaMalloc(&es,cnt*sizeof(Real)));
    CK(cudaMalloc(&wr,cnt*sizeof(Real))); CK(cudaMalloc(&er,cnt*sizeof(Real)));
    const int tpb=128; const int nyb=(int)(((long)B*niq*ng+tpb-1)/tpb);

    auto step=[&](){
        fv3::halo_exchange_x_batched<Real>(Bf.q,(int)B,TQ,nx,ny,ng,ws,es,wr,er,left,right,MPI_COMM_WORLD,MPI_FLOAT);
        fv3::halo_periodic_y_batched<Real><<<nyb,tpb>>>(Bf.q,(int)B,TQ,niq,ng,ny);
        fv3::tracer_2d_gpu_launch<Real>(
            Bf.q,Bf.cx_b,Bf.cy_b,Bf.mfx_b,Bf.mfy_b,Bf.rax_b,Bf.ray_b,
            Bf.area_b,Bf.dxa_b,Bf.dya_b,Bf.fx,Bf.fy,Bf.qi,Bf.qj,Bf.fx2,Bf.fy2,
            Bf.sr,Bf.sb,Bf.lines,Bf.dp1,Bf.dp2_lev,g,T,npz,nq,
            is,ie,js,je,isd,ied,jsd,jed, nx+1,ny+1,hord,lim_fac,
            /*nested*/true,3, false,false,false,false);
    };

    step(); CK(cudaDeviceSynchronize());              // warm-up
    MPI_Barrier(MPI_COMM_WORLD);
    const double t0=MPI_Wtime();
    for (int it=0;it<iters;++it) step();
    CK(cudaDeviceSynchronize());
    MPI_Barrier(MPI_COMM_WORLD);
    const double secs=MPI_Wtime()-t0;

    CK(cudaMemcpy(q.data(),Bf.q,(size_t)B*TQ*sizeof(Real),cudaMemcpyDeviceToHost));
    double lsum=0.0;
    for (int iq=0;iq<nq;++iq) for (int k=0;k<npz;++k) for (int j=js;j<=je;++j) for (int i=is;i<=ie;++i)
        lsum += (double)q[((size_t)iq*npz+k)*TQ+fv3::idx2(i,j,isd,jsd,niq)];
    double gsum=0.0; MPI_Reduce(&lsum,&gsum,1,MPI_DOUBLE,MPI_SUM,0,MPI_COMM_WORLD);

    if (rank==0){
        std::printf("tracer_2d MPI driver: nranks=%d GX=%d nx_local=%d ny=%d npz=%d nq=%d iters=%d\n",
                    nranks,GX,nx,ny,npz,nq,iters);
        std::printf("time taken: %.6f s  (%.4f ms/iter)\n", secs, secs/iters*1000.0);
        std::printf("global sum(q): %.10e   [must match across nranks for same GX]\n", gsum);
    }
    cudaFree(ws);cudaFree(es);cudaFree(wr);cudaFree(er);
    fv3::tracer_2d_gpu_free<Real>(Bf);
    MPI_Finalize();
    return 0;
}
