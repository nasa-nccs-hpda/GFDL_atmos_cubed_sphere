# Profiling Plan For Module Selection

Date: 2026-06-08

## Purpose

The static ranking in `docs/next_module_ranking.md` identifies good candidates
for the next Held-Suarez Fortran-to-C++ hybrid translation.  Before starting a
larger dynamics translation, measure the true runtime importance of the
candidates in matched all-Fortran and hybrid Held-Suarez runs.

The profiling goal is to answer:

- How much wall-clock time is spent in forcing versus dynamics versus
  diagnostics/I/O?
- Within dynamics, how much time is spent in pressure/geopotential,
  `four_in_one`, vertical advection, transforms, implicit correction, spectral
  damping, and leapfrog update?
- Does the hybrid forcing-module executable have the same runtime structure as
  the all-Fortran executable?
- Which candidate gives the best next payoff for modernization and GPU
  portability?

## Runs To Profile

Use the same container and runtime configuration that produced the successful
Held-Suarez hybrid build and runs.

Profile these two duration-matched runs:

1. All-Fortran Held-Suarez 30-day run.
2. Hybrid forcing-module Held-Suarez 30-day run.

The runs should use the same:

- Resolution.
- Namelist/runtime settings.
- Processor count.
- Container image.
- `GFDL_WORK` and `GFDL_DATA` layout.
- Diagnostics cadence, or a deliberately minimized diagnostics cadence for a
  separate compute-only profile.

## Representative Commands

Hybrid 30-day run:

```bash
python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --days 30 \
  --production-diag \
  --overwrite \
  2>&1 | tee logs/hybrid_run_30day_profile.log
```

All-Fortran 30-day run:

```bash
python3 hybrid_experiments/held_suarez_cpp_force/run_fortran_held_suarez.py \
  --days 30 \
  --production-diag \
  --overwrite \
  2>&1 | tee logs/fortran_run_30day_profile.log
```

If `run_fortran_held_suarez.py` does not exist yet, create it as a
non-invasive wrapper that mirrors
`hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py` but
selects the original Held-Suarez executable instead of `held_suarez_hybrid.x`.

Do not use the original long default experiment duration for profiling unless
that is intentional.  The first comparison should be a duration-matched 30-day
run.

## Profiling Levels

### Level 1: Existing run timing

Start with logs from unmodified all-Fortran and hybrid runs.

Collect:

- Total wall-clock time.
- Model start and completion timestamps.
- Any existing FMS/MPI clock summaries.
- Output file generation time if visible in logs.

This level confirms whether forcing replacement changed total runtime and
whether I/O dominates the small 30-day profile.

### Level 2: Coarse component timers

Add temporary timing around the largest runtime regions in
`src/atmos_spectral/driver/solo/atmosphere.F90` through a source overlay, not by
editing production source.

Time these blocks inside `atmosphere(Time)`:

- `hs_forcing`
- `spectral_dynamics`
- `compute_pressures_and_heights`
- `spectral_diagnostics`
- time-level rotation and small driver overhead

Expected output:

```text
PROFILE atmosphere hs_forcing_seconds=...
PROFILE atmosphere spectral_dynamics_seconds=...
PROFILE atmosphere pressure_height_seconds=...
PROFILE atmosphere diagnostics_seconds=...
PROFILE atmosphere total_steps=...
```

This level separates forcing cost from dynamics and diagnostics/I/O.

### Level 3: Dynamics-region timers

Add temporary timing inside `src/atmos_spectral/model/spectral_dynamics.F90`
through an overlay.  Keep instrumentation coarse enough that it does not change
the algorithm or flood logs.

Time these blocks inside `spectral_dynamics`:

- `pressure_variables`
- `compute_pressure_gradient`
- `four_in_one`
- `compute_geopotential`
- `trans_grid_to_spherical` for pressure/tendency paths
- `vert_advection` for `u`, `v`, and `t`
- `horizontal_advection`
- `vor_div_from_uv_grid`
- geopotential-plus-kinetic-energy transform and Laplacian
- `implicit_correction`
- `compute_spectral_damping_vor`
- `compute_spectral_damping_div`
- `compute_spectral_damping` for temperature
- `leapfrog` / `leapfrog_2level_A`
- future-state transforms back to grid
- `update_tracers`, if active

Expected output:

```text
PROFILE spectral_dynamics pressure_variables_seconds=...
PROFILE spectral_dynamics pressure_gradient_seconds=...
PROFILE spectral_dynamics four_in_one_seconds=...
PROFILE spectral_dynamics compute_geopotential_seconds=...
PROFILE spectral_dynamics vert_advection_u_seconds=...
PROFILE spectral_dynamics vert_advection_v_seconds=...
PROFILE spectral_dynamics vert_advection_t_seconds=...
PROFILE spectral_dynamics horizontal_advection_seconds=...
PROFILE spectral_dynamics transforms_seconds=...
PROFILE spectral_dynamics implicit_seconds=...
PROFILE spectral_dynamics damping_seconds=...
PROFILE spectral_dynamics leapfrog_seconds=...
PROFILE spectral_dynamics future_grid_update_seconds=...
PROFILE spectral_dynamics total_steps=...
```

