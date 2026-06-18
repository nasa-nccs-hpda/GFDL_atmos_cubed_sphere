// driver_tracer_2d_cpu.cc — CPU benchmark for the tracer_2d compute core.
//   Usage: tracer-2d-driver-cpu <resolution> <iterations> [npz] [nq]
// Transports nq tracers over npz levels (single tile, nsplt=1, unit grid) for
// <iterations> steps; reports time and a q checksum (cross-checks the GPU driver).
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <chrono>
#include <vector>

#include "tracer_2d.hpp"

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

    std::printf("tracer_2d CPU driver: resolution=%d iterations=%d npz=%d nq=%d\n", n, n_iter, npz, nq);
    auto t0=std::chrono::steady_clock::now();
    for (int it=0; it<n_iter; ++it)
        fv3::tracer_2d_cpu<Real>(q.data(), dp1.data(), cx.data(), cy.data(), mfx.data(), mfy.data(),
            is,ie,js,je,isd,ied,jsd,jed, n+1,n+1,npz,nq,hord,lim_fac, false,0, true,true,true,true);
    auto t1=std::chrono::steady_clock::now();
    const double ms=std::chrono::duration<double,std::milli>(t1-t0).count();

    double s=0.0;
    for (int iq=0;iq<nq;++iq) for (int k=0;k<npz;++k) for (int j=js;j<=je;++j) for (int i=is;i<=ie;++i)
        s += double(q[((size_t)iq*npz+k)*Tq+fv3::idx2(i,j,isd,jsd,niq)]);
    std::printf("time taken: %.6f s  (%.4f ms/iter over %d iters)\n", ms/1000.0, ms/double(n_iter), n_iter);
    std::printf("sum(q): %.10e  (npz*nq=%d transports/iter)\n", s, npz*nq);
    return 0;
}
