// transform_reference.cpp — see transform_reference.h.

#include "transform_reference.h"

#include <cmath>
#include <random>
#include <stdexcept>

namespace transforms {

static const double PI = 3.14159265358979323846;

ReferenceTransform::ReferenceTransform(const Tables& tables)
    : tab_(tables), cfg_(tables.cfg) {}

// ---- Legendre forward: spherical -> fourier -------------------------------
// Mirrors spherical_fourier.F90::trans_spherical_to_fourier_3d, single grid
// domain (nd=1), south_to_north=.true.  For each hemisphere abscissa jh the
// southern latitude is jh and its northern mirror is lat_max-1-jh.
void ReferenceTransform::legendre_fwd(const std::vector<cd>& spectral,
                                      std::vector<cd>& fourier,
                                      const Tile& t) const {
    const int nn = cfg_.nn(), nlev = cfg_.num_levels;
    const int lat_max = cfg_.lat_max, nhem = cfg_.nhem();
    const int ns = 0;              // ns even -> neven=0, nodd=1
    auto S = [&](int m, int n, int k) -> const cd& {
        return spectral[(size_t(m) * nn + n) * nlev + k];
    };
    auto F = [&](int m, int lat, int k) -> cd& {
        return fourier[(size_t(m) * lat_max + lat) * nlev + k];
    };

    for (int jh = 0; jh < nhem; ++jh) {
        const int south = jh, north = lat_max - 1 - jh;
        for (int k = 0; k < nlev; ++k) {
            for (int m = t.m0; m < t.m1; ++m) {
                cd xe(0.0, 0.0), xo(0.0, 0.0);
                for (int n = ns; n <= cfg_.num_spherical; n += 2)
                    xe += S(m, n, k) * tab_.legendre[tab_.idx(m, n, jh)];
                for (int n = ns + 1; n <= cfg_.num_spherical; n += 2)
                    xo += S(m, n, k) * tab_.legendre[tab_.idx(m, n, jh)];
                F(m, south, k) = xe - xo;
                F(m, north, k) = xe + xo;
            }
        }
    }
}

// ---- Legendre inverse: fourier -> spherical -------------------------------
// Mirrors trans_fourier_to_spherical_3d (Gaussian quadrature with legendre_wts).
void ReferenceTransform::legendre_inv(const std::vector<cd>& fourier,
                                      std::vector<cd>& spectral,
                                      const Tile& t) const {
    const int nn = cfg_.nn(), nlev = cfg_.num_levels;
    const int lat_max = cfg_.lat_max, nhem = cfg_.nhem();
    const int ns = 0;
    auto S = [&](int m, int n, int k) -> cd& {
        return spectral[(size_t(m) * nn + n) * nlev + k];
    };
    auto F = [&](int m, int lat, int k) -> const cd& {
        return fourier[(size_t(m) * lat_max + lat) * nlev + k];
    };

    for (int m = t.m0; m < t.m1; ++m)
        for (int n = 0; n <= cfg_.num_spherical; ++n)
            for (int k = 0; k < nlev; ++k)
                S(m, n, k) = cd(0.0, 0.0);

    for (int jh = 0; jh < nhem; ++jh) {
        const int south = jh, north = lat_max - 1 - jh;
        for (int k = 0; k < nlev; ++k) {
            for (int m = t.m0; m < t.m1; ++m) {
                cd xe = F(m, north, k) + F(m, south, k);
                cd xo = F(m, north, k) - F(m, south, k);
                for (int n = ns; n <= cfg_.num_spherical; n += 2)
                    S(m, n, k) += xe * tab_.legendre_wts[tab_.idx(m, n, jh)];
                for (int n = ns + 1; n <= cfg_.num_spherical; n += 2)
                    S(m, n, k) += xo * tab_.legendre_wts[tab_.idx(m, n, jh)];
            }
        }
    }
}

// ---- FFT stages -----------------------------------------------------------
void fft_radix2(std::vector<cd>& a, int sign) {
    const int n = int(a.size());
    if (n & (n - 1)) throw std::runtime_error("fft_radix2: N not power of two");
    // bit-reversal permutation
    for (int i = 1, j = 0; i < n; ++i) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) std::swap(a[i], a[j]);
    }
    for (int len = 2; len <= n; len <<= 1) {
        double ang = sign * 2.0 * PI / len;
        cd wlen(std::cos(ang), std::sin(ang));
        for (int i = 0; i < n; i += len) {
            cd w(1.0, 0.0);
            for (int j = 0; j < len / 2; ++j) {
                cd u = a[i + j];
                cd v = a[i + j + len / 2] * w;
                a[i + j] = u + v;
                a[i + j + len / 2] = u - v;
                w *= wlen;
            }
        }
    }
}