This level identifies whether the static top candidates are actually
wall-clock-relevant.

### Level 4: Function-level profiling

If container/toolchain support allows, supplement coarse timers with compiler or
system profiling.

Options:

- Compiler instrumentation such as `-pg`, if compatible with the Isca build and
  container toolchain.
- Linux `perf`, if permitted in the runtime environment.
- Lightweight sampling through external HPC/container tooling, if available.
- FMS or MPP clock utilities, if the existing codebase provides a clean clock
  API that can be used from overlays.

Use this only after Level 2 and Level 3, because coarse timers are easier to
compare and less sensitive to tool availability.

## Instrumentation Rules

- Do not modify production Fortran source.
- Use source overlays, following the successful hybrid forcing-module approach.
- Build through `CodeBase.compile()`, not manual `mkmf`.
- Keep instrumentation under an explicit profiling compile flag, for example
  `-DPROFILE_HS_MODULE_SELECTION`, if preprocessing support is needed.
- Print aggregated totals at model end or at long intervals, not every
  timestep.
- Use the same timing method in all-Fortran and hybrid runs.
- Run inside the same Apptainer/container environment used for successful
  Held-Suarez builds.

## Suggested Timer Implementation

For the first pass, prefer coarse Fortran timers using `system_clock` in overlay
sources.  Accumulate elapsed seconds in module variables and print totals at
`atmosphere_end` or `spectral_dynamics_end`.

Implementation pattern:

```fortran
integer :: t0, t1, rate
real :: elapsed

call system_clock(t0, rate)
! profiled block
call system_clock(t1)
elapsed = real(t1 - t0) / real(rate)
accumulator = accumulator + elapsed
```

If the local FMS/MPI clock infrastructure has a lightweight clock utility that
is already used in this codebase, that can replace `system_clock`, but only if
it avoids adding diagnostic or MPI complexity to the experiment.

## Comparison Metrics

For each profiled run, report:

- Total runtime.
- Number of model steps.
- Seconds per model step.
- Component wall-clock seconds.
- Component percentage of total model runtime.
- Hybrid minus all-Fortran runtime difference.
- Forcing-module runtime contribution before and after hybrid replacement.
- Dynamics-region breakdown.

Recommended table:

| Component | All-Fortran seconds | Hybrid seconds | All-Fortran % | Hybrid % | Delta seconds | Notes |
|---|---:|---:|---:|---:|---:|---|
| Forcing | | | | | | |
| Spectral dynamics | | | | | | |
| Pressure/geopotential | | | | | | |
| `four_in_one` | | | | | | |
| Vertical advection | | | | | | |
| Transforms | | | | | | |
| Implicit correction | | | | | | |
| Spectral damping | | | | | | |
| Leapfrog | | | | | | |
| Diagnostics/I/O | | | | | | |

## Output Files

Suggested logs:

```text
logs/fortran_run_30day_profile.log
logs/hybrid_run_30day_profile.log
logs/fortran_run_30day_profile_timers.log
logs/hybrid_run_30day_profile_timers.log
```

Suggested report:

```text
docs/profiling_report_module_selection.md
```

Suggested machine-readable summary:

```text
tests/reports/module_selection_profile.json
```

## Decision Criteria

After profiling, choose the next module by combining:

- Static ranking from `docs/next_module_ranking.md`.
- Measured wall-clock contribution.
- Isolation difficulty.
- Validation feasibility.
- GPU-portability relevance.
- Reuse value for future GEOS modernization.

Expected outcomes:

- If `four_in_one` is a meaningful runtime contributor, keep it as the next
  translation target.
- If `leapfrog` is small in wall-clock but quick to validate, consider it as a
  low-risk warmup before `four_in_one`.
- If `press_and_geopot` is a large contributor, it may be the best module-level
  translation after or before `four_in_one`.
- If transforms dominate, defer direct translation until there is a separate
  transform-library/GPU strategy.
- If diagnostics/I/O dominates the 30-day run, rerun with minimized diagnostics
  to profile compute kernels fairly.

## Recommended Immediate Plan

1. Run uninstrumented duration-matched 30-day all-Fortran and hybrid runs.
2. Confirm output equivalence or document known numerical differences.
3. Add a temporary profiling overlay for `atmosphere.F90`.
4. Build all-Fortran profiling and hybrid profiling executables through
   `CodeBase.compile()`.
5. Run 30-day profiles with identical settings.
6. If `spectral_dynamics` dominates, add the Level 3 dynamics-region overlay.
7. Produce `docs/profiling_report_module_selection.md`.
8. Start translation of the selected next module only after the profiling report
   confirms the target.
