# Checkpoint 2026-07-15 — TASK 4 & TASK 5 CLOSEOUT

Self-contained: a new session needs only this file to confirm tasks 4 and 5 are
done and to understand the validated performance result. It also **corrects the
task-4 performance numbers**, which were measured across a container/node change
and are not a valid absolute baseline. Do not re-litigate task-4's cross-node
figures — the same-node A/B below supersedes them for the resident-vs-per-call delta.

Branch: `perf/resident-semi-y-integration`.
Commits: task-3 `ce4ddc2` (divergence fold) → task-4 `91eebe0` (scaling driver;
did NOT touch the `.cu`) → task-5 `8d516b6` (resident grid-metrics) → A/B harness
`09bf62b`/`f571170`.

## STATUS
- **Task 4 (larger-resolution scaling): DONE.** Established the T85→T170 scaling
  behaviour of the resident FV-advection path and identified the next win. See the
  correction below regarding its absolute numbers.
- **Task 5 (resident grid-metrics): DONE — a confirmed win at both resolutions.**
  Upload the 6 run-constant grid metrics (`c, dyy, cc, dy, dy_plus, dy_minus`) to the
  device ONCE in `resident_advection_begin` instead of every call. Numerics bit-exact
  at T85 and T170; H2D roughly halved-to-quartered with kernel time unchanged.

## TASK 5 — what changed
`translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu`:
added `metrics_resident` + `metrics_nx/ny/nz` to PersistentContext; BEGIN now uploads
the 6 metric slots only on the first call or on a grid-dim change; `q_halo/va_halo/ua`
still upload every call. Safe because in resident mode only begin/finish touch those
slots and finish only READS them. No numerical path changed → bit-exact by construction,
and confirmed so (below).

## TASK 5 — validation (numerics)
30-day runs, Fortran vs CPU-C++ vs resident-CUDA, at BOTH resolutions:
- T85 (128×256) and T170 (256×512): **all comparisons bit-exact** — Fortran = CPU =
  CUDA, max abs/rel error 0, no NaN, no OOM at T170.
- Reports: `tests/reports/{T85,T170}L25_task5_validation.{md,json}`.
- Gotcha: the host `nco_ncl` conda env lacks xarray/numpy, so the validator silently
  falls back to ncdump and reports the netCDF `_FillValue` (9.96921e+36) as data — a
  bogus "0 diff". Run the validator with the `sci` env python:
  `/panfs/ccds02/app/modules/miniforge/platform/x86_64/rhel/8.10/24.9.0/envs/sci/bin/python`.

## TASK 5 — validation (performance): the isolated, trustworthy A/B
Measured with `scripts/ab_compare.sh` on gpu022, same node + same (freshly rebuilt)
container for both sides, differing ONLY in `fv_advection_kernels_cuda.cu`
(task-5 resident vs the pre-task-5 metrics-per-call source at `91eebe0`). Per-rank
average over 16 ranks. Kernel time ≈ equal between sides confirms a clean comparison.

**T85 (5-day):**
| | h2d (s) | kernel (s) | total (s) |
|---|---|---|---|
| metrics per-call | 6.153 | 8.095 | 16.338 |
| metrics resident | 1.089 | 8.444 | 11.982 |
| **Δ** | **−5.06 (−82%)** | +0.35 (noise) | **−4.36 (−27%)** |

**T170 (3-day):**
| | h2d (s) | kernel (s) | total (s) |
|---|---|---|---|
| metrics per-call | 8.937 | 22.651 | 35.373 |
| metrics resident | 4.329 | 21.278 | 29.476 |
| **Δ** | **−4.61 (−52%)** | −1.37 (noise) | **−5.90 (−17%)** |

The relative win shrinks with resolution because the haloed field uploads
(`q_halo/va_halo/ua`) grow with the grid, so the constant metrics are a smaller slice
of total H2D at T170. It is a solid win at both scales.

## CORRECTION to the task-4 performance numbers
Task-4 reported (per-rank avg, 30-day): resident-T170 total 412.4 vs task-2 419.2, and
proposed task-5 would reach ~395.6 (~5.6% win). **Those absolute numbers are not a valid
baseline for any later run:** they were taken with the OLD container on gpu018/gpu011,
and the cluster environment changed (container rebuilt per node; sessions move between
gpu011/012/022, which are not identical hardware). A later resident sweep on gpu022 with
the rebuilt container profiled ~2× faster in kernel AND h2d — a shift far too large to
come from any code change, i.e. pure toolchain/hardware. Lesson: **only compare profiles
collected on the same node in the same container.** The A/B tables above are that
comparison; they, not the task-4 30-day totals, are the authoritative resident-vs-
per-call delta. (Task-4's qualitative finding — that residency had unexploited H2D
headroom in the per-call metric re-upload — is confirmed; its absolute seconds are not.)

## Reproducing the A/B
```bash
cd /explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere
git pull --ff-only origin perf/resident-semi-y-integration
# T85 (default):
nohup bash scripts/ab_compare.sh >/dev/null 2>&1 & disown
# T170:
AB_RES=T170 AB_DT=150 AB_DAYS=3 nohup bash scripts/ab_compare.sh >/dev/null 2>&1 & disown
```
Per side it sets the `.cu` source, recompiles the CUDA overlay via
`run_compile_fv_kernels.sh` (`USE_CUDA_FV_ADVECTION_KERNELS=1`), runs the model, then
scrapes per-rank-avg h2d/kernel/total. Output: `logs/fv_kernels_scaling/ab_<host>_<res>/RESULTS.txt`.

## Environment gotchas (bit us during task-5; keep for the next run)
- **`run_hybrid_held_suarez.py` does NOT compile** — it runs a prebuilt exe, and its
  `--overwrite` only overwrites the output DATA dir. To test a `.cu` change you MUST
  recompile with `run_compile_fv_kernels.sh` (or `compile_native_overlay.py fv_kernels_cuda`).
- **mpirun needs `OMPI_MCA_rmaps_base_oversubscribe=1`** (+`OMPI_MCA_btl_vader_single_copy_mechanism=none`)
  or `mpirun -np 16` dies instantly ("not enough slots") on a busy login node.
- **The container bakes `GFDL_BASE` = the stale AAI checkout** (commit 40db38d, which
  predates the `--resolution/--levels/--dt-atmos` flags). Always re-`export GFDL_BASE`
  (and WORK/DATA) INSIDE the container invocation, or you run the wrong checkout's runner.
- **`/lscratch` container is node-local** and rebuilt per node; **`/tmp` is node-local and
  may not be bind-mounted into the container** — put in-container scripts under
  `/explore/nobackup/people/rlgill/...`. Launch long jobs with `nohup ... & disown`.

## Remaining (optional)
- **T42 point** (deferred from task-4): the low end of the primary matrix, cheap to add
  (dt_atmos 600). Would complete the T42/T85/T170 scaling curve. Not required to close task-5.
- No further residency headroom is obvious: after task-5, per-call H2D is the haloed
  fields (`q_halo/va_halo/ua`), which are genuinely per-timestep data, not constants.
