# T85L25 Held-Suarez Forcing Performance Experiment Plan

Date: 2026-06-17

## Objective

Run a controlled T85L25 30-day performance comparison for the three existing
Held-Suarez forcing implementations:

1. Original all-Fortran forcing.
2. CPU C++ hybrid forcing.
3. CUDA hybrid forcing.

The comparison uses identical:

- horizontal resolution: `T85`;
- vertical levels: `25`;
- timestep: `300 s`;
- diagnostics: original production Held-Suarez diagnostic table;
- MPI rank count: `16`;
- simulation length: `30 days`.

This experiment does not translate any new module and does not modify
production source.

## Existing CUDA Forcing Implementation

CUDA source:

```text
translated/held_suarez/cuda/forcing_module/hs_forcing_cuda.h
translated/held_suarez/cuda/forcing_module/hs_forcing_cuda.cu
translated/held_suarez/cuda/forcing_module/hs_forcing_cuda_kernels.cuh
translated/held_suarez/cuda/forcing_module/validate_hs_forcing_cuda.cpp
```

CPU C++ forcing source and C ABI:

```text
translated/held_suarez/cpp/forcing_module/include/held_suarez_c_api.h
translated/held_suarez/cpp/forcing_module/include/held_suarez_config.hpp
translated/held_suarez/cpp/forcing_module/include/held_suarez_forcing.hpp
translated/held_suarez/cpp/forcing_module/src/held_suarez_c_api.cpp
```

Fortran ISO_C_BINDING wrapper:

```text
translated/held_suarez/cpp/forcing_module/fortran/hs_forcing_c_interface.F90
```

Isca overlay source:

```text
src/extra/local_overrides/hs_forcing/hs_forcing.F90
```

Build integration:

```text
translated/held_suarez/cpp/forcing_module/Makefile
hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py
run_compile_hybrid.sh
src/extra/env/hybrid
src/extra/python/isca/templates/mkmf.template.hybrid
src/extra/python/isca/templates/mkmf.template.hybrid_cuda
```

CUDA run wrappers:

```text
hybrid_experiments/held_suarez_cpp_force/run_hybrid_1day_cuda.sh
hybrid_experiments/held_suarez_cpp_force/run_hybrid_30day_cuda.sh
```

Validation report:

```text
tests/reports/hs_forcing_cuda_poc_report.md
```

Current validation status from the repository:

- CPU C++ forcing module is validated against standalone Fortran baseline.
- Fortran -> C API -> C++ forcing path is validated.
- Hybrid `held_suarez_hybrid.x` builds and has completed 1-day and 30-day CPU
  hybrid runs.
- CUDA backend exists and is selected at runtime with `HS_FORCE_BACKEND=cuda`.
- CUDA backend preserves the public Fortran and C interfaces.
- CUDA-enabled build uses `USE_CUDA_HS_FORCE=1`, `nvcc`, and
  `mkmf.template.hybrid_cuda`.
- CUDA backend is a proof-of-architecture path and is not expected, a priori,
  to deliver large full-model speedup because CPU/GPU transfers occur every
  forcing call and the rest of the model remains CPU-resident.

## Runtime Configuration

CPU hybrid default:

```bash
export HS_FORCE_BACKEND=cpu
export HS_PROFILE=1
```

CUDA hybrid:

```bash
export HS_FORCE_BACKEND=cuda
export HS_PROFILE=1
```

CUDA build:

```bash
export USE_CUDA_HS_FORCE=1
```

The code intentionally does not silently fall back to CPU if
`HS_FORCE_BACKEND=cuda` is requested but CUDA support is unavailable.

## Executable Paths

All executables are generated under the Isca work tree:

```text
$GFDL_WORK/codebase/_isca/build/held_suarez/held_suarez.x
$GFDL_WORK/codebase/<source-token>/build/held_suarez_hybrid/held_suarez_hybrid.x
```

Important:

```text
CPU and CUDA hybrid builds both produce held_suarez_hybrid.x.
```

Therefore either:

1. run the CPU hybrid case before rebuilding the CUDA hybrid executable; or
2. copy/archive the CPU executable before the CUDA build.

This plan uses option 1 for simplicity.

## Build Commands

Run inside the Isca Apptainer container or use the existing container wrapper
where shown.

## Smoke Test First

Before any 30-day T85L25 performance run, first verify that the CUDA-enabled
hybrid executable builds and that a short T85L25 CUDA run starts, writes output,
and prints `HS_PROFILE` timing.

Smoke-test scripts:

```text
run_T85L25_cuda_smoke.sh
scripts/run_T85L25_cuda_smoke.sh
```

Use the root wrapper from the H100/GPU host allocation:

```bash
./run_T85L25_cuda_smoke.sh
```

