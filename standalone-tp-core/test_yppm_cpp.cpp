// C++ unit tests for the Fortran yppm subroutine, called via the
// yppm_c bind(C) wrapper, AND for the native C++ port (yppm.hpp).
//
// Domain (matches Fortran test_yppm.f90):
//   n=20, ng=3, ifirst=ilast=1 (single x-column), nested=true
//   isd=-2, ied=4, js=1, je=20, jsd=-2, jed=23, npx=2, npy=21
//
// Array layout (Fortran column-major, first index contiguous):
//   q    (1:1, -2:23)  -> 1x26 flat array; q(1,j) = data[j - jsd]
//   flux (1:1,  1:21)  -> 1x21 flat array; flux(1,j) = data[j - js]
//   cry  (-2:4, 1:21)  -> 7x21 flat array
//   dya  (-2:4, -2:23) -> 7x26 flat array
//
// Test summary:
//   Fortran (via yppm_c): 8 assertions across 6 tests
//   C++ native (yppm.hpp): 9 assertions across 6 tests
//     - Tests 1-4, 6 check same analytical values as Fortran tests
//     - Test 5 also checks bit-exact agreement with Fortran for jord=8
//
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#include "yppm.hpp"

// C-linkage prototype for the Fortran yppm_c wrapper.
// All scalars are passed by value; arrays are passed as pointers to
// their first (lower-bound-corner) element in Fortran column-major order.
extern "C" {
void yppm_c(float*       flux,
            const float* q,
            const float* cry,
            int jord,
            int ifirst, int ilast,
            int isd,    int ied,
            int js,     int je,
            int jsd,    int jed,
            int npx,    int npy,
            const float* dya,
            int nested_int,
            int grid_type,
            float lim_fac);
}

// ---------------------------------------------------------------------------
// Domain constants (doubly-periodic, single x-column, ng=3 halo)
// ---------------------------------------------------------------------------
namespace Dom {
    static const int n      = 20;
    static const int ng     = 3;
    static const int ifirst = 1,      ilast = 1;
    static const int isd    = ifirst - ng;   // -2
    static const int ied    = ilast  + ng;   //  4
    static const int js     = 1,      je  = n;
    static const int jsd    = js - ng;       // -2
    static const int jed    = je + ng;       // 23
    static const int npx    = 2,      npy = n + 1;

    // Flat array sizes (Fortran column-major)
    static const int sz_q    = (ilast - ifirst + 1) * (jed - jsd + 1); // 1x26
    static const int sz_flux = (ilast - ifirst + 1) * (je  - js  + 2); // 1x21
    static const int sz_cry  = (ied   - isd   + 1) * (je  - js  + 2); // 7x21
    static const int sz_dya  = (ied   - isd   + 1) * (jed - jsd + 1); // 7x26

    // Index helpers for single x-column arrays
    // q(1, j)    -> data[j - jsd]
    inline int q_idx(int j)    { return j - jsd; }
    // flux(1, j) -> data[j - js]
    inline int flux_idx(int j) { return j - js;  }
}

// ---------------------------------------------------------------------------
// Test infrastructure
// ---------------------------------------------------------------------------
static int n_failed = 0;

static void assert_test(const std::string& name, bool passed) {
    std::cout << (passed ? "PASS: " : "FAIL: ") << name << "\n";
    if (!passed) ++n_failed;
}

// ---------------------------------------------------------------------------
// Test 1: Constant field, jord=8 (monotonic PPM)
// For q=const all slopes are zero -> flux == q everywhere.
// ---------------------------------------------------------------------------
static void test_constant_jord8() {
    std::vector<float> q   (Dom::sz_q,    1.0f);
    std::vector<float> cry (Dom::sz_cry,  0.5f);
    std::vector<float> dya (Dom::sz_dya,  1.0f);
    std::vector<float> flux(Dom::sz_flux);

    yppm_c(flux.data(), q.data(), cry.data(),
           8, Dom::ifirst, Dom::ilast, Dom::isd, Dom::ied,
           Dom::js, Dom::je, Dom::jsd, Dom::jed,
           Dom::npx, Dom::npy, dya.data(), 1, 0, 1.0f);

    bool ok = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok = ok && (std::abs(flux[Dom::flux_idx(j)] - 1.0f) < 1.e-6f);
    assert_test("constant q=1, c=+0.5, jord=8: flux==1", ok);
}

