# four_in_one Timing Report

Date: 2026-06-16

## Status

Prepared, not yet run.

This phase adds non-invasive timing instrumentation for
`spectral_dynamics_mod::four_in_one` through a source overlay.  No C++
translation has been started.

## Files Changed

Overlay source:

```text
src/extra/local_overrides/spectral_dynamics/spectral_dynamics.F90
```

Build/run helpers:

```text
hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py
hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py
```

Documentation:

```text
docs/four_in_one_timing_plan.md
docs/four_in_one_timing_report.md
```

## Instrumentation Summary

Compile guard:

```text
-DPROFILE_FOUR_IN_ONE
```

Timed region:

```text
spectral_dynamics_mod::four_in_one
```

Timer:

```text
system_clock
```

Accumulated metrics:

```text
profile_four_in_one_seconds
profile_four_in_one_calls
```

Report location:

```text
spectral_dynamics_end
```

Expected log marker:

```text
PROFILE_FOUR_IN_ONE calls_max= ... seconds_max= ... avg_seconds_per_call_max= ...
```

## Build Target

New target:

```text
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py profile_four_in_one
```

Expected executable:

```text
held_suarez_profile_four_in_one.x
```

This executable is separate from:

```text
held_suarez_hybrid.x
held_suarez_fortran.x
```

## Exact Build Command

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
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py profile_four_in_one \
  2>&1 | tee logs/four_in_one_profile_compile.log
'
```

## Exact 30-Day Run Command

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
    --executable-name held_suarez_profile_four_in_one.x \
    --exp-name held_suarez_profile_four_in_one \
    --days 30 \
    --production-diag \
    --overwrite; } \
  2>&1 | tee logs/four_in_one_profile_30day.log
'
```

## Results

Not yet available.

Fill after run:

| Metric | Value |
|---|---:|
| Total model wall-clock seconds | TBD |
| `four_in_one` calls max across PEs | TBD |
| `four_in_one` seconds max across PEs | TBD |
| `four_in_one` average seconds per call | TBD |
| `four_in_one` fraction of model wall-clock | TBD |

## Next Decision

Proceed with CPU C++ translation only if `four_in_one` is measurable enough to
justify the workflow.  If its fraction is negligible, profile
`vert_advection_3d` next.

