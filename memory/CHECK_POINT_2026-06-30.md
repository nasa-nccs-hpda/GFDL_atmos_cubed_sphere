# Checkpoint - 2026-06-30

## Start here

Read as historical baseline, in order:

- `memory/FINAL_PROJECT_CHECKPOINT_2026-06-19.md`
- `memory/CHECK_POINT_2026-06-25.md`

Then use the notes below as the delta from this session.

## Repository and branch

- Branch: `perf/resident-semi-y-integration`
- Repo in use this session: `/explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere`
- `x86_64 + V100` (gpu011), `singularity`/`apptainer`, container `/lscratch/rlgill/isca-debian_latest`

## Big picture task sequence

1. integrate CUDA `semi_y_3d` into resident pre-halo FV boundary — DONE (2026-06-25)
2. `q1` halo-only transfers — **DONE this session**
3. broader `update_tracers`-level residency — next
4. larger-resolution scaling studies
5. transforms/vendor-library study later

## Current checkpoint

Completion of task 2 (q1 halo-only transfers), plus a correctness bug
(`d_q2`) discovered and fixed along the way.

## What was implemented

- **q1 halo-only transfers.** The device q1 interior now stays resident across
  begin -> finish. `resident_advection_begin` D2H shrinks from the full interior
  to the two edge interior rows per side (what the MPI send and polar fold need);
  `resident_advection_finish` H2D shrinks from the full q1 to the four halo rows
  only. Interior never leaves the device after begin.
- **`d_q2` correctness bug fixed.** begin previously formed `d_q2 = semi_y(q1)`
  with no `+q`, reading q1 halo rows it had not filled yet. It now receives the
  haloed q, strips the interior device-side (D2D) for the x-direction kernels,
  runs semi_y over the haloed q, and adds the field via a new `form_q2_kernel`
  to give `q2 = q + semi_y(q)`, matching the Fortran cross term.
- The begin wrapper, the Fortran C interface q extent, and the overlay call site
  were updated to pass `q(:,js-2:je+2,:)` (haloed). The begin C-ABI arg count is
  unchanged — only q's required extent changed.
- The standalone validator was reworked: `resident_q1` is checked on edge rows
  only; expected q1/q2 are derived from `q_sphere` (haloed q), with `q1_combined`
  modelling the device's halo + resident interior.
- A stale `q2` parameter was removed from the `resident_advection_finish`
  declaration in the header so it matched the definition (the interim commit had
  left them out of sync and the resident check did not compile).

## Validation status

All gates passed in this clone/environment:

- standalone `make USE_CUDA_FV_ADVECTION_KERNELS=1 cuda_resident_check` — all
  rows pass, including `resident_combined_dq_dt`
- native CUDA overlay compile (`USE_CUDA_FV_ADVECTION_KERNELS=1 ./run_compile_fv_kernels.sh`)
- one-day smoke
- 30-day run
- 30-day NetCDF validation: exact vs CPU C++, rounding-level vs Fortran
  (max rel ~1e-7 for ps/temp; ucomp/vcomp abs ~2.5e-5, large rel only because
  their means are ~0) — consistent with the historical baseline tolerance
- repeat 30-day run

## Performance

- Stable 30-day runtime: **~176.5 s** (176.67 s, repeat 176.47 s, ±0.1%)
- Down from the ~193.4 s task-1 baseline: **~8.7% faster**
- Profile confirms the win: resident `d2h` dropped to ~0.013 s

## Environment facts / gotchas

- Build and run scripts default `GFDL_WORK`/`GFDL_DATA` to
  `…/SystemTesting/AAI/Isca/…`; pass `GFDL_BASE=…/innovation-lab-repositories/…`
  to use this session's source. Use `FV_KERNELS_OVERWRITE=1` to re-run.
- Run/compile scripts wrap themselves in apptainer; run them from the host shell,
  not from inside the container.
- The NetCDF validation script runs host `python3` directly. The container python
  has no NetCDF backend and no `ncdump`. Validate on host gpu011 with
  `module load anaconda/24.9.0 nco/5.0.3` (ncdump fallback path).
- Reference experiments `held_suarez_default` (Fortran) and
  `held_suarez_fv_kernels_30day` (CPU) live under the jli30 `isca_data` root;
  they were symlinked into the AAI rlgill `isca_data` root so one `--data-root`
  resolves all three experiments.

## Commits (on `perf/resident-semi-y-integration`, pushed to origin)

- `2db70b7` Resident FV advection: q1 halo-only transfers
- `f6e7049` Validator: model halo-only residency in resident dq_dt check
- `d33fd44` Fix resident d_q2: compute q2 = q + semi_y(q) from haloed q

## What is next

1. Decide what should go into the next formal project checkpoint / whether to
   open a PR from this branch (production `src/atmos_*` untouched; changes live in
   `translated/`, the overlay, wrappers, scripts, and reports).
2. Begin task 3: broader `update_tracers`-level residency.
3. Optional cleanup: separate true source changes from local-env/build artifacts
   before any upstream PR (triage started this session; `.gitignore` not changed).
