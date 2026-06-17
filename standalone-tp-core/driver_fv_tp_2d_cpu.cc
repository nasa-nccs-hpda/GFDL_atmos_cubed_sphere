// driver_fv_tp_2d_cpu.cc — CPU C++ benchmark for the full fv_tp_2d operator.
//
//   Usage: fv-tp-2d-driver-cpu <resolution> <iterations>
//
// Same single-tile workload and synthetic inputs as the Fortran tp-core-driver
// (q = sin(pi*i*j/((npx-1)(npy-1))), crx=cry=xfx=yfx=0.5, ra_*=area=dxa=dya=1,
// hord=8), so sum(fx)/sum(fy) cross-check the Fortran driver and the GPU driver.
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <chrono>
#include <vector>

#include "fv_tp_2d.hpp"

using Real = float;

int main(int argc, char** argv)
{
    if (argc != 3) { std::fprintf(stderr, "Usage: %s <resolution> <iterations>\n", argv[0]); return 2; }
    const int n = std::atoi(argv[1]);
    const int n_iter = std::atoi(argv[2]);
    if (n < 1 || n_iter < 1) { std::fprintf(stderr, "resolution and iterations must be >= 1\n"); return 2; }

    const int ng = 3, hord = 8;
    const Real lim_fac = Real(1);
    const int is = 1, ie = n, js = 1, je = n;
    const int isd = is-ng, ied = ie+ng, jsd = js-ng, jed = je+ng;
    const int npx = n+1, npy = n+1;

    const int niq = ied-isd+1, nicrx = ie-is+2, nirax = ie-is+1;
    const size_t sz_q   = (size_t)niq   * (jed-jsd+1);
    const size_t sz_crx = (size_t)nicrx * (jed-jsd+1);
    const size_t sz_cry = (size_t)niq   * (je-js+2);
    const size_t sz_rax = (size_t)nirax * (jed-jsd+1);
    const size_t sz_ray = (size_t)niq   * (je-js+1);
    const size_t sz_fx  = (size_t)nicrx * (je-js+1);
    const size_t sz_fy  = (size_t)nirax * (je-js+2);

    std::vector<Real> q(sz_q);
    std::vector<Real> crx(sz_crx,0.5f), xfx(sz_crx,0.5f), cry(sz_cry,0.5f), yfx(sz_cry,0.5f);
    std::vector<Real> ra_x(sz_rax,1.0f), ra_y(sz_ray,1.0f);
    std::vector<Real> area(sz_q,1.0f), dxa(sz_q,1.0f), dya(sz_q,1.0f);
    std::vector<Real> fx(sz_fx,0.f), fy(sz_fy,0.f);

    const float PI = 3.1415927f;
    for (int j = jsd; j <= jed; ++j)
        for (int i = isd; i <= ied; ++i)
            q[fv3::idx2(i,j,isd,jsd,niq)] = std::sin(PI*float(i*j)/float((npx-1)*(npy-1)));

    std::printf("fv_tp_2d CPU driver: resolution=%d iterations=%d\n", n, n_iter);

    auto t0 = std::chrono::steady_clock::now();
    for (int it = 0; it < n_iter; ++it) {
        fv3::fv_tp_2d_cpu<Real>(
            q.data(), crx.data(), cry.data(), xfx.data(), yfx.data(),
            ra_x.data(), ra_y.data(), area.data(), dxa.data(), dya.data(),
            fx.data(), fy.data(), is,ie,js,je,isd,ied,jsd,jed, npx,npy, hord, lim_fac,
            false, 0, true,true,true,true);
    }
    auto t1 = std::chrono::steady_clock::now();
    const double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    double sfx = 0.0, sfy = 0.0;
    for (size_t t = 0; t < sz_fx; ++t) sfx += double(fx[t]);
    for (size_t t = 0; t < sz_fy; ++t) sfy += double(fy[t]);

    std::printf("time taken: %.6f s  (%.4f ms/iter over %d iters)\n",
                ms/1000.0, ms/double(n_iter), n_iter);
    std::printf("sum(fx): %.10e , sum(fy): %.10e\n", sfx, sfy);
    return 0;
}
