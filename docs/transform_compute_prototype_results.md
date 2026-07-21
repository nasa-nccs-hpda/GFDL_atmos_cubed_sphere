# Transform-stack GPU feasibility — T2: compute-ceiling prototype

Phase T2 of `docs/transform_stack_feasibility_plan.md`. Builds on T1
(`docs/transform_feasibility_analysis.md`). **Single rank, no transpose** — this
measures the *compute* ceiling only; the fourier transpose is characterized in
T1 and cost-modeled in T3.

## What the prototype is

A standalone harness that runs the two GPU-ideal halves of the transform
pipeline and compares them to a faithful single-core CPU reference:

- **Legendre** — per-`m` batched **complex GEMM** (cuBLAS `ZgemmStridedBatched`),
  even/odd hemisphere folding exactly as `spherical_fourier.F90`.
- **FFT** — length-128 batched **real↔complex** (cuFFT `D2Z`/`Z2D`), the
  Temperton-consistent normalization (`1/N` on the forward pass), cuFFT's native
  Hermitian layout (no repack), as T1 predicted.

Sources:
- `translated/held_suarez/cpp/transforms/` — `transform_tables.{h,cpp}`
  (ports of `compute_gaussian`/`compute_legendre`), `transform_reference.{h,cpp}`
  (CPU reference + round trip + synthetic input).
- `translated/held_suarez/cuda/transforms/` — `transform_gpu.{h,cu}` (GPU stages
  + timing), `transform_bench.cu` (harness), `Makefile`.

It reports, at two tile shapes:
1. **Full single-rank tile** — 43 `m` × 64 lat × 25 lev (the compute ceiling).
2. **16-rank per-rank tile** — 3 `m` (Legendre) / 4 lat (FFT) × 25 lev (the true
   per-rank work at T42L25 on 16 ranks; exposes shrinkage).

For each stage: single-core **CPU ms**, **GPU kernel-only ms** (data resident)
and **GPU transfer-inclusive ms** (per-call H2D+D2H — the naive-offload
*transfer trap*), with speedups and GPU GFLOP/s.

## Off-device validation already done (local, host clang++, no GPU)

These ran on the editing checkout and gate the on-device run:

| Check | Result |
|---|---|
| CPU spectral→grid→spectral round trip (full tile) | max abs err **2.49e-14** |
| Gaussian hemisphere weight sum | **1.0** (sphere = 2) ✓ |
| Forward Legendre GEMM operand layout vs reference | max abs err **0.0** |
| Inverse Legendre GEMM operand layout vs reference | max abs err **0.0** |

So the transform math, the FFT normalization pair, and the exact column-major
even/odd GEMM index layouts used by the `.cu` are confirmed correct. The only
thing the host run adds is the CUDA/cuBLAS/cuFFT API execution + timing.

## Build & run on the host (H100 GPU node, in the container)

`nvcc`/cuFFT/cuBLAS live in the apptainer container; a visible GPU is required
(`nvcc` present ≠ GPU visible — use `apptainer exec --nv`). From an allocated
H100 node:

```bash
# adjust to your paths; mirrors scripts/ab_compare.sh
export GFDL_BASE=/explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere
export CONTAINER=/lscratch/rlgill/isca-debian_latest   # or your isca-sandbox image

apptainer exec --nv \
  --bind /explore/nobackup/people/rlgill:/explore/nobackup/people/rlgill \
  "$CONTAINER" bash -lc '
    set -e
    cd '"$GFDL_BASE"'/translated/held_suarez/cuda/transforms
    nvidia-smi -L
    make clean && make ARCH=sm_90
    ./transform_bench            # optional: ./transform_bench <gpu_iters> <cpu_iters>
'
```

`make ARCH=sm_90` targets H100. Default is already `sm_90`; override for other
GPUs. Default iterations: 200 GPU / 20 CPU.

## Results (H100 node, 2026-07-21; gpu_iters=200 cpu_iters=20)

### Numerics (full tile)
```
max|input|            = 1.401e+00
CPU round-trip error  = 4.698e-14 (abs)
GPU round-trip error  = 0.000e+00 (abs)   <- bit-exact recovery of the input
GPU-vs-CPU agreement  = 4.698e-14 (abs)   <- machine precision; pipeline correct
GPU round-trip time   = 9.3149 ms (transfer-inclusive)
```
The cuFFT + cuBLAS pipeline is numerically confirmed: it recovers the
band-limited input to 0.0 and agrees with the CPU reference to 5e-14.

### Full single-rank tile: 43 m × 64 lat × 25 lev
| stage | CPU ms | GPU ker ms | GPU xfer ms | spd ker | spd xfr | GPU GF/s | xfr MB |
|---|---|---|---|---|---|---|---|
| legendre_fwd | 2.0950 | 0.0206 | 0.1909 | 101.6 | 11.0 | 587.3 | 1.772 |
| fft_inv | 9.3194 | 0.0061 | 0.2865 | 1532 | 32.5 | 589.2 | 3.149 |
| fft_fwd | 9.4878 | 0.0062 | 0.2865 | 1519 | 33.1 | 573.8 | 3.149 |
| legendre_inv | 2.0584 | 0.0206 | 0.1913 | 100.1 | 10.8 | 588.7 | 1.772 |