// ---------------------------------------------------------------------------
// Test 2: Constant field, jord=2 (perfectly linear scheme)
// ---------------------------------------------------------------------------
static void test_constant_jord2() {
    std::vector<float> q   (Dom::sz_q,    1.0f);
    std::vector<float> cry (Dom::sz_cry,  0.5f);
    std::vector<float> dya (Dom::sz_dya,  1.0f);
    std::vector<float> flux(Dom::sz_flux);

    yppm_c(flux.data(), q.data(), cry.data(),
           2, Dom::ifirst, Dom::ilast, Dom::isd, Dom::ied,
           Dom::js, Dom::je, Dom::jsd, Dom::jed,
           Dom::npx, Dom::npy, dya.data(), 1, 0, 1.0f);

    bool ok = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok = ok && (std::abs(flux[Dom::flux_idx(j)] - 1.0f) < 1.e-6f);
    assert_test("constant q=1, c=+0.5, jord=2: flux==1", ok);
}

// ---------------------------------------------------------------------------
// Test 3: Linear field q(j)=j, jord=8, c=+0.5
// PPM is exact on linear fields (uniform grid).
// Analytical result: flux(j) = j - 0.75
//   bl=-0.5, br=+0.5; c>0 branch: flux = q(j-1) + (1-c)*(br - c*(bl+br))
//                                       = (j-1) + 0.5*(0.5 - 0) = j - 0.75
// ---------------------------------------------------------------------------
static void test_linear_positive_courant() {
    std::vector<float> q   (Dom::sz_q);
    std::vector<float> cry (Dom::sz_cry,  0.5f);
    std::vector<float> dya (Dom::sz_dya,  1.0f);
    std::vector<float> flux(Dom::sz_flux);

    for (int j = Dom::jsd; j <= Dom::jed; ++j)
        q[Dom::q_idx(j)] = float(j);

    yppm_c(flux.data(), q.data(), cry.data(),
           8, Dom::ifirst, Dom::ilast, Dom::isd, Dom::ied,
           Dom::js, Dom::je, Dom::jsd, Dom::jed,
           Dom::npx, Dom::npy, dya.data(), 1, 0, 1.0f);

    bool ok = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok = ok && (std::abs(flux[Dom::flux_idx(j)] - (float(j) - 0.75f)) < 1.e-5f);
    assert_test("linear q=j, c=+0.5, jord=8: flux==j-0.75", ok);
}

// ---------------------------------------------------------------------------
// Test 4: Linear field q(j)=j, jord=8, c=-0.5
// Analytical result: flux(j) = j - 0.25
//   c<0 branch: flux = q(j) + (1+c)*(bl + c*(bl+br))
//                    = j + 0.5*(-0.5 + 0) = j - 0.25
// ---------------------------------------------------------------------------
static void test_linear_negative_courant() {
    std::vector<float> q   (Dom::sz_q);
    std::vector<float> cry (Dom::sz_cry, -0.5f);
    std::vector<float> dya (Dom::sz_dya,  1.0f);
    std::vector<float> flux(Dom::sz_flux);

    for (int j = Dom::jsd; j <= Dom::jed; ++j)
        q[Dom::q_idx(j)] = float(j);

    yppm_c(flux.data(), q.data(), cry.data(),
           8, Dom::ifirst, Dom::ilast, Dom::isd, Dom::ied,
           Dom::js, Dom::je, Dom::jsd, Dom::jed,
           Dom::npx, Dom::npy, dya.data(), 1, 0, 1.0f);

    bool ok = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok = ok && (std::abs(flux[Dom::flux_idx(j)] - (float(j) - 0.25f)) < 1.e-5f);
    assert_test("linear q=j, c=-0.5, jord=8: flux==j-0.25", ok);
}

