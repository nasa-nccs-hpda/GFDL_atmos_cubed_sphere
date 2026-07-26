# FV Advection Resolution/GPU Experiment Plan

Date: 2026-07-24

## Goal

Measure how the Held-Suarez FV advection CUDA hybrid behaves as spatial
resolution increases.

The experiment matrix varies:

- spatial resolution: `T42L25`, `T85L25`, `T170L25`, `T340L25`
- run length: `30`, `60`, `90`, `120` days
- model/configuration:
  - all-Fortran CPU baseline, 16 MPI ranks
  - FV advection CUDA hybrid, 16 MPI ranks sharing 1 GPU
  - FV advection CUDA hybrid, 16 MPI ranks over 4 GPUs
  - FV advection CUDA hybrid, 16 MPI ranks over 16 GPUs

Primary question:

```text
At what resolution, if any, does FV CUDA begin to amortize launch,
communication, and CPU/GPU transfer overhead?
```

## Existing Executables To Check

Before running, check:

```bash
CPU_X=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_isca/build/held_suarez/held_suarez.x
FV_CUDA_X=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_kernels_cuda/held_suarez_fv_kernels_cuda.x

ls -lh "$CPU_X" "$FV_CUDA_X"
```

Optional comparison executable:

```bash
FV_CPU_X=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_kernels/held_suarez_fv_kernels.x
ls -lh "$FV_CPU_X"
```

Do not use transform profiling executables as "transform GPU" runs. Current
transform executables are profiling builds only, not GPU-transform models.

## Build Commands If Executables Are Missing

Run builds from outside the container.

Set common paths:

```bash
export CONTAINER=/lscratch/jli30/isca-sandbox
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
mkdir -p "$GFDL_BASE/logs"
```

### Build FV CUDA Hybrid Executable

```bash
singularity exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "$CONTAINER" \
  bash -lc '
set -e
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=hybrid
cd "$GFDL_BASE"
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py fv_kernels_cuda
' 2>&1 | tee "$GFDL_BASE/logs/matrix_compile_fv_kernels_cuda.log"
```

Expected executable:

```text
$GFDL_WORK/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_kernels_cuda/held_suarez_fv_kernels_cuda.x
```

### Build Optional FV CPU C++ Hybrid Executable

```bash
singularity exec \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "$CONTAINER" \
  bash -lc '
set -e
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=hybrid
cd "$GFDL_BASE"
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py fv_kernels
' 2>&1 | tee "$GFDL_BASE/logs/matrix_compile_fv_kernels_cpu.log"
```

### Build Pure CPU Baseline If Stock `/isca` Executable Is Missing

Preferred baseline is the stock Isca executable:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_isca/build/held_suarez/held_suarez.x
```

If it is missing, rebuild the original Held-Suarez test case inside the Isca
container:

```bash
singularity exec \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "$CONTAINER" \
  bash -lc '
set -e
export GFDL_BASE=/isca
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=ubuntu_conda
cd /isca
python3 exp/test_cases/held_suarez/held_suarez_test_case.py
' 2>&1 | tee "$GFDL_BASE/logs/matrix_compile_or_run_stock_held_suarez.log"
```

This may also launch the original experiment. If only a compile-only stock
baseline is needed, inspect the original Isca test workflow first rather than
modifying production files.

## Resolution And Timestep Plan

Use conservative timesteps first:

| Resolution | Levels | Suggested `dt_atmos` | Notes |
|---|---:|---:|---|
| `T42` | 25 | 600 | Existing baseline scale |
| `T85` | 25 | 300 | Already used successfully |
| `T170` | 25 | 150 | Start with smoke test |
| `T340` | 25 | 75 | Expensive; smoke test required |

If `T340` is unstable at `dt_atmos=75`, test `dt_atmos=60`.

## Experiment Naming

Use:

```text
held_suarez_<config>_<resolution>L25_<days>day
```

Examples:

```text
held_suarez_fortran_16cpu_T85L25_30day
held_suarez_fv_cuda_a_grid_1gpu_T85L25_30day
held_suarez_fv_cuda_a_grid_4gpu_T85L25_30day
held_suarez_fv_cuda_a_grid_16gpu_T85L25_30day
```

Logs:

```text
logs/matrix_<resolution>L25_<config>_<days>day.log
```

Examples:

```text
logs/matrix_T85L25_fortran_16cpu_30day.log
logs/matrix_T85L25_fv_cuda_a_grid_1gpu_30day.log
logs/matrix_T85L25_fv_cuda_a_grid_4gpu_30day.log
logs/matrix_T85L25_fv_cuda_a_grid_16gpu_30day.log
```

Outputs:

```text
$GFDL_DATA/<experiment_name>/run0001/atmos_monthly.nc
```

## Runtime Environment For FV CUDA

Use the latest broad a-grid resident path:

```bash
export FV_KERNELS_CUDA_MODE=resident
export FV_KERNELS_RESIDENT_BOUNDARY=a_grid
export FV_KERNELS_RESIDENT_STATIC_METRICS=1
export FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only
export FV_KERNELS_PROFILE=1
export FV_KERNELS_GPU_MAPPING=local_rank
```

For 16 GPUs with one MPI rank per node:

```bash
export FV_KERNELS_REQUIRE_UNIQUE_GPU=1
```

For 1 GPU or 4 GPUs with multiple ranks sharing a GPU:

```bash
export FV_KERNELS_REQUIRE_UNIQUE_GPU=0
```

Check markers in logs:

```bash
grep "PROFILE_FV_GPU_MAPPING" logs/<log>.log
grep "PROFILE_FV_ADVECTION_CUDA" logs/<log>.log
```

## Slurm Allocation Prescriptions

### CPU Baseline

Use one CPU node with 16 MPI ranks:

```bash
salloc \
  --nodes=1 \
  --ntasks-per-node=16 \
  --cpus-per-task=1 \
  --mem=350G \
  --time=4:00:00 \
  --partition=grace
