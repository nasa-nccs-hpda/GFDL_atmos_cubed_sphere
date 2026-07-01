# Checkpoint 2026-07-01 — TASK 3 COMPLETE → start TASK 4

Self-contained: a new session needs only this file to (a) confirm task 3 is done and
(b) start task 4. Do NOT re-explore or re-litigate task-3 perf first — it is closed.

## STATUS: TASK 3 DONE (closed neutral, 2026-07-01 evening)
Task 3 = scope-B divergence fold (commit `ce4ddc2` on branch
`perf/resident-semi-y-integration`). It is COMPLETE:
- **Architecture goal met.** `resident_advection_begin` now computes uc, vc, div and
  `dq = q*div` on-device and keeps them resident; `resident_advection_finish` uploads
  only the q1 halo rows. Per full grid-tracer call H2D dropped ~6·count → ~3·count,
  13 → ~10 transfers. finish-H2D→q1-halo-only confirmed in the profile.
- **Numerics accepted.** 30-day CPU-vs-CUDA validated at rounding level (ps rel ~1e-6,
  temp ~1e-4 K, ucomp/vcomp abs ~2.5e-5; Fortran-vs-CPU exact). Bit-exactness loss vs
  task-2 was ACCEPTED by user 2026-07-01. See [[task3-validation-bitexact]].
- **Runtime: indistinguishable from task-2 within measurement noise** (details below).
  NOT a regression, NOT a confirmed speedup — the effect is below the machine's noise
  floor and does not need fixing.

## Runtime verdict — why "neutral within noise" (do NOT reopen this)
The earlier single-profile "+1.2% regression" (task-3 179.76 vs task-2 177.65) was
cross-session drift, not a real signal. Same-session back-to-back and then 5 interleaved
rounds on gpu011 (30-day, FV_KERNELS_PROFILE=1, 16 cores) settled it:

Interleaved rounds, diff = task3 − task2 (positive = task-3 slower):
| round | task3 s | task2 s | diff s | pct |
|---|---|---|---|---|
| 1 | 205.824 | 203.364 | +2.460 | +1.21% |
| 2 | 207.129 | 210.369 | −3.240 | −1.54% |
| 3 | 210.609 | 197.315 | +13.294 | +6.74% |
| 4 | 212.373 | 205.630 | +6.744 | +3.28% |
| 5 | 210.770 | 203.737 | +7.033 | +3.45% |

- means: task-3 209.34 s, task-2 204.08 s, mean diff +5.26 s (+2.58%).
- NOT significant: diff std 6.12 s, SEM 2.74 s, t(4)=1.92, p≈0.13.
- Sign is mixed: 4/5 rounds task-2 faster, 1/5 task-3 faster; an earlier standalone
  same-session pair had task-3 FASTER by 1.22% (t3 207.55 / t2 210.11). Sign is a coin-flip.
- The mean lean is outlier-driven: round-3 task-2=197.3 s is a low outlier (task-2's
  other runs 203.4–210.4; task-3 never dipped near it); it alone contributes +13.3 to the sum.
- Per-run spread is the real story: task-2 197.3–210.4 (6.4%), task-3 205.8–212.4 (3.1%).
  gpu011 wall-time noise floor is ~5–6% (shared V100/node contention) — 2–3× any plausible
  ~1–2% build difference. The signal is simply not resolvable at end-to-end wall time.

Measurement lesson for future perf work on gpu011: single-run wall-time comparisons are
worthless here, and even n=5 interleaved cannot resolve ~1–2%. If a definitive sign is ever
required: (1) exclusive node reservation to kill contention, (2) ~18–20 interleaved rounds
(to detect 2% against std≈6 s at 80% power), and/or (3) compare the lower-noise internal
mpp_clocks (CUDA `kernel`/`h2d`) that measure the changed work directly, not end-to-end wall.

## Closeout housekeeping
- [x] Task-3 perf question resolved and recorded (this file).
- [ ] Delete the task-2 baseline clone on gpu011 (frees space; not needed again as-is —
      task 4 will want a fresh baseline anyway):
      `rm -rf /explore/nobackup/people/rlgill/gfdl_task2_baseline`
- [x] Completion checkpoint committed on branch `perf/resident-semi-y-integration`.

## NEXT: TASK 4 — larger-resolution scaling
Task sequence (from `memory/CHECK_POINT_2026-06-30_task3.md`, "Task sequence"):
1. semi_y resident — DONE (06-25)
2. q1 halo-only transfers + d_q2 bug fix — DONE (06-30)
3. broader update_tracers residency (scope-B divergence fold) — **DONE (07-01, this file)**
4. **larger-resolution scaling — START HERE (next session)**
5. transforms / vendor-library study — later