// ---------------------------------------------------------------------------
// Test 5: Step function, jord=8, c=+0.5
// q=0 for j<11, q=1 for j>=11.  Monotone limiter prevents over/undershoot.
// Checks:
//   (a) all flux in [0, 1]
//   (b) flux==0 for faces well below the step (j=3..8)
//   (c) flux==1 for faces well above the step (j=14..je+1)
// ---------------------------------------------------------------------------
static void test_monotone_bounds() {
    static const int mid = 11;
    std::vector<float> q   (Dom::sz_q);
    std::vector<float> cry (Dom::sz_cry, 0.5f);
    std::vector<float> dya (Dom::sz_dya, 1.0f);
    std::vector<float> flux(Dom::sz_flux);

    for (int j = Dom::jsd; j <= Dom::jed; ++j)
        q[Dom::q_idx(j)] = (j < mid) ? 0.0f : 1.0f;

    yppm_c(flux.data(), q.data(), cry.data(),
           8, Dom::ifirst, Dom::ilast, Dom::isd, Dom::ied,
           Dom::js, Dom::je, Dom::jsd, Dom::jed,
           Dom::npx, Dom::npy, dya.data(), 1, 0, 1.0f);

    bool ok_bounds = true, ok_below = true, ok_above = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j) {
        float f = flux[Dom::flux_idx(j)];
        ok_bounds = ok_bounds && (f >= -1.e-6f) && (f <= 1.0f + 1.e-6f);
    }
    for (int j = 3; j <= mid - 3; ++j)
        ok_below = ok_below && (std::abs(flux[Dom::flux_idx(j)]) < 1.e-6f);
    for (int j = mid + 3; j <= Dom::je + 1; ++j)
        ok_above = ok_above && (std::abs(flux[Dom::flux_idx(j)] - 1.0f) < 1.e-6f);

    assert_test("step q, jord=8: 0 <= flux <= 1 (no overshoot)", ok_bounds);
    assert_test("step q, jord=8: flux==0 far below step (j=3..mid-3)", ok_below);
    assert_test("step q, jord=8: flux==1 far above step (j=mid+3..je+1)", ok_above);
}

// ---------------------------------------------------------------------------
// Test 6: Near-zero positive field, jord=-5 (positive-definite limiter)
// The jord<0 branch enforces al>=0; the limiter preserves non-negativity.
// ---------------------------------------------------------------------------
static void test_positive_definite() {
    std::vector<float> q   (Dom::sz_q,    1.e-20f);
    std::vector<float> cry (Dom::sz_cry,  0.5f);
    std::vector<float> dya (Dom::sz_dya,  1.0f);
    std::vector<float> flux(Dom::sz_flux);

    yppm_c(flux.data(), q.data(), cry.data(),
           -5, Dom::ifirst, Dom::ilast, Dom::isd, Dom::ied,
           Dom::js, Dom::je, Dom::jsd, Dom::jed,
           Dom::npx, Dom::npy, dya.data(), 1, 0, 1.0f);

    bool ok = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok = ok && (flux[Dom::flux_idx(j)] >= 0.0f);
    assert_test("near-zero q, jord=-5: all flux >= 0 (positive-definite)", ok);
}

// ===========================================================================
// Native C++ yppm tests (yppm.hpp)
// Same domain and inputs as the Fortran tests above.
// cry_col and dya_col are extracted from the 7-column arrays for i=ifirst=1.
// ===========================================================================
namespace {
    // NMAX >= je - js + 1 = 20
    static const int NMAX = 20;

