# four_in_one Performance Modernization Plan

Date: 2026-06-15

## Target

Chosen module/routine:

```text
src/atmos_spectral/model/spectral_dynamics.F90
spectral_dynamics_mod::four_in_one
```

This is the next Held-Suarez modernization target after the completed forcing
module hybrid workflow.  The goal is wall-clock performance relevance, not just
another small translation proof.

## Target Routines

Primary routine:

```text
four_in_one
```

Calling context:

```text
spectral_dynamics
  pressure_variables
  compute_pressure_gradient
  four_in_one
  compute_geopotential
  vert_advection
  transforms
  damping
  leapfrog
```

Inputs to capture:

```text
divg
u_grid
v_grid
t_grid
p_surf
ln_p_half
ln_p_full
p_full
dx_psg
dy_psg
dt_psg
wg
wg_full
dt_tg
dt_ug
dt_vg
```

Module state needed:

```text
rdgas
cp_air
dpk
dbk
bk
num_levels
vert_difference_option
local grid bounds
```

Outputs and inout arrays to validate:

```text
dt_psg
wg
wg_full
dt_tg
dt_ug
dt_vg
```

## Required Baseline Harness

Create a standalone Fortran baseline harness before translating the routine.

Suggested location:

```text
tests/fortran_baseline/four_in_one/
```

The harness should:

- Initialize or inject the module constants and vertical-coordinate arrays used
  by `four_in_one`.
- Generate deterministic input arrays matching the Held-Suarez grid shape for
  a small baseline case.
- Include both supported `vert_difference_option` paths if both are relevant:
  `simmons_and_burridge` and `mcm`.
- Write binary or NetCDF-free array blobs for all inputs and outputs.
- Record dimensions, option flags, and scalar constants in a small metadata
  file.

Start with the exact runtime option used by the current Held-Suarez experiment,
then add the alternate path as an edge-case test.

## C++ Translation Strategy

Create the C++ implementation under:

```text
translated/held_suarez/cpp/four_in_one/
```

Recommended structure:

```text
include/four_in_one.h
src/four_in_one.cpp
tests/driver_four_in_one.cpp
Makefile
```

Translation approach:

- Keep the first C++ version CPU-only and scalar/loop-based.
- Preserve Fortran operation order inside each vertical column.
- Use explicit dimension and stride parameters rather than hidden global state.
- Pass constants and vertical-coordinate arrays through a small config struct.
- Match Fortran array layout carefully.  The existing forcing-module workflow
  should be reused for binary input/output comparison.
- Avoid CUDA in the first translation.  CUDA should come only after standalone
  CPU parity and hybrid parity are established.

Expected C++ API shape:

```text
four_in_one_driver(config, dimensions, inputs, inout_outputs)
```

This can later be wrapped by a stable C ABI for Fortran integration.

## Hybrid Integration Strategy

Use the same non-invasive overlay approach that worked for the forcing module.

Do not modify production `spectral_dynamics.F90`.

Recommended path:

```text
src/extra/local_overrides/spectral_dynamics/spectral_dynamics.F90
```

Hybrid integration steps:

1. Copy or overlay only the minimum required `spectral_dynamics.F90` changes.
2. Replace the body or call site of `four_in_one` with an `iso_c_binding`
   wrapper call under a compile flag such as:

   ```text
   -DUSE_CPP_FOUR_IN_ONE
   ```

3. Keep a Fortran fallback path in the overlay so the same overlay can build
   both baseline and hybrid variants.
4. Build the C++ static library inside the same Apptainer container and target
   architecture as the model.
5. Link through a dedicated mkmf template if additional C++/CUDA libraries are
   required.
6. Build through `CodeBase.compile()`, not manual `mkmf`.

Suggested executable names:

```text
held_suarez_four_in_one_fortran.x
held_suarez_four_in_one_hybrid.x
```

## Comparison Metrics

Standalone comparison:

- Max absolute error for each output array.
- RMSE for each output array.
- Number of elements above tolerance.
- Separate reporting for:
  - `dt_psg`
  - `wg`
  - `wg_full`
  - `dt_tg`
  - `dt_ug`
  - `dt_vg`

Suggested initial tolerances:

```text
absolute: 1e-12 to 1e-10
relative: 1e-12 to 1e-10
```

For bit-reproducibility attempts, compare exact binary output first, then relax
only if expression ordering or compiler differences make exact parity
unreasonable.

Hybrid model comparison:

- 1-timestep or 1-day smoke run.
- 30-day duration-matched all-Fortran versus hybrid run.
- Compare selected NetCDF fields:
  - `ps`
  - `ucomp`
  - `vcomp`
  - `temp`
  - `vor`
  - `div`
- Report max absolute error, RMSE, variable/dimension match, and time-coordinate
  match.

Performance comparison:

- Total model wall-clock time.
- Seconds per model step.
- `four_in_one` total time.
- `four_in_one` time fraction.
- Dynamics-region totals before and after hybrid replacement.

## Expected Performance Benefit

Expected benefit: moderate if `four_in_one` is a measurable fraction of
`spectral_dynamics`; low if transform or vertical-advection costs dominate.

Reasons for optimism:

- Called every timestep.
- Large regular loops over 3D grid arrays.
- Directly affects dynamics-state tendencies.
- Horizontal columns are mostly independent.
- Avoids I/O and MPI inside the target kernel.

Reasons for caution:

- The full spectral model may spend more time in transforms, vertical
  advection, or diagnostics.
- `four_in_one` includes vertical recurrence through `dmean_tot`, limiting
  parallelism across levels within one column.
- CPU/GPU transfer overhead would erase benefit if only this one kernel is
  offloaded while the rest of dynamics remains on CPU.

The first GPU version, if pursued, should be treated as an architecture step
unless profiling proves that `four_in_one` is a large wall-clock component.

## Profiling And Timing Method

Before translating, implement Level 2 and Level 3 timers from
`docs/profiling_plan_for_module_selection.md`.

Minimum timers:

```text
atmosphere total
hs_forcing
spectral_dynamics
compute_pressures_and_heights
diagnostics
```

Dynamics timers:

```text
pressure_variables
compute_pressure_gradient
four_in_one
compute_geopotential
vert_advection_u
vert_advection_v
vert_advection_t
horizontal_advection
transforms
implicit_correction
spectral_damping
leapfrog
future_grid_update
```

Implementation rules:

- Use overlays, not production-source edits.
- Use `system_clock` or existing FMS clock utilities.
- Accumulate totals and print once near model end.
- Use identical instrumentation for all-Fortran and hybrid runs.
- Run duration-matched 30-day profiles inside the same container.

Decision threshold:

- If `four_in_one` is a clear measurable part of total model runtime, continue
  with translation and hybrid integration.
- If `four_in_one` is small but `vert_advection` dominates, switch the next
  performance target to `vert_advection_3d`.
- If transforms dominate, treat transform modernization as a larger redesign
  milestone rather than a direct routine translation.

## Deliverables For This Phase

1. `tests/fortran_baseline/four_in_one/`
2. `translated/held_suarez/cpp/four_in_one/`
3. Standalone comparison report under `tests/reports/`
4. Overlay source under `src/extra/local_overrides/`
5. Native Isca hybrid executable built with `CodeBase.compile()`
6. 1-day smoke test
7. 30-day output comparison
8. Timing report showing whether the translation affects wall-clock runtime

