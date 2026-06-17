// test_fv_tp_2d_gpu.cu — GPU-vs-CPU test for the device-resident fv_tp_2d.
//
// Runs the GPU orchestrator (fv3::fv_tp_2d_gpu) and the CPU reference
// (fv3::fv_tp_2d_cpu) on the same synthetic field for several hord values and
// requires fx and fy to agree to tolerance (GPU/CPU differ only by FMA, since
// both run the same scheme). The CPU reference is itself validated against the
// Fortran fv_tp_2d in test_fv_tp_2d_cpp.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

#include "fv_tp_2d.hpp"
#include "fv_tp_2d_gpu.cuh"

static int n_failed = 0;
static void check(const char* name, bool ok) {
    std::printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok) ++n_failed;
}

int main() {
    int dev = 0; cudaDeviceProp prop;
    if (cudaGetDeviceProperties(&prop, dev) == cudaSuccess)
        std::printf("GPU: %s (SM %d.%d)\n\n", prop.name, prop.major, prop.minor);

    const int n  = 32, ng = 3;
    const int is = 1, ie = n, js = 1, je = n;
    const int isd = is-ng, ied = ie+ng, jsd = js-ng, jed = je+ng;
    const int npx = n+1, npy = n+1;
    const float lim_fac = 1.0f;

    const int niq = ied-isd+1, nicrx = ie-is+2, nirax = ie-is+1;
    const size_t sz_q   = (size_t)niq   * (jed-jsd+1);
    const size_t sz_crx = (size_t)nicrx * (jed-jsd+1);
    const size_t sz_cry = (size_t)niq   * (je-js+2);
    const size_t sz_rax = (size_t)nirax * (jed-jsd+1);
    const size_t sz_ray = (size_t)niq   * (je-js+1);
    const size_t sz_fx  = (size_t)nicrx * (je-js+1);
    const size_t sz_fy  = (size_t)nirax * (je-js+2);

    std::vector<float> q0(sz_q);
    std::vector<float> crx(sz_crx,0.5f), xfx(sz_crx,0.5f), cry(sz_cry,0.5f), yfx(sz_cry,0.5f);
    std::vector<float> ra_x(sz_rax,1.0f), ra_y(sz_ray,1.0f);
    std::vector<float> area(sz_q,1.0f), dxa(sz_q,1.0f), dya(sz_q,1.0f);

    const float PI = 3.1415927f;
    for (int j = jsd; j <= jed; ++j)
        for (int i = isd; i <= ied; ++i)
            q0[fv3::idx2(i,j,isd,jsd,niq)] = std::sin(PI*float(i*j)/float((npx-1)*(npy-1)));

    const int NB = 4;   // batched tiles; every tile must match the single-tile CPU result
    const int hords[] = {5, 6, 8, 9, 10, 12, 13};
    for (int k = 0; k < (int)(sizeof(hords)/sizeof(hords[0])); ++k) {
        const int hord = hords[k];

        // CPU single-tile reference.
        std::vector<float> q_c = q0;
        std::vector<float> fx_c(sz_fx,0.f), fy_c(sz_fy,0.f);
        fv3::fv_tp_2d_cpu<float>(
            q_c.data(), crx.data(), cry.data(), xfx.data(), yfx.data(),
            ra_x.data(), ra_y.data(), area.data(), dxa.data(), dya.data(),
            fx_c.data(), fy_c.data(), is,ie,js,je,isd,ied,jsd,jed, npx,npy, hord, lim_fac,
            false, 0, true,true,true,true);

        // NB replicated tiles (uniform fields; q replicated per tile).
        std::vector<float> q_g((size_t)NB*sz_q);
        std::vector<float> crxB((size_t)NB*sz_crx,0.5f), xfxB((size_t)NB*sz_crx,0.5f);
        std::vector<float> cryB((size_t)NB*sz_cry,0.5f), yfxB((size_t)NB*sz_cry,0.5f);
        std::vector<float> raxB((size_t)NB*sz_rax,1.0f), rayB((size_t)NB*sz_ray,1.0f);
        std::vector<float> areaB((size_t)NB*sz_q,1.0f), dxaB((size_t)NB*sz_q,1.0f), dyaB((size_t)NB*sz_q,1.0f);
        std::vector<float> fx_g((size_t)NB*sz_fx,0.f), fy_g((size_t)NB*sz_fy,0.f);
        for (int b = 0; b < NB; ++b)
            for (size_t t = 0; t < sz_q; ++t) q_g[(size_t)b*sz_q + t] = q0[t];

        cudaError_t e = fv3::fv_tp_2d_gpu<float>(
            q_g.data(), crxB.data(), cryB.data(), xfxB.data(), yfxB.data(),
            raxB.data(), rayB.data(), areaB.data(), dxaB.data(), dyaB.data(),
            fx_g.data(), fy_g.data(), NB, is,ie,js,je,isd,ied,jsd,jed, npx,npy, hord, lim_fac,
            false, 0, true,true,true,true);
        if (e != cudaSuccess) {
            std::fprintf(stderr, "fv_tp_2d_gpu failed: %s\n", cudaGetErrorString(e));
            return 1;
        }

        float mdx = 0.f, mdy = 0.f;
        for (int b = 0; b < NB; ++b) {
            for (size_t t = 0; t < sz_fx; ++t) mdx = std::max(mdx, std::abs(fx_c[t]-fx_g[(size_t)b*sz_fx+t]));
            for (size_t t = 0; t < sz_fy; ++t) mdy = std::max(mdy, std::abs(fy_c[t]-fy_g[(size_t)b*sz_fy+t]));
        }
        char buf[160];
        std::snprintf(buf, sizeof buf,
            "GPU vs CPU fv_tp_2d [hord=%d, %d tiles]: max|fx|=%.2e max|fy|=%.2e < 1e-4",
            hord, NB, mdx, mdy);
        check(buf, mdx < 1.e-4f && mdy < 1.e-4f);
    }

    std::printf("\n");
    if (n_failed == 0) { std::printf("All tests PASSED\n"); return 0; }
    std::printf("FAIL: %d test(s) failed\n", n_failed);
    return 1;
}