    // Extract the single x-column (i=ifirst=1, ci=ifirst-isd=1-(-2)=3) from
    // a cry or dya array dimensioned (isd:ied, j_lo:j_hi).
    static void extract_col(float* col, const std::vector<float>& arr2d,
                             int ni, int ci, int nj)
    {
        for (int j = 0; j < nj; ++j)
            col[j] = arr2d[ci + ni * j];
    }
}

// ---------------------------------------------------------------------------
// C++ Test 1: Constant field, jord=8
// ---------------------------------------------------------------------------
static void test_cpp_constant_jord8() {
    std::vector<float> q  (Dom::sz_q,    1.0f);
    std::vector<float> cry(Dom::sz_cry,  0.5f);
    std::vector<float> dya(Dom::sz_dya,  1.0f);

    const int ni_cry = Dom::ied - Dom::isd + 1;  // 7
    const int ci     = Dom::ifirst - Dom::isd;    // 3

    float cry_col[NMAX + 3], dya_col[NMAX + 7];
    float flux_col[NMAX + 3];
    extract_col(cry_col, cry, ni_cry, ci, Dom::je - Dom::js + 2);
    extract_col(dya_col, dya, ni_cry, ci, Dom::jed - Dom::jsd + 1);

    fv3::ScratchYPPM<float, NMAX> scratch;
    fv3::yppm_col<float, NMAX>(
        flux_col, q.data() + Dom::q_idx(Dom::jsd), cry_col,
        8, Dom::js, Dom::je, Dom::jsd, Dom::jed, Dom::npx, Dom::npy,
        dya_col, true, 0, 1.0f, scratch);

    bool ok = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok = ok && (std::abs(flux_col[j - Dom::js] - 1.0f) < 1.e-6f);
    assert_test("C++: constant q=1, c=+0.5, jord=8: flux==1", ok);
}

// ---------------------------------------------------------------------------
// C++ Test 2: Constant field, jord=2
// ---------------------------------------------------------------------------
static void test_cpp_constant_jord2() {
    std::vector<float> q  (Dom::sz_q,    1.0f);
    std::vector<float> cry(Dom::sz_cry,  0.5f);
    std::vector<float> dya(Dom::sz_dya,  1.0f);

    const int ni_cry = Dom::ied - Dom::isd + 1;
    const int ci     = Dom::ifirst - Dom::isd;

    float cry_col[NMAX + 3], dya_col[NMAX + 7];
    float flux_col[NMAX + 3];
    extract_col(cry_col, cry, ni_cry, ci, Dom::je - Dom::js + 2);
    extract_col(dya_col, dya, ni_cry, ci, Dom::jed - Dom::jsd + 1);

    fv3::ScratchYPPM<float, NMAX> scratch;
    fv3::yppm_col<float, NMAX>(
        flux_col, q.data() + Dom::q_idx(Dom::jsd), cry_col,
        2, Dom::js, Dom::je, Dom::jsd, Dom::jed, Dom::npx, Dom::npy,
        dya_col, true, 0, 1.0f, scratch);

    bool ok = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok = ok && (std::abs(flux_col[j - Dom::js] - 1.0f) < 1.e-6f);
    assert_test("C++: constant q=1, c=+0.5, jord=2: flux==1", ok);
}

