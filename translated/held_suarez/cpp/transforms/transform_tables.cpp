// transform_tables.cpp — see transform_tables.h.

#include "transform_tables.h"

#include <cmath>
#include <stdexcept>

namespace transforms {

static const double PI = 3.14159265358979323846;

// Port of gauss_and_legendre.F90::compute_gaussian (Numerical Recipes gauleg).
// Newton iteration on Legendre polynomial P_n; n = 2*n_hem.
void compute_gaussian(std::vector<double>& sin_hem,
                      std::vector<double>& wts_hem,
                      int n_hem) {
    sin_hem.assign(n_hem, 0.0);
    wts_hem.assign(n_hem, 0.0);

    // converg = .1**precision(converg); double precision -> 15 digits.
    const int nprec = 15;
    const double converg = std::pow(0.1, nprec);
    const int itermax = 10;
    const int n = 2 * n_hem;

    for (int i = 1; i <= n_hem; ++i) {
        double z = std::cos(PI * (i - 0.25) / (n + 0.5));
        double pp = 0.0, z1 = 0.0;
        bool converged = false;
        for (int iter = 1; iter <= itermax; ++iter) {
            double p1 = 1.0, p2 = 0.0, p3;
            for (int j = 1; j <= n; ++j) {
                p3 = p2;
                p2 = p1;
                p1 = ((2.0 * j - 1.0) * z * p2 - (j - 1.0) * p3) / j;
            }
            pp = n * (z * p1 - p2) / (z * z - 1.0);
            z1 = z;
            z = z1 - p1 / pp;
            if (std::fabs(z - z1) < converg) { converged = true; break; }
        }
        if (!converged)
            throw std::runtime_error("compute_gaussian: abscissas failed to converge");
        sin_hem[i - 1] = z;
        wts_hem[i - 1] = 2.0 / ((1.0 - z * z) * pp * pp);
    }
}

// Port of gauss_and_legendre.F90::compute_legendre.
// Recurrence in n at fixed m using eps(m,n); output legendre[m][n][j].
void compute_legendre(std::vector<double>& legendre,
                      const Config& cfg,
                      const std::vector<double>& sin_lat) {
    const int num_fourier   = cfg.num_fourier;
    const int fourier_inc   = cfg.fourier_inc;
    const int num_spherical = cfg.num_spherical;
    const int n_lat         = cfg.nhem();
    const int fourier_max   = num_fourier * fourier_inc;

    const int NM = fourier_max + 1;   // 0:fourier_max
    const int NN = num_spherical + 1; // 0:num_spherical
    auto P = [&](std::vector<double>& a, int m, int n) -> double& {
        return a[m * NN + n];
    };

    std::vector<double> eps(NM * NN, 0.0);
    std::vector<double> b(NM, 0.0);
    for (int n = 0; n <= num_spherical; ++n)
        for (int m = 0; m <= fourier_max; ++m) {
            double m2 = double(m) * m;
            double l2 = double(m + n) * (m + n);
            eps[m * NN + n] = std::sqrt((l2 - m2) / (4.0 * l2 - 1.0));
        }
    for (int m = 1; m <= fourier_max; ++m)
        b[m] = std::sqrt(0.5 * (2.0 * m + 1.0) / double(m));

    std::vector<double> cos_lat(n_lat);
    for (int j = 0; j < n_lat; ++j)
        cos_lat[j] = std::sqrt(1.0 - sin_lat[j] * sin_lat[j]);

    legendre.assign(size_t(cfg.nm()) * cfg.nn() * n_lat, 0.0);
    std::vector<double> poly(NM * NN, 0.0);

    for (int j = 0; j < n_lat; ++j) {
        P(poly, 0, 0) = std::sqrt(0.5);
        for (int m = 1; m <= fourier_max; ++m)
            P(poly, m, 0) = b[m] * cos_lat[j] * P(poly, m - 1, 0);
        for (int m = 0; m <= fourier_max; ++m)
            P(poly, m, 1) = sin_lat[j] * P(poly, m, 0) / eps[m * NN + 1];
        for (int n = 2; n <= num_spherical; ++n)
            for (int m = 0; m <= fourier_max; ++m)
                P(poly, m, n) = (sin_lat[j] * P(poly, m, n - 1)
                                 - eps[m * NN + (n - 1)] * P(poly, m, n - 2))
                                / eps[m * NN + n];
        for (int n = 0; n <= num_spherical; ++n)
            for (int m = 0; m <= num_fourier; ++m)
                legendre[(size_t(m) * cfg.nn() + n) * n_lat + j] =
                    P(poly, m * fourier_inc, n);
    }
}

// Mirror of spherical_fourier.F90 define_gaussian + define_legendre with
// south_to_north = .true. (the H-S default).
Tables build_tables(const Config& cfg) {
    Tables t;
    t.cfg = cfg;

    std::vector<double> sin_hem, wts_hem;
    compute_gaussian(sin_hem, wts_hem, cfg.nhem());

    // south_to_north: southern hemisphere abscissas are negative.
    std::vector<double> sin_hem_s(cfg.nhem());
    for (int j = 0; j < cfg.nhem(); ++j) sin_hem_s[j] = -sin_hem[j];

    t.sin_lat.assign(cfg.lat_max, 0.0);
    t.wts_lat.assign(cfg.lat_max, 0.0);
    for (int j = 0; j < cfg.nhem(); ++j) {
        t.sin_lat[j] = sin_hem_s[j];                 // 1..lat_max/2 : south
        t.sin_lat[cfg.lat_max - 1 - j] = -sin_hem_s[j];
        t.wts_lat[j] = wts_hem[j];
        t.wts_lat[cfg.lat_max - 1 - j] = wts_hem[j];
    }

    // Legendre table uses the (southern) hemisphere abscissas, as in
    // define_legendre (compute_legendre called with sin_hem).
    compute_legendre(t.legendre, cfg, sin_hem_s);

    t.legendre_wts.assign(t.legendre.size(), 0.0);
    for (int m = 0; m <= cfg.num_fourier; ++m)
        for (int n = 0; n <= cfg.num_spherical; ++n)
            for (int j = 0; j < cfg.nhem(); ++j)
                t.legendre_wts[t.idx(m, n, j)] =
                    t.legendre[t.idx(m, n, j)] * t.wts_lat[j];

    return t;
}

}  // namespace transforms
