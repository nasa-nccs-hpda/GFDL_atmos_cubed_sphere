# Transform-stack GPU feasibility — T1: structure & transpose characterization

Date: 2026-07-20. Branch `gpu/transform-stack-feasibility`. Phase T1 of
`docs/transform_stack_feasibility_plan.md`. **Source analysis only — no code, no runs.**

## Config (source-confirmed)

Runnable H-S = `exp/test_cases/held_suarez/held_suarez_test_case.py`: **T42L25 on 16 MPI ranks**.
`num_fourier=42`, `num_spherical=43`, `lon_max=128`, `lat_max=64`, `num_levels=25`, triangular truncation
(L=42). Built `-r8` → `real`=8 B, `complex`=16 B.

**Decomposition (defaults, `spec_mpp.F90:48-88`) — both axes 1-D, on the same 16 PEs:**

| Space | Layout | Split axis | Per-rank tile at 16 ranks |
|---|---|---|---|
| Grid | `(1,16)` | latitude only | `(128 lon, 4 lat, 25 lev)` — all lons, **4 latitudes** |
| Spectral | `(16,1)` | wavenumber `m` only | `ms:me ∈ {2,3}` of m=0:42; `ns:ne=0:43` (full n) |

## The pipeline (one representative transform)

Each spectral↔grid transform is three stages with an MPI transpose in the middle. For
`trans_spherical_to_grid` (spectral → grid):

```
spectral (my-m, all-n, 25 lev)
  --[Legendre: spherical_to_fourier]-->  fourier_s (my-m, all-64-lat, 25 lev)
  --[reverse_transpose_fourier: MPI]-->  fourier_g (all-m, my-4-lat, 25 lev)
  --[inverse FFT: fourier_to_grid]---->  grid (128 lon, my-4-lat, 25 lev)
```

`trans_grid_to_spherical` is the mirror (forward FFT → `transpose_fourier` → Legendre + truncation).

## Stage-by-stage GPU assessment

### FFT — clean cuFFT, no obstacle ✓
`grid_fourier.F90` → `fft_mod` → Temperton `fft991` (real↔half-complex, length `n=lon_max=128`, a power of
two). Maps **directly** to a cuFFT batched plan (`cufftPlanMany`, `CUFFT_D2Z`/`CUFFT_Z2D`): real side
`istride=1, idist=128`; complex side `ostride=1, odist=65` (cuFFT's native Hermitian layout of `n/2+1=65`
coefficients is exactly what `fourier_g(0:64,...)` holds). The CPU code's `n+2=130` padding and re/im repack
loops are Temperton in-place artifacts and are **not** needed on GPU. Only real work: apply `1/n=1/128` scale
on the forward transform (cuFFT is unnormalized) and fold the per-level Fortran loop into the batch. Batch =
`lat_per_rank × num_levels` = **4 × 25 = 100 per rank** (1600 single-rank). Truncation (zero coeffs 43:64) is a
trivial masked op between FFT and Legendre.

### Legendre — clean batched GEMM, but per-rank work is tiny ⚠
`spherical_fourier.F90`. Per zonal wavenumber `m` the contraction over `n` is a GEMM; `m` is the batch index:
forward per-m shape **M=32 (lat/2, hemisphere symmetry) × N=25 (lev) × K=44 (n)**, split even/odd (K=22+22);
inverse is the transpose using `legendre_wts`. Full 3D field, single rank (all 43 m): **~6.05 MFLOP**. Legendre
tables `legendre` + `legendre_wts` = **~946 KiB total**, level-independent (upload once, resident forever).

**The catch:** at 16 ranks a rank owns only **2–3 wavenumbers**, so its per-transform Legendre work is
~6 MFLOP × (3/43) ≈ **0.4 MFLOP** over matrices of shape 32×25×44 — minuscule. Triangular truncation also leaves
~50% of the (m,n) rectangle structurally zero (dense GEMM wastes ~½ the FLOPs unless the triangle is packed).