// ---------------------------------------------------------------------------
// C++ Test 3: Linear field q(j)=j, jord=8, c=+0.5 -> flux==j-0.75
// ---------------------------------------------------------------------------
static void test_cpp_linear_positive_courant() {
    std::vector<float> q  (Dom::sz_q);
    std::vector<float> cry(Dom::sz_cry,  0.5f);
    std::vector<float> dya(Dom::sz_dya,  1.0f);

    for (int j = Dom::jsd; j <= Dom::jed; ++j)
        q[Dom::q_idx(j)] = float(j);

    const int ni_cry = Dom::ied - Dom::isd + 1;
    const int ci     = Dom::ifirst - Dom::isd;

    float cry_col[NMAX + 3], dya_col[NMAX + 7];
    float flux_col[NMAX + 3];
    extract_col(cry_col, cry, ni_cry, ci, Dom::je - Dom::js + 2);
    extract_col(dya_col, dya, ni_cry, ci, Dom::jed - Dom::jsd + 1);

    fv3::ScratchYPPM<float, NMAX> scratch;
    fv3::yppm_col<float, NMAX>(
        flux_col, q.data() + Dom::q_idx(Dom::jsd), cry_col,
        8, Dom::js, Dom::je, Dom::jsd, Dom::jed, Dom::npx, Dom::npy,
        dya_col, true, 0, 1.0f, scratch);

    bool ok = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok = ok && (std::abs(flux_col[j - Dom::js] - (float(j) - 0.75f)) < 1.e-5f);
    assert_test("C++: linear q=j, c=+0.5, jord=8: flux==j-0.75", ok);
}

// ---------------------------------------------------------------------------
// C++ Test 4: Linear field q(j)=j, jord=8, c=-0.5 -> flux==j-0.25
// ---------------------------------------------------------------------------
static void test_cpp_linear_negative_courant() {
    std::vector<float> q  (Dom::sz_q);
    std::vector<float> cry(Dom::sz_cry, -0.5f);
    std::vector<float> dya(Dom::sz_dya,  1.0f);

    for (int j = Dom::jsd; j <= Dom::jed; ++j)
        q[Dom::q_idx(j)] = float(j);

    const int ni_cry = Dom::ied - Dom::isd + 1;
    const int ci     = Dom::ifirst - Dom::isd;

    float cry_col[NMAX + 3], dya_col[NMAX + 7];
    float flux_col[NMAX + 3];
    extract_col(cry_col, cry, ni_cry, ci, Dom::je - Dom::js + 2);
    extract_col(dya_col, dya, ni_cry, ci, Dom::jed - Dom::jsd + 1);

    fv3::ScratchYPPM<float, NMAX> scratch;
    fv3::yppm_col<float, NMAX>(
        flux_col, q.data() + Dom::q_idx(Dom::jsd), cry_col,
        8, Dom::js, Dom::je, Dom::jsd, Dom::jed, Dom::npx, Dom::npy,
        dya_col, true, 0, 1.0f, scratch);

    bool ok = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok = ok && (std::abs(flux_col[j - Dom::js] - (float(j) - 0.25f)) < 1.e-5f);
    assert_test("C++: linear q=j, c=-0.5, jord=8: flux==j-0.25", ok);
}

