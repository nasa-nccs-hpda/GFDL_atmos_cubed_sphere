# Plan: Transform-stack GPU feasibility prototype (de-risk the ~39% region)

## Context

The Held-Suarez GPU port uses **CUDA C++** in the existing `nvcc`-in-container overlay (Option C). FV horizontal
advection (~12%) is already ported, validated, and resident on the GPU. The committed end-state is a **persistent
device-resident dynamics state**.

The transform stack is the largest region by far — **~35–39% of MPP wall time**, spread over ~9 coupled call sites
(`transforms.F90`, `spherical_fourier.F90`, `grid_fourier.F90`, `shared/fft/fft.F90`). It is the only region whose
acceleration materially moves whole-model wall time; everything else is Amdahl-bounded to low single digits.

But it is **not** a drop-in overlay. Each spectral↔grid transform is a three-stage pipeline —
Legendre transform → **MPI "fourier transpose" (all-to-all)** → FFT — and the transpose in the middle is the crux.
The compute stages are GPU-ideal (Legendre ≈ batched GEMM; FFT → cuFFT); the transpose is the unknown that decides
whether a GPU port nets a gain or drowns in transfer. The runnable config (`held_suarez_test_case.py`) is **T42L25 on
16 ranks (`NCORES=16`)**, so the transpose is a genuine cross-rank exchange, not a single-tile no-op.

**This is a feasibility prototype, not a port.** Goal: answer *can the transform stack be GPU-accelerated with net
gain, and how must the transpose be handled* — producing a go/no-go plus a transpose-strategy recommendation, before
committing to a multi-week redesign. Mirrors the cheap de-risking pass the advection work did before its port. **No
production integration, no model-source overlays in this phase.**

## Guardrails (auto mode)

- All work on branch `gpu/transform-stack-feasibility` (created off `profile/hs-second-level-split`). Undo = checkout back.
- **Cheap-first, checkpoint between phases.** Phase T1 is analysis + measurement only. Pause and report before T2
  (which writes prototype code). Pause again before T3's conclusions.
- **No production Fortran overlays, no full-model rebuilds** in this feasibility work — standalone harness + captured
  fixtures only. A model run happens only to capture one transform fixture, nothing speculative.
- **Compile and run happen on the host** (GPU node, via the apptainer container — `nvcc`/`mpifort` live there), not on
  the local editing checkout. T1 is source analysis (local). T2/T3 build + run are host commands, supplied for the
  user to execute.
- A failing numeric round-trip or a build error is a hard stop to report, not a thing to grind on.

## Phases

### T1 — Structure & transpose characterization (analysis + measurement; cheap). **[checkpoint]**
Deep-read the transform pipeline and nail the numbers for one representative hot transform (e.g.
`trans_spherical_to_grid_3d`, the path under `transform_future_uv_from_vor_div` / `transform_vor_div_from_uv`):
- Exact data flow and array layouts at each stage: spectral `(ms:me, ns:ne, k)` → fourier_s → (transpose) → fourier_g
  → grid `(is:ie, js:je, k)`, and the mirror direction.
- **Legendre GEMM shape** — the `legendre(0:num_fourier, 0:num_spherical, lat_max/2)` table dims and the batched
  matmul dimensions per level; estimate FLOPs.
- **FFT conventions** — Temperton `fft991` real↔complex layout and how it maps to a cuFFT batched plan.
- **Transpose data volume** — bytes moved by `transpose_fourier` / `reverse_transpose_fourier` per call, per step,
  and the pelist/decomposition structure at T42L25 on 16 ranks.
- Deliverable: `docs/transform_feasibility_analysis.md` with the shapes, volumes, and per-stage cost estimates.

### T2 — Standalone compute prototype (bounded code). **[checkpoint]**
Single-rank, **no transpose** — establish the compute ceiling:
- Capture one real transform round-trip fixture from the model (or synthesize representative spectral input).
- Prototype the Legendre stage as a GPU GEMM (cuBLAS) + the FFT via cuFFT; compare a full spectral→grid→spectral
  round-trip against the Fortran CPU baseline for **numerics** (round-trip error within spectral tolerance) and
  **compute time** (GPU vs single-core CPU).
- Deliverable: standalone prototype under `translated/held_suarez/{cpp,cuda}/transforms/` + microbench results.

### T3 — Transpose cost model + go/no-go (analysis).
- Measure the host-stage transpose cost (D2H + MPI all-to-all + H2D for the fourier-array volume from T1) and weigh it
  against the T2 compute win; sketch the CUDA-aware MPI / device-resident alternative.
- Deliverable: transpose-strategy recommendation and a go/no-go for the full transform port, with an achievable
  transform-region speedup estimate (honest, Amdahl-aware).

## Critical files (read-only in this phase)

- `src/atmos_spectral/tools/transforms.F90` (public API, `transpose_fourier` ~1014, `reverse_transpose_fourier` ~970).
- `src/atmos_spectral/tools/spherical_fourier.F90` (`trans_spherical_to_fourier_3d` ~177 — the Legendre loop nest).
- `src/atmos_spectral/tools/grid_fourier.F90` + `src/shared/fft/fft.F90` / `fft99.F90` (FFT backend → cuFFT).
- `exp/test_cases/held_suarez/held_suarez_test_case.py` (T42L25, 16 ranks — decomposition source of truth).
- Overlay template to mirror later (not touched now): `translated/held_suarez/.../fv_advection/kernels/`.

## Verification

Feasibility, not integration: success for T2 is a spectral→grid→spectral round-trip on GPU matching the Fortran
baseline within spectral tolerance, plus a measured compute speedup. Success for the phase overall is a defensible
transpose strategy and go/no-go — not a model run. If T3 says go, the *next* plan is the full transform port
(cuFFT + Legendre GEMM + chosen transpose) on the resident spine, with the standard validation ladder.

## Risks

- **Transpose dominates.** If host-staging the fourier array every call costs more than the compute saves (the
  transfer trap advection already hit), the gain requires CUDA-aware MPI / device-resident transpose — a real lift.
  T3 must quantify this, not hand-wave it.
- **cuFFT layout mismatch.** Temperton `fft991` packing may not map 1:1 to a cuFFT plan; a repack step could add cost.
- **Distributed correctness.** The 16-rank decomposition means the prototype's single-rank compute must still reflect
  the true per-rank tile shapes, or the cost model misleads.
- **Amdahl honesty.** Even a large transform speedup is capped by the ~39% share; report whole-model gains against MPP
  wall time and do not oversell.
