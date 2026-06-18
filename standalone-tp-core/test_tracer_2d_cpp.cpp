// test_tracer_2d_cpp.cpp — validate the C++ tracer_2d_cpu against the Fortran
// tracer_2d_core (single tile, nsplt=1, unit grid) over npz levels x nq tracers
// for several hord values, comparing the updated q to tolerance.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#include "tracer_2d.hpp"

extern "C" {
void tracer_2d_core_c(float* q, const float* dp1, const float* cx, const float* cy,
                      const float* mfx, const float* mfy,
                      int n, int npz, int nq, int hord, float lim_fac);
}

static int n_failed = 0;
static void check(const std::string& s, bool ok){ std::printf("%s: %s\n", ok?"PASS":"FAIL", s.c_str()); if(!ok) ++n_failed; }

int main() {
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
        std::vector<float> q_c = q0, q_f = q0;
        fv3::tracer_2d_cpu<float>(q_c.data(), dp1.data(), cx.data(), cy.data(), mfx.data(), mfy.data(),
            is,ie,js,je,isd,ied,jsd,jed, n+1,n+1,npz,nq,hord,lim_fac, false,0, true,true,true,true);
        tracer_2d_core_c(q_f.data(), dp1.data(), cx.data(), cy.data(), mfx.data(), mfy.data(),
            n, npz, nq, hord, lim_fac);

        float md=0.f;
        for (int iq=0;iq<nq;++iq) for (int k=0;k<npz;++k)
            for (int j=js;j<=je;++j) for (int i=is;i<=ie;++i) {
                const size_t o=((size_t)iq*npz+k)*Tq + fv3::idx2(i,j,isd,jsd,niq);
                md = std::max(md, std::abs(q_c[o]-q_f[o]));
            }
        char buf[128]; std::snprintf(buf,sizeof buf,"C++ vs Fortran tracer_2d [hord=%d]: max|dq|=%.2e < 1e-4", hord, md);
        check(buf, md < 1.e-4f);
    }
    std::printf("\n");
    if (n_failed==0){ std::printf("All tests PASSED\n"); return 0; }
    std::printf("FAIL: %d test(s) failed\n", n_failed); return 1;
}
