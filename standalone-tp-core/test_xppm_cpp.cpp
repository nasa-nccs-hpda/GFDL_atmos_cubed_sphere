// test_xppm_cpp.cpp — correctness tests for the C++ xppm port (xppm.hpp).
//
// Two layers:
//   1. Analytic checks via the Fortran xppm (constant -> flux=const, linear
//      -> flux=i-0.75 / i-0.25), confirming the Fortran reference and the
//      single-row layout.
//   2. The key check: for many iord values and several q patterns, with the
//      cubed-sphere boundary code BOTH off (nested) and on (nested=false),
//      require the C++ xppm_col output to match the real Fortran xppm output.
//      This exercises every code path — including the boundary branches — and
//      directly validates the hand-transcription from yppm_col.
//
// Domain: a single j-row, sweeping over i (ng=3 halo):
//   is=1, ie=20, isd=-2, ied=23, jfirst=jlast=1, jsd=-2, jed=4, npx=21, npy=2
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#include "xppm.hpp"

extern "C" {
void xppm_c(float*       flux,
            const float* q,
            const float* c,
            int iord,
            int is,     int ie,
            int isd,    int ied,
            int jfirst, int jlast,
            int jsd,    int jed,
            int npx,    int npy,
            const float* dxa,
            int nested_int,
            int grid_type,
            float lim_fac);
}

namespace Dom {
    static const int n      = 20;
    static const int ng     = 3;
    static const int is     = 1,      ie  = n;
    static const int isd    = is - ng;       // -2
    static const int ied    = ie + ng;       // 23
    static const int jfirst = 1,      jlast = 1;
    static const int jsd    = jfirst - ng;   // -2
    static const int jed    = jlast  + ng;   //  4
    static const int npx    = n + 1,  npy = 2;

    static const int ni_q   = ied - isd + 1;            // 26  (q/dxa per row)
    static const int ni_c   = ie  - is  + 2;            // 21  (c/flux per row)

    static const int sz_q    = ni_q * (jlast - jfirst + 1);   // 26
    static const int sz_flux = ni_c * (jlast - jfirst + 1);   // 21
    static const int sz_c    = ni_c * (jlast - jfirst + 1);   // 21
    static const int sz_dxa  = ni_q * (jed - jsd + 1);        // 26*7

    inline int q_idx(int i)    { return i - isd; }   // q(i,1)    -> data[i-isd]
    inline int flux_idx(int i) { return i - is;  }   // flux(i,1) -> data[i-is]
}

static const int NMAX = 20;  // >= ie - is + 1

static int n_failed = 0;
static void assert_test(const std::string& name, bool passed) {
    std::cout << (passed ? "PASS: " : "FAIL: ") << name << "\n";
    if (!passed) ++n_failed;
}

// ---------------------------------------------------------------------------
// Fortran reference (single row, uniform dxa=1).
// ---------------------------------------------------------------------------
static std::vector<float> fortran_xppm(const std::vector<float>& q,
                                       const std::vector<float>& c,
                                       int iord, bool nested)
{
    std::vector<float> flux(Dom::sz_flux, 0.f);
    std::vector<float> dxa(Dom::sz_dxa, 1.0f);
    xppm_c(flux.data(), q.data(), c.data(), iord,
           Dom::is, Dom::ie, Dom::isd, Dom::ied,
           Dom::jfirst, Dom::jlast, Dom::jsd, Dom::jed,
           Dom::npx, Dom::npy, dxa.data(), nested ? 1 : 0, 0, 1.0f);
    return flux;
}

// ---------------------------------------------------------------------------
// C++ port (xppm.hpp), single row, uniform dxa=1.
// ---------------------------------------------------------------------------
static std::vector<float> cpp_xppm(const std::vector<float>& q,
                                   const std::vector<float>& c,
                                   int iord, bool nested)
{
    std::vector<float> flux(Dom::sz_flux, 0.f);
    std::vector<float> dxa(Dom::ni_q, 1.0f);
    fv3::ScratchXPPM<float, NMAX> s;
    fv3::xppm_col<float>(flux.data(), q.data(), c.data(), iord,
                         Dom::is, Dom::ie, Dom::isd, Dom::ied, Dom::npx, Dom::npy,
                         dxa.data(), nested, 0, 1.0f, s.view(NMAX));
    return flux;
}

