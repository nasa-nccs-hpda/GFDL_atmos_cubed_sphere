// driver_fv_tp_2d_cpu.cc — CPU C++ benchmark for the full fv_tp_2d operator.
//
//   Usage: fv-tp-2d-driver-cpu <resolution> <iterations> [levels]
//
// Processes `levels` independent tiles per iteration (serially) — the CPU
// counterpart to the batched GPU driver. Same single-tile synthetic inputs as
// the Fortran tp-core-driver (q=sin(...), crx=cry=xfx=yfx=0.5,
// ra_*=area=dxa=dya=1, hord=8); sum(fx)/sum(fy) over all tiles cross-check the
// Fortran/GPU drivers at levels=1.
//
// NOTE: fv_tp_2d_cpu is a clarity-first reference (it gathers each line before
// calling yppm_col/xppm_col), so it is somewhat slower than the optimized
// Fortran — the Fortran tp-core-driver is the CPU baseline of record.
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <chrono>
#include <vector>

#include "fv_tp_2d.hpp"

using Real = float;

int main(int argc, char** argv)
{
    if (argc < 3 || argc > 4) { std::fprintf(stderr, "Usage: %s <resolution> <iterations> [levels]\n", argv[0]); return 2; }
    const int n = std::atoi(argv[1]);
    const int n_iter = std::atoi(argv[2]);
    const int levels = (argc == 4) ? std::atoi(argv[3]) : 1;
    if (n < 1 || n_iter < 1 || levels < 1) { std::fprintf(stderr, "args must be >= 1\n"); return 2; }

    const int ng = 3, hord = 8;
    const Real lim_fac = Real(1);
    const int is = 1, ie = n, js = 1, je = n;
    const int isd = is-ng, ied = ie+ng, jsd = js-ng, jed = je+ng;
    const int npx = n+1, npy = n+1;

    const int niq = ied-isd+1, nicrx = ie-is+2, nirax = ie-is+1;
    const size_t tq   = (size_t)niq   * (jed-jsd+1);
    const size_t tcrx = (size_t)nicrx * (jed-jsd+1);
    const size_t tcry = (size_t)niq   * (je-js+2);
    const size_t trax = (size_t)nirax * (jed-jsd+1);
    const size_t tray = (size_t)niq   * (je-js+1);
    const size_t tfx  = (size_t)nicrx * (je-js+1);
    const size_t tfy  = (size_t)nirax * (je-js+2);
    const size_t B = (size_t)levels;

    std::vector<Real> q(B*tq);
    std::vector<Real> crx(B*tcrx,0.5f), xfx(B*tcrx,0.5f), cry(B*tcry,0.5f), yfx(B*tcry,0.5f);
    std::vector<Real> ra_x(B*trax,1.0f), ra_y(B*tray,1.0f);
    std::vector<Real> area(B*tq,1.0f), dxa(B*tq,1.0f), dya(B*tq,1.0f);
    std::vector<Real> fx(B*tfx,0.f), fy(B*tfy,0.f);

    const float PI = 3.1415927f;
    for (size_t b = 0; b < B; ++b)
        for (int j = jsd; j <= jed; ++j)
            for (int i = isd; i <= ied; ++i)
                q[b*tq + fv3::idx2(i,j,isd,jsd,niq)] = std::sin(PI*float(i*j)/float((npx-1)*(npy-1)));

    std::printf("fv_tp_2d CPU driver: resolution=%d iterations=%d levels=%d\n", n, n_iter, levels);

    auto t0 = std::chrono::steady_clock::now();
    for (int it = 0; it < n_iter; ++it)
        for (size_t b = 0; b < B; ++b)
            fv3::fv_tp_2d_cpu<Real>(
                q.data()+b*tq, crx.data()+b*tcrx, cry.data()+b*tcry, xfx.data()+b*tcrx, yfx.data()+b*tcry,
                ra_x.data()+b*trax, ra_y.data()+b*tray, area.data()+b*tq, dxa.data()+b*tq, dya.data()+b*tq,
                fx.data()+b*tfx, fy.data()+b*tfy, is,ie,js,je,isd,ied,jsd,jed, npx,npy, hord, lim_fac,
                false, 0, true,true,true,true);
    auto t1 = std::chrono::steady_clock::now();
    const double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    double sfx = 0.0, sfy = 0.0;
    for (size_t t = 0; t < fx.size(); ++t) sfx += double(fx[t]);
    for (size_t t = 0; t < fy.size(); ++t) sfy += double(fy[t]);

    std::printf("time taken: %.6f s  (%.4f ms/iter over %d iters)\n",
                ms/1000.0, ms/double(n_iter), n_iter);
    std::printf("sum(fx): %.10e , sum(fy): %.10e  (over %d tiles)\n", sfx, sfy, levels);
    return 0;
}
