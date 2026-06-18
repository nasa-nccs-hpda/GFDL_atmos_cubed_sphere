# T85L25 Held-Suarez Forcing Performance Results Template

Date: 2026-06-17

Fill this after running:

```text
docs/T85L25_forcing_performance_experiment_plan.md
```

## Run Configuration

| Setting | Value |
|---|---|
| Resolution | T85 |
| Vertical levels | 25 |
| lon_max x lat_max | 256 x 128 |
| 3D state cells | 819,200 |
| dt_atmos | 300 s |
| Simulation length | 30 days |
| Timesteps | 8,640 |
| MPI ranks | 16 |
| Diagnostics | production Held-Suarez |
| Container | TBD |
| Git commit | TBD |
| CUDA device | TBD |
| CUDA runtime/compiler | TBD |

## Build Summary

| Variant | Build Command | Executable | Build Status | Build Log |
|---|---|---|---|---|
| all-Fortran | verify stock `/isca` build | `held_suarez.x` | TBD | `logs/T85L25_build_fortran.log` |
| CPU C++ hybrid | `USE_CUDA_HS_FORCE=0 ./run_compile_hybrid.sh` | `held_suarez_hybrid.x` | TBD | `logs/T85L25_build_hybrid_cpu.log` |
| CUDA hybrid | `USE_CUDA_HS_FORCE=1 ./run_compile_hybrid.sh` | `held_suarez_hybrid.x` | TBD | `logs/T85L25_build_hybrid_cuda.log` |

## Timing Summary

| Metric | all-Fortran | CPU C++ hybrid | CUDA hybrid |
|---|---:|---:|---:|
| Shell real time (s) | TBD | TBD | TBD |
| Shell user time (s) | TBD | TBD | TBD |
| Shell sys time (s) | TBD | TBD | TBD |
| Model MPP tmin (s) | TBD | TBD | TBD |
| Model MPP tmax (s) | TBD | TBD | TBD |
| Model MPP tavg (s) | TBD | TBD | TBD |
| Model MPP tstd (s) | TBD | TBD | TBD |
| HS forcing wrapper time (s) | not instrumented | TBD | TBD |
| HS forcing C++/CUDA backend time (s) | not instrumented | TBD | TBD |
| HS forcing calls | not instrumented | TBD | TBD |
| Avg forcing time per call (s) | not instrumented | TBD | TBD |
| Forcing fraction of MPP tmax | not instrumented | TBD | TBD |

## Speedup Summary

Use shell real time first, then repeat with model MPP tmax if needed.

| Speedup Metric | Formula | Value |
|---|---|---:|
| CPU hybrid speedup vs Fortran | `fortran_real / cpu_hybrid_real` | TBD |
| CUDA hybrid speedup vs Fortran | `fortran_real / cuda_hybrid_real` | TBD |
| CUDA speedup vs CPU hybrid | `cpu_hybrid_real / cuda_hybrid_real` | TBD |
| CPU hybrid MPP speedup vs Fortran | `fortran_mpp_tmax / cpu_hybrid_mpp_tmax` | TBD |
| CUDA hybrid MPP speedup vs Fortran | `fortran_mpp_tmax / cuda_hybrid_mpp_tmax` | TBD |
| CUDA MPP speedup vs CPU hybrid | `cpu_hybrid_mpp_tmax / cuda_hybrid_mpp_tmax` | TBD |

## Numerical Agreement

| Comparison | Report | Dimension Match | Overall Pass | Max Abs Error | RMSE | Notes |
|---|---|---|---|---:|---:|---|
| Fortran vs CPU hybrid | `tests/reports/T85L25_fortran_vs_hybrid_cpu.json` | TBD | TBD | TBD | TBD | TBD |
| Fortran vs CUDA hybrid | `tests/reports/T85L25_fortran_vs_hybrid_cuda.json` | TBD | TBD | TBD | TBD | TBD |
| CPU hybrid vs CUDA hybrid | `tests/reports/T85L25_hybrid_cpu_vs_hybrid_cuda.json` | TBD | TBD | TBD | TBD | TBD |

Fields to inspect first:

```text
ps
bk
pk
ucomp
vcomp
temp
vor
div
```

The comparison script can also compare all numeric fields with `--all-fields`.

## Expected Output Files

| Variant | Output File | Exists | Size | Notes |
|---|---|---|---:|---|
| all-Fortran | `$GFDL_DATA/held_suarez_fortran_T85L25/run0001/atmos_monthly.nc` | TBD | TBD | TBD |
| CPU C++ hybrid | `$GFDL_DATA/held_suarez_hybrid_cpu_T85L25/run0001/atmos_monthly.nc` | TBD | TBD | TBD |
| CUDA hybrid | `$GFDL_DATA/held_suarez_hybrid_cuda_T85L25/run0001/atmos_monthly.nc` | TBD | TBD | TBD |

## HS_PROFILE Extraction

CPU hybrid log:

```text
logs/T85L25_hybrid_cpu_30day.log
```

CUDA hybrid log:

```text
logs/T85L25_hybrid_cuda_30day.log
```

Record the following blocks:

```text
HS_PROFILE Fortran wrapper profile summary
...
HS_PROFILE end Fortran wrapper profile summary

HS_PROFILE C++ forcing profile summary
...
HS_PROFILE end C++ forcing profile summary
```

## Interpretation

### Total Runtime

TBD.

### Forcing Runtime Fraction

TBD.

### CPU C++ Replacement Value

TBD.

### CUDA Prototype Value

TBD.

### Numerical Agreement

TBD.

## Final Recommendation

Choose one after filling the timing and comparison tables:

```text
A. CUDA forcing shows meaningful T85L25 end-to-end speedup; continue optimizing.
B. CUDA forcing is useful as architecture validation only; target larger modules.
C. CPU C++ hybrid is neutral or slower; keep as validation pathway only.
D. Numerical disagreement requires debugging before performance conclusions.
```

Current expectation before measurement:

```text
CUDA forcing is likely architecture validation rather than a major speedup path,
but T85L25 should measure whether the forcing fraction grows enough to change
that conclusion.
```
