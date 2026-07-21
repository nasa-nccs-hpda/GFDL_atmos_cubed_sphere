// transform_tables.h — Gaussian latitudes + associated Legendre tables.
//
// Faithful C++ ports of src/atmos_spectral/tools/gauss_and_legendre.F90
// (compute_gaussian, compute_legendre) so the standalone prototype uses the
// exact same tables the spectral model builds. Level of truncation is
// triangular (fourier_inc = 1) at T42L25, matching held_suarez_test_case.py.
//
// Part of the transform-stack GPU feasibility study (phase T2). Reference
// analysis: docs/transform_feasibility_analysis.md.

#ifndef TRANSFORM_TABLES_H
#define TRANSFORM_TABLES_H

#include <vector>

namespace transforms {

// Spectral / grid geometry for one transform config.  The runnable H-S config
// is T42L25: num_fourier=42, num_spherical=43, lon_max=128, lat_max=64.
struct Config {
    int num_fourier;    // highest zonal wavenumber m (0:num_fourier)
    int num_spherical;  // highest meridional index n (0:num_spherical)
    int fourier_inc;    // zonal wavenumber increment (1 for triangular)
    int lon_max;        // longitudes  (== 2*(lenc-1))
    int lat_max;        // gaussian latitudes (even)
    int num_levels;     // vertical levels (batch dimension)

    int nm()   const { return num_fourier + 1; }    // # zonal wavenumbers  (43)
    int nn()   const { return num_spherical + 1; }   // # meridional indices (44)
    int nhem() const { return lat_max / 2; }         // hemisphere latitudes (32)
    int lenc() const { return lon_max / 2 + 1; }     // # fourier coeffs     (65)

    static Config t42l25() { return Config{42, 43, 1, 128, 64, 25}; }
};

// Gaussian abscissas (sin of latitude) and quadrature weights for one
// hemisphere. Port of compute_gaussian(). sin_hem/wts_hem have n_hem entries.
void compute_gaussian(std::vector<double>& sin_hem,
                      std::vector<double>& wts_hem,
                      int n_hem);

// Associated Legendre polynomials legendre[m][n][j], flattened row-major as
// legendre[(m*nn + n)*n_hem + j], for m in 0:num_fourier, n in 0:num_spherical,
// j in 0:n_hem-1 (southern hemisphere abscissas). Port of compute_legendre().
void compute_legendre(std::vector<double>& legendre,
                      const Config& cfg,
                      const std::vector<double>& sin_hem);

// Full-globe geometry derived from the hemisphere tables, mirroring
// spherical_fourier.F90 define_gaussian/define_legendre with south_to_north.
struct Tables {
    Config cfg;
    std::vector<double> sin_lat;       // lat_max
    std::vector<double> wts_lat;       // lat_max (hemisphere weights, mirrored)
    std::vector<double> legendre;      // nm*nn*nhem : legendre[(m*nn+n)*nhem+j]
    std::vector<double> legendre_wts;  // nm*nn*nhem : legendre * wts_lat(j)

    // index helper into the (m,n,j) tables
    int idx(int m, int n, int j) const { return (m * cfg.nn() + n) * cfg.nhem() + j; }
};

Tables build_tables(const Config& cfg);

}  // namespace transforms

#endif  // TRANSFORM_TABLES_H
