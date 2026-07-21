// transform_gpu.h — GPU implementation of the transform compute stages.
//
// Phase T2 of the transform-stack feasibility study: establish the single-rank
// COMPUTE ceiling (no fourier transpose). The two GPU-ideal halves are:
//   * Legendre  -> per-m batched complex GEMM  (cuBLAS ZgemmStridedBatched)
//   * FFT       -> length-128 batched real<->complex (cuFFT D2Z / Z2D)
//
// One GpuTransform is built per measured tile. A tile carries two independent
// work ranges that mirror the real per-rank decomposition (the transpose that
// couples them is out of scope here):
//   * Legendre stages batch over m in [m0,m1)   (all latitudes produced)
//   * FFT stages batch over lat in [lat0,lat1)  (all wavenumbers)
// so the "16-rank tile" (2-3 m, 4 lat) exposes how per-rank shrinkage erodes
// the GPU win, exactly as docs/transform_feasibility_analysis.md calls for.
//
// Numerics match transform_reference.* (cuFFT Hermitian layout; 1/N on the
// forward FFT). Round-trip correctness is validated on the full tile only; the
// shrunk tile is timing-only (its two stage groups don't form one pipeline).

#ifndef TRANSFORM_GPU_H
#define TRANSFORM_GPU_H

#include <complex>
#include <vector>

#include "transform_reference.h"  // Config, Tile, Tables, cd
#include "transform_tables.h"

namespace transforms {

// Timing for one stage: kernel-only (compute already resident) vs
// transfer-inclusive (H2D input + kernels + D2H output), both in milliseconds,
// averaged over the timed iterations.
struct StageTiming {
    double kernel_ms = 0.0;
    double xfer_ms = 0.0;   // transfer-inclusive (>= kernel_ms)
    long long flops = 0;    // useful arithmetic per invocation (for GFLOP/s)
    long long bytes_h2d = 0, bytes_d2h = 0;
};

class GpuTransform {
public:
    GpuTransform(const Tables& tables, const Tile& tile);
    ~GpuTransform();

    GpuTransform(const GpuTransform&) = delete;
    GpuTransform& operator=(const GpuTransform&) = delete;

    // Full spectral->grid->spectral round trip (full tile assumed). Returns the
    // recovered spectral field on the host for numeric comparison, and the
    // transfer-inclusive round-trip time.
    void round_trip(const std::vector<cd>& spectral_in,
                    std::vector<cd>& spectral_out, double& total_ms);

    // Per-stage timing over the tile's ranges. iters timed after warmup.
    StageTiming time_legendre_fwd(int iters);
    StageTiming time_legendre_inv(int iters);
    StageTiming time_fft_inv(int iters);
    StageTiming time_fft_fwd(int iters);

    const Config& cfg() const { return cfg_; }
    const Tile& tile() const { return tile_; }

    struct Impl;  // exposed so timing helpers can reach device buffers

private:
    Impl* p_;
    Config cfg_;
    Tile tile_;
};

}  // namespace transforms

#endif  // TRANSFORM_GPU_H
