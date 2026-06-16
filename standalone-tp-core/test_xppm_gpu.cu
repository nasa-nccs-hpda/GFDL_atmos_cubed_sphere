// test_xppm_gpu.cu — GPU unit tests for the multi-row xppm launch API.
//
// Mirrors test_yppm_gpu.cu in the i-direction. Each test row is replicated
// into NCOL identical rows; the launch must (a) reproduce the CPU xppm_col
// result bit-for-bit and (b) produce identical output for every replicated
// row (exercising the per-thread row indexing).
//
// Coverage:
//   - 6 analytic scenarios (nested=true), mirroring the yppm GPU test.
//   - A comprehensive GPU-vs-CPU sweep over every iord, with the cubed-sphere
//     boundary code both off (nested) and on (nested=false).
//
// Domain (single j-row, sweep over i, ng=3 halo):
//   is=1, ie=20, isd=-2, ied=23, npx=21, npy=2
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

#include "xppm.hpp"
#include "xppm_gpu.cuh"

#define CUDA_CHECK(call)                                                        \
    do {                                                                        \
        cudaError_t _e = (call);                                                \
        if (_e != cudaSuccess) {                                                \
            fprintf(stderr, "CUDA error %s:%d: %s\n",                           \
                    __FILE__, __LINE__, cudaGetErrorString(_e));                \
            exit(1);                                                            \
        }                                                                       \
    } while (0)

namespace Dom {
    static const int n      = 20;
    static const int ng     = 3;
    static const int is     = 1,      ie  = n;
    static const int isd    = is - ng;       // -2
    static const int ied    = ie + ng;       // 23
    static const int npx    = n + 1,  npy = 2;

    static const int nj_q    = ied - isd + 1;   // 26  (q/dxa per row)
    static const int nj_flux = ie  - is  + 2;   // 21  (c/flux per row)

    inline int q_idx(int i)    { return i - isd; }
    inline int flux_idx(int i) { return i - is;  }
}

static const int NMAX = 20;   // >= ie - is + 1
static const int NCOL = 5;    // replicated identical rows

static int n_failed = 0;
static void check(const char* name, bool passed) {
    printf("%s: %s\n", passed ? "PASS" : "FAIL", name);
    if (!passed) ++n_failed;
}

// ---------------------------------------------------------------------------
// CPU reference: run xppm_col on host data, return flux row.
// ---------------------------------------------------------------------------
static std::vector<float> cpu_ref(const float* q_row, const float* c_row,
                                  const float* dxa_row, int iord, bool nested)
{
    std::vector<float> flux(Dom::nj_flux, 0.f);
    fv3::ScratchXPPM<float, NMAX> scratch;
    fv3::xppm_col<float>(
        flux.data(), q_row, c_row, iord,
        Dom::is, Dom::ie, Dom::isd, Dom::ied, Dom::npx, Dom::npy,
        dxa_row, nested, 0, 1.0f, scratch.view(NMAX));
    return flux;
}

// ---------------------------------------------------------------------------
// Multi-row GPU run via the reusable launch API (fv3::xppm_gpu).
// Replicates the single test row into NCOL rows (row-contiguous), runs them
// all, asserts every row is identical, and returns row 0's flux.
// ---------------------------------------------------------------------------
static std::vector<float> run_gpu(const float* q_row, const float* c_row,
                                  const float* dxa_row, int iord, bool nested)
{
    const int nj_q    = Dom::nj_q;
    const int nj_flux = Dom::nj_flux;

    std::vector<float> q_all   (static_cast<size_t>(NCOL) * nj_q);
    std::vector<float> dxa_all (static_cast<size_t>(NCOL) * nj_q);
    std::vector<float> c_all   (static_cast<size_t>(NCOL) * nj_flux);
    std::vector<float> flux_all(static_cast<size_t>(NCOL) * nj_flux, 0.f);

    for (int t = 0; t < NCOL; ++t) {
        for (int i = 0; i < nj_q; ++i) {
            q_all  [t * nj_q + i] = q_row  [i];
            dxa_all[t * nj_q + i] = dxa_row[i];
        }
        for (int i = 0; i < nj_flux; ++i)
            c_all[t * nj_flux + i] = c_row[i];
    }

    cudaError_t e = fv3::xppm_gpu<float>(
        flux_all.data(), q_all.data(), c_all.data(), dxa_all.data(),
        NCOL, iord, Dom::is, Dom::ie, Dom::isd, Dom::ied, Dom::npx, Dom::npy,
        nested, 0, 1.0f);
    if (e != cudaSuccess) {
        fprintf(stderr, "xppm_gpu failed: %s\n", cudaGetErrorString(e));
        exit(1);
    }

    bool all_equal = true;
    for (int t = 1; t < NCOL; ++t)
        for (int i = 0; i < nj_flux; ++i)
            if (flux_all[t * nj_flux + i] != flux_all[i]) all_equal = false;
    check("GPU: multi-row launch produces identical rows", all_equal);

    return std::vector<float>(flux_all.begin(), flux_all.begin() + nj_flux);
}