The root wrapper enters the Isca Apptainer container with `--nv`, sets the
Isca runtime environment, then runs the container-side script.  This is the
recommended command from the repository root.

If you are already inside the Isca container on a GPU-visible node, run:

```bash
scripts/run_T85L25_cuda_smoke.sh
```

Equivalent manual container entry:

```bash
apptainer exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  /lscratch/jli30/isca-sandbox \
  bash
```

Then inside the container:

```bash
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=hybrid
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd ${GFDL_BASE}
scripts/run_T85L25_cuda_smoke.sh
```

The script does all of the following:

```text
USE_CUDA_HS_FORCE=1
GFDL_ENV=hybrid
GFDL_MKMF_TEMPLATE=hybrid_cuda
HS_FORCE_BACKEND=cuda
HS_PROFILE=1
resolution = T85
num_levels = 25
dt_atmos = 300
days = 1
num_cores = 16
```

Log:

```text
logs/T85L25_cuda_smoke.log
```

Expected output directory:

```text
$GFDL_DATA/held_suarez_T85L25_cuda_smoke/
```

Expected success markers:

```text
Generated: .../held_suarez_hybrid.x
Resolution = T85
Levels = 25
dt_atmos = 300
HS_FORCE_BACKEND = cuda
HS_PROFILE Fortran wrapper profile summary
HS_PROFILE C++ forcing profile summary
Run 1 complete
```

If this smoke test fails, do not start the 30-day comparison.  Diagnose the
first build, link, CUDA runtime, or model-startup error from
`logs/T85L25_cuda_smoke.log`.

Preflight failure means the script is not running in the correct execution
environment.  Required checks include:

```text
mpifort available
nc-config available
nvcc available
python can import isca and jinja2
nvidia-smi -L reports at least one line beginning with `GPU `
```

If the log shows missing `mpifort`, missing `nvcc`, missing `nc-config`,
`ModuleNotFoundError: No module named 'jinja2'`, or `No devices were found`,
then rerun from an allocated H100/GPU node through the root wrapper:

```bash
./run_T85L25_cuda_smoke.sh
```

If the build succeeds but the run aborts with:

```text
HS CUDA backend error: cudaGetDeviceCount failed: no CUDA-capable device is detected
```

then the executable is CUDA-enabled, but the container cannot see a GPU.  This
is not a model-code or link failure.  Re-run on a GPU-visible allocation and
confirm the smoke log contains a line like:

```text
nvidia-smi -L output:
GPU 0: ...
```

### A. Build all-Fortran baseline

```bash
ls -lh ${GFDL_WORK}/codebase/_isca/build/held_suarez/held_suarez.x \
  2>&1 | tee logs/T85L25_build_fortran.log
```

Expected executable:

```text
$GFDL_WORK/codebase/_isca/build/held_suarez/held_suarez.x
```

### B. Build CPU C++ hybrid forcing

```bash
USE_CUDA_HS_FORCE=0 ./run_compile_hybrid.sh
cp logs/hybrid_compile_latest.log logs/T85L25_build_hybrid_cpu.log
```

Expected executable:

```text
$GFDL_WORK/codebase/<source-token>/build/held_suarez_hybrid/held_suarez_hybrid.x
```

### C. Build CUDA hybrid forcing

Run after the CPU hybrid run is complete:

```bash
USE_CUDA_HS_FORCE=1 ./run_compile_hybrid.sh
cp logs/hybrid_compile_latest.log logs/T85L25_build_hybrid_cuda.log
```

Expected executable:

```text
$GFDL_WORK/codebase/<source-token>/build/held_suarez_hybrid/held_suarez_hybrid.x
```

The CUDA build should show:

```text
USE_CUDA_HS_FORCE= 1
GFDL_MKMF_TEMPLATE= hybrid_cuda
NVCC= /path/to/nvcc
```

## Run Commands

Preferred production run scripts:

```bash
scripts/run_T85L25_fortran_30day.sh
scripts/run_T85L25_cpu_hybrid_30day.sh
scripts/run_T85L25_cuda_hybrid_30day.sh
```

Sequential wrapper:

```bash
scripts/run_T85L25_all.sh
```

These scripts use `scripts/run_T85L25_case.py`, preserve existing output by
default, and only overwrite `run0001` when `T85_OVERWRITE=1` is exported.

The inline runner below is retained as a reference for the underlying Isca
experiment mechanics. Prefer the checked-in scripts above for production runs.

Common settings:

```bash
export SCALING_RES=T85
export SCALING_LEVELS=25
export SCALING_DT=300
export SCALING_DAYS=30
export SCALING_CORES=16
export SCALING_PRODUCTION_DIAG=1
mkdir -p logs tests/reports
```

