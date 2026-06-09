// test_yppm_gpu.cu — GPU unit tests for the multi-column yppm launch API.
//
// Strategy: drive the reusable fv3::yppm_gpu launch (one thread per column,
// per-column scratch from one runtime-sized device buffer). Each test column
// is replicated into NCOL identical columns; the launch must (a) reproduce the
// CPU yppm_col result bit-for-bit and (b) produce identical output for every
// replicated column, which exercises the per-thread column indexing.
//
// Each test:
//   1. Fills host input arrays (same domain as test_yppm_cpp.cpp).
//   2. Calls run_gpu, which replicates the column and runs fv3::yppm_gpu.
//   3. Checks analytic expectations and bit-exact agreement vs the CPU ref.
//
// Domain: n=20, ng=3, ifirst=ilast=1, nested=true
//   isd=-2, ied=4, js=1, je=20, jsd=-2, jed=23, npx=2, npy=21
//
// Build (A100, sm_80):
//   nvcc -std=c++14 -arch=sm_80 test_yppm_gpu.cu -o test_yppm_gpu
//
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "yppm.hpp"
#include "yppm_gpu.cuh"

// ---------------------------------------------------------------------------
// CUDA error-checking macro
// ---------------------------------------------------------------------------
#define CUDA_CHECK(call)                                                        \
    do {                                                                        \
        cudaError_t _e = (call);                                                \
        if (_e != cudaSuccess) {                                                \
            fprintf(stderr, "CUDA error %s:%d: %s\n",                          \
                    __FILE__, __LINE__, cudaGetErrorString(_e));                 \
            exit(1);                                                             \
        }                                                                       \
    } while (0)

// ---------------------------------------------------------------------------
// Domain constants (identical to test_yppm_cpp.cpp)
// ---------------------------------------------------------------------------
namespace Dom {
    static const int n      = 20;
    static const int ng     = 3;
    static const int ifirst = 1,       ilast = 1;
    static const int isd    = ifirst - ng;   // -2
    static const int ied    = ilast  + ng;   //  4
    static const int js     = 1,       je  = n;
    static const int jsd    = js - ng;       // -2
    static const int jed    = je + ng;       // 23
    static const int npx    = 2,       npy = n + 1;

    static const int sz_q    = (jed - jsd + 1);              // 26
    static const int sz_flux = (je  - js  + 2);              // 21
    static const int sz_cry  = (je  - js  + 2);              // 21 (single col)
    static const int sz_dya  = (jed - jsd + 1);              // 26 (single col)

    inline int q_idx(int j)    { return j - jsd; }
    inline int flux_idx(int j) { return j - js; }
}

static const int NMAX = 20;

// ---------------------------------------------------------------------------
// Test infrastructure
// ---------------------------------------------------------------------------
static int n_failed = 0;

static void check(const char* name, bool passed) {
    printf("%s: %s\n", passed ? "PASS" : "FAIL", name);
    if (!passed) ++n_failed;
}

// ---------------------------------------------------------------------------
// CPU reference: run yppm_col on host data, return flux array.
// ---------------------------------------------------------------------------
static std::vector<float> cpu_ref(
    const float* q_col,        // length sz_q,    indexed from q_idx(jsd)
    const float* cry_col,      // length sz_cry,  indexed from 0 -> flux_idx(js)
    const float* dya_col,      // length sz_dya,  indexed from q_idx(jsd)
    int jord)
{
    std::vector<float> flux(Dom::sz_flux, 0.f);
    fv3::ScratchYPPM<float, NMAX> scratch;
    fv3::yppm_col<float>(
        flux.data(), q_col, cry_col,
        jord, Dom::js, Dom::je, Dom::jsd, Dom::jed, Dom::npx, Dom::npy,
        dya_col, true, 0, 1.0f, scratch.view(NMAX));
    return flux;
}

// ---------------------------------------------------------------------------
// Number of identical columns to replicate for the multi-column launch.
// Running several columns through the real launch API and requiring identical
// output proves the per-thread column indexing in the kernel — not just the
// single-column math.
// ---------------------------------------------------------------------------
static const int NCOL = 5;

