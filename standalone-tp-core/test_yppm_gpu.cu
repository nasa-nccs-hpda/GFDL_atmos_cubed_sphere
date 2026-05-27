// test_yppm_gpu.cu — GPU unit tests for yppm_col via CUDA kernel.
//
// Strategy: 1 thread per x-column; ScratchYPPM lives in thread-local
// (register/local) memory. For NMAX=20 the scratch is ~670 bytes —
// well within CUDA per-thread local memory limits on A100.
//
// Each test:
//   1. Fills host input arrays (same domain as test_yppm_cpp.cpp).
//   2. Copies them to device.
//   3. Launches a single-thread kernel that calls yppm_col<float,NMAX>.
//   4. Copies flux output back to host.
//   5. Compares to CPU reference produced by the same yppm_col.
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
    fv3::yppm_col<float, NMAX>(
        flux.data(), q_col, cry_col,
        jord, Dom::js, Dom::je, Dom::jsd, Dom::jed, Dom::npx, Dom::npy,
        dya_col, true, 0, 1.0f, scratch);
    return flux;
}

// ---------------------------------------------------------------------------
// GPU kernel: one thread, one x-column
// All arrays are offset-adjusted by the caller to start at index 0.
// ---------------------------------------------------------------------------
__global__
void yppm_kernel(
    float*       flux_col,   // output [sz_flux]
    const float* q_col,      // [sz_q]
    const float* cry_col,    // [sz_cry]
    const float* dya_col,    // [sz_dya]
    int jord, int js, int je, int jsd, int jed,
    int npx, int npy, bool nested, int grid_type, float lim_fac)
{
    fv3::ScratchYPPM<float, NMAX> scratch;
    fv3::yppm_col<float, NMAX>(
        flux_col, q_col, cry_col,
        jord, js, je, jsd, jed, npx, npy,
        dya_col, nested, grid_type, lim_fac, scratch);
}

// ---------------------------------------------------------------------------
// Launch helper: copies host arrays to device, runs kernel, copies back.
// Returns host-side flux output.
// ---------------------------------------------------------------------------
static std::vector<float> run_gpu(
    const float* h_q,    // length Dom::sz_q
    const float* h_cry,  // length Dom::sz_cry
    const float* h_dya,  // length Dom::sz_dya
    int jord)
{
    float *d_q, *d_cry, *d_dya, *d_flux;
    CUDA_CHECK(cudaMalloc(&d_q,    Dom::sz_q    * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_cry,  Dom::sz_cry  * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_dya,  Dom::sz_dya  * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_flux, Dom::sz_flux * sizeof(float)));
    CUDA_CHECK(cudaMemset(d_flux, 0, Dom::sz_flux * sizeof(float)));

    CUDA_CHECK(cudaMemcpy(d_q,   h_q,   Dom::sz_q   * sizeof(float), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_cry, h_cry, Dom::sz_cry * sizeof(float), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_dya, h_dya, Dom::sz_dya * sizeof(float), cudaMemcpyHostToDevice));

    yppm_kernel<<<1, 1>>>(
        d_flux, d_q, d_cry, d_dya,
        jord, Dom::js, Dom::je, Dom::jsd, Dom::jed,
        Dom::npx, Dom::npy, true, 0, 1.0f);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());

    std::vector<float> h_flux(Dom::sz_flux);
    CUDA_CHECK(cudaMemcpy(h_flux.data(), d_flux, Dom::sz_flux * sizeof(float), cudaMemcpyDeviceToHost));

    cudaFree(d_q); cudaFree(d_cry); cudaFree(d_dya); cudaFree(d_flux);
    return h_flux;
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