void ReferenceTransform::fft_inv(const std::vector<cd>& fourier,
                                 std::vector<double>& grid,
                                 const Tile& t) const {
    const int N = cfg_.lon_max, lenc = cfg_.lenc();
    const int lat_max = cfg_.lat_max, nlev = cfg_.num_levels;
    std::vector<cd> full(N);
    for (int lat = t.lat0; lat < t.lat1; ++lat) {
        for (int k = 0; k < nlev; ++k) {
            // cuFFT Z2D convention: DC & Nyquist are real; fill Hermitian half.
            for (int m = 0; m < lenc; ++m)
                full[m] = fourier[(size_t(m) * lat_max + lat) * nlev + k];
            full[0] = cd(full[0].real(), 0.0);
            full[N / 2] = cd(full[N / 2].real(), 0.0);
            for (int m = 1; m < N / 2; ++m) full[N - m] = std::conj(full[m]);
            fft_radix2(full, +1);  // synthesis: no normalization
            for (int x = 0; x < N; ++x)
                grid[(size_t(x) * lat_max + lat) * nlev + k] = full[x].real();
        }
    }
}

void ReferenceTransform::fft_fwd(const std::vector<double>& grid,
                                 std::vector<cd>& fourier,
                                 const Tile& t) const {
    const int N = cfg_.lon_max, lenc = cfg_.lenc();
    const int lat_max = cfg_.lat_max, nlev = cfg_.num_levels;
    const double inv_n = 1.0 / double(N);
    std::vector<cd> full(N);
    for (int lat = t.lat0; lat < t.lat1; ++lat) {
        for (int k = 0; k < nlev; ++k) {
            for (int x = 0; x < N; ++x)
                full[x] = cd(grid[(size_t(x) * lat_max + lat) * nlev + k], 0.0);
            fft_radix2(full, -1);  // analysis
            for (int m = 0; m < lenc; ++m)
                fourier[(size_t(m) * lat_max + lat) * nlev + k] = full[m] * inv_n;
        }
    }
}

// ---- Full round trip ------------------------------------------------------
void ReferenceTransform::round_trip(const std::vector<cd>& spectral_in,
                                    std::vector<cd>& spectral_out) const {
    const Tile t = Tile::full(cfg_);
    std::vector<cd> fourier(size_t(cfg_.lenc()) * cfg_.lat_max * cfg_.num_levels,
                            cd(0.0, 0.0));
    std::vector<double> grid(size_t(cfg_.lon_max) * cfg_.lat_max * cfg_.num_levels,
                             0.0);
    legendre_fwd(spectral_in, fourier, t);
    fft_inv(fourier, grid, t);
    std::fill(fourier.begin(), fourier.end(), cd(0.0, 0.0));
    fft_fwd(grid, fourier, t);
    spectral_out.assign(spectral_in.size(), cd(0.0, 0.0));
    legendre_inv(fourier, spectral_out, t);
}

// ---- Synthetic input ------------------------------------------------------
std::vector<cd> synth_spectral(const Config& cfg, unsigned seed) {
    std::mt19937 rng(seed);
    std::uniform_real_distribution<double> u(-1.0, 1.0);
    std::vector<cd> s(size_t(cfg.nm()) * cfg.nn() * cfg.num_levels, cd(0.0, 0.0));
    const int nn = cfg.nn(), nlev = cfg.num_levels;
    for (int m = 0; m <= cfg.num_fourier; ++m)
        for (int n = 0; n <= cfg.num_spherical; ++n) {
            if (m + n > cfg.num_fourier) continue;   // triangular truncation
            for (int k = 0; k < nlev; ++k) {
                double re = u(rng);
                double im = (m == 0) ? 0.0 : u(rng);  // real zonal mean
                s[(size_t(m) * nn + n) * nlev + k] = cd(re, im);
            }
        }
    return s;
}

}  // namespace transforms