Task 4 = larger-resolution scaling. It is described at the roadmap level in
`memory/CHECK_POINT_2026-06-30_task3.md`; task 5 (transforms/vendor-library study) is
described there too. Read those one-liners plus the deeper background in
`memory/CHECK_POINT_2026-06-30_task3_validation.md` and
`memory/CHECK_POINT_2026-06-30_task3.md` before scoping task 4. The resident CUDA FV
path task 3 built (branch HEAD, `ce4ddc2`) is the starting point to scale up.

## Safe shipping state / backout
- Current shippable state = task-3 (`ce4ddc2`): resident H2D architecture, rounding-level
  CPU-vs-CUDA numerics, runtime neutral vs task-2.
- To back out task 3 entirely: revert `ce4ddc2` → task-2 (`d33fd44`), which was
  CPU-vs-CUDA bit-exact. Do this only if rounding-level numerics become unacceptable.

## Env / gotchas (gpu011) — carry into task 4
- gpu011: x86_64 + Tesla V100, apptainer. Container `/lscratch/rlgill/isca-debian_latest`.
- Cluster repo `/explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere`.
- Run scripts self-wrap in `apptainer exec --nv` — run from the HOST shell, not inside.
  Container binds only `/explore/nobackup/people/rlgill`.
- **git worktree fails in-container** (its `.git` points at a non-bind-mounted `/panfs/...`
  realpath → Isca `git log` dies). Use a full `git clone` for any baseline copy.
- Always pass `GFDL_BASE=$PWD` (default points at the AAI GFDL clone, a different copy).
  Build dir is keyed by GFDL_BASE path, so a clone builds separately (no clobber).
- `FV_KERNELS_OVERWRITE=1` to redo a run over existing output.
- NetCDF validation runs HOST python3 (`module load anaconda/24.9.0 nco/5.0.3`); container
  python lacks a NetCDF backend/ncdump. Refs `held_suarez_default` (Fortran) +
  `held_suarez_fv_kernels_30day` (CPU) are symlinked into the rlgill AAI isca_data root.

## Build / validate recipe (reuse for task 4)
On gpu011, from the branch checkout, GFDL_BASE=$PWD:
1. Standalone kernel gate: `cd translated/held_suarez/cuda/fv_advection` then the
   `cuda_resident_check` gate (exact invocation in `CHECK_POINT_2026-06-30_task3_validation.md`).
2. `GFDL_BASE_OVERRIDE=$PWD USE_CUDA_FV_ADVECTION_KERNELS=1 ./run_compile_fv_kernels.sh`
   (compile script at REPO ROOT, builds target `fv_kernels_cuda`).
3. `git checkout -- .` (scrub regenerated tracked artifacts, else Isca's
   write_source_control_status dies on non-UTF-8 `git diff` bytes).
4. `GFDL_BASE=$PWD FV_KERNELS_OVERWRITE=1 scripts/run_fv_kernels_resident_30day.sh`
5. NetCDF validation (host python): `tests/validate_T85L25_forcing_outputs.py` with
   `--fortran-exp held_suarez_default --cpu-exp held_suarez_fv_kernels_30day
   --cuda-exp <the cuda exp> --run 1 --filename atmos_monthly.nc --data-root $GFDL_DATA`.
   PASS bar = rounding level (bit-exact CPU-vs-CUDA NOT required, accepted 2026-07-01).

## To recreate a baseline clone (worktrees DO NOT work — see gotcha)
```
cd /explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere
git clone . ../gfdl_baseline && cd ../gfdl_baseline && git checkout <ref>
# sed the run script's experiment name so it can't clobber validated output
GFDL_BASE_OVERRIDE=$PWD USE_CUDA_FV_ADVECTION_KERNELS=1 ./run_compile_fv_kernels.sh
git checkout -- .
GFDL_BASE=$PWD FV_KERNELS_OVERWRITE=1 scripts/run_fv_kernels_resident_30day.sh
```

Related: [[task3-divergence-fold]] [[task3-validation-bitexact]] [[resident-dq2-bug]]
Roadmap + task-4/5 descriptions: `memory/CHECK_POINT_2026-06-30_task3.md`,
`memory/CHECK_POINT_2026-06-30_task3_validation.md`.