```

For longer or higher-resolution runs, increase `--time`.

### FV CUDA, 1 GPU

One node, one GPU, 16 MPI ranks sharing the GPU:

```bash
salloc \
  --nodes=1 \
  --gres=gpu:1 \
  --ntasks-per-node=16 \
  --cpus-per-task=1 \
  --mem=350G \
  --time=4:00:00 \
  --partition=grace
```

### FV CUDA, 4 GPUs

Preferred on this system, based on previous availability: four nodes, one GPU
per node, four MPI ranks per node:

```bash
salloc \
  --nodes=4 \
  --gres=gpu:1 \
  --ntasks-per-node=4 \
  --cpus-per-task=1 \
  --mem=350G \
  --time=4:00:00 \
  --partition=grace
```

If Slurm rejects this due to CPU layout, try:

```bash
salloc \
  --nodes=4 \
  --gres=gpu:1 \
  --ntasks-per-node=4 \
  --cpus-per-task=4 \
  --mem=350G \
  --time=4:00:00 \
  --partition=grace
```

Then launch with `srun -n 16 --ntasks-per-node=4`.

### FV CUDA, 16 GPUs

Sixteen nodes, one GPU per node, one MPI rank per GPU:

```bash
salloc \
  --nodes=16 \
  --gres=gpu:1 \
  --ntasks-per-node=1 \
  --cpus-per-task=4 \
  --mem=350G \
  --time=6:00:00 \
  --partition=grace
```

Then launch with `srun -n 16 --ntasks-per-node=1`.

## Container Preflight On Allocated Nodes

Before running model jobs:

```bash
srun -n "$SLURM_NNODES" --ntasks-per-node=1 bash -lc '
hostname
test -d /lscratch/jli30/isca-sandbox && echo SANDBOX_OK || echo SANDBOX_MISSING
nvidia-smi -L || true
'
```

If a node is missing the sandbox, use the existing `build_sandbox.sh` workflow
or build manually on each missing node:

```bash
singularity build --sandbox /lscratch/jli30/isca-sandbox docker://nasanccs/isca-debian:latest
```

## Prepare-Then-Run Pattern

Use `scripts/run_T85L25_case.py` as the base runner even for other resolutions.
Despite the name, it accepts `--resolution`, `--levels`, `--dt-atmos`, and
`--days`.

For external `srun` launches, always use `--prepare-only` first. This writes
`input.nml`, tables, and copies the executable into the run directory.

### Prepare CPU Baseline

Template:

```bash
singularity exec \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "$CONTAINER" \
  bash -lc "
set -e
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=ubuntu_conda
cd \$GFDL_BASE
python3 scripts/run_T85L25_case.py \
  --exp-name held_suarez_fortran_16cpu_${RES}L25_${DAYS}day \
  --executable-name held_suarez.x \
  --backend-label fortran_16cpu \
  --codebase-dir /isca \
  --resolution ${RES} \
  --levels 25 \
  --dt-atmos ${DT} \
  --days ${DAYS} \
  --num-cores 16 \
  --overwrite \
  --prepare-only