// ---------------------------------------------------------------------------
// C++ Test 5: Step function, jord=8
// Also verifies bit-exact agreement with Fortran yppm_c output.
// ---------------------------------------------------------------------------
static void test_cpp_monotone_bounds() {
    static const int mid = 11;
    std::vector<float> q  (Dom::sz_q);
    std::vector<float> cry(Dom::sz_cry,  0.5f);
    std::vector<float> dya(Dom::sz_dya,  1.0f);

    for (int j = Dom::jsd; j <= Dom::jed; ++j)
        q[Dom::q_idx(j)] = (j < mid) ? 0.0f : 1.0f;

    const int ni_cry = Dom::ied - Dom::isd + 1;
    const int ci     = Dom::ifirst - Dom::isd;

    float cry_col[NMAX + 3], dya_col[NMAX + 7];
    float flux_col_cpp[NMAX + 3];
    extract_col(cry_col, cry, ni_cry, ci, Dom::je - Dom::js + 2);
    extract_col(dya_col, dya, ni_cry, ci, Dom::jed - Dom::jsd + 1);

    fv3::ScratchYPPM<float, NMAX> scratch;
    fv3::yppm_col<float, NMAX>(
        flux_col_cpp, q.data() + Dom::q_idx(Dom::jsd), cry_col,
        8, Dom::js, Dom::je, Dom::jsd, Dom::jed, Dom::npx, Dom::npy,
        dya_col, true, 0, 1.0f, scratch);

    // Correctness: no overshoot, far-field exact
    bool ok_bounds = true, ok_below = true, ok_above = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j) {
        float f = flux_col_cpp[j - Dom::js];
        ok_bounds = ok_bounds && (f >= -1.e-6f) && (f <= 1.0f + 1.e-6f);
    }
    for (int j = 3; j <= mid - 3; ++j)
        ok_below = ok_below && (std::abs(flux_col_cpp[j - Dom::js]) < 1.e-6f);
    for (int j = mid + 3; j <= Dom::je + 1; ++j)
        ok_above = ok_above && (std::abs(flux_col_cpp[j - Dom::js] - 1.0f) < 1.e-6f);

    assert_test("C++: step q, jord=8: 0<=flux<=1 (no overshoot)", ok_bounds);
    assert_test("C++: step q, jord=8: matches Fortran (below+above step)", ok_below && ok_above);

    // Bit-exact agreement with Fortran: run yppm_c on same inputs and compare
    std::vector<float> flux_fortran(Dom::sz_flux);
    yppm_c(flux_fortran.data(), q.data(), cry.data(),
           8, Dom::ifirst, Dom::ilast, Dom::isd, Dom::ied,
           Dom::js, Dom::je, Dom::jsd, Dom::jed,
           Dom::npx, Dom::npy, dya.data(), 1, 0, 1.0f);

    bool ok_exact = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok_exact = ok_exact && (flux_col_cpp[j - Dom::js] == flux_fortran[Dom::flux_idx(j)]);
    assert_test("C++: step q, jord=8: bit-exact agreement with Fortran", ok_exact);
}

// ---------------------------------------------------------------------------
// C++ Test 6: Near-zero q, jord=-5 (positive-definite)
// ---------------------------------------------------------------------------
static void test_cpp_positive_definite() {
    std::vector<float> q  (Dom::sz_q,    1.e-20f);
    std::vector<float> cry(Dom::sz_cry,  0.5f);
    std::vector<float> dya(Dom::sz_dya,  1.0f);

    const int ni_cry = Dom::ied - Dom::isd + 1;
    const int ci     = Dom::ifirst - Dom::isd;

    float cry_col[NMAX + 3], dya_col[NMAX + 7];
    float flux_col[NMAX + 3];
    extract_col(cry_col, cry, ni_cry, ci, Dom::je - Dom::js + 2);
    extract_col(dya_col, dya, ni_cry, ci, Dom::jed - Dom::jsd + 1);

    fv3::ScratchYPPM<float, NMAX> scratch;
    fv3::yppm_col<float, NMAX>(
        flux_col, q.data() + Dom::q_idx(Dom::jsd), cry_col,
        -5, Dom::js, Dom::je, Dom::jsd, Dom::jed, Dom::npx, Dom::npy,
        dya_col, true, 0, 1.0f, scratch);

    bool ok = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok = ok && (flux_col[j - Dom::js] >= 0.0f);
    assert_test("C++: near-zero q, jord=-5: all flux >= 0 (positive-definite)", ok);
}

// ---------------------------------------------------------------------------
int main() {
    test_constant_jord8();
    test_constant_jord2();
    test_linear_positive_courant();
    test_linear_negative_courant();
    test_monotone_bounds();
    test_positive_definite();

    std::cout << "\n--- Native C++ yppm (yppm.hpp) tests ---\n";
    test_cpp_constant_jord8();
    test_cpp_constant_jord2();
    test_cpp_linear_positive_courant();
    test_cpp_linear_negative_courant();
    test_cpp_monotone_bounds();
    test_cpp_positive_definite();

    if (n_failed == 0) {
        std::cout << "All tests PASSED\n";
        return 0;
    }
    std::cout << "FAIL: " << n_failed << " test(s) failed\n";
    return 1;
}
