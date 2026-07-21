// transform_bench.cu — T2 compute-ceiling harness for the transform stack.
//
// Answers the two T2 questions on one GPU node, single rank, no transpose:
//   (1) NUMERICS  — does the cuFFT + cuBLAS round trip match the CPU reference
//                   and recover a band-limited input within spectral tolerance?
//   (2) COMPUTE   — GPU vs single-core CPU per stage, at the full single-rank
//                   tile (64 lat, 43 m) AND the 16-rank per-rank tile (4 lat,
//                   2-3 m), kernel-only vs transfer-inclusive (the naive
//                   per-call offload). The second tile exposes how per-rank
//                   shrinkage erodes the GPU win (docs/transform_feasibility_analysis.md).
//
// Build/run: see Makefile and docs/transform_compute_prototype_results.md.

#include <chrono>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#include "transform_gpu.h"
#include "transform_reference.h"
#include "transform_tables.h"

using namespace transforms;
using Clock = std::chrono::high_resolution_clock;

static double max_abs_diff(const std::vector<cd>& a, const std::vector<cd>& b) {
    double m = 0;
    for (size_t i = 0; i < a.size(); ++i) m = std::max(m, std::abs(a[i] - b[i]));
    return m;
}
static double max_abs(const std::vector<cd>& a) {
    double m = 0; for (auto& v : a) m = std::max(m, std::abs(v)); return m;
}

// Time a CPU stage (single core) over `iters`, return ms/iter.
template <class Fn>
static double time_cpu(Fn fn, int iters) {
    fn();  // warmup
    auto t0 = Clock::now();
    for (int i = 0; i < iters; ++i) fn();
    auto t1 = Clock::now();
    return std::chrono::duration<double, std::milli>(t1 - t0).count() / iters;
}

static double gflops(long long flops, double ms) {
    return ms > 0 ? flops / (ms * 1e6) : 0.0;
}

struct Row {
    const char* name;
    double cpu_ms, gpu_kernel_ms, gpu_xfer_ms;
    long long flops;
    long long bytes;  // per-call transfer volume (h2d+d2h)
};

static void print_table(const char* title, const std::vector<Row>& rows) {
    printf("\n%s\n", title);
    printf("%-16s %10s %10s %10s %9s %9s %10s %9s\n", "stage", "CPU ms",
           "GPUker ms", "GPUxfer ms", "spd ker", "spd xfr", "GPU GF/s", "xfr MB");
    printf("%s\n", std::string(96, '-').c_str());
    for (auto& r : rows) {
        printf("%-16s %10.4f %10.4f %10.4f %9.2f %9.2f %10.1f %9.3f\n",
               r.name, r.cpu_ms, r.gpu_kernel_ms, r.gpu_xfer_ms,
               r.cpu_ms / r.gpu_kernel_ms, r.cpu_ms / r.gpu_xfer_ms,
               gflops(r.flops, r.gpu_kernel_ms), r.bytes / 1048576.0);
    }
}

