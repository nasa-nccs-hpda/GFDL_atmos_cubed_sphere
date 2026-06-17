# Dynamics Deep Profile Plan

Date: 2026-06-16

## Purpose

The broad 30-day dynamics-region profile found large mixed regions:

```text
transforms: 32.748 s, 38.92%
tracer_correction_diagnostics: 27.401 s, 32.56%
advection: 6.659 s, 7.91%
press_geopot: 4.051 s, 4.81%
```

The project decision is not to translate yet.  This second-level profile splits
the large mixed regions into actionable call-site timers before selecting the
next performance-targeted modernization module or region.

## Source Strategy

Production source remains untouched.

Overlay source:

```text
src/extra/local_overrides/spectral_dynamics/spectral_dynamics.F90
```

Original source replaced in the profile build:

```text
atmos_spectral/model/spectral_dynamics.F90
```

Compile guard:

```text
-DPROFILE_DYNAMICS_DEEP
```

## Profile Target

Native overlay build target:

```text
profile_dynamics_deep
```

Expected executable:

```text
held_suarez_profile_dynamics_deep.x
```

## Expected Markers

The profile prints one line per deep region from `spectral_dynamics_end`:

```text
PROFILE_DYNAMICS_DEEP name=<region> calls_max=... time_max=... avg_max=...
```

The values are max-reduced across MPI ranks with `mpp_max`, and PE 0 prints
the final markers.

## Deep Regions

Transform-heavy split:

```text
transform_dt_ln_ps
transform_dt_t
transform_vor_div_from_uv
transform_phis_plus_ke
transform_future_div
transform_future_vor
transform_future_uv_from_vor_div
transform_future_t
transform_future_ln_ps
```

Advection split:

```text
horizontal_advection_temperature
vertical_advection_u
vertical_advection_v
vertical_advection_t
```

Tracer/correction/diagnostic split:

```text
update_tracers
compute_corrections
every_step_diagnostics
tracer_horizontal_advection
tracer_vertical_advection
tracer_grid_to_spectral
tracer_spectral_to_grid
tracer_grid_horizontal_advection
```

Notes:

- There are no separate `horizontal_advection_u` or `horizontal_advection_v`
  calls in the main Held-Suarez `spectral_dynamics` timestep path.  Wind
  tendencies pass through `vor_div_from_uv_grid` and the transform stack.
- `src/atmos_spectral/model/transforms.F90` is not present in this tree.  The
  transform work is reached through `transforms_mod` calls from
  `spectral_dynamics.F90`, so this profile splits the actual call sites used by
  Held-Suarez.
- `src/atmos_spectral/model/hs_forcing.F90` is not present or relevant to this
  dynamics-region split.  The completed forcing-module hybrid path remains
  unchanged.
- Tracer-specific markers will remain at zero calls if the current dry
  Held-Suarez run has no active tracer work in those branches.

## Exact Container Build Command

Run from the repository root:

```bash
apptainer exec \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  /lscratch/jli30/isca-sandbox \
  bash -lc '
set -e
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=ubuntu_conda
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd ${GFDL_BASE}
mkdir -p logs
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py profile_dynamics_deep \
  2>&1 | tee logs/dynamics_deep_profile_compile.log
'
```

## Exact 30-Day Deep Profile Run Command

Run after successful executable generation:

```bash
apptainer exec \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  /lscratch/jli30/isca-sandbox \
  bash -lc '
set -e
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=ubuntu_conda
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd ${GFDL_BASE}
mkdir -p logs
{ time python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
    --executable-name held_suarez_profile_dynamics_deep.x \
    --exp-name held_suarez_profile_dynamics_deep \
    --days 30 \
    --production-diag \
    --overwrite; } \
  2>&1 | tee logs/dynamics_deep_profile_30day.log
'
```

## Decision Use

After the run, parse:

```text
logs/dynamics_deep_profile_30day.log
```

Use the same runtime bands as the broad profile:

| Runtime Fraction | Meaning |
|---:|---|
| `>20%` | Excellent target |
| `10-20%` | Strong target |
| `5-10%` | Reasonable target |
| `2-5%` | Weak but possible |
| `<2%` | Do not target for performance |

The next translation target should be selected only after the deep profile
shows which specific transform, advection, tracer, correction, or diagnostic
call sites own the measured runtime.
