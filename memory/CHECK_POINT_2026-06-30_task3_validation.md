# Checkpoint - 2026-06-30 (Task 3 validation on gpu011)

## Start here
Read first: `memory/CHECK_POINT_2026-06-30_task3.md` (task 3 = scope-B divergence
fold). This file = the gpu011 validation delta.

## Repo / env
- Branch `perf/resident-semi-y-integration`. Code edited on arm64 Mac clone,
  pushed; built + validated on **gpu011** (x86_64+V100, apptainer).
- Cluster repo: `/explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere`.
- Commits this session (pushed): script fixes only (`41b7bc4`, `cbaf45b`,
  `5c5727e`) — no kernel changes. Task-3 kernels were already committed `ce4ddc2`.

## Canonical gate scripts (use these, NOT run_hybrid_*.sh)
- `scripts/run_fv_kernels_resident_1day.sh` / `_30day.sh` / `_30day_repeat.sh`
  — already correct: rlgill container, AAI work/data, `held_suarez_fv_kernels_cuda.x`,
  `FV_KERNELS_CUDA_MODE=resident`, proper exp names; all env-overridable.
- `scripts/validate_fv_kernels_resident_{1day,30day}.sh` — compare only (no run).
- Run with `GFDL_BASE=$PWD` so it uses THIS branch (their default GFDL_BASE points
  at the AAI GFDL clone, a different working copy). `FV_KERNELS_OVERWRITE=1` to redo.
- Validate runs **host** python3: `module load anaconda/24.9.0 nco/5.0.3`;
  pass `GFDL_DATA=.../rlgill/SystemTesting/AAI/Isca/isca_data`. (xarray absent →
  ncdump fallback; works.)
- `run_hybrid_smoke.sh` etc. were a detour — they default to `held_suarez_hybrid.x`
  and don't set resident mode. Not the gates.

## Env gotchas learned
- jli30 paths are read-only for rlgill: never write work/data there. AAI rlgill
  roots are writable; 30-day refs are symlinked in (`held_suarez_default`,
  `held_suarez_fv_kernels_30day`). 1-day refs were not — linked this session
  (`held_suarez_fortran_1day_baseline`, `held_suarez_fv_kernels_1day`).
- jli30 container `/lscratch/jli30/isca-sandbox` is gone → use
  `/lscratch/rlgill/isca-debian_latest`.
- Step 1 `make run` in tests/fortran_baseline regenerates **tracked** binaries
  (`*.bin`, `.mod`, `test_fv_advection_kernels`, kernel `.o`/`.a`). They dirty the
  tree; Isca's `write_source_control_status` does `git diff` and dies on their
  non-UTF-8 bytes (`UnicodeDecodeError 0x87`). Fix: `git checkout -- .` before any
  model run. (Real fix TODO: gitignore these generated artifacts.)
- **1-day validation is meaningless**: `--production-diag` writes `atmos_monthly.nc`,
  which at 1 day is all NetCDF fill (9.96921e+36). CPU-vs-CUDA "0" is fill==fill.
  Use 30-day (full month) for any real comparison.

## Gate results (30-day, this branch's task-3 build)
- cuda_resident_check: PASS (incl. resident_combined_dq_dt).
- compile (run_compile_fv_kernels.sh, USE_CUDA_FV_ADVECTION_KERNELS=1): clean.
- 1-day resident run: ok (13.6 s); validate not meaningful (see above).
- 30-day resident run: ok; wall `real 3m24s` (whole script incl. setup/IO — NOT
  the integration time; integration timing is in the FV_KERNELS_PROFILE log).
- 30-day NetCDF validation (cpu vs cuda):
  - ps   maxabs 0.1 Pa  (rel 9.9e-7)
  - temp maxabs 1e-4 K  (rel 4.1e-7)
  - ucomp maxabs 2.5e-5 (L2 2.1e-7)
  - vcomp maxabs 2.81e-5 (rel 0.156 only because mean≈3.6e-5)
  - Fortran vs CPU = exact 0.

## KEY OBSERVATION + OPEN QUESTION
- Task 2 had **CPU-vs-CUDA bit-exact (maxabs 0)**. Task 3 is **no longer
  bit-exact** — cpu-vs-cuda now sits at the rounding level above, because the
  divergence fold (uc/vc/div) now runs on-device and reorders the FP ops vs the
  host C++ path. Magnitudes are within the rounding tolerance already accepted vs
  Fortran, but the exact CPU match is lost by design of the fold.
- **OPEN: is losing CPU-vs-CUDA bit-exactness (now rounding-level) acceptable?**
  If yes → finish gates: (1) profile to confirm finish H2D dropped to ~q1-halo
  only (task-3's goal) + record integration time vs ~176.5 s; (2) repeat 30-day
  for ±0.1% stability; then commit/checkpoint as done.

## Not yet done
- Profiling gate (H2D drop + runtime vs 176.5 s baseline).
- Repeat 30-day stability.
- Decision on the bit-exactness question above.
