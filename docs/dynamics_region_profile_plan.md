# Dynamics Region Profile Plan

Date: 2026-06-16

## Purpose

The previous isolated routine profiles did not identify a large enough
performance target:

```text
four_in_one: about 2.6% of model MPP runtime
vert_advection_3d u+v+t: about 0.34% of model MPP runtime
```

Before selecting the next Fortran-to-C++ translation target, profile broader
regions in the Held-Suarez spectral dynamics path.

This is a timing-only experiment.  No module translation is started.

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
-DPROFILE_DYNAMICS_REGIONS
```

## Profile Target

Native overlay build target:

```text
profile_dynamics_regions
```

Expected executable:

```text
held_suarez_profile_dynamics_regions.x
```

## Timed Regions

The profile prints one line per region from `spectral_dynamics_end`, which is
known to be reached by the Held-Suarez run.

Expected markers:

```text
PROFILE_DYNAMICS_REGION name=spectral_dynamics_step calls_max=... time_max=... avg_max=...
PROFILE_DYNAMICS_REGION name=press_geopot calls_max=... time_max=... avg_max=...
PROFILE_DYNAMICS_REGION name=transforms calls_max=... time_max=... avg_max=...
PROFILE_DYNAMICS_REGION name=advection calls_max=... time_max=... avg_max=...
PROFILE_DYNAMICS_REGION name=damping calls_max=... time_max=... avg_max=...
PROFILE_DYNAMICS_REGION name=leapfrog_update calls_max=... time_max=... avg_max=...
PROFILE_DYNAMICS_REGION name=tracer_correction_diagnostics calls_max=... time_max=... avg_max=...
```

Region definitions:

| Region | Scope |
|---|---|
| `spectral_dynamics_step` | Full `spectral_dynamics` timestep loop body. |
| `press_geopot` | `pressure_variables`, pressure-gradient setup, virtual temperature selection, `four_in_one`, and `compute_geopotential`. |
| `transforms` | Accumulated transform-heavy calls in the main timestep path: grid-to-spectral transforms, `vor_div_from_uv_grid`, future-state spectral-to-grid transforms, and `uv_grid_from_vor_div`. |
| `advection` | u/v/t vertical advection plus temperature horizontal advection in the main dry dynamics path. |
| `damping` | Optional implicit correction plus spectral damping calls for vorticity, divergence, and temperature. |
| `leapfrog_update` | Leapfrog or RAW-filtered leapfrog updates of spectral prognostic fields. |
| `tracer_correction_diagnostics` | `update_tracers`, mass/water/energy corrections, time update, and every-step diagnostics. |

Notes:

- `spectral_dynamics_step` is an envelope region and should not be summed with
  the subregions.
- `transforms` is accumulated across several separated call groups, so its
  call count is expected to be larger than the timestep count.
- The regions are coarse by design.  The goal is target selection, not detailed
  line-level optimization.

## MPI Behavior

Each region reports:

```text
calls_max
time_max
avg_max
```

The values are max-reduced across MPI ranks using `mpp_max`.  PE 0 prints the
final markers.

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
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py profile_dynamics_regions \
  2>&1 | tee logs/dynamics_region_profile_compile.log
'
```

## Exact 30-Day Profile Run Command

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
    --executable-name held_suarez_profile_dynamics_regions.x \
    --exp-name held_suarez_profile_dynamics_regions \
    --days 30 \
    --production-diag \
    --overwrite; } \
  2>&1 | tee logs/dynamics_region_profile_30day.log
'
```

## Decision Use

After the run, parse:

```text
logs/dynamics_region_profile_30day.log
```

Use the measured runtime fractions to choose the next target:

| Runtime Fraction | Decision |
|---:|---|
| `>10%` | Strong GO |
| `5-10%` | GO |
| `2-5%` | PARTIAL GO |
| `<2%` | Weak performance target |

Preference should go to regions that are:

- called every timestep,
- large enough to affect wall-clock time,
- dominated by regular numerical kernels,
- minimally coupled to I/O, diagnostics, and MPI infrastructure,
- realistic to isolate with the existing overlay/hybrid workflow.
