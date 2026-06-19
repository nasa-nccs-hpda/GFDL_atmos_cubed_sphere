# semi_y_3d Native Overlay Integration Report

Date: 2026-06-18

## Objective

Prepare the first non-invasive native Isca integration for:

```text
src/atmos_spectral/model/fv_advection.F90
fv_advection_mod::semi_y_3d
```

The original production Fortran source was not modified.

## Overlay Mechanism

The original path_names entry:

```text
atmos_spectral/model/fv_advection.F90
```

is replaced with:

```text
../translated/held_suarez/cpp/fv_advection/semi_y_3d/fortran/semi_y_3d_c_interface.F90
extra/local_overrides/fv_advection/fv_advection.F90
```

The overlay source is a copy of production `fv_advection.F90` with only the
private `semi_y_3d` body guarded:

```text
USE_CPP_SEMI_Y_3D  -> semi_y_3d_cpp_wrapper
USE_CUDA_SEMI_Y_3D -> semi_y_3d_cuda_wrapper
no flag            -> original Fortran body
```

Halo exchange, domain decomposition, `a_grid_horiz_advection_3d`, and all
other finite-volume kernels remain in Fortran.

## Files Added

```text
src/extra/local_overrides/fv_advection/fv_advection.F90
src/extra/python/isca/templates/mkmf.template.fv_hybrid
src/extra/python/isca/templates/mkmf.template.fv_hybrid_cuda
run_compile_fv_semi_y.sh
```

## Files Updated

```text
hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py
```

## Executables

CPU C++ local-kernel overlay:

```text
held_suarez_fv_semi_y_3d.x
```

CUDA local-kernel overlay:

```text
held_suarez_fv_semi_y_3d_cuda.x
```

## Build Commands

CPU C++ overlay:

```bash
./run_compile_fv_semi_y.sh
```

CUDA overlay:

```bash
USE_CUDA_SEMI_Y_3D=1 ./run_compile_fv_semi_y.sh
```

Expected logs:

```text
logs/fv_semi_y_compile_latest.log
logs/fv_semi_y_cuda_compile_latest.log
```

Expected executable locations:

```text
$GFDL_WORK/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_semi_y_3d/held_suarez_fv_semi_y_3d.x
$GFDL_WORK/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_semi_y_3d_cuda/held_suarez_fv_semi_y_3d_cuda.x
```

## Verification

Completed before native overlay build:

```text
Fortran baseline fixture: PASS
CPU C++ fixture: PASS, exact
CUDA fixture: PASS, exact
Fortran -> C -> C++ fixture: PASS, exact
Fortran -> C -> CUDA fixture: PASS, exact
```

Local checks completed:

```text
compile_native_overlay.py syntax check passed
fv_advection overlay preprocessor paths inspected
CPU libsemi_y_3d.a rebuild passed in local shell
```

Native Isca overlay builds completed inside the container:

```text
held_suarez_fv_semi_y_3d.x
held_suarez_fv_semi_y_3d_cuda.x
```

1-day model smoke tests completed:

```text
held_suarez_fv_semi_y_3d_smoke
held_suarez_fv_semi_y_3d_cuda_smoke
```

Duration-matched 1-day model validation against the stock all-Fortran
baseline completed:

```text
report: tests/reports/semi_y_3d_1day_model_validation_report.md
json:   tests/reports/semi_y_3d_1day_model_validation_report.json
```

Summary:

```text
Fortran vs CPU overlay:  dimension_match=true, max_abs_error=0, rmse=0
Fortran vs CUDA overlay: dimension_match=true, max_abs_error=0, rmse=0
CPU overlay vs CUDA:     dimension_match=true, max_abs_error=0, rmse=0
Compared fields: ps, temp, ucomp, vcomp
```

Duration-matched 30-day CPU and CUDA overlay simulations completed and were
compared against the stock 30-day all-Fortran baseline.

Commands:

```bash
scripts/run_fv_semi_y_cpu_30day.sh
scripts/run_fv_semi_y_cuda_30day.sh
scripts/validate_fv_semi_y_30day.sh
```

Use:

```bash
FV_SEMI_Y_OVERWRITE=1 scripts/run_fv_semi_y_cpu_30day.sh
FV_SEMI_Y_OVERWRITE=1 scripts/run_fv_semi_y_cuda_30day.sh
```

only if intentionally replacing existing 30-day output directories.

Expected outputs:

```text
$GFDL_DATA/held_suarez_fv_semi_y_3d_30day/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_fv_semi_y_3d_cuda_30day/run0001/atmos_monthly.nc
tests/reports/semi_y_3d_30day_model_validation_report.md
tests/reports/semi_y_3d_30day_model_validation_report.json
```

30-day validation result:

```text
report: tests/reports/semi_y_3d_30day_model_validation_report.md
json:   tests/reports/semi_y_3d_30day_model_validation_report.json
logs:
  logs/fv_semi_y_cpu_30day.log
  logs/fv_semi_y_cuda_30day.log
  logs/fv_semi_y_30day_model_validation.log
```

Summary:

```text
Fortran vs CPU overlay:  dimension_match=true, max_abs_error=0, rmse=0
Fortran vs CUDA overlay: dimension_match=true, max_abs_error=0, rmse=0
CPU overlay vs CUDA:     dimension_match=true, max_abs_error=0, rmse=0
Compared fields: ps, temp, ucomp, vcomp
```

## Next Milestone

Choose the next finite-volume local kernel to modernize. Candidate next kernels
from `docs/fv_advection_kernel_modernization_plan.md` include:

```text
semi_x_3d
slope_sphere
slope_x
vanleer_sphere_3d
vanleer_x_3d
```

Create its standalone Fortran baseline fixture before starting C++ translation.