Define the reusable runner once:

```bash
run_t85_case() {
  local exp_name="$1"
  local executable_name="$2"
  local codebase_dir="${3:-${GFDL_BASE}}"
  time python3 - "${exp_name}" "${executable_name}" "${codebase_dir}" \
    "${SCALING_RES}" "${SCALING_LEVELS}" "${SCALING_DT}" "${SCALING_DAYS}" "${SCALING_CORES}" <<'PY'
import sys
import os
from pathlib import Path

repo_root = Path.cwd()
sys.path.insert(0, str(repo_root / "exp" / "test_cases" / "held_suarez"))

import held_suarez_test_case as original
from isca import DryCodeBase, Experiment, GFDL_BASE

exp_name, executable_name, codebase_dir = sys.argv[1], sys.argv[2], sys.argv[3]
resolution, levels = sys.argv[4], int(sys.argv[5])
dt_atmos, days, num_cores = int(sys.argv[6]), int(sys.argv[7]), int(sys.argv[8])

class RuntimeCodeBase(DryCodeBase):
    pass

RuntimeCodeBase.executable_name = executable_name
cb = RuntimeCodeBase.from_directory(codebase_dir)
exp = Experiment(exp_name, codebase=cb)
exp.namelist = original.namelist.copy()
exp.diag_table = original.diag.copy()
exp.set_resolution(resolution, levels)
exp.update_namelist({"main_nml": {"days": days, "dt_atmos": dt_atmos}})

print("Experiment =", exp.name)
print("Executable =", cb.executable_fullpath)
print("Resolution =", resolution)
print("Levels =", levels)
print("Days =", days)
print("dt_atmos =", dt_atmos)
print("num_cores =", num_cores)
print("Data dir =", exp.datadir)
overwrite = bool(int(os.environ.get("T85_OVERWRITE", "0")))
exp.run(1, num_cores=num_cores, use_restart=False, overwrite_data=overwrite)
PY
}
```

### A. Run all-Fortran baseline

```bash
HS_PROFILE=0 HS_FORCE_BACKEND= \
run_t85_case held_suarez_fortran_T85L25 held_suarez.x /isca \
  2>&1 | tee logs/T85L25_fortran_30day.log
```

Expected output:

```text
$GFDL_DATA/held_suarez_fortran_T85L25/run0001/atmos_monthly.nc
```

### B. Run CPU C++ hybrid forcing

Run this before rebuilding the hybrid executable with CUDA support:

```bash
HS_PROFILE=1 HS_FORCE_BACKEND=cpu \
run_t85_case held_suarez_hybrid_cpu_T85L25 held_suarez_hybrid.x \
  2>&1 | tee logs/T85L25_hybrid_cpu_30day.log
```

Expected output:

```text
$GFDL_DATA/held_suarez_hybrid_cpu_T85L25/run0001/atmos_monthly.nc
logs/T85L25_hybrid_cpu_30day.log
```

Expected timing markers:

```text
HS_PROFILE Fortran wrapper profile summary
HS_PROFILE C++ forcing profile summary
```

### C. Run CUDA hybrid forcing

First rebuild the hybrid executable with `USE_CUDA_HS_FORCE=1`, then run:

```bash
HS_PROFILE=1 HS_FORCE_BACKEND=cuda \
run_t85_case held_suarez_hybrid_cuda_T85L25 held_suarez_hybrid.x \
  2>&1 | tee logs/T85L25_hybrid_cuda_30day.log
```

Expected output:

```text
$GFDL_DATA/held_suarez_hybrid_cuda_T85L25/run0001/atmos_monthly.nc
logs/T85L25_hybrid_cuda_30day.log
```

## Timing Collection Workflow

For each run, extract:

- shell `real`, `user`, `sys` from the shell `time` output;
- model MPP runtime from the Isca/FMS runtime summary;
- forcing runtime from `HS_PROFILE` blocks for CPU and CUDA hybrid runs.

Forcing-specific runtime in the all-Fortran baseline is not currently available
without additional instrumentation of the original Fortran forcing source.
Total model runtime speedups remain computable.

Metrics:

```text
total_wall_clock_time = shell real
model_mpp_runtime = model runtime tmax or tavg
forcing_module_runtime = HS_PROFILE total seconds
cpu_hybrid_speedup_vs_fortran = fortran_wall / cpu_hybrid_wall
cuda_hybrid_speedup_vs_fortran = fortran_wall / cuda_hybrid_wall
cuda_speedup_vs_cpu_hybrid = cpu_hybrid_wall / cuda_hybrid_wall
```

Also compute forcing fraction for hybrid runs:

```text
forcing_fraction = forcing_module_runtime / model_mpp_runtime
```

