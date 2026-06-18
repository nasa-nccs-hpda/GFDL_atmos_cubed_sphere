// driver_tracer_2d_gpu.cu — device-resident GPU benchmark for tracer_2d.
//   Usage: tracer-2d-driver-gpu <resolution> <iterations> [npz] [nq]
// Sets up the batch (npz*nq tiles) once on the device, then times <iterations>
// batched transport+update launches. Reports time and a q checksum
// (cross-checks the CPU driver at matching res/npz/nq).
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <vector>

#include <cuda_runtime.h>

#include "tracer_2d.hpp"
#include "tracer_2d_gpu.cuh"

#define CUDA_CHECK(c) do{ cudaError_t _e=(c); if(_e!=cudaSuccess){ \
    std::fprintf(stderr,"CUDA error %s:%d: %s\n",__FILE__,__LINE__,cudaGetErrorString(_e)); std::exit(1);} }while(0)

using Real = float;

int main(int argc, char** argv) {
    if (argc < 3 || argc > 5) { std::fprintf(stderr,"Usage: %s <res> <iters> [npz] [nq]\n",argv[0]); return 2; }
    const int n=std::atoi(argv[1]), n_iter=std::atoi(argv[2]);
    const int npz = (argc>=4)?std::atoi(argv[3]):64;
    const int nq  = (argc>=5)?std::atoi(argv[4]):4;
    if (n<1||n_iter<1||npz<1||nq<1){ std::fprintf(stderr,"args must be >= 1\n"); return 2; }

    const int ng=3, hord=8; const Real lim_fac=1;
    const int is=1, ie=n, js=1, je=n, isd=is-ng, ied=ie+ng, jsd=js-ng, jed=je+ng;
    const int niq=ied-isd+1, njq=jed-jsd+1, nicrx=ie-is+2, nirax=ie-is+1;
    const int Tq=niq*njq, Tcx=nicrx*njq, Tcy=niq*(je-js+2), Tmfx=nicrx*(je-js+1), Tmfy=nirax*(je-js+2);

    std::vector<Real> q((size_t)npz*nq*Tq), dp1((size_t)npz*Tq);
    std::vector<Real> cx((size_t)npz*Tcx), cy((size_t)npz*Tcy), mfx((size_t)npz*Tmfx), mfy((size_t)npz*Tmfy);
    const float PI=3.1415927f;
    for (int k=0;k<npz;++k){
        for (int j=jsd;j<=jed;++j) for (int i=is;i<=ie+1;++i) cx[(size_t)k*Tcx+fv3::idx2(i,j,is,jsd,nicrx)]=0.4f+0.001f*(i+0.5f*j);
        for (int j=js;j<=je+1;++j) for (int i=isd;i<=ied;++i) cy[(size_t)k*Tcy+fv3::idx2(i,j,isd,js,niq)]=0.4f+0.001f*(0.5f*i+j);
        for (int j=js;j<=je;++j) for (int i=is;i<=ie+1;++i) mfx[(size_t)k*Tmfx+fv3::idx2(i,j,is,js,nicrx)]=0.5f+0.002f*i;
        for (int j=js;j<=je+1;++j) for (int i=is;i<=ie;++i) mfy[(size_t)k*Tmfy+fv3::idx2(i,j,is,js,nirax)]=0.5f+0.002f*j;
        for (int j=jsd;j<=jed;++j) for (int i=isd;i<=ied;++i) dp1[(size_t)k*Tq+fv3::idx2(i,j,isd,jsd,niq)]=1.0f+0.01f*k;
        for (int iq=0;iq<nq;++iq) for (int j=jsd;j<=jed;++j) for (int i=isd;i<=ied;++i)
            q[((size_t)iq*npz+k)*Tq+fv3::idx2(i,j,isd,jsd,niq)]=1.0f+0.5f*std::sin(PI*float(i*j)/float(n*n))+0.05f*iq+0.005f*k;
    }

    std::printf("tracer_2d GPU driver: resolution=%d iterations=%d npz=%d nq=%d (batch=%d)\n", n, n_iter, npz, nq, npz*nq);

    const fv3::FvTpTiles T = fv3::fv_tp_tiles(is,ie,js,je,isd,ied,jsd,jed);
    const fv3::FvTpGpuScratch g = fv3::fv_tp_2d_gpu_scratch(is,ie,js,je,isd,ied,jsd,jed, npz*nq);
    fv3::TracerGpuBufs<Real> B_{};
    CUDA_CHECK(fv3::tracer_2d_gpu_setup<Real>(B_, q.data(), dp1.data(), cx.data(), cy.data(), mfx.data(), mfy.data(),
        T, g, npz, nq, is,ie,js,je,isd,ied,jsd,jed));

    auto launch=[&](){ return fv3::tracer_2d_gpu_launch<Real>(
        B_.q, B_.cx_b, B_.cy_b, B_.mfx_b, B_.mfy_b, B_.rax_b, B_.ray_b,
        B_.area_b, B_.dxa_b, B_.dya_b, B_.fx, B_.fy, B_.qi, B_.qj, B_.fx2, B_.fy2,
        B_.sr, B_.sb, B_.lines, B_.dp1, B_.dp2_lev, g, T, npz, nq,
        is,ie,js,je,isd,ied,jsd,jed, n+1,n+1,hord,lim_fac,false,0,true,true,true,true); };

    CUDA_CHECK(launch()); CUDA_CHECK(cudaDeviceSynchronize());
    cudaEvent_t s0,s1; CUDA_CHECK(cudaEventCreate(&s0)); CUDA_CHECK(cudaEventCreate(&s1));
    CUDA_CHECK(cudaEventRecord(s0));
    for (int it=0; it<n_iter; ++it) CUDA_CHECK(launch());
    CUDA_CHECK(cudaEventRecord(s1)); CUDA_CHECK(cudaEventSynchronize(s1));
    float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,s0,s1));

    CUDA_CHECK(cudaMemcpy(q.data(), B_.q, (size_t)npz*nq*Tq*sizeof(Real), cudaMemcpyDeviceToHost));
    double sum=0.0;
    for (int iq=0;iq<nq;++iq) for (int k=0;k<npz;++k) for (int j=js;j<=je;++j) for (int i=is;i<=ie;++i)
        sum += double(q[((size_t)iq*npz+k)*Tq+fv3::idx2(i,j,isd,jsd,niq)]);
    std::printf("time taken: %.6f s  (%.4f ms/iter over %d iters)\n", ms/1000.0, ms/double(n_iter), n_iter);
    std::printf("sum(q): %.10e  (npz*nq=%d transports/iter)\n", sum, npz*nq);

    cudaEventDestroy(s0); cudaEventDestroy(s1);
    fv3::tracer_2d_gpu_free<Real>(B_);
    return 0;
}