"
```

### Prepare FV CUDA Hybrid

Template:

```bash
singularity exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "$CONTAINER" \
  bash -lc "
set -e
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=hybrid
cd \$GFDL_BASE
python3 scripts/run_T85L25_case.py \
  --exp-name held_suarez_fv_cuda_a_grid_${GPU_LABEL}_${RES}L25_${DAYS}day \
  --executable-name held_suarez_fv_kernels_cuda.x \
  --backend-label fv_cuda_a_grid_${GPU_LABEL} \
  --resolution ${RES} \
  --levels 25 \
  --dt-atmos ${DT} \
  --days ${DAYS} \
  --num-cores 16 \
  --overwrite \
  --prepare-only
"
```

## Run Commands

After prepare, set:

```bash
RUN_DIR=$GFDL_WORK/experiment/<experiment_name>/run
LOG=$GFDL_BASE/logs/matrix_<resolution>L25_<config>_<days>day.log
```

### Run CPU Baseline

```bash
srun --mpi=pmix -n 16 singularity exec \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "$CONTAINER" \
  bash -lc "
set -e
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=ubuntu_conda
source /isca/src/extra/env/ubuntu_conda
cd $RUN_DIR
./held_suarez.x
" 2>&1 | tee "$LOG"
```

### Run FV CUDA Hybrid

For 1 GPU:

```bash
export GPU_LABEL=1gpu
export FV_KERNELS_REQUIRE_UNIQUE_GPU=0
srun --mpi=pmix -n 16 --ntasks-per-node=16 singularity exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "$CONTAINER" \
  bash -lc "
set -e
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=hybrid
export FV_KERNELS_CUDA_MODE=resident
export FV_KERNELS_RESIDENT_BOUNDARY=a_grid
export FV_KERNELS_RESIDENT_STATIC_METRICS=1
export FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only
export FV_KERNELS_PROFILE=1
export FV_KERNELS_GPU_MAPPING=local_rank
export FV_KERNELS_REQUIRE_UNIQUE_GPU=0
source \$GFDL_BASE/src/extra/env/hybrid
cd $RUN_DIR
./held_suarez_fv_kernels_cuda.x
" 2>&1 | tee "$LOG"
```

For 4 GPUs:

```bash
export GPU_LABEL=4gpu
export FV_KERNELS_REQUIRE_UNIQUE_GPU=0
srun --mpi=pmix -n 16 --ntasks-per-node=4 singularity exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "$CONTAINER" \
  bash -lc "
set -e
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=hybrid
export FV_KERNELS_CUDA_MODE=resident
export FV_KERNELS_RESIDENT_BOUNDARY=a_grid
export FV_KERNELS_RESIDENT_STATIC_METRICS=1
export FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only
export FV_KERNELS_PROFILE=1
export FV_KERNELS_GPU_MAPPING=local_rank
export FV_KERNELS_REQUIRE_UNIQUE_GPU=0
source \$GFDL_BASE/src/extra/env/hybrid
cd $RUN_DIR
./held_suarez_fv_kernels_cuda.x
" 2>&1 | tee "$LOG"
```

For 16 GPUs:

```bash
export GPU_LABEL=16gpu
export FV_KERNELS_REQUIRE_UNIQUE_GPU=1
srun --mpi=pmix -n 16 --ntasks-per-node=1 singularity exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "$CONTAINER" \
  bash -lc "
