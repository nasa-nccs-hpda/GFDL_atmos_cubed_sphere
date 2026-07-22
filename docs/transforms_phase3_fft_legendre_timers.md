# Spectral Transforms Phase 3 FFT And Legendre Timers

Date: 2026-07-22

## Goal

Split the T85L25 transform cost into FFT time versus Legendre time and identify
which component dominates.

Phase 2 confirmed:

```text
Broad dynamics transforms timer:        142.453 s
Dynamics-deep transform call-site sum:  143.151 s
Transform module non-overlap total:     180.321 s
```

Phase 3 adds sub-timers inside the transform stack while preserving the Phase 2
top-level timers.

## Files Changed

Overlay files:

```text
src/extra/local_overrides/transforms_top/transforms.F90
src/extra/local_overrides/transforms_top/grid_fourier.F90
src/extra/local_overrides/transforms_top/spherical_fourier.F90
```

Build machinery:

```text
hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py
```

Production transform files remain untouched.

## Build Target

New target:

```text
profile_transforms_stage
```

Expected executable:

```text
held_suarez_profile_transforms_stage.x
```

Compile flags:

```text
-DPROFILE_DYNAMICS_DEEP
-DPROFILE_TRANSFORMS_TOP
-DPROFILE_TRANSFORMS_STAGE
```

## New Markers

Phase 3 prints `PROFILE_TRANSFORM_STAGE` markers.

FFT wrapper markers from `grid_fourier_mod`:

```text
PROFILE_TRANSFORM_STAGE name=fft_forward_total ...
PROFILE_TRANSFORM_STAGE name=fft_forward_pack ...
PROFILE_TRANSFORM_STAGE name=fft_forward_kernel ...
PROFILE_TRANSFORM_STAGE name=fft_inverse_total ...
PROFILE_TRANSFORM_STAGE name=fft_inverse_kernel ...
PROFILE_TRANSFORM_STAGE name=fft_inverse_unpack ...
```

Legendre markers from `spherical_fourier_mod`:

```text
PROFILE_TRANSFORM_STAGE name=legendre_spherical_to_fourier_total ...
PROFILE_TRANSFORM_STAGE name=legendre_spherical_to_fourier_loop ...
PROFILE_TRANSFORM_STAGE name=legendre_fourier_to_spherical_total ...
PROFILE_TRANSFORM_STAGE name=legendre_fourier_to_spherical_loop ...
```

The run should also print:

```text
PROFILE_TRANSFORM_TOP ...
PROFILE_DYNAMICS_DEEP ...
```

## Interpretation

Direction mapping:

| Model Direction | FFT Stage | Legendre Stage |
|---|---|---|
| Grid to spectral | `fft_forward_*` | `legendre_fourier_to_spherical_*` |
| Spectral to grid | `legendre_spherical_to_fourier_*` | `fft_inverse_*` |

Recommended aggregate calculations:

```text
fft_total = fft_forward_total + fft_inverse_total
legendre_total = legendre_fourier_to_spherical_total + legendre_spherical_to_fourier_total

fft_kernel_total = fft_forward_kernel + fft_inverse_kernel
legendre_loop_total = legendre_fourier_to_spherical_loop + legendre_spherical_to_fourier_loop

forward_transform_subtotal = fft_forward_total + legendre_fourier_to_spherical_total
inverse_transform_subtotal = legendre_spherical_to_fourier_total + fft_inverse_total
```

Important: these sub-timers are module-wide. Compare them to
`PROFILE_TRANSFORM_TOP nonoverlap_total` first, then compare the relevant
dynamics call-site subset to the broad `PROFILE_DYNAMICS_REGION transforms`
timer.

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
  profile_transforms_stage \
  2>&1 | tee logs/T85L25_transforms_stage_profile_compile.log
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
  --executable-name held_suarez_profile_transforms_stage.x \
  --exp-name held_suarez_profile_transforms_stage_T85L25_30day \
  --backend-label transforms_stage \
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
RUN_DIR=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/experiment/held_suarez_profile_transforms_stage_T85L25_30day/run
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
./held_suarez_profile_transforms_stage.x
" 2>&1 | tee logs/T85L25_transforms_stage_profile_16node_30day.log
```

## Check Command

```bash
grep -E "PROFILE_TRANSFORM_STAGE|PROFILE_TRANSFORM_TOP|PROFILE_DYNAMICS_DEEP|Integration completed|Total runtime|FATAL|ERROR|MPI_ABORT" \
  logs/T85L25_transforms_stage_profile_16node_30day.log
```

## Pass Criteria

The Phase 3 run passes if:

1. `held_suarez_profile_transforms_stage.x` builds.
2. The run completes through `2000 Feb 1`.
3. `PROFILE_TRANSFORM_STAGE` markers are present.
4. FFT and Legendre call counts are plausible relative to Phase 2 primitive
   transform counts.
5. The report can rank:
   - FFT total time;
   - Legendre total time;
   - FFT kernel time;
   - Legendre loop time;
   - wrapper packing/unpacking overhead.

## Next Report

After the log is ready, create:

```text
docs/T85L25_transforms_stage_profile_recommendation.md
```

The report should answer:

```text
Does FFT or Legendre dominate the T85L25 transform bottleneck?
```

