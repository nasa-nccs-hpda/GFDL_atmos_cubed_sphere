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
$GFDL_WORK/codebase/<source-token>/build/held_suarez_fortran/held_suarez_fortran.x
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

### A. Build all-Fortran baseline

```bash
GFDL_ENV=ubuntu_conda \
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py fortran \
  2>&1 | tee logs/T85L25_build_fortran.log
```

Expected executable:

```text
$GFDL_WORK/codebase/<source-token>/build/held_suarez_fortran/held_suarez_fortran.x
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

The following commands use a small inline runner so that all three variants use
the same T85L25 namelist settings while selecting different prebuilt
executables.

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
  /usr/bin/time -p python3 - "${exp_name}" "${executable_name}" \
    "${SCALING_RES}" "${SCALING_LEVELS}" "${SCALING_DT}" "${SCALING_DAYS}" "${SCALING_CORES}" <<'PY'
import sys
from pathlib import Path

repo_root = Path.cwd()
sys.path.insert(0, str(repo_root / "exp" / "test_cases" / "held_suarez"))

import held_suarez_test_case as original
from isca import DryCodeBase, Experiment, GFDL_BASE

exp_name, executable_name = sys.argv[1], sys.argv[2]
resolution, levels = sys.argv[3], int(sys.argv[4])
dt_atmos, days, num_cores = int(sys.argv[5]), int(sys.argv[6]), int(sys.argv[7])

class RuntimeCodeBase(DryCodeBase):
    pass

RuntimeCodeBase.executable_name = executable_name
cb = RuntimeCodeBase.from_directory(GFDL_BASE)
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
exp.run(1, num_cores=num_cores, use_restart=False, overwrite_data=True)
PY
}
```

### A. Run all-Fortran baseline

```bash
HS_PROFILE=0 HS_FORCE_BACKEND= \
run_t85_case held_suarez_T85L25_fortran held_suarez_fortran.x \
  2>&1 | tee logs/T85L25_fortran_30day.log
```

Expected output:

```text
$GFDL_DATA/held_suarez_T85L25_fortran/run0001/atmos_monthly.nc
```

### B. Run CPU C++ hybrid forcing

Run this before rebuilding the hybrid executable with CUDA support:

```bash
HS_PROFILE=1 HS_FORCE_BACKEND=cpu \
run_t85_case held_suarez_T85L25_hybrid_cpu held_suarez_hybrid.x \
  2>&1 | tee logs/T85L25_hybrid_cpu_30day.log
```

Expected output:

```text
$GFDL_DATA/held_suarez_T85L25_hybrid_cpu/run0001/atmos_monthly.nc
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
run_t85_case held_suarez_T85L25_hybrid_cuda held_suarez_hybrid.x \
  2>&1 | tee logs/T85L25_hybrid_cuda_30day.log
```

Expected output:

```text
$GFDL_DATA/held_suarez_T85L25_hybrid_cuda/run0001/atmos_monthly.nc
logs/T85L25_hybrid_cuda_30day.log
```

## Timing Collection Workflow

For each run, extract:

- shell `real`, `user`, `sys` from `/usr/bin/time -p`;
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

Compare all-Fortran vs CPU hybrid:

```bash
python3 tests/compare_hybrid_outputs.py \
  --baseline-exp held_suarez_T85L25_fortran \
  --candidate-exp held_suarez_T85L25_hybrid_cpu \
  --run 1 \
  --filename atmos_monthly.nc \
  --all-fields \
  --out tests/reports/T85L25_fortran_vs_hybrid_cpu.json \
  2>&1 | tee logs/T85L25_compare_fortran_vs_hybrid_cpu.log
```

Compare all-Fortran vs CUDA hybrid:

```bash
python3 tests/compare_hybrid_outputs.py \
  --baseline-exp held_suarez_T85L25_fortran \
  --candidate-exp held_suarez_T85L25_hybrid_cuda \
  --run 1 \
  --filename atmos_monthly.nc \
  --all-fields \
  --out tests/reports/T85L25_fortran_vs_hybrid_cuda.json \
  2>&1 | tee logs/T85L25_compare_fortran_vs_hybrid_cuda.log
```

Compare CPU hybrid vs CUDA hybrid:

```bash
python3 tests/compare_hybrid_outputs.py \
  --baseline-exp held_suarez_T85L25_hybrid_cpu \
  --candidate-exp held_suarez_T85L25_hybrid_cuda \
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
$GFDL_DATA/held_suarez_T85L25_fortran/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_T85L25_hybrid_cpu/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_T85L25_hybrid_cuda/run0001/atmos_monthly.nc
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