// ---------------------------------------------------------------------------
// Multi-column GPU run via the reusable launch API (fv3::yppm_gpu).
// Replicates the single test column into NCOL columns (column-contiguous),
// runs them all, asserts every column produced identical output, and returns
// column 0's flux for the analytic / bit-exact comparisons.
// ---------------------------------------------------------------------------
static std::vector<float> run_gpu(
    const float* h_q,    // length Dom::sz_q    (== nj_q)
    const float* h_cry,  // length Dom::sz_cry  (== nj_flux)
    const float* h_dya,  // length Dom::sz_dya  (== nj_q)
    int jord)
{
    const int nj_q    = Dom::sz_q;     // jed - jsd + 1
    const int nj_flux = Dom::sz_flux;  // je  - js  + 2

    std::vector<float> q_all   (static_cast<size_t>(NCOL) * nj_q);
    std::vector<float> dya_all (static_cast<size_t>(NCOL) * nj_q);
    std::vector<float> cry_all (static_cast<size_t>(NCOL) * nj_flux);
    std::vector<float> flux_all(static_cast<size_t>(NCOL) * nj_flux, 0.f);

    for (int t = 0; t < NCOL; ++t) {
        for (int j = 0; j < nj_q; ++j) {
            q_all  [t * nj_q + j] = h_q  [j];
            dya_all[t * nj_q + j] = h_dya[j];
        }
        for (int j = 0; j < nj_flux; ++j)
            cry_all[t * nj_flux + j] = h_cry[j];
    }

    cudaError_t e = fv3::yppm_gpu<float>(
        flux_all.data(), q_all.data(), cry_all.data(), dya_all.data(),
        NCOL, jord, Dom::js, Dom::je, Dom::jsd, Dom::jed, Dom::npx, Dom::npy,
        true, 0, 1.0f);
    if (e != cudaSuccess) {
        fprintf(stderr, "yppm_gpu failed: %s\n", cudaGetErrorString(e));
        exit(1);
    }

    bool all_equal = true;
    for (int t = 1; t < NCOL; ++t)
        for (int j = 0; j < nj_flux; ++j)
            if (flux_all[t * nj_flux + j] != flux_all[j]) all_equal = false;
    check("GPU: multi-column launch produces identical columns", all_equal);

    return std::vector<float>(flux_all.begin(), flux_all.begin() + nj_flux);
}

// ---------------------------------------------------------------------------
// Compare GPU and CPU flux: require bit-exact agreement
// ---------------------------------------------------------------------------
static bool compare(const std::vector<float>& gpu, const std::vector<float>& cpu) {
    if (gpu.size() != cpu.size()) return false;
    for (size_t i = 0; i < gpu.size(); ++i)
        if (gpu[i] != cpu[i]) return false;
    return true;
}

// ---------------------------------------------------------------------------
// Test 1: Constant q=1, cry=+0.5, jord=8  -> flux == 1 everywhere
// ---------------------------------------------------------------------------
static void test_constant_jord8() {
    std::vector<float> q  (Dom::sz_q,    1.0f);
    std::vector<float> cry(Dom::sz_cry,  0.5f);
    std::vector<float> dya(Dom::sz_dya,  1.0f);

    auto gpu_flux = run_gpu(q.data(), cry.data(), dya.data(), 8);
    auto cpu_flux = cpu_ref(q.data(), cry.data(), dya.data(), 8);

    bool ok_val = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok_val = ok_val && (std::abs(gpu_flux[Dom::flux_idx(j)] - 1.0f) < 1.e-6f);

    check("GPU: constant q=1, c=+0.5, jord=8: flux==1", ok_val);
    check("GPU: constant q=1, c=+0.5, jord=8: bit-exact vs CPU", compare(gpu_flux, cpu_flux));
}

// ---------------------------------------------------------------------------
// Test 2: Constant q=1, cry=+0.5, jord=2  -> flux == 1 everywhere
// ---------------------------------------------------------------------------
static void test_constant_jord2() {
    std::vector<float> q  (Dom::sz_q,    1.0f);
    std::vector<float> cry(Dom::sz_cry,  0.5f);
    std::vector<float> dya(Dom::sz_dya,  1.0f);

    auto gpu_flux = run_gpu(q.data(), cry.data(), dya.data(), 2);
    auto cpu_flux = cpu_ref(q.data(), cry.data(), dya.data(), 2);

    bool ok_val = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok_val = ok_val && (std::abs(gpu_flux[Dom::flux_idx(j)] - 1.0f) < 1.e-6f);

    check("GPU: constant q=1, c=+0.5, jord=2: flux==1", ok_val);
    check("GPU: constant q=1, c=+0.5, jord=2: bit-exact vs CPU", compare(gpu_flux, cpu_flux));
}

// ---------------------------------------------------------------------------
// Test 3: Linear q(j)=j, cry=+0.5, jord=8  -> flux==j-0.75
// ---------------------------------------------------------------------------
static void test_linear_positive_courant() {
    std::vector<float> q  (Dom::sz_q);
    std::vector<float> cry(Dom::sz_cry,  0.5f);
    std::vector<float> dya(Dom::sz_dya,  1.0f);

    for (int j = Dom::jsd; j <= Dom::jed; ++j)
        q[Dom::q_idx(j)] = float(j);

    auto gpu_flux = run_gpu(q.data(), cry.data(), dya.data(), 8);
    auto cpu_flux = cpu_ref(q.data(), cry.data(), dya.data(), 8);

    bool ok_val = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok_val = ok_val && (std::abs(gpu_flux[Dom::flux_idx(j)] - (float(j) - 0.75f)) < 1.e-5f);

    check("GPU: linear q=j, c=+0.5, jord=8: flux==j-0.75", ok_val);
    check("GPU: linear q=j, c=+0.5, jord=8: bit-exact vs CPU", compare(gpu_flux, cpu_flux));
}

