# Checkpoint 2026-07-01 — Task 3 perf triage (standalone)

Self-contained: a new session needs only this file. Do NOT re-explore first.

## TL;DR
Task 3 (scope-B divergence fold, commit `ce4ddc2` on branch
`perf/resident-semi-y-integration`) is built, and its 30-day CPU-vs-CUDA numerics
are validated at rounding level (bit-exactness loss ACCEPTED by user 2026-07-01).
The finish-H2D→q1-halo goal is met. BUT a single 30-day profile showed task-3 at
179.76 s vs a re-profiled task-2 (`d33fd44`) at 177.65 s = **+1.2%**. This is
probably NOISE, not a regression — do the repeat runs in Step 1 before touching code.

## Why +1.2% is suspect (don't chase it blindly)
Per-full-call H2D, in units of `count = nx*ny*nz` (q1_count≈vc_count≈count):
- Task-2: begin q+ua+va, finish uc+vc+dq_dt  → **~6·count**, 13 H2D calls
- Task-3: begin q+va(haloed)+ua, finish q1-halo only → **~3·count**, ~10 H2D calls
Task-3 moves FEWER bytes and fewer transfers, yet measured h2d rose 12.80→15.95 s.
Bytes therefore do NOT explain it. The 6 grid metrics (c,cc,dy,dy_plus,dy_minus,dyy)
are tiny 1-D arrays (~ny each) — not a bandwidth factor. Also the re-profiled task-2
(177.65 s) is already ~0.6% above the earlier-session task-2 (176.5 s), so there is
real cross-session drift. Conclusion: treat +1.2% as unproven until repeated.

## Rank-0 profile numbers (30-day, FV_KERNELS_PROFILE=1)
| metric | task-2 d33fd44 | task-3 ce4ddc2 |
|---|---|---|
| Total runtime (mpp_clock) | 177.65 s | 179.76 s |
| resident_advection_begin  | 12.02 s | 25.70 s |
| resident_advection_finish | 12.48 s | 1.73 s |
| CUDA h2d (total)          | 12.80 s | 15.95 s |
| CUDA kernel               | 7.95 s  | 7.53 s |
begin+finish == CUDA total per rank; kernel ~flat, so begin↑/finish↓ is work moved.

## STEP 1 — decide if there is even a problem (do this first)
Run repeats of BOTH builds; compare Total runtime. Env + gotchas at bottom.
Task-3 build = branch HEAD (already built). Task-2 build = clean clone at d33fd44.

Task-3 repeat (cluster repo, task-3 executable already built):
```
cd /explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere
GFDL_BASE=$PWD FV_KERNELS_OVERWRITE=1 scripts/run_fv_kernels_resident_30day_repeat.sh
grep 'Total runtime' logs/fv_kernels_cuda_resident_30day_repeat.log
```
Task-2 repeat (rebuild the clone if it was cleaned up — see Step 4 to recreate):
```
cd ../gfdl_task2_baseline   # clone at d33fd44 with exp-name sed already applied
GFDL_BASE=$PWD FV_KERNELS_OVERWRITE=1 scripts/run_fv_kernels_resident_30day.sh
grep 'Total runtime' logs/fv_kernels_cuda_resident_30day.log
```
Decision:
- If task-3 lands within ~±0.3% of task-2 across repeats → NO regression.
  Task 3 is DONE: it meets its H2D-architecture goal at neutral runtime with
  accepted rounding-level numerics. Commit/checkpoint as complete, delete the clone.
- If task-3 is consistently >~0.5% slower → real regression; go to Step 2.

## STEP 2 — attribute the H2D (only if Step 1 confirms a regression)
The byte model says task-3 should be lighter, so a real +3.2 s h2d must be latency
or strided-copy cost, not bytes. Get per-array evidence, don't guess:
- Instrument `copy_to_existing_device` (cuda .cu line 334) to accumulate per-`name`
  bytes and time, and print at teardown. Also time the two `cudaMemcpy2D` D2D
  interior strips in task-3 begin (see below) — they may be counted oddly or slow.
- Rebuild + 30-day; compare per-array h2d task-2 vs task-3 to find the real culprit.

## STEP 3 — candidate fixes (cheap→expensive; only what Step 2 points to)
File: `translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu`
- Task-3 `resident_advection_begin` starts line **1351**; its H2D block is **1420-1428**;
  D2D interior strips of q and va are **1431-1445**. Slot map comment: **160-163**
  (kNumBuffers=20, slots 17..19 spare). copy helper: **334**.
- (a) Make the 6 static metrics resident: upload c,cc,dy,dy_plus,dy_minus,dyy ONCE
  (first begin call or a resident-init), guard subsequent calls with a flag in
  PersistentContext. Low risk, tiny bytes — do only if Step 2 shows metric-copy
  LATENCY (many small launches) matters; unlikely to be the +2 s alone.