## Numerical Comparison Workflow

Preferred forcing validation report:

```bash
export GFDL_DATA=${GFDL_DATA:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data}
mkdir -p logs tests/reports

python3 tests/validate_T85L25_forcing_outputs.py \
  --fortran-exp held_suarez_fortran_T85L25 \
  --cpu-exp held_suarez_hybrid_cpu_T85L25 \
  --cuda-exp held_suarez_hybrid_cuda_T85L25 \
  --filename atmos_monthly.nc \
  --fields temperature ucomp vcomp ps \
  --markdown-out tests/reports/T85L25_forcing_validation_report.md \
  --json-out tests/reports/T85L25_forcing_validation_report.json \
  2>&1 | tee logs/T85L25_forcing_validation.log
```

This command compares `atmos_monthly.nc` for:

```text
Fortran vs CPU hybrid
Fortran vs CUDA hybrid
CPU hybrid vs CUDA hybrid
```

It computes max absolute error, RMSE, max pointwise relative error, relative
L2 error, and a variable-by-variable summary for `temp`, `ucomp`, `vcomp`,
`ps`, plus any forcing-related diagnostics present in the NetCDF files.

The pairwise JSON-only commands below are retained as a lower-level fallback.

Compare all-Fortran vs CPU hybrid:

```bash
python3 tests/compare_hybrid_outputs.py \
  --baseline-exp held_suarez_fortran_T85L25 \
  --candidate-exp held_suarez_hybrid_cpu_T85L25 \
  --run 1 \
  --filename atmos_monthly.nc \
  --all-fields \
  --out tests/reports/T85L25_fortran_vs_hybrid_cpu.json \
  2>&1 | tee logs/T85L25_compare_fortran_vs_hybrid_cpu.log
```

Compare all-Fortran vs CUDA hybrid:

```bash
python3 tests/compare_hybrid_outputs.py \
  --baseline-exp held_suarez_fortran_T85L25 \
  --candidate-exp held_suarez_hybrid_cuda_T85L25 \
  --run 1 \
  --filename atmos_monthly.nc \
  --all-fields \
  --out tests/reports/T85L25_fortran_vs_hybrid_cuda.json \
  2>&1 | tee logs/T85L25_compare_fortran_vs_hybrid_cuda.log
```

Compare CPU hybrid vs CUDA hybrid:

```bash
python3 tests/compare_hybrid_outputs.py \
  --baseline-exp held_suarez_hybrid_cpu_T85L25 \
  --candidate-exp held_suarez_hybrid_cuda_T85L25 \
  --run 1 \
  --filename atmos_monthly.nc \
  --all-fields \
  --out tests/reports/T85L25_hybrid_cpu_vs_hybrid_cuda.json \
  2>&1 | tee logs/T85L25_compare_hybrid_cpu_vs_hybrid_cuda.log
```

## Expected Log Locations

```text
logs/T85L25_build_fortran.log
logs/T85L25_build_hybrid_cpu.log
logs/T85L25_build_hybrid_cuda.log
logs/T85L25_fortran_30day.log
logs/T85L25_hybrid_cpu_30day.log
logs/T85L25_hybrid_cuda_30day.log
logs/T85L25_compare_fortran_vs_hybrid_cpu.log
logs/T85L25_compare_fortran_vs_hybrid_cuda.log
logs/T85L25_compare_hybrid_cpu_vs_hybrid_cuda.log
```

## Expected Output Locations

```text
$GFDL_DATA/held_suarez_fortran_T85L25/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_hybrid_cpu_T85L25/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_hybrid_cuda_T85L25/run0001/atmos_monthly.nc
```

Comparison reports:

```text
tests/reports/T85L25_fortran_vs_hybrid_cpu.json
tests/reports/T85L25_fortran_vs_hybrid_cuda.json
tests/reports/T85L25_hybrid_cpu_vs_hybrid_cuda.json
```

## Success Criteria

- All three runs complete 30 simulated days.
- CPU hybrid and CUDA hybrid logs contain `HS_PROFILE` summaries.
- CUDA run confirms `HS_FORCE_BACKEND=cuda`.
- NetCDF dimensions match across all three runs.
- Numeric comparison reports are generated.
- Final performance table can be filled in
  `docs/T85L25_forcing_performance_results_template.md`.

## Known Limitations

- CPU and CUDA hybrid builds share the same executable name and build
  directory.  Run CPU hybrid before rebuilding CUDA hybrid, or archive the CPU
  executable.
- Forcing-specific runtime for original all-Fortran forcing is not currently
  available without additional non-invasive instrumentation.
- CUDA forcing still transfers data every forcing call; performance is expected
  to mainly validate architecture rather than produce large model speedup.
