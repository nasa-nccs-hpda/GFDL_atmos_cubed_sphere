# T85L25 Dynamics Region Profile Plan

## Purpose

The T85L25 16-node / 16-GPU FV advection CUDA run showed that the FV CUDA
resident `a_grid` region is only about 0.58% of total runtime:

```text
Total MPP runtime:        319.243 s
FV CUDA resident max:       1.862 s
```

The next step is to profile broad dynamics regions at T85L25 using the existing
non-invasive spectral dynamics overlay.

## Instrumentation

Overlay source:

```text
src/extra/local_overrides/spectral_dynamics/spectral_dynamics.F90
```

Compile flag:

```text
-DPROFILE_DYNAMICS_REGIONS
```

Build target:

```text
profile_dynamics_regions
```

Executable:

```text
held_suarez_profile_dynamics_regions.x
```

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

## Build Command

Run from the repository root:

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
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none

cd "$GFDL_BASE"
mkdir -p logs

python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py \
  profile_dynamics_regions \
  2>&1 | tee logs/T85L25_dynamics_region_profile_compile.log
'
```

## Prepare T85L25 Run Directory

Use `scripts/run_T85L25_case.py --prepare-only` so Isca writes `input.nml`,
tables, executable, and `run.sh` without launching its internal `mpirun`.

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
  --executable-name held_suarez_profile_dynamics_regions.x \
  --exp-name held_suarez_profile_dynamics_regions_T85L25_30day \
  --backend-label dynamics_regions \
  --resolution T85 \
  --levels 25 \
  --dt-atmos 300 \
  --days 30 \
  --num-cores 16 \
  --overwrite \
  --prepare-only
'
```

Verify:

```bash
RUN_DIR=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/experiment/held_suarez_profile_dynamics_regions_T85L25_30day/run

ls -l "$RUN_DIR" | head
grep -nE "days|dt_atmos|num_levels|spectral_trunc|fourier_lat_max|num_fourier" \
  "$RUN_DIR/input.nml"
```

## 16-Node Run Command

Use the same external Slurm launch pattern that worked for the T85 FV CUDA run.

```bash
RUN_DIR=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/experiment/held_suarez_profile_dynamics_regions_T85L25_30day/run
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

echo HOST=\$(hostname) SLURM_LOCALID=\${SLURM_LOCALID:-unset} SLURM_PROCID=\${SLURM_PROCID:-unset}

./held_suarez_profile_dynamics_regions.x
" 2>&1 | tee logs/T85L25_dynamics_region_profile_16node_30day.log
```

## Check Command

```bash
grep -E "PROFILE_DYNAMICS_REGION|Integration completed|Total runtime|FATAL|ERROR|MPI_ABORT" \
  logs/T85L25_dynamics_region_profile_16node_30day.log
```

Expected completion:

```text
Integration completed through 2000 Feb 1 0:0:0
Total runtime ...
PROFILE_DYNAMICS_REGION name=...
```

## Analysis Targets

After the run, compute for each region:

```text
region_fraction = time_max / total_mpp_runtime_tmax
```

Classification:

| Runtime Fraction | Meaning |
|---:|---|
| >20% | Excellent target |
| 10-20% | Strong target |
| 5-10% | Reasonable target |
| 2-5% | Weak but possible |
| <2% | Do not target for performance |

## Expected Outcome

The T85 FV CUDA result suggests the next hotspot is not FV advection. This run
should identify whether the T85L25 cost is dominated by:

- transform-heavy spectral dynamics;
- tracer/correction/diagnostic region;
- advection outside the translated FV boundary;
- pressure/geopotential;
- communication overhead not captured by local CUDA timing.
