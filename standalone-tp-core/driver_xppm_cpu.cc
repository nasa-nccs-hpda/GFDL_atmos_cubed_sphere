// driver_xppm_cpu.cc — CPU baseline benchmark for xppm (same algorithm as the
// GPU driver), for an apples-to-apples CPU-vs-GPU comparison.
//
//   Usage: xppm-driver-cpu <resolution> <iterations> [levels]
//
// Builds the SAME synthetic tile and row-contiguous layout as
// driver_xppm_gpu.cu, then runs the host xppm_col over all ncol rows in a
// timed loop (one shared runtime-sized scratch, reused serially). Timing
// covers compute only, matching the kernel-only timing of the GPU driver.
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <chrono>
#include <vector>

#include "xppm.hpp"

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
    const int iord   = 8;
    const Real lim_fac = Real(1);
    const bool nested  = false;
    const int grid_type = 0;

    const int is     = 1,        ie    = n;
    const int isd    = is-ng,    ied   = ie+ng;
    const int jfirst = 1,        jlast = n;
    const int npx    = n+1,      npy   = n+1;

    const int nrows   = jlast - jfirst + 1;
    const long ncol   = static_cast<long>(nrows) * levels;
    const int ni      = ie  - is  + 1;
    const int nj_q    = ied - isd + 1;
    const int nj_flux = ie  - is  + 2;

    printf("xppm CPU driver: resolution=%d iterations=%d levels=%d ncol=%ld\n",
           n, n_iter, levels, ncol);

    std::vector<Real> q   (static_cast<size_t>(ncol) * nj_q);
    std::vector<Real> dxa (static_cast<size_t>(ncol) * nj_q,    Real(1));
    std::vector<Real> c   (static_cast<size_t>(ncol) * nj_flux, Real(0.5));
    std::vector<Real> flux(static_cast<size_t>(ncol) * nj_flux, Real(0));

    const double two_pi = 6.283185307179586;
    for (long r = 0; r < ncol; ++r) {
        Real* qr = q.data() + r * nj_q;
        for (int i = 0; i < nj_q; ++i)
            qr[i] = Real(1.0 + 0.5 * std::cos(two_pi * double(i) / double(nj_q)));
    }

    std::vector<Real> rbuf(fv3::yppm_scratch_real_words(ni));
    std::vector<char> bbuf(fv3::yppm_scratch_bool_words(ni));
    fv3::ScratchXPPMView<Real> s = fv3::yppm_make_scratch_view<Real>(
        rbuf.data(), reinterpret_cast<bool*>(bbuf.data()), ni);

    auto t0 = std::chrono::steady_clock::now();
    for (int it = 0; it < n_iter; ++it) {
        for (long row = 0; row < ncol; ++row) {
            fv3::xppm_col<Real>(
                flux.data() + row * nj_flux,
                q.data()    + row * nj_q,
                c.data()    + row * nj_flux,
                iord, is, ie, isd, ied, npx, npy,
                dxa.data()  + row * nj_q,
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