static bool bit_equal(const std::vector<float>& a, const std::vector<float>& b) {
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); ++i) if (a[i] != b[i]) return false;
    return true;
}

// ---------------------------------------------------------------------------
// Analytic scenarios (nested=true), mirroring the yppm GPU test.
// ---------------------------------------------------------------------------
static void test_constant(int iord) {
    std::vector<float> q(Dom::nj_q, 1.0f), c(Dom::nj_flux, 0.5f), dxa(Dom::nj_q, 1.0f);
    auto g = run_gpu(q.data(), c.data(), dxa.data(), iord, true);
    auto r = cpu_ref(q.data(), c.data(), dxa.data(), iord, true);
    bool okv = true;
    for (int i = Dom::is; i <= Dom::ie + 1; ++i)
        okv = okv && (std::abs(g[Dom::flux_idx(i)] - 1.0f) < 1.e-6f);
    char buf[96]; snprintf(buf, sizeof buf, "GPU: constant q=1, c=+0.5, iord=%d: flux==1", iord);
    check(buf, okv);
    snprintf(buf, sizeof buf, "GPU: constant q=1, c=+0.5, iord=%d: bit-exact vs CPU", iord);
    check(buf, bit_equal(g, r));
}

static void test_linear(float courant, float off) {
    std::vector<float> q(Dom::nj_q), c(Dom::nj_flux, courant), dxa(Dom::nj_q, 1.0f);
    for (int i = Dom::isd; i <= Dom::ied; ++i) q[Dom::q_idx(i)] = float(i);
    auto g = run_gpu(q.data(), c.data(), dxa.data(), 8, true);
    auto r = cpu_ref(q.data(), c.data(), dxa.data(), 8, true);
    bool okv = true;
    for (int i = Dom::is; i <= Dom::ie + 1; ++i)
        okv = okv && (std::abs(g[Dom::flux_idx(i)] - (float(i) - off)) < 1.e-5f);
    char buf[96]; snprintf(buf, sizeof buf, "GPU: linear q=i, c=%.1f, iord=8: flux==i-%.2f", courant, off);
    check(buf, okv);
    snprintf(buf, sizeof buf, "GPU: linear q=i, c=%.1f, iord=8: bit-exact vs CPU", courant);
    check(buf, bit_equal(g, r));
}

static void test_step_monotone() {
    std::vector<float> q(Dom::nj_q), c(Dom::nj_flux, 0.5f), dxa(Dom::nj_q, 1.0f);
    const int mid = 11;
    for (int i = Dom::isd; i <= Dom::ied; ++i) q[Dom::q_idx(i)] = (i < mid) ? 0.0f : 1.0f;
    auto g = run_gpu(q.data(), c.data(), dxa.data(), 8, true);
    auto r = cpu_ref(q.data(), c.data(), dxa.data(), 8, true);
    bool ok_bounds = true;
    for (int i = Dom::is; i <= Dom::ie + 1; ++i) {
        float f = g[Dom::flux_idx(i)];
        ok_bounds = ok_bounds && (f >= -1.e-6f) && (f <= 1.0f + 1.e-6f);
    }
    check("GPU: step q, iord=8: 0<=flux<=1 (no overshoot)", ok_bounds);
    check("GPU: step q, iord=8: bit-exact vs CPU", bit_equal(g, r));
}