set -e
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=hybrid
export FV_KERNELS_CUDA_MODE=resident
export FV_KERNELS_RESIDENT_BOUNDARY=a_grid
export FV_KERNELS_RESIDENT_STATIC_METRICS=1
export FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only
export FV_KERNELS_PROFILE=1
export FV_KERNELS_GPU_MAPPING=local_rank
export FV_KERNELS_REQUIRE_UNIQUE_GPU=1
source \$GFDL_BASE/src/extra/env/hybrid
cd $RUN_DIR
./held_suarez_fv_kernels_cuda.x
" 2>&1 | tee "$LOG"
```

## Recommended Run Ladder

Do not start with the full 64-run matrix.

### Stage 0: Smoke Test Matrix

Run 1-day smoke tests first:

```text
T42L25:  fortran, 1gpu, 4gpu, 16gpu
T85L25:  fortran, 1gpu, 4gpu, 16gpu
T170L25: fortran, 1gpu, 4gpu, 16gpu
T340L25: fortran, 1gpu, 4gpu, 16gpu
```

Pass criteria:

- `Integration completed`
- `Total runtime` marker present
- CUDA runs include `PROFILE_FV_GPU_MAPPING`
- CUDA runs include `PROFILE_FV_ADVECTION_CUDA`
- output NetCDF exists

### Stage 1: 30-Day Resolution/GPU Matrix

Run:

```text
4 resolutions x 4 configurations x 30 days = 16 runs
```

This is the most important stage. It answers whether a full 60/90/120-day
matrix is worth running.

### Stage 2: Duration Scaling

Only after Stage 1 passes:

```text
60 days
90 days
120 days
```

Run in increasing duration order. Stop a resolution/configuration path if
runtime scales poorly, validation fails, or queue cost becomes too high.

## Validation

For each resolution and duration, compare each CUDA output against the matching
all-Fortran baseline:

```text
$GFDL_DATA/held_suarez_fortran_16cpu_${RES}L25_${DAYS}day/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_fv_cuda_a_grid_${GPU_LABEL}_${RES}L25_${DAYS}day/run0001/atmos_monthly.nc
```

Use the existing NetCDF validation script pattern. If reusing
`tests/validate_T85L25_forcing_outputs.py`, pass experiment names and data root,
not raw file paths:

```bash
python3 tests/validate_T85L25_forcing_outputs.py \
  --fortran-exp held_suarez_fortran_16cpu_${RES}L25_${DAYS}day \
  --cpu-exp held_suarez_fv_cuda_a_grid_1gpu_${RES}L25_${DAYS}day \
  --cuda-exp held_suarez_fv_cuda_a_grid_16gpu_${RES}L25_${DAYS}day \
  --run 1 \
  --filename atmos_monthly.nc \
  --data-root /explore/nobackup/people/jli30/SystemTesting/Isca/isca_data \
  --markdown-out tests/reports/matrix_${RES}L25_${DAYS}day_validation.md \
  --json-out tests/reports/matrix_${RES}L25_${DAYS}day_validation.json
```

For a cleaner matrix, create a future validation helper that accepts an
arbitrary list of experiment names. Do not modify validation scripts until the
run plan is accepted.

## Metrics To Extract

From each log:

- completion status
- shell real/user/sys if available
- `Total runtime` tmax/tavg
- `PROFILE_FV_GPU_MAPPING`
- `PROFILE_FV_ADVECTION_CUDA`
- allocation, H2D, kernel, sync, D2H, free, total

Compute:

```text
speedup_vs_fortran = fortran_mpp_tmax / cuda_mpp_tmax
gpu_scaling_4_vs_1 = cuda_1gpu_mpp_tmax / cuda_4gpu_mpp_tmax
gpu_scaling_16_vs_1 = cuda_1gpu_mpp_tmax / cuda_16gpu_mpp_tmax
gpu_scaling_16_vs_4 = cuda_4gpu_mpp_tmax / cuda_16gpu_mpp_tmax
fv_fraction = fv_cuda_total_max / model_mpp_tmax
```

## Summary Table Template

| Resolution | Days | Config | Nodes | MPI Ranks | GPUs | dt | MPP Runtime | FV CUDA Total | H2D | Kernel | D2H | Speedup Vs Fortran | Validation | Log |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| T42L25 | 30 | fortran_16cpu | 1 | 16 | 0 | 600 | | | | | | 1.000 | | |
| T42L25 | 30 | fv_cuda_a_grid_1gpu | 1 | 16 | 1 | 600 | | | | | | | | |
| T42L25 | 30 | fv_cuda_a_grid_4gpu | 4 | 16 | 4 | 600 | | | | | | | | |
| T42L25 | 30 | fv_cuda_a_grid_16gpu | 16 | 16 | 16 | 600 | | | | | | | | |

## Recommended First Batch

First complete:

```text
T42L25 30-day: fortran, 1gpu, 4gpu, 16gpu
T85L25 30-day: fortran, 1gpu, 4gpu, 16gpu
T170L25 30-day: fortran, 1gpu, 4gpu, 16gpu
```

Then decide whether to run:

```text
T340L25 30-day
```

T340 should be preceded by a 1-day smoke test because it is much more expensive
and may expose timestep, memory, or output-volume issues.

## Stop Conditions

Stop a matrix branch after the first:

- compile failure
- MPI/container launch failure
- missing executable
- missing `Total runtime`
- missing CUDA profile markers in CUDA runs
- failed NetCDF validation
- unacceptable queue/runtime cost

Document the exact failed command and log path before continuing with another
branch.
