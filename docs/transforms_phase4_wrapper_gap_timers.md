# Spectral Transforms Phase 4 Wrapper-Gap Timers

Date: 2026-07-22

## Goal

Instrument the transform wrapper overhead not explained by Phase 3 FFT and
Legendre timers.

Phase 3 result:

```text
Transform module non-overlap total: 181.807 s
FFT total:                           14.925 s
Legendre total:                      60.103 s
Unexplained wrapper gap:            106.779 s
```

Phase 4 adds `PROFILE_TRANSFORM_WRAPPER` timers in `transforms.F90`.

## Files Changed

Overlay:

```text
src/extra/local_overrides/transforms_top/transforms.F90
```

Build target:

```text
hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py
```

Production source remains untouched.

## Build Target

New target:

```text
profile_transforms_wrapper
```

Expected executable:

```text
held_suarez_profile_transforms_wrapper.x
```

Compile flags:

```text
-DPROFILE_DYNAMICS_DEEP
-DPROFILE_TRANSFORMS_TOP
-DPROFILE_TRANSFORMS_STAGE
-DPROFILE_TRANSFORMS_WRAPPER
```

This target keeps Phase 2 top-level and Phase 3 FFT/Legendre markers enabled
so the wrapper accounting can be compared in one log.

## New Markers

Phase 4 prints:

```text
PROFILE_TRANSFORM_WRAPPER name=<stage> calls_max=... time_max=... avg_max=...
```

Wrapper stages:

```text
s2g_spectral_y_sum
s2g_reverse_transpose
s2g_fourier_truncation
s2g_grid_extract
g2s_grid_copy
g2s_x_update
g2s_fourier_truncation
g2s_transpose
g2s_spectral_truncation
vor_div_u_copy
vor_div_u_divide_by_cos
vor_div_v_copy
vor_div_v_divide_by_cos
vor_div_compute
vor_div_truncation
uv_compute_ucos_vcos
uv_u_divide_by_cos
uv_v_divide_by_cos
transpose_pack
transpose_sync_self
transpose_transmit
transpose_final_sync
reverse_transpose_transmit
reverse_transpose_unpack
reverse_transpose_final_sync
```

Interpretation:

- `g2s_*` stages occur in `trans_grid_to_spherical_3d`.
- `s2g_*` stages occur in `trans_spherical_to_grid_3d`.
- `transpose_*` stages occur inside `transpose_fourier`.
- `reverse_transpose_*` stages occur inside `reverse_transpose_fourier`.
- `vor_div_*` and `uv_*` stages split the composite wind transform helpers.

Some timers are nested. For example:

```text
g2s_transpose includes transpose_pack + transpose_sync_self +
transpose_transmit + transpose_final_sync.
```

Use nested timers to classify the source of the wrapper cost; do not blindly
sum parent and child timers together.

## Build Command

Run from outside the container:

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
  profile_transforms_wrapper \
  2>&1 | tee logs/T85L25_transforms_wrapper_profile_compile.log
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
  --executable-name held_suarez_profile_transforms_wrapper.x \
  --exp-name held_suarez_profile_transforms_wrapper_T85L25_30day \
  --backend-label transforms_wrapper \
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
RUN_DIR=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/experiment/held_suarez_profile_transforms_wrapper_T85L25_30day/run
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
./held_suarez_profile_transforms_wrapper.x
" 2>&1 | tee logs/T85L25_transforms_wrapper_profile_16node_30day.log
```

## Check Command

```bash
grep -E "PROFILE_TRANSFORM_WRAPPER|PROFILE_TRANSFORM_STAGE|PROFILE_TRANSFORM_TOP|PROFILE_DYNAMICS_DEEP|Integration completed|Total runtime|FATAL|ERROR|MPI_ABORT" \
  logs/T85L25_transforms_wrapper_profile_16node_30day.log
```

## Analysis Plan

After the log is available, update:

```text
docs/T85L25_transforms_top_profile_recommendation.md
```

Compute:

- parent `g2s_transpose` and child transpose stage totals;
- parent `s2g_reverse_transpose` and child reverse-transpose stage totals;
- `mpp_update_domains` time through `g2s_x_update`;
- `mpp_sum` time through `s2g_spectral_y_sum`;
- truncation time;
- wind helper math time;
- array copy/extraction time;
- remaining unexplained gap after FFT, Legendre, and wrapper timers.

## Expected Outcome

This profile should determine whether the `106.779 s` wrapper gap is mainly:

1. communication and synchronization;
2. local pack/unpack/transposition;
3. domain update and spectral reduction;
4. spectral helper math and truncation;
5. or broad transform orchestration overhead not yet captured.