// ---------------------------------------------------------------------------
// Test 4: Linear q(j)=j, cry=-0.5, jord=8  -> flux==j-0.25
// ---------------------------------------------------------------------------
static void test_linear_negative_courant() {
    std::vector<float> q  (Dom::sz_q);
    std::vector<float> cry(Dom::sz_cry, -0.5f);
    std::vector<float> dya(Dom::sz_dya,  1.0f);

    for (int j = Dom::jsd; j <= Dom::jed; ++j)
        q[Dom::q_idx(j)] = float(j);

    auto gpu_flux = run_gpu(q.data(), cry.data(), dya.data(), 8);
    auto cpu_flux = cpu_ref(q.data(), cry.data(), dya.data(), 8);

    bool ok_val = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok_val = ok_val && (std::abs(gpu_flux[Dom::flux_idx(j)] - (float(j) - 0.25f)) < 1.e-5f);

    check("GPU: linear q=j, c=-0.5, jord=8: flux==j-0.25", ok_val);
    check("GPU: linear q=j, c=-0.5, jord=8: bit-exact vs CPU", compare(gpu_flux, cpu_flux));
}

// ---------------------------------------------------------------------------
// Test 5: Step function, jord=8  -> no overshoot; far-field exact
// ---------------------------------------------------------------------------
static void test_step_monotone() {
    static const int mid = 11;
    std::vector<float> q  (Dom::sz_q);
    std::vector<float> cry(Dom::sz_cry,  0.5f);
    std::vector<float> dya(Dom::sz_dya,  1.0f);

    for (int j = Dom::jsd; j <= Dom::jed; ++j)
        q[Dom::q_idx(j)] = (j < mid) ? 0.0f : 1.0f;

    auto gpu_flux = run_gpu(q.data(), cry.data(), dya.data(), 8);
    auto cpu_flux = cpu_ref(q.data(), cry.data(), dya.data(), 8);

    bool ok_bounds = true, ok_below = true, ok_above = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j) {
        float f = gpu_flux[Dom::flux_idx(j)];
        ok_bounds = ok_bounds && (f >= -1.e-6f) && (f <= 1.0f + 1.e-6f);
    }
    for (int j = 3; j <= mid - 3; ++j)
        ok_below = ok_below && (std::abs(gpu_flux[Dom::flux_idx(j)]) < 1.e-6f);
    for (int j = mid + 3; j <= Dom::je + 1; ++j)
        ok_above = ok_above && (std::abs(gpu_flux[Dom::flux_idx(j)] - 1.0f) < 1.e-6f);

    check("GPU: step q, jord=8: 0<=flux<=1 (no overshoot)", ok_bounds);
    check("GPU: step q, jord=8: far-field exact (below+above step)", ok_below && ok_above);
    check("GPU: step q, jord=8: bit-exact vs CPU", compare(gpu_flux, cpu_flux));
}

// ---------------------------------------------------------------------------
// Test 6: Near-zero q, jord=-5 (positive-definite)  -> all flux >= 0
// ---------------------------------------------------------------------------
static void test_positive_definite() {
    std::vector<float> q  (Dom::sz_q,    1.e-20f);
    std::vector<float> cry(Dom::sz_cry,  0.5f);
    std::vector<float> dya(Dom::sz_dya,  1.0f);

    auto gpu_flux = run_gpu(q.data(), cry.data(), dya.data(), -5);
    auto cpu_flux = cpu_ref(q.data(), cry.data(), dya.data(), -5);

    bool ok = true;
    for (int j = Dom::js; j <= Dom::je + 1; ++j)
        ok = ok && (gpu_flux[Dom::flux_idx(j)] >= 0.0f);

    check("GPU: near-zero q, jord=-5: all flux >= 0 (positive-definite)", ok);
    check("GPU: near-zero q, jord=-5: bit-exact vs CPU", compare(gpu_flux, cpu_flux));
}

// ---------------------------------------------------------------------------
int main() {
    int dev = 0;
    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, dev));
    printf("GPU: %s (SM %d.%d)\n\n", prop.name, prop.major, prop.minor);

    test_constant_jord8();
    test_constant_jord2();
    test_linear_positive_courant();
    test_linear_negative_courant();
    test_step_monotone();
    test_positive_definite();

    printf("\n");
    if (n_failed == 0) {
        printf("All tests PASSED\n");
        return 0;
    }
    printf("FAIL: %d test(s) failed\n", n_failed);
    return 1;
}