### 16-rank per-rank tile: 3 m × 4 lat × 25 lev
| stage | CPU ms | GPU ker ms | GPU xfer ms | spd ker | spd xfr | GPU GF/s | xfr MB |
|---|---|---|---|---|---|---|---|
| legendre_fwd | 0.0991 | 0.0185 | 0.0534 | 5.36 | 1.86 | 45.7 | 0.124 |
| fft_inv | 0.5822 | 0.0033 | 0.0399 | 176.6 | 14.6 | 67.9 | 0.197 |
| fft_fwd | 0.6110 | 0.0033 | 0.0361 | 185.0 | 16.9 | 67.8 | 0.197 |
| legendre_inv | 0.1125 | 0.0205 | 0.0531 | 5.49 | 2.12 | 41.3 | 0.124 |

## Findings

1. **Correctness: settled.** Round trip is bit-exact on GPU; the FFT and
   Legendre halves and their normalization map cleanly, as T1 predicted.

2. **Compute halves are genuinely GPU-friendly at full tile** — ~590 GF/s
   (FP64) on both Legendre and FFT, 100–1500× a single core. The FFT speedup is
   inflated (the CPU baseline is a naive complex radix-2, ~2× a tuned real FFT
   and unvectorized); the **Legendre ~100× kernel speedup is the trustworthy
   compute signal** since its CPU baseline is the exact even/odd formulation.

3. **Per-rank shrinkage collapses GPU efficiency** — the decisive number.
   GFLOP/s falls **587 → 46 for Legendre (~13×)** and **589 → 68 for FFT (~9×)**
   going from the full tile to the real 16-rank tile. The 32×25×22 GEMMs and
   4×25 FFT batch badly under-fill an H100. Legendre kernel speedup drops from
   ~100× to ~5×; the matrices are simply too small to saturate the device.

4. **Isolated per-stage transfer is NOT the trap here — but this understates
   the real cost.** Even transfer-inclusive, every per-rank stage still beats
   one CPU core (1.86–16.9×), because the volumes are tiny (0.12–0.20 MB) and
   H100 transfer is fast. *This does not overturn T1.* The prototype counts one
   H2D+D2H per stage in isolation; the real pipeline pays **13 transpose
   crossings per step-routine, each an MPI all-to-all + barrier**, and without
   CUDA-aware MPI each also forces D2H→H2D. That cost — not single-stage
   transfer — is what T3 must weigh, and it is excluded here by design.

5. **Decomposition is the lever, quantified.** The ~9–13× efficiency gap
   between full and per-rank tiles is the concrete cost of the 16-way split.
   Rank-per-GPU / higher resolution (bigger per-rank tiles) is where the
   compute win becomes large enough to survive the transpose overhead.

## How to read it

- **spd ker > 1 and spd xfr < 1** on the per-rank tile is the expected signature
  of the transfer trap: the compute is faster on GPU only if data is already
  resident; a per-call offload loses to PCIe/NVLink round-trips. This is the
  quantitative core of the go/no-go.
- **Full-tile GFLOP/s ≫ per-rank-tile GFLOP/s** quantifies how badly the tiny
  per-rank matrices under-fill the GPU — the decomposition lever from T1.
- Compare full-tile vs per-rank kernel speedups to see how much of the ceiling
  survives the 16-rank shrinkage.

## Honest caveats (for T3)

- **CPU FFT** is a straightforward complex radix-2 (does ~2× the work of a tuned
  real FFT and is not vectorized like Temperton `fft991`); the CPU baseline is
  therefore a *representative* single-core reference, not the model's exact FFT
  cost. Legendre CPU is the exact even/odd formulation. Read FFT speedups as
  order-of-magnitude.
- **Dense GEMM** — the triangular truncation leaves ~½ the (m,n) rectangle
  structurally zero; the prototype does not pack the triangle, so reported
  Legendre GFLOP/s counts dense FLOPs.
- **Single stream, one GPU.** No overlap of transfer with compute; the
  transfer-inclusive number is the pessimistic per-call bound, which is exactly
  the naive-offload case the study is testing.
- FLOP formulas: Legendre = `8·M·N·K` per complex GEMM (both stages); FFT =
  `2.5·N·log2 N·batch` (nominal real-FFT).

## Feeds into T3

T3 weighs the surviving compute win (kernel-only, full tile and per-rank)
against the transpose cost (D2H + MPI all-to-all + H2D for the ~0.98 MiB/call
fourier volume from T1, ×13 crossings/step), and the CUDA-aware-MPI /
device-resident alternative — producing the Amdahl-aware achievable
transform-region speedup and the go/no-go.
