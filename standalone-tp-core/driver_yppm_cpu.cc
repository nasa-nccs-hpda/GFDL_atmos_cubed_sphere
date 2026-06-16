// driver_yppm_cpu.cc — CPU baseline benchmark for yppm (same algorithm as the
// GPU driver), for an apples-to-apples CPU-vs-GPU comparison.
//
//   Usage: yppm-driver-cpu <resolution> <iterations> [levels]
//
// Builds the SAME synthetic tile and column-contiguous layout as
// driver_yppm_gpu.cu, then runs the host yppm_col over all ncol columns in a
// timed loop (one shared runtime-sized scratch, reused serially). Timing
// covers compute only (no host/device copies exist here), matching the
// kernel-only timing of the GPU driver. The checksum should match the GPU
// driver's to FMA tolerance.
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <chrono>
#include <vector>

#include "yppm.hpp"

using Real = float;

int main(int argc, char** argv)
{
    if (argc < 3 || argc > 4) {
        fprintf(stderr, "Usage: %s <resolution> <iterations> [levels]\n", argv[0]);
        return 2;
    }
    const int n      = std::atoi(argv[1]);
    const int n_iter = std::atoi(argv[2]);
    const int levels = (argc == 4) ? std::atoi(argv[3]) : 1;
    if (n < 1 || n_iter < 1 || levels < 1) {
        fprintf(stderr, "resolution, iterations, and levels must be >= 1\n");
        return 2;
    }

    const int ng     = 3;
    const int jord   = 8;
    const Real lim_fac = Real(1);
    const bool nested  = false;
    const int grid_type = 0;

    const int ifirst = 1,        ilast = n;
    const int isd    = ifirst-ng, ied  = ilast+ng;
    const int js     = 1,        je    = n;
    const int jsd    = js-ng,    jed   = je+ng;
    const int npx    = n+1,      npy   = n+1;

    const int ni      = ied - isd + 1;
    const long ncol   = static_cast<long>(ni) * levels;
    const int nj      = je  - js  + 1;
    const int nj_q    = jed - jsd + 1;
    const int nj_flux = je  - js  + 2;

    printf("yppm CPU driver: resolution=%d iterations=%d levels=%d ncol=%ld\n",
           n, n_iter, levels, ncol);

    std::vector<Real> q   (static_cast<size_t>(ncol) * nj_q);
    std::vector<Real> dya (static_cast<size_t>(ncol) * nj_q,    Real(1));
    std::vector<Real> cry (static_cast<size_t>(ncol) * nj_flux, Real(0.5));
    std::vector<Real> flux(static_cast<size_t>(ncol) * nj_flux, Real(0));

    const double two_pi = 6.283185307179586;
    for (long col = 0; col < ncol; ++col) {
        Real* qc = q.data() + col * nj_q;
        for (int j = 0; j < nj_q; ++j)
            qc[j] = Real(1.0 + 0.5 * std::cos(two_pi * double(j) / double(nj_q)));
    }

    // One runtime-sized scratch, reused across columns (serial).
    std::vector<Real> rbuf(fv3::yppm_scratch_real_words(nj));
    std::vector<char> bbuf(fv3::yppm_scratch_bool_words(nj));
    fv3::ScratchYPPMView<Real> s = fv3::yppm_make_scratch_view<Real>(
        rbuf.data(), reinterpret_cast<bool*>(bbuf.data()), nj);

    auto t0 = std::chrono::steady_clock::now();
    for (int it = 0; it < n_iter; ++it) {
        for (long col = 0; col < ncol; ++col) {
            fv3::yppm_col<Real>(
                flux.data() + col * nj_flux,
                q.data()    + col * nj_q,
                cry.data()  + col * nj_flux,
                jord, js, je, jsd, jed, npx, npy,
                dya.data()  + col * nj_q,
                nested, grid_type, lim_fac, s);
        }
    }
    auto t1 = std::chrono::steady_clock::now();
    const double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    double sum = 0.0;
    for (size_t i = 0; i < flux.size(); ++i) sum += double(flux[i]);

    printf("time taken: %.6f s  (%.4f ms/iter over %d iters)\n",
           ms / 1000.0, ms / double(n_iter), n_iter);
    printf("sum(flux): %.10e\n", sum);
    return 0;
}
