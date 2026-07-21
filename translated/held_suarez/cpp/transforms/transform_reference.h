// transform_reference.h — single-core CPU reference for the spectral<->grid
// transform pipeline, the numeric + timing baseline for the GPU prototype.
//
// Mirrors the compute stages of the model's transform stack for ONE MPI rank
// with NO fourier transpose (phase T2 measures the compute ceiling only; the
// transpose is characterized separately in T1 and modeled in T3):
//
//   spectral (m,n,k)  --legendre_fwd-->  fourier (m,lat,k)
//                     --ifft (per lat,k)->  grid (lon,lat,k)
//                     --fft  (per lat,k)->  fourier (m,lat,k)
//                     --legendre_inv-->  spectral (m,n,k)
//
// Legendre stages reproduce spherical_fourier.F90 (even/odd hemisphere folding,
// south_to_north=.true.). FFT stages use a length-N radix-2 transform with the
// Temperton-consistent normalization (1/N on the forward/analysis pass, none on
// the inverse/synthesis pass) and cuFFT-compatible Hermitian handling, so the
// CPU reference and the cuFFT path share one convention.

#ifndef TRANSFORM_REFERENCE_H
#define TRANSFORM_REFERENCE_H

#include <complex>
#include <vector>

#include "transform_tables.h"

namespace transforms {

using cd = std::complex<double>;

// Flattened field layouts (row-major, C order):
//   spectral[(m*nn + n)*nlev + k]      complex, m:0..num_fourier n:0..num_spherical
//   fourier [(m*lat_max + lat)*nlev+k] complex, m:0..lenc-1 (m>num_fourier are 0)
//   grid    [(x*lat_max + lat)*nlev+k] real,    x:0..lon_max-1
//
// A "tile" restricts the work range so we can measure the per-rank shrinkage:
//   Legendre stages run over m in [m0,m1); FFT stages over lat in [lat0,lat1).
struct Tile {
    int m0, m1;      // zonal-wavenumber range for Legendre stages
    int lat0, lat1;  // latitude range for FFT stages
    static Tile full(const Config& c) { return Tile{0, c.nm(), 0, c.lat_max}; }
};

class ReferenceTransform {
public:
    explicit ReferenceTransform(const Tables& tables);

    // spectral (m in [t.m0,t.m1)) -> fourier (all lat).  fourier is expected
    // sized lenc*lat_max*nlev; entries with m>=nm are left untouched (caller
    // zero-fills for the FFT truncation pad).
    void legendre_fwd(const std::vector<cd>& spectral,
                      std::vector<cd>& fourier, const Tile& t) const;

    // fourier (all lat) -> spectral (m in [t.m0,t.m1)); accumulates full
    // hemisphere quadrature. Zeroes the written m-range first.
    void legendre_inv(const std::vector<cd>& fourier,
                      std::vector<cd>& spectral, const Tile& t) const;

    // fourier -> grid, per (lat in [t.lat0,t.lat1), level). Inverse/synthesis
    // FFT (cuFFT Z2D convention: DC + Nyquist imag ignored, no normalization).
    void fft_inv(const std::vector<cd>& fourier,
                 std::vector<double>& grid, const Tile& t) const;

    // grid -> fourier, per (lat, level). Forward/analysis FFT scaled by 1/N,
    // keeping coeffs 0..lenc-1 (cuFFT D2Z convention).
    void fft_fwd(const std::vector<double>& grid,
                 std::vector<cd>& fourier, const Tile& t) const;

    // Full spectral->grid->spectral round trip over the full tile.
    void round_trip(const std::vector<cd>& spectral_in,
                    std::vector<cd>& spectral_out) const;

    const Config& cfg() const { return cfg_; }

private:
    const Tables& tab_;
    Config cfg_;
};

// Length-N in-place complex FFT, radix-2 Cooley-Tukey. sign=-1 forward,
// sign=+1 inverse; no normalization (caller scales). N must be a power of two.
void fft_radix2(std::vector<cd>& a, int sign);

// Synthesize a triangular-truncated random spectral field (m+n<=num_fourier),
// with real m=0 coefficients so the round trip is exact. Deterministic seed.
std::vector<cd> synth_spectral(const Config& cfg, unsigned seed = 12345u);

}  // namespace transforms

#endif  // TRANSFORM_REFERENCE_H