- (b) va is uploaded HALOED (q1_count) in task-3 to feed compute_vc (vc reads the
  y-halo). Task-2 uploaded va interior (count) + host-computed vc. Check whether vc
  needs the full va halo or only the 2 edge rows per side; if edge-only, shrink the
  va upload toward count.
- (c) Reconsider the q/va D2D interior strips (1431-1445): if kernels can index the
  haloed buffers directly, the strips (and the extra buffers) may be removable.
Keep the [[resident-dq2-bug]] lesson: the test reference must independently recompute
uc/vc/div and dq=q*div; don't mirror the kernel.

## STEP 4 — re-validate any code change (mandatory gate order)
On gpu011, GFDL_BASE=$PWD, from the branch checkout:
1. `cd translated/held_suarez/cuda/fv_advection && <cuda_resident_check>` (the
   standalone kernel gate that already passed; must still pass — see
   `CHECK_POINT_2026-06-30_task3_validation.md` for its exact invocation).
2. `GFDL_BASE_OVERRIDE=$PWD USE_CUDA_FV_ADVECTION_KERNELS=1 ./run_compile_fv_kernels.sh`
   (compile script is at REPO ROOT, uses GFDL_BASE_OVERRIDE, builds target fv_kernels_cuda).
3. `git checkout -- .` (scrub regenerated tracked artifacts, else Isca's
   write_source_control_status dies on non-UTF-8 `git diff` bytes).
4. `GFDL_BASE=$PWD FV_KERNELS_OVERWRITE=1 scripts/run_fv_kernels_resident_30day.sh`
5. NetCDF validation (host python, NOT container):
   `module load anaconda/24.9.0 nco/5.0.3` then
   `python3 tests/validate_T85L25_forcing_outputs.py --fortran-exp held_suarez_default
    --cpu-exp held_suarez_fv_kernels_30day --cuda-exp held_suarez_fv_kernels_cuda_resident_30day
    --run 1 --filename atmos_monthly.nc --data-root $GFDL_DATA --markdown-out <md> --json-out <json>`
   PASS bar = rounding level (ps rel ~1e-6, temp ~1e-4 K, ucomp/vcomp abs ~2.5e-5;
   Fortran-vs-CPU exact). Bit-exact CPU-vs-CUDA is NOT required (accepted 2026-07-01).
6. Repeat 30-day for ±0.1% stability.

## To recreate the task-2 baseline clone (worktrees DO NOT work — see gotcha)
```
cd /explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere
git clone . ../gfdl_task2_baseline && cd ../gfdl_task2_baseline && git checkout d33fd44
sed -i 's/held_suarez_fv_kernels_cuda_resident_30day/held_suarez_fv_kernels_cuda_resident_30day_task2/' scripts/run_fv_kernels_resident_30day.sh
GFDL_BASE_OVERRIDE=$PWD USE_CUDA_FV_ADVECTION_KERNELS=1 ./run_compile_fv_kernels.sh
git checkout -- .
GFDL_BASE=$PWD FV_KERNELS_OVERWRITE=1 scripts/run_fv_kernels_resident_30day.sh
```
Cleanup when done: `cd ../GFDL_atmos_cubed_sphere && rm -rf ../gfdl_task2_baseline`

## Env / gotchas (from CHECK_POINT_2026-06-30_task3_validation.md)
- gpu011: x86_64 + Tesla V100, apptainer. Container `/lscratch/rlgill/isca-debian_latest`.
- Cluster repo `/explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere`.
- Scripts wrap themselves in `apptainer exec --nv` — run from HOST shell, not inside.
  Container binds only `/explore/nobackup/people/rlgill`.
- **git worktree fails in-container**: worktree `.git` points to a `/panfs/ccds02/...`
  realpath that is not bind-mounted → Isca `git log` dies. Use a full `git clone`.
- Always pass `GFDL_BASE=$PWD` (default points at the AAI GFDL clone, a different copy).
  Build dir is keyed by GFDL_BASE path, so a clone builds separately (no clobber).
- Run script hardcodes the experiment name → in the clone, sed it to `..._task2` so it
  can't overwrite the validated task-3 output. `FV_KERNELS_OVERWRITE=1` to redo a run.
- Validation runs HOST python3; container python lacks a NetCDF backend/ncdump.
- Refs `held_suarez_default` (Fortran) + `held_suarez_fv_kernels_30day` (CPU) are
  symlinked into the rlgill AAI isca_data root; one --data-root resolves all three.
- If backing out task 3 entirely: revert `ce4ddc2`; task-2 (`d33fd44`) = 176.5 s,
  CPU-vs-CUDA bit-exact — the safe shipping state.

Related: [[task3-divergence-fold]] [[task3-validation-bitexact]] [[resident-dq2-bug]]
