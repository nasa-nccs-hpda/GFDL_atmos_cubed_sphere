# Spectral Transforms Phase 2 Top-Level Timers

Date: 2026-07-22

## Goal

Add top-level transform timers to confirm that transform-module timing explains
the T85L25 broad `transforms` region:

```text
PROFILE_DYNAMICS_REGION name=transforms time_max=142.453 s
```

The Phase 2 timers distinguish:

- direct forward grid-to-spectral transforms;
- direct inverse spectral-to-grid transforms;
- composite `vor_div_from_uv_grid` transforms;
- composite `uv_grid_from_vor_div` transforms;
- primitive nested transforms inside the wind composites.

## Files Changed

Overlay source added:

```text
src/extra/local_overrides/transforms_top/transforms.F90
```

Build machinery updated:

```text
hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py
```

Production source under `src/atmos_spectral/tools/` was not modified.

## Compile Flag

New flag:

```text
-DPROFILE_TRANSFORMS_TOP
```

The new build target also enables:

```text
-DPROFILE_DYNAMICS_DEEP
```

This keeps model-level call-site timers and transform-module timers in the same
run.

## Executable

Build target:

```text
profile_transforms_top
```

Expected executable:

```text
held_suarez_profile_transforms_top.x
```

## Timer Markers

The overlay prints:

```text
PROFILE_TRANSFORM_TOP name=grid_to_spherical_direct calls_max=... time_max=... avg_max=...
PROFILE_TRANSFORM_TOP name=spherical_to_grid_direct calls_max=... time_max=... avg_max=...
PROFILE_TRANSFORM_TOP name=vor_div_from_uv_grid_composite calls_max=... time_max=... avg_max=...
PROFILE_TRANSFORM_TOP name=uv_grid_from_vor_div_composite calls_max=... time_max=... avg_max=...
PROFILE_TRANSFORM_TOP name=grid_to_spherical_nested_vor_div calls_max=... time_max=... avg_max=...
PROFILE_TRANSFORM_TOP name=spherical_to_grid_nested_uv calls_max=... time_max=... avg_max=...
PROFILE_TRANSFORM_TOP name=nonoverlap_total calls_max=... time_max=... avg_max=...
```

Interpretation:

- `grid_to_spherical_direct`: primitive forward transforms called directly from
  model code.
- `spherical_to_grid_direct`: primitive inverse transforms called directly from
  model code.
- `vor_div_from_uv_grid_composite`: wrapper time for wind-grid to
  vorticity/divergence spectral conversion. Includes nested forward transforms.
- `uv_grid_from_vor_div_composite`: wrapper time for vorticity/divergence to
  wind-grid conversion. Includes nested inverse transforms.
- `grid_to_spherical_nested_vor_div`: primitive forward transforms called from
  inside `vor_div_from_uv_grid`.
- `spherical_to_grid_nested_uv`: primitive inverse transforms called from
  inside `uv_grid_from_vor_div`.
- `nonoverlap_total`: direct forward + direct inverse + wind composite wrapper
  times. This is the first number to compare against the broad dynamics
  `transforms` timer.

The nested timers are printed for call hierarchy accounting and should not be
added to `nonoverlap_total`, because they are already included inside the
composite wrapper timers.

## Expected Call Counts

At T85L25 with `dt_atmos=300` and a 30-day run, the broad profile showed:

```text
PROFILE_DYNAMICS_REGION transforms calls_max=43200
```

The top-level transform-module timers count real public transform entries, so
their call count will not match the broad timer exactly. The broad timer groups
some future-state inverse transforms into one timed region.

Useful derived quantities:

```text
model_steps = 8640
forward_direct_calls_per_step = grid_to_spherical_direct / model_steps
inverse_direct_calls_per_step = spherical_to_grid_direct / model_steps
composite_wind_calls_per_step = (vor_div + uv_from_vor_div) / model_steps
primitive_forward_calls_per_step = (grid_to_spherical_direct + grid_to_spherical_nested_vor_div) / model_steps
primitive_inverse_calls_per_step = (spherical_to_grid_direct + spherical_to_grid_nested_uv) / model_steps
```

Expected broad behavior:

```text
nonoverlap_total should be close to the broad transforms timer, about 142 s at
T85L25, allowing for timer placement and profiling-run noise.
```

## Build Command

Run inside the Isca container:

```bash
singularity exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  /lscratch/jli30/isca-sandbox \
  bash -lc '
set -e
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=ubuntu_conda
cd "$GFDL_BASE"
mkdir -p logs
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py \
  profile_transforms_top \
  2>&1 | tee logs/T85L25_transforms_top_profile_compile.log
'
```

## T85L25 Prepare Command

```bash
singularity exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  /lscratch/jli30/isca-sandbox \
  bash -lc '
set -e
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=ubuntu_conda
cd "$GFDL_BASE"
python3 scripts/run_T85L25_case.py \
  --executable-name held_suarez_profile_transforms_top.x \
  --exp-name held_suarez_profile_transforms_top_T85L25_30day \
  --backend-label transforms_top \
  --resolution T85 \
  --levels 25 \
  --dt-atmos 300 \
  --days 30 \
  --num-cores 16 \
  --overwrite \
  --prepare-only
'
```

## T85L25 16-Node Run Command

```bash
RUN_DIR=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/experiment/held_suarez_profile_transforms_top_T85L25_30day/run
CONTAINER=/lscratch/jli30/isca-sandbox

srun --mpi=pmix -n 16 --ntasks-per-node=1 singularity exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "$CONTAINER" \
  bash -lc "
set -e
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=ubuntu_conda
source \$GFDL_BASE/src/extra/env/ubuntu_conda
cd $RUN_DIR
./held_suarez_profile_transforms_top.x
" 2>&1 | tee logs/T85L25_transforms_top_profile_16node_30day.log
```

## Check Command

```bash
grep -E "PROFILE_TRANSFORM_TOP|PROFILE_DYNAMICS_DEEP|Integration completed|Total runtime|FATAL|ERROR|MPI_ABORT" \
  logs/T85L25_transforms_top_profile_16node_30day.log
```

## Pass Criteria

The Phase 2 run passes if:

1. The executable builds through `CodeBase.compile()`.
2. The run completes through `2000 Feb 1`.
3. `PROFILE_TRANSFORM_TOP` markers are present.
4. `PROFILE_DYNAMICS_DEEP` markers are present.
5. `PROFILE_TRANSFORM_TOP name=nonoverlap_total` is close to the broad
   `PROFILE_DYNAMICS_REGION name=transforms` result from the previous T85L25
   run.

## Next Analysis Report

After the log is available, create:

```text
docs/T85L25_transforms_top_profile_recommendation.md
```

The report should compute:

- forward vs inverse transform time;
- composite wind-transform cost;
- primitive call counts per timestep;
- non-overlap total vs broad transforms timer;
- which direction or wrapper deserves Phase 3 stage timers.