// ---------------------------------------------------------------------------
// Analytic tests (Fortran), mirroring the yppm analytic checks.
// ---------------------------------------------------------------------------
static void test_constant(int iord) {
    std::vector<float> q(Dom::sz_q, 1.0f), c(Dom::sz_c, 0.5f);
    auto flux = fortran_xppm(q, c, iord, true);
    bool ok = true;
    for (int i = Dom::is; i <= Dom::ie + 1; ++i)
        ok = ok && (std::abs(flux[Dom::flux_idx(i)] - 1.0f) < 1.e-6f);
    assert_test("constant q=1, c=+0.5, iord=" + std::to_string(iord) + ": flux==1", ok);
}

static void test_linear(float courant, float expect_off) {
    std::vector<float> q(Dom::sz_q), c(Dom::sz_c, courant);
    for (int i = Dom::isd; i <= Dom::ied; ++i) q[Dom::q_idx(i)] = float(i);
    auto flux = fortran_xppm(q, c, 8, true);
    bool ok = true;
    for (int i = Dom::is; i <= Dom::ie + 1; ++i)
        ok = ok && (std::abs(flux[Dom::flux_idx(i)] - (float(i) - expect_off)) < 1.e-4f);
    assert_test("linear q=i, c=" + std::to_string(courant) +
                ", iord=8: flux==i-" + std::to_string(expect_off), ok);
}

// ---------------------------------------------------------------------------
// The port-correctness check: C++ xppm_col vs Fortran xppm, all paths.
// ---------------------------------------------------------------------------
static float max_diff(const std::vector<float>& a, const std::vector<float>& b) {
    float m = 0.f;
    for (int i = Dom::is; i <= Dom::ie + 1; ++i) {
        const float d = std::abs(a[Dom::flux_idx(i)] - b[Dom::flux_idx(i)]);
        if (d > m) m = d;
    }
    return m;
}

static void compare_all_paths(const std::vector<float>& q,
                              const std::vector<float>& c,
                              const std::string& label)
{
    const int iords[] = {1, 2, 3, 4, 5, -5, 6, 7, 8, 9, 10, 11, 12, 13};
    for (bool nested : {true, false}) {
        for (int iord : iords) {
            auto f_ref = fortran_xppm(q, c, iord, nested);
            auto f_cpp = cpp_xppm  (q, c, iord, nested);
            const float md = max_diff(f_ref, f_cpp);
            assert_test("C++ vs Fortran [" + label + ", nested=" +
                        (nested ? "T" : "F") + ", iord=" + std::to_string(iord) +
                        "]: max|diff|<1e-4 (" + std::to_string(md) + ")", md < 1.e-4f);
        }
    }
}

int main() {
    // Analytic sanity
    test_constant(8);
    test_constant(2);
    test_linear( 0.5f, 0.75f);
    test_linear(-0.5f, 0.25f);

    // Comprehensive C++-vs-Fortran comparison over all iord paths.
    // Pattern A: smooth field.
    {
        std::vector<float> q(Dom::sz_q), c(Dom::sz_c, 0.5f);
        const double two_pi = 6.283185307179586;
        for (int i = Dom::isd; i <= Dom::ied; ++i)
            q[Dom::q_idx(i)] = float(1.0 + 0.5 * std::sin(two_pi * double(i - Dom::isd) / double(Dom::ni_q)));
        compare_all_paths(q, c, "smooth");
    }
    // Pattern B: step (exercises limiters / monotonicity).
    {
        std::vector<float> q(Dom::sz_q), c(Dom::sz_c, 0.5f);
        for (int i = Dom::isd; i <= Dom::ied; ++i)
            q[Dom::q_idx(i)] = (i < 11) ? 0.0f : 1.0f;
        compare_all_paths(q, c, "step");
    }
    // Pattern C: smooth field, negative Courant.
    {
        std::vector<float> q(Dom::sz_q), c(Dom::sz_c, -0.5f);
        const double two_pi = 6.283185307179586;
        for (int i = Dom::isd; i <= Dom::ied; ++i)
            q[Dom::q_idx(i)] = float(1.0 + 0.5 * std::cos(two_pi * double(i - Dom::isd) / double(Dom::ni_q)));
        compare_all_paths(q, c, "smooth,c<0");
    }

    std::cout << "\n";
    if (n_failed == 0) { std::cout << "All tests PASSED\n"; return 0; }
    std::cout << "FAIL: " << n_failed << " test(s) failed\n";
    return 1;
}
