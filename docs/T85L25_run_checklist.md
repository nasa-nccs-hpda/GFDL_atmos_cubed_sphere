# T85L25 Forcing Performance Run Checklist

Date: 2026-06-17

## Run Configuration

All three production runs use:

```text
resolution = T85
levels = 25
dt_atmos = 300 s
days = 30
MPI ranks = 16
diagnostics = original Held-Suarez production diag table
```

Experiment names:

```text
held_suarez_fortran_T85L25
held_suarez_hybrid_cpu_T85L25
held_suarez_hybrid_cuda_T85L25
```

## Build Verification

All-Fortran executable:

```bash
ls -lh \
  ${GFDL_WORK}/codebase/_isca/build/held_suarez/held_suarez.x \
  2>&1 | tee logs/T85L25_build_fortran.log
```

Expected:

```text
$GFDL_WORK/codebase/_isca/build/held_suarez/held_suarez.x
```

CPU hybrid executable:

```bash
USE_CUDA_HS_FORCE=0 ./run_compile_hybrid.sh
cp logs/hybrid_compile_latest.log logs/T85L25_build_hybrid_cpu.log
```

CUDA hybrid executable:

```bash
USE_CUDA_HS_FORCE=1 ./run_compile_hybrid.sh
cp logs/hybrid_compile_latest.log logs/T85L25_build_hybrid_cuda.log
```

Important:

```text
CPU and CUDA hybrid builds both produce held_suarez_hybrid.x.
```

For individual runs, either CPU-only or CUDA-enabled `held_suarez_hybrid.x` can
run the CPU backend with `HS_FORCE_BACKEND=cpu`.

For `scripts/run_T85L25_all.sh`, use a CUDA-enabled `held_suarez_hybrid.x`
built with `USE_CUDA_HS_FORCE=1`.  The same executable then runs:

```text
HS_FORCE_BACKEND=cpu
HS_FORCE_BACKEND=cuda
```

## Launch Commands

By default, scripts preserve existing output directories.  To overwrite
existing `run0001` output explicitly:

```bash
export T85_OVERWRITE=1
```

All-Fortran:

```bash
scripts/run_T85L25_fortran_30day.sh
```

CPU C++ hybrid:

```bash
scripts/run_T85L25_cpu_hybrid_30day.sh
```

CUDA hybrid:

```bash
scripts/run_T85L25_cuda_hybrid_30day.sh
```

Sequential wrapper:

```bash
scripts/run_T85L25_all.sh
```

Recommended full sequence for the all wrapper:

```bash
ls -lh ${GFDL_WORK}/codebase/_isca/build/held_suarez/held_suarez.x
USE_CUDA_HS_FORCE=1 ./run_compile_hybrid.sh
scripts/run_T85L25_all.sh
```

Alternative manual sequence if you want a CPU-only hybrid executable for the
CPU run:

```bash
ls -lh ${GFDL_WORK}/codebase/_isca/build/held_suarez/held_suarez.x
USE_CUDA_HS_FORCE=0 ./run_compile_hybrid.sh
scripts/run_T85L25_fortran_30day.sh
scripts/run_T85L25_cpu_hybrid_30day.sh
USE_CUDA_HS_FORCE=1 ./run_compile_hybrid.sh
scripts/run_T85L25_cuda_hybrid_30day.sh
```

## Expected Log Locations

```text
logs/T85L25_fortran_30day.log
logs/T85L25_hybrid_cpu_30day.log
logs/T85L25_hybrid_cuda_30day.log
logs/T85L25_all_30day.log
```

## Expected Output Locations

```text
$GFDL_DATA/held_suarez_fortran_T85L25/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_hybrid_cpu_T85L25/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_hybrid_cuda_T85L25/run0001/atmos_monthly.nc
```

## Verify Completion

Check run completion markers:

```bash
rg -n "Integration completed|Run 1 complete|FailedRunError|FATAL|ERROR|HS CUDA backend error" \
  logs/T85L25_fortran_30day.log \
  logs/T85L25_hybrid_cpu_30day.log \
  logs/T85L25_hybrid_cuda_30day.log
```

Check outputs exist:

```bash
ls -lh \
  ${GFDL_DATA}/held_suarez_fortran_T85L25/run0001/atmos_monthly.nc \
  ${GFDL_DATA}/held_suarez_hybrid_cpu_T85L25/run0001/atmos_monthly.nc \
  ${GFDL_DATA}/held_suarez_hybrid_cuda_T85L25/run0001/atmos_monthly.nc
```

Check T85L25 namelist settings:

```bash
grep -n "lon_max\\|lat_max\\|num_fourier\\|num_spherical\\|num_levels\\|dt_atmos" \
  ${GFDL_DATA}/held_suarez_fortran_T85L25/run0001/input.nml \
  ${GFDL_DATA}/held_suarez_hybrid_cpu_T85L25/run0001/input.nml \
  ${GFDL_DATA}/held_suarez_hybrid_cuda_T85L25/run0001/input.nml
```

Expected values:

```text
lon_max = 256
lat_max = 128
num_fourier = 85
num_spherical = 86
num_levels = 25
dt_atmos = 300
```

Check hybrid forcing timing:

```bash
rg -n "HS_PROFILE|HS_FORCE_BACKEND|Backend|Executable|Resolution|Levels|dt_atmos" \
  logs/T85L25_hybrid_cpu_30day.log \
  logs/T85L25_hybrid_cuda_30day.log
```

CUDA-specific check:

```bash
rg -n "nvidia-smi -L output|GPU |HS CUDA backend error|cudaGetDeviceCount" \
  logs/T85L25_hybrid_cuda_30day.log
```

## After Runs

Fill:

```text
docs/T85L25_forcing_performance_results_template.md
```

Then run NetCDF comparisons:

```bash
python3 tests/compare_hybrid_outputs.py \
  --baseline-exp held_suarez_fortran_T85L25 \
  --candidate-exp held_suarez_hybrid_cpu_T85L25 \
  --run 1 \
  --filename atmos_monthly.nc \
  --all-fields \
  --out tests/reports/T85L25_fortran_vs_hybrid_cpu.json

python3 tests/compare_hybrid_outputs.py \
  --baseline-exp held_suarez_fortran_T85L25 \
  --candidate-exp held_suarez_hybrid_cuda_T85L25 \
  --run 1 \
  --filename atmos_monthly.nc \
  --all-fields \
  --out tests/reports/T85L25_fortran_vs_hybrid_cuda.json

python3 tests/compare_hybrid_outputs.py \
  --baseline-exp held_suarez_hybrid_cpu_T85L25 \
  --candidate-exp held_suarez_hybrid_cuda_T85L25 \
  --run 1 \
  --filename atmos_monthly.nc \
  --all-fields \
  --out tests/reports/T85L25_hybrid_cpu_vs_hybrid_cuda.json
```