static std::vector<Row> bench_tile(const Tables& tab, const Tile& tile,
                                   int gpu_iters, int cpu_iters) {
    const Config& cfg = tab.cfg;
    ReferenceTransform R(tab);
    GpuTransform G(tab, tile);

    // Buffers for CPU stage timing (full arrays; tile restricts the work).
    std::vector<cd> spec = synth_spectral(cfg);
    std::vector<cd> fourier(size_t(cfg.lenc()) * cfg.lat_max * cfg.num_levels, cd(0, 0));
    std::vector<double> grid(size_t(cfg.lon_max) * cfg.lat_max * cfg.num_levels, 0.0);
    std::vector<cd> spec2(spec.size(), cd(0, 0));
    R.legendre_fwd(spec, fourier, Tile::full(cfg));  // seed fourier/grid for FFT stages
    R.fft_inv(fourier, grid, Tile::full(cfg));

    Row lf{"legendre_fwd", 0, 0, 0, 0, 0};
    Row fi{"fft_inv", 0, 0, 0, 0, 0};
    Row ff{"fft_fwd", 0, 0, 0, 0, 0};
    Row li{"legendre_inv", 0, 0, 0, 0, 0};

    lf.cpu_ms = time_cpu([&] { R.legendre_fwd(spec, fourier, tile); }, cpu_iters);
    fi.cpu_ms = time_cpu([&] { R.fft_inv(fourier, grid, tile); }, cpu_iters);
    ff.cpu_ms = time_cpu([&] { R.fft_fwd(grid, fourier, tile); }, cpu_iters);
    li.cpu_ms = time_cpu([&] { R.legendre_inv(fourier, spec2, tile); }, cpu_iters);

    StageTiming glf = G.time_legendre_fwd(gpu_iters);
    StageTiming gfi = G.time_fft_inv(gpu_iters);
    StageTiming gff = G.time_fft_fwd(gpu_iters);
    StageTiming gli = G.time_legendre_inv(gpu_iters);

    auto fill = [](Row& r, const StageTiming& s) {
        r.gpu_kernel_ms = s.kernel_ms; r.gpu_xfer_ms = s.xfer_ms;
        r.flops = s.flops; r.bytes = s.bytes_h2d + s.bytes_d2h;
    };
    fill(lf, glf); fill(fi, gfi); fill(ff, gff); fill(li, gli);
    return {lf, fi, ff, li};
}

int main(int argc, char** argv) {
    int gpu_iters = argc > 1 ? atoi(argv[1]) : 200;
    int cpu_iters = argc > 2 ? atoi(argv[2]) : 20;

    Config cfg = Config::t42l25();
    Tables tab = build_tables(cfg);
    printf("Transform compute prototype (T2)  T%dL%d  lon=%d lat=%d\n",
           cfg.num_fourier, cfg.num_levels, cfg.lon_max, cfg.lat_max);
    printf("gpu_iters=%d cpu_iters=%d\n", gpu_iters, cpu_iters);

    // ---- Numerics: full single-rank tile round trip -----------------------
    {
        ReferenceTransform R(tab);
        std::vector<cd> s_in = synth_spectral(cfg), cpu_out, gpu_out;
        double total_ms = 0;
        R.round_trip(s_in, cpu_out);
        GpuTransform G(tab, Tile::full(cfg));
        G.round_trip(s_in, gpu_out, total_ms);
        printf("\n== Numerics (full tile spectral->grid->spectral) ==\n");
        printf("  max|input|            = %.3e\n", max_abs(s_in));
        printf("  CPU round-trip error  = %.3e (abs)\n", max_abs_diff(s_in, cpu_out));
        printf("  GPU round-trip error  = %.3e (abs)\n", max_abs_diff(s_in, gpu_out));
        printf("  GPU-vs-CPU agreement  = %.3e (abs)\n", max_abs_diff(cpu_out, gpu_out));
        printf("  GPU round-trip time   = %.4f ms (transfer-inclusive)\n", total_ms);
    }

    // ---- Compute: full single-rank tile -----------------------------------
    Tile full = Tile::full(cfg);
    auto rows_full = bench_tile(tab, full, gpu_iters, cpu_iters);
    print_table("== Full single-rank tile: 43 m x 64 lat x 25 lev ==", rows_full);

    // ---- Compute: 16-rank per-rank tile (3 wavenumbers, 4 latitudes) ------
    Tile r16{0, 3, 0, 4};
    auto rows_r16 = bench_tile(tab, r16, gpu_iters, cpu_iters);
    print_table("== 16-rank per-rank tile: 3 m x 4 lat x 25 lev ==", rows_r16);

    printf("\nnote: 'spd ker' = CPU/GPU with data resident; 'spd xfr' = CPU vs GPU\n"
           "including per-call H2D+D2H (the naive offload / transfer trap).\n");
    return 0;
}
