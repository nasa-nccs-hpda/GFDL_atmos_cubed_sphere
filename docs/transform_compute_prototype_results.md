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

## Results (fill in from the host run)

Paste the harness output below.

### Numerics (full tile)
```
max|input|            = ____
CPU round-trip error  = ____   (expect ~1e-13 or better)
GPU round-trip error  = ____   (expect ~1e-12 or better)
GPU-vs-CPU agreement  = ____   (expect ~1e-12 — confirms GPU pipeline correct)
GPU round-trip time   = ____ ms (transfer-inclusive)
```

### Full single-rank tile: 43 m × 64 lat × 25 lev
| stage | CPU ms | GPU ker ms | GPU xfer ms | spd ker | spd xfr | GPU GF/s | xfr MB |
|---|---|---|---|---|---|---|---|
| legendre_fwd |  |  |  |  |  |  |  |
| fft_inv |  |  |  |  |  |  |  |
| fft_fwd |  |  |  |  |  |  |  |
| legendre_inv |  |  |  |  |  |  |  |

### 16-rank per-rank tile: 3 m × 4 lat × 25 lev
| stage | CPU ms | GPU ker ms | GPU xfer ms | spd ker | spd xfr | GPU GF/s | xfr MB |
|---|---|---|---|---|---|---|---|
| legendre_fwd |  |  |  |  |  |  |  |
| fft_inv |  |  |  |  |  |  |  |
| fft_fwd |  |  |  |  |  |  |  |
| legendre_inv |  |  |  |  |  |  |  |

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
