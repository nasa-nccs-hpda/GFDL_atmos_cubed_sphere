// test_fv_tp_2d_cpp.cpp — correctness test for the C++ fv_tp_2d port.
//
// Compares fv3::fv_tp_2d_cpu against the real Fortran fv_tp_2d (via the
// fv_tp_2d_c binding) on the same synthetic field the standalone driver uses
// (q = sin(pi*i*j/((npx-1)(npy-1))), crx=cry=xfx=yfx=0.5, ra_*=area=dxa=dya=1),
// for several hord values, requiring fx and fy to agree to tolerance. This
// validates the orchestration the PPM unit tests do not cover: copy_corners,
// the q_i/q_j cross terms, and the flux average.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "fv_tp_2d.hpp"

extern "C" {
void fv_tp_2d_c(float* q, const float* crx, const float* cry,
                const float* xfx, const float* yfx,
                const float* ra_x, const float* ra_y,
                float* fx, float* fy,
                int n, int npx, int npy, int hord, float lim_fac,
                int nested_int, int grid_type);
}

static int n_failed = 0;
static void assert_test(const std::string& name, bool ok) {
    std::printf("%s: %s\n", ok ? "PASS" : "FAIL", name.c_str());
    if (!ok) ++n_failed;
}

int main() {
    const int n  = 32;
    const int ng = 3;
    const int is = 1,      ie  = n;
    const int js = 1,      je  = n;
    const int isd = is-ng, ied = ie+ng;
    const int jsd = js-ng, jed = je+ng;
    const int npx = n+1,   npy = n+1;
    const float lim_fac = 1.0f;

    // Strides / flat sizes (column-major, i fastest).
    const int niq   = ied - isd + 1;   // q/area/dxa/dya/cry/yfx
    const int nicrx = ie  - is  + 2;   // crx/xfx/fx
    const int nirax = ie  - is  + 1;   // ra_x/fy
    const size_t sz_q   = (size_t)niq   * (jed - jsd + 1);
    const size_t sz_crx = (size_t)nicrx * (jed - jsd + 1);
    const size_t sz_cry = (size_t)niq   * (je  - js  + 2);
    const size_t sz_rax = (size_t)nirax * (jed - jsd + 1);
    const size_t sz_ray = (size_t)niq   * (je  - js  + 1);
    const size_t sz_fx  = (size_t)nicrx * (je  - js  + 1);
    const size_t sz_fy  = (size_t)nirax * (je  - js  + 2);

    // Inputs (match model/tp-core-driver/input/input_arrays.f90).
    std::vector<float> q0  (sz_q);
    std::vector<float> crx (sz_crx, 0.5f), xfx(sz_crx, 0.5f);
    std::vector<float> cry (sz_cry, 0.5f), yfx(sz_cry, 0.5f);
    std::vector<float> ra_x(sz_rax, 1.0f), ra_y(sz_ray, 1.0f);
    std::vector<float> area(sz_q, 1.0f), dxa(sz_q, 1.0f), dya(sz_q, 1.0f);

    const float PI = 3.1415927f;
    for (int j = jsd; j <= jed; ++j)
        for (int i = isd; i <= ied; ++i)
            q0[fv3::idx2(i,j,isd,jsd,niq)] =
                std::sin(PI * float(i*j) / float((npx-1)*(npy-1)));

    const int hords[] = {5, 6, 8, 9, 10, 12, 13};
    for (int k = 0; k < (int)(sizeof(hords)/sizeof(hords[0])); ++k) {
        const int hord = hords[k];

        std::vector<float> q_f = q0, q_c = q0;   // each side modifies its own q (corners)
        std::vector<float> fx_f(sz_fx, 0.f), fy_f(sz_fy, 0.f);
        std::vector<float> fx_c(sz_fx, 0.f), fy_c(sz_fy, 0.f);

        fv_tp_2d_c(q_f.data(), crx.data(), cry.data(), xfx.data(), yfx.data(),
                   ra_x.data(), ra_y.data(), fx_f.data(), fy_f.data(),
                   n, npx, npy, hord, lim_fac, /*nested*/0, /*grid_type*/0);

        fv3::fv_tp_2d_cpu<float>(
            q_c.data(), crx.data(), cry.data(), xfx.data(), yfx.data(),
            ra_x.data(), ra_y.data(), area.data(), dxa.data(), dya.data(),
            fx_c.data(), fy_c.data(),
            is, ie, js, je, isd, ied, jsd, jed, npx, npy, hord, lim_fac,
            /*nested*/false, /*grid_type*/0,
            /*sw*/true, /*se*/true, /*nw*/true, /*ne*/true);

        float mdx = 0.f, mdy = 0.f;
        for (size_t t = 0; t < sz_fx; ++t) mdx = std::max(mdx, std::abs(fx_f[t] - fx_c[t]));
        for (size_t t = 0; t < sz_fy; ++t) mdy = std::max(mdy, std::abs(fy_f[t] - fy_c[t]));

        char buf[160];
        std::snprintf(buf, sizeof buf,
            "C++ vs Fortran fv_tp_2d [hord=%d]: max|fx|=%.2e max|fy|=%.2e < 1e-4",
            hord, mdx, mdy);
        assert_test(buf, mdx < 1.e-4f && mdy < 1.e-4f);
    }

    std::printf("\n");
    if (n_failed == 0) { std::printf("All tests PASSED\n"); return 0; }
    std::printf("FAIL: %d test(s) failed\n", n_failed);
    return 1;
}
