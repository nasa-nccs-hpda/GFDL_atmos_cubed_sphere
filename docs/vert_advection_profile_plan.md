# vert_advection_3d Profile Plan

Date: 2026-06-16

## Purpose

`four_in_one` measured at about 2.6% of the 30-day Held-Suarez model runtime,
so it is not an ideal standalone performance target.  The next step is to
profile `vert_advection_mod::vert_advection_3d` before selecting the next
module for translation.

The first vertical-advection profile executable compiled with
`-DPROFILE_VERT_ADVECTION`, but the expected module-level marker did not print.
The likely cause is that `vert_advection_end` is not called by the Held-Suarez
shutdown path.  This updated plan moves timing to the `spectral_dynamics.F90`
call sites and reports from `spectral_dynamics_end`, which is reached during
the 30-day run.

This is a timing-only experiment.  No C++ translation is started.

## Target Routine

Source file:

```text
src/atmos_shared/vert_advection/vert_advection.F90
```

Module:

```text
vert_advection_mod
```

Routine:

```text
vert_advection_3d
```

Generic interface:

```fortran
interface vert_advection
   module procedure vert_advection_1d, vert_advection_2d, vert_advection_3d
end interface
```

The Held-Suarez spectral dynamics path calls the generic `vert_advection` with
3D arrays, so it dispatches to `vert_advection_3d`.

## Held-Suarez Call Sites

Primary every-timestep dry dynamics calls in
`src/atmos_spectral/model/spectral_dynamics.F90`:

```text
u wind:
call vert_advection(delta_t, wg, dp, ug(:,:,:,time_level), dt_grid_tmp, scheme=uv_vert_advect_scheme, form=ADVECTIVE_FORM)

v wind:
call vert_advection(delta_t, wg, dp, vg(:,:,:,time_level), dt_grid_tmp, scheme=uv_vert_advect_scheme, form=ADVECTIVE_FORM)

temperature:
call vert_advection(delta_t, wg, dp, tg(:,:,:,time_level), dt_grid_tmp, scheme=t_vert_advect_scheme, form=ADVECTIVE_FORM)
```

Tracer-related call sites also exist in `update_tracers`:

```text
spectral tracer path:
call vert_advection(delta_t, wg, dp, grid_tracers(:,:,:,time_level,ntr), dt_tmp, ...)

grid tracer path:
call vert_advection(delta_t, wg, dp, tr_future, dt_tmp, ...)
```

The current call-site instrumentation times the u, v, and temperature calls.
The reported `total` is therefore the u+v+t total.  Tracer call-site timing can
be added later if the rerun shows vertical advection is important enough.

For the current dry Held-Suarez run, the expected minimum call count is:

```text
30 days * 86400 s/day / 600 s timestep * 3 fields = 12960 calls
```

## Overlay Source

Production source remains untouched.

Overlay path:

```text
src/extra/local_overrides/spectral_dynamics/spectral_dynamics.F90
```

Original source replaced in the profile build:

```text
atmos_spectral/model/spectral_dynamics.F90
```

The older module-level overlay remains available but is not the reporting hook
for this rerun:

```text
src/extra/local_overrides/vert_advection/vert_advection.F90
```

## Instrumentation

Compile guard:

```text
-DPROFILE_VERT_ADVECTION
```

Metrics:

```text
profile_vert_advection_u_seconds
profile_vert_advection_v_seconds
profile_vert_advection_t_seconds
profile_vert_advection_u_calls
profile_vert_advection_v_calls
profile_vert_advection_t_calls
```

Timer:

```fortran
call system_clock(t0, rate)
call vert_advection(...)
call system_clock(t1)
```

Report location:

```text
spectral_dynamics_end
```

MPI behavior:

- The report uses `mpp_max` for elapsed seconds and call count.
- PE 0 prints one summary line per field plus one total line.

Expected log markers:

```text
PROFILE_VERT_ADVECTION_CALLSITE field=u calls_max=... time_max=... avg_max=...
PROFILE_VERT_ADVECTION_CALLSITE field=v calls_max=... time_max=... avg_max=...
PROFILE_VERT_ADVECTION_CALLSITE field=t calls_max=... time_max=... avg_max=...
PROFILE_VERT_ADVECTION_CALLSITE total calls_max=... time_max=... avg_max=...
```

## Build Target

Native overlay build target:

```text
profile_vert_advection
```

Expected executable:

```text
held_suarez_profile_vert_advection.x
```

This is separate from:

```text
held_suarez_hybrid.x
held_suarez_profile_four_in_one.x
```

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
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py profile_vert_advection \
  2>&1 | tee logs/vert_advection_profile_callsite_compile.log
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
    --executable-name held_suarez_profile_vert_advection.x \
    --exp-name held_suarez_profile_vert_advection_callsite \
    --days 30 \
    --production-diag \
    --overwrite; } \
  2>&1 | tee logs/vert_advection_profile_30day_callsite.log
'
```
