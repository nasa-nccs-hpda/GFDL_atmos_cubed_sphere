// test_tracer_2d_gpu.cu — validate the batched GPU tracer transport against the
// CPU reference (tracer_2d_cpu) over npz x nq, several hord values. GPU and CPU
// run the same scheme; agreement is to FMA tolerance. The CPU reference itself
// is checked against Fortran in test_tracer_2d_cpp.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

#include "tracer_2d.hpp"
#include "tracer_2d_gpu.cuh"

static int n_failed = 0;
static void check(const char* s, bool ok){ std::printf("%s: %s\n", ok?"PASS":"FAIL", s); if(!ok) ++n_failed; }

int main() {
    int dev=0; cudaDeviceProp p;
    if (cudaGetDeviceProperties(&p,dev)==cudaSuccess) std::printf("GPU: %s (SM %d.%d)\n\n",p.name,p.major,p.minor);

    const int n=24, ng=3, npz=6, nq=4;
    const int is=1, ie=n, js=1, je=n, isd=is-ng, ied=ie+ng, jsd=js-ng, jed=je+ng;
    const float lim_fac=1.0f;
    const int niq=ied-isd+1, njq=jed-jsd+1, nicrx=ie-is+2, nirax=ie-is+1;
    const int Tq=niq*njq, Tcx=nicrx*njq, Tcy=niq*(je-js+2), Tmfx=nicrx*(je-js+1), Tmfy=nirax*(je-js+2);

    std::vector<float> q0((size_t)npz*nq*Tq), dp1((size_t)npz*Tq);
    std::vector<float> cx((size_t)npz*Tcx), cy((size_t)npz*Tcy), mfx((size_t)npz*Tmfx), mfy((size_t)npz*Tmfy);
    const float PI=3.1415927f;
    for (int k=0;k<npz;++k) {
        for (int j=jsd;j<=jed;++j) for (int i=is;i<=ie+1;++i)
            cx[(size_t)k*Tcx + fv3::idx2(i,j,is,jsd,nicrx)] = 0.4f + 0.001f*(i + 0.5f*j);
        for (int j=js;j<=je+1;++j) for (int i=isd;i<=ied;++i)
            cy[(size_t)k*Tcy + fv3::idx2(i,j,isd,js,niq)] = 0.4f + 0.001f*(0.5f*i + j);
        for (int j=js;j<=je;++j) for (int i=is;i<=ie+1;++i)
            mfx[(size_t)k*Tmfx + fv3::idx2(i,j,is,js,nicrx)] = 0.5f + 0.002f*i;
        for (int j=js;j<=je+1;++j) for (int i=is;i<=ie;++i)
            mfy[(size_t)k*Tmfy + fv3::idx2(i,j,is,js,nirax)] = 0.5f + 0.002f*j;
        for (int j=jsd;j<=jed;++j) for (int i=isd;i<=ied;++i)
            dp1[(size_t)k*Tq + fv3::idx2(i,j,isd,jsd,niq)] = 1.0f + 0.01f*k;
        for (int iq=0;iq<nq;++iq)
            for (int j=jsd;j<=jed;++j) for (int i=isd;i<=ied;++i)
                q0[((size_t)iq*npz+k)*Tq + fv3::idx2(i,j,isd,jsd,niq)] =
                    1.0f + 0.5f*std::sin(PI*float(i*j)/float(n*n)) + 0.05f*iq + 0.005f*k;
    }

    const int hords[] = {8, 9, 10, 12, 13};
    for (int h=0; h<(int)(sizeof(hords)/sizeof(hords[0])); ++h) {
        const int hord = hords[h];
        std::vector<float> q_c = q0, q_g = q0;
        fv3::tracer_2d_cpu<float>(q_c.data(), dp1.data(), cx.data(), cy.data(), mfx.data(), mfy.data(),
            is,ie,js,je,isd,ied,jsd,jed, n+1,n+1,npz,nq,hord,lim_fac, false,0, true,true,true,true);
        cudaError_t e = fv3::tracer_2d_gpu<float>(q_g.data(), dp1.data(), cx.data(), cy.data(), mfx.data(), mfy.data(),
            is,ie,js,je,isd,ied,jsd,jed, n+1,n+1,npz,nq,hord,lim_fac, false,0, true,true,true,true);
        if (e!=cudaSuccess){ std::fprintf(stderr,"tracer_2d_gpu failed: %s\n", cudaGetErrorString(e)); return 1; }

        float md=0.f;
        for (int iq=0;iq<nq;++iq) for (int k=0;k<npz;++k)
            for (int j=js;j<=je;++j) for (int i=is;i<=ie;++i) {
                const size_t o=((size_t)iq*npz+k)*Tq + fv3::idx2(i,j,isd,jsd,niq);
                md = std::max(md, std::abs(q_c[o]-q_g[o]));
            }
        char buf[128]; std::snprintf(buf,sizeof buf,"GPU vs CPU tracer_2d [hord=%d, %dx%d]: max|dq|=%.2e < 1e-4", hord, npz, nq, md);
        check(buf, md < 1.e-4f);
    }
    std::printf("\n");
    if (n_failed==0){ std::printf("All tests PASSED\n"); return 0; }
    std::printf("FAIL: %d test(s) failed\n", n_failed); return 1;
}