### Transpose — the crux ✗(unknown)
`transpose_fourier` / `reverse_transpose_fourier` (`transforms.F90:970-1056`) remap `fourier_g` (all-m /
my-lats) ⇄ `fourier_s` (my-m / all-lats). It is a **hand-rolled all-to-all**: a ring of paired `mpp_transmit`
sends over the 16-PE pelist, `layout-1 = 15` messages per rank per call, closed by `mpp_sync()`.

**Volume (16 B/complex):**
- One full 25-level transpose: physical field 43×64×25 = 68,800 complex = 1.05 MB; off-rank ×15/16 =
  **≈0.98 MiB/call**, as 240 `mpp_transmit` messages across the 16 ranks.
- Per leapfrog step-routine: **13 transpose crossings** (11 full + 2 single-level `ln_ps`) from 10 call sites →
  **≈10.9 MiB off-rank traffic, ~3,120 messages, 13 `mpp_sync` barriers** — ×`num_steps` per dynamics timestep.

## The decisive finding

**At T42L25 on 16 ranks the per-rank problem is tiny, and the transpose is a frequent host MPI barrier.** A
rank's grid tile is 4 latitudes; its spectral tile is 2–3 wavenumbers. The compute that GPU would accelerate is
sub-MFLOP per call over matrices smaller than a single GPU warp wants to chew. Meanwhile the pipeline crosses
the network 13× per step-routine with a barrier each time.

Consequences for a GPU port:
1. **A naive per-call offload loses.** Tiny kernels + per-transform PCIe transfer + 13 host round-trips/step is
   exactly the transfer-bound trap the advection work already proved fatal — only worse, because the kernels are
   smaller and the host hops more frequent.
2. **Net gain requires full residency *and* device-to-device transpose.** Keep the whole spectral/grid state on
   the GPU across the timestep; do the Legendre GEMMs and cuFFTs on resident data (no D2H/H2D); and cross the
   network with **CUDA-aware MPI / NCCL** so the transpose is device→device. Without CUDA-aware MPI, every
   transpose forces a D2H before and H2D after — 26 transfers/step — which almost certainly erases the compute
   win at this size.
3. **Decomposition is a lever.** Per-rank work scales inversely with rank count. One MPI rank per GPU with a
   much larger tile (fewer ranks, or higher resolution like T85/T170) makes the GEMMs/FFTs big enough to matter.
   T42L25-on-16 is close to the worst case for GPU offload of transforms.

The compute halves (FFT, Legendre) are unambiguously GPU-friendly and map cleanly. The verdict hinges entirely
on the transpose strategy and residency — which is precisely what T2 (compute ceiling, single-rank) and T3
(transpose cost model) must quantify.

## Feeds into T2 / T3

- **T2 (compute prototype, single rank, no transpose):** measure the cuFFT + cuBLAS-batched-GEMM round-trip vs
  the Fortran CPU baseline. Do it at the **single-rank tile (all 64 lats, all 43 m)** *and* at the **16-rank
  tile (4 lats, 2–3 m)** to expose how badly per-rank shrinkage erodes the GPU win. Validate round-trip numerics
  within spectral tolerance.
- **T3 (transpose cost model + go/no-go):** weigh the T2 compute win against (a) host-staged transpose (26
  transfers/step + MPI) and (b) CUDA-aware MPI device-to-device. Report an honest, Amdahl-aware achievable
  transform-region speedup, and whether it is contingent on a coarser decomposition (rank-per-GPU / higher res).

## Preliminary lean (to be confirmed by T2/T3)

GPU acceleration of the transform stack is **compute-feasible but decomposition- and transpose-gated**. At the
current T42L25/16-rank config it is likely a net loss unless we (i) hold the full state resident on device and
(ii) use CUDA-aware MPI for the transpose — and even then the tiny per-rank matrices cap the win. The stronger
case is at rank-per-GPU / higher resolution. This is a design-scale commitment, not an incremental overlay —
consistent with every prior doc that flagged transforms as a redesign, now with numbers behind it.