static void test_positive_definite() {
    std::vector<float> q(Dom::nj_q, 1.e-20f), c(Dom::nj_flux, 0.5f), dxa(Dom::nj_q, 1.0f);
    auto g = run_gpu(q.data(), c.data(), dxa.data(), -5, true);
    auto r = cpu_ref(q.data(), c.data(), dxa.data(), -5, true);
    bool ok = true;
    for (int i = Dom::is; i <= Dom::ie + 1; ++i) ok = ok && (g[Dom::flux_idx(i)] >= 0.0f);
    check("GPU: near-zero q, iord=-5: all flux >= 0 (positive-definite)", ok);
    check("GPU: near-zero q, iord=-5: bit-exact vs CPU", bit_equal(g, r));
}

static float max_abs_diff(const std::vector<float>& a, const std::vector<float>& b) {
    float m = 0.f;
    for (int i = Dom::is; i <= Dom::ie + 1; ++i) {
        const float d = std::abs(a[Dom::flux_idx(i)] - b[Dom::flux_idx(i)]);
        if (d > m) m = d;
    }
    return m;
}

// ---------------------------------------------------------------------------
// Comprehensive GPU-vs-CPU sweep over all iords, boundary off and on.
//
// GPU (device) and CPU (host) run the SAME xppm_col, but nvcc contracts
// a*b + c into fused multiply-adds on the device and not on the host, so the
// results agree only to ~1 ULP for general fields (they are bit-identical for
// the exactly-representable named scenarios above). Require a tight tolerance,
// not bit-exactness, and print the magnitude so any real divergence is visible.
// The host port itself is checked against Fortran in test_xppm_cpp.
// ---------------------------------------------------------------------------
static void sweep_gpu_vs_cpu(const std::vector<float>& q, const std::vector<float>& c,
                             const std::vector<float>& dxa, const char* label)
{
    const float TOL = 1.e-5f;
    const int iords[] = {1, 2, 3, 4, 5, -5, 6, 7, 8, 9, 10, 11, 12, 13};
    for (int ni = 0; ni < 2; ++ni) {
        const bool nested = (ni == 0);
        for (int k = 0; k < (int)(sizeof(iords)/sizeof(iords[0])); ++k) {
            const int iord = iords[k];
            auto g = run_gpu(q.data(), c.data(), dxa.data(), iord, nested);
            auto r = cpu_ref(q.data(), c.data(), dxa.data(), iord, nested);
            const float md = max_abs_diff(g, r);
            char buf[160];
            snprintf(buf, sizeof buf,
                     "GPU vs CPU [%s, nested=%c, iord=%d]: max|diff|=%.2e < %.0e",
                     label, nested ? 'T' : 'F', iord, md, TOL);
            check(buf, md < TOL);
        }
    }
}

int main() {
    int dev = 0;
    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, dev));
    printf("GPU: %s (SM %d.%d)\n\n", prop.name, prop.major, prop.minor);

    test_constant(8);
    test_constant(2);
    test_linear( 0.5f, 0.75f);
    test_linear(-0.5f, 0.25f);
    test_step_monotone();
    test_positive_definite();

    // Sweep over all paths with a smooth field and a step field.
    {
        std::vector<float> q(Dom::nj_q), c(Dom::nj_flux, 0.5f), dxa(Dom::nj_q, 1.0f);
        const double two_pi = 6.283185307179586;
        for (int i = Dom::isd; i <= Dom::ied; ++i)
            q[Dom::q_idx(i)] = float(1.0 + 0.5 * std::sin(two_pi * double(i - Dom::isd) / double(Dom::nj_q)));
        sweep_gpu_vs_cpu(q, c, dxa, "smooth");
    }
    {
        std::vector<float> q(Dom::nj_q), c(Dom::nj_flux, 0.5f), dxa(Dom::nj_q, 1.0f);
        for (int i = Dom::isd; i <= Dom::ied; ++i) q[Dom::q_idx(i)] = (i < 11) ? 0.0f : 1.0f;
        sweep_gpu_vs_cpu(q, c, dxa, "step");
    }

    printf("\n");
    if (n_failed == 0) { printf("All tests PASSED\n"); return 0; }
    printf("FAIL: %d test(s) failed\n", n_failed);
    return 1;
}
