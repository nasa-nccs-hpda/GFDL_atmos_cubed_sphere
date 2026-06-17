# four_in_one Timing Plan

Date: 2026-06-16

## Purpose

Before translating `spectral_dynamics_mod::four_in_one`, measure whether it is
large enough to justify a standalone C++ hybrid translation.

This timing experiment is non-invasive:

- Production `src/atmos_spectral/model/spectral_dynamics.F90` is untouched.
- Timing is added only in an overlay source.
- Timing compiles only when `-DPROFILE_FOUR_IN_ONE` is present.
- The existing `held_suarez_hybrid.x` executable is not modified.

## Overlay Source

Overlay path:

```text
src/extra/local_overrides/spectral_dynamics/spectral_dynamics.F90
```

Original source replaced in the profile build:

```text
src/atmos_spectral/model/spectral_dynamics.F90
```

## Instrumentation

The overlay adds:

```text
PROFILE_FOUR_IN_ONE
profile_four_in_one_seconds
profile_four_in_one_calls
```

Timing method:

```fortran
call system_clock(t0, rate)
call four_in_one original body
call system_clock(t1)
```

The timer accumulates local elapsed seconds and call count for
`four_in_one`.  At `spectral_dynamics_end`, it reduces the maximum elapsed time
and maximum call count across PEs using `mpp_max`, then root PE prints one log
line:

```text
PROFILE_FOUR_IN_ONE calls_max= ... seconds_max= ... avg_seconds_per_call_max= ...
```

## Build Target

The native overlay compiler now supports:

```text
profile_four_in_one
```

Expected executable:

```text
held_suarez_profile_four_in_one.x
```

The profile build uses the standard dry Isca compile path plus one overlay and
one compile flag:

```text
-DPROFILE_FOUR_IN_ONE
```

No C++ translation or CUDA code is involved.

## Build Command

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
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py profile_four_in_one \
  2>&1 | tee logs/four_in_one_profile_compile.log
'
```

## 30-Day Profile Run Command

Run from the repository root after the executable is generated:

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

Expected output directory:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_profile_four_in_one/run0001/
```

## Success Criteria

Build success:

```text
Generated: .../held_suarez_profile_four_in_one.x
```

Run success:

```text
Integration completed through 2000 Feb  1   0: 0: 0
Run 1 complete
PROFILE_FOUR_IN_ONE calls_max= ...
```

The exact completion date may vary with calendar details, but the run should
complete 30 simulated days and write `atmos_monthly.nc`.

## Decision Use

After the run, parse:

```text
logs/four_in_one_profile_30day.log
```

Compute:

- Total model wall-clock time from shell `time`.
- `four_in_one` max PE time.
- Number of `four_in_one` calls.
- Average time per call.
- Fraction of model wall-clock time.

If `four_in_one` is measurable, proceed to the standalone Fortran baseline
harness.  If it is negligible, profile `vert_advection_3d` and the transform
stack before translating.

