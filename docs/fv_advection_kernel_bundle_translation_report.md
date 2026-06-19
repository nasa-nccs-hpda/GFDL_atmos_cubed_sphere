# FV Advection Kernel Bundle Translation Report

## Scope

Started bundled CPU C++ translation for:

- `semi_x_3d`
- `slope_x`
- `slope_sphere`
- `vanleer_x_3d`
- `vanleer_sphere_3d`

Included required helpers:

- `find_cell_x`
- `integer_flux_x`

This bundle is intentionally separate from the completed `semi_y_3d` path so that the existing validated overlay remains untouched.

## Files Added

Baseline fixture:

- `tests/fortran_baseline/fv_advection_kernels/README.md`
- `tests/fortran_baseline/fv_advection_kernels/Makefile`
- `tests/fortran_baseline/fv_advection_kernels/test_fv_advection_kernels.F90`
- `tests/fortran_baseline/fv_advection_kernels/inputs/.gitkeep`
- `tests/fortran_baseline/fv_advection_kernels/outputs/.gitkeep`

CPU C++ translation:

- `translated/held_suarez/cpp/fv_advection/kernels/README.md`
- `translated/held_suarez/cpp/fv_advection/kernels/Makefile`
- `translated/held_suarez/cpp/fv_advection/kernels/include/fv_advection_kernels.hpp`
- `translated/held_suarez/cpp/fv_advection/kernels/src/fv_advection_kernels.cpp`
- `translated/held_suarez/cpp/fv_advection/kernels/tests/run_fv_advection_kernels_fixture.cpp`
- `translated/held_suarez/cpp/fv_advection/kernels/compare_outputs.py`

CUDA fixture:

- `translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.h`
- `translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu`
- `translated/held_suarez/cuda/fv_advection/kernels/validate_fv_advection_kernels_cuda.cpp`

Plan:

- `docs/fv_advection_kernel_bundle_plan.md`

## Build Status

Local C++ compile check succeeded:

```sh
make -C translated/held_suarez/cpp/fv_advection/kernels all
```

The Fortran baseline fixture has not been run in this shell because no local `mpifort` or `gfortran` is available.

Important correction:

During native-overlay preparation, `vanleer_sphere_3d` was rechecked against the actual production body in `src/atmos_spectral/model/fv_advection.F90`. The first standalone fixture used an older/different metric form. The fixture and CPU/CUDA implementations have now been corrected to match production:

- production `flux = vc*cc*(...)`
- production update `dq_dt -= (flux(j+1)-flux(j))/(dy*c)`
- `dy(js-1:je+1)` is now passed through the C/CUDA ABI as an array

The validation ladder was regenerated after this correction and now passes with zero error.

Current CPU C++ validation status after the `vanleer_sphere_3d` production-form correction:

```text
status: PASS
max_abs_error: 0.0 for all compared outputs
mismatch_count: 0 for all compared outputs
```

CUDA fixture implementation has been added. It is built and validated inside the CUDA-capable container because `nvcc` is unavailable outside the container.

Current standalone CUDA validation status after the `vanleer_sphere_3d` production-form correction:

```text
overall_pass: true
max_abs_error: 0.0 for all compared outputs
mismatches_above_tolerance: 0 for all compared outputs
```

Fortran C-wrapper fixture files have been added and updated for the production `dy(:)` ABI:

- `translated/held_suarez/cpp/fv_advection/kernels/fortran/fv_advection_kernels_c_interface.F90`
- `translated/held_suarez/cpp/fv_advection/kernels/fortran/run_on_baseline.F90`
- `translated/held_suarez/cpp/fv_advection/kernels/fortran/Makefile`

Current Fortran C-wrapper validation status:

```text
CPU wrapper status: PASS
CUDA wrapper status: PASS
max_abs_error: 0.0 for all compared outputs
mismatch_count: 0 for all compared outputs
```

Native overlay files added:

- `src/extra/local_overrides/fv_advection_kernels/fv_advection.F90`
- `src/extra/python/isca/templates/mkmf.template.fv_kernels_hybrid`
- `src/extra/python/isca/templates/mkmf.template.fv_kernels_hybrid_cuda`
- `run_compile_fv_kernels.sh`

Native build targets added to `compile_native_overlay.py`:

- `fv_kernels`
- `fv_kernels_cuda`

Expected executables:

- `held_suarez_fv_kernels.x`
- `held_suarez_fv_kernels_cuda.x`

## Next Commands

Inside the Isca container:

```sh
cd /explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere

cd tests/fortran_baseline/fv_advection_kernels
make FC=mpifort clean run

cd ../../../translated/held_suarez/cpp/fv_advection/kernels
make check
```

Expected report:

`tests/reports/fv_advection_kernels_cpp_compare_report.json`

Then run CUDA validation inside the CUDA-capable container:

```sh
cd /explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/translated/held_suarez/cpp/fv_advection/kernels
make USE_CUDA_FV_ADVECTION_KERNELS=1 cuda_check
```

Expected report:

`tests/reports/fv_advection_kernels_cuda_compare_report.json`

Then run the Fortran C-wrapper validation:

```sh
cd /explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/translated/held_suarez/cpp/fv_advection/kernels/fortran
make FC=mpifort check 2>&1 | tee ../../../../../../logs/fv_advection_kernels_fortran_c_check.log
```

Expected report:

`tests/reports/fv_advection_kernels_fortran_c_compare_report.json`

CUDA C-wrapper validation:

```sh
cd /explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/translated/held_suarez/cpp/fv_advection/kernels/fortran
make FC=mpifort BACKEND=cuda check 2>&1 | tee ../../../../../../logs/fv_advection_kernels_fortran_cuda_c_check.log
```

Expected report:

`tests/reports/fv_advection_kernels_fortran_cuda_c_compare_report.json`

## Expected Outcome

The C++ translation should match the Fortran fixture to exact or near-exact double precision. If the first comparison fails, the likely debugging targets are:

- Fortran lower-bound to C++ zero-based index mapping
- `int` versus `floor` behavior for negative Courant numbers
- periodic x wrap logic in `find_cell_x` and `integer_flux_x`
- y-index offsets in `slope_sphere` and `vanleer_sphere_3d`

## Next Milestone

After Fortran C-wrapper validation passes:

1. Build CPU and CUDA model executables.
2. Run 1-day smoke tests.
3. Run 30-day NetCDF validation against all-Fortran baseline.

Native build commands inside the Isca/CUDA environment:

```sh
./run_compile_fv_kernels.sh
USE_CUDA_FV_ADVECTION_KERNELS=1 ./run_compile_fv_kernels.sh
```

Expected latest logs:

- `logs/fv_kernels_compile_latest.log`
- `logs/fv_kernels_cuda_compile_latest.log`

## Native Build Results

Both native Isca overlay executables were generated successfully.

CPU C++ bundle executable:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_kernels/held_suarez_fv_kernels.x
```

CUDA bundle executable:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_kernels_cuda/held_suarez_fv_kernels_cuda.x
```

Build logs:

```text
logs/fv_kernels_compile_latest.log
logs/fv_kernels_cuda_compile_latest.log
```

Both logs end with `Compilation complete` and `Generated:` for the expected executable. Warnings in the build logs are existing Isca/FMS compiler warnings and not new link or compile failures for the FV kernel bundle.

## Next Step

Run 1-day smoke tests for:

- `held_suarez_fv_kernels.x`
- `held_suarez_fv_kernels_cuda.x`

Then compare against the existing all-Fortran 1-day baseline before running 30-day validation.

## 1-Day Smoke Results

The 1-day smoke runs completed for both native overlay executables:

- CPU C++ bundle: `held_suarez_fv_kernels.x`
- CUDA bundle: `held_suarez_fv_kernels_cuda.x`

Smoke log:

```text
logs/fv_kernels_1day_smoke.log
```

The CUDA run completed through `2000 Jan 2 00:00:00`, wrote `atmos_monthly.nc`,
and archived restarts. CPU and CUDA smoke outputs are bitwise identical in the
1-day monthly comparison.

The all-Fortran-vs-hybrid 1-day comparison using `atmos_monthly.nc` is not
meaningful because the 1-day monthly diagnostic file contains NetCDF fill values
for fields whose output interval exceeds the run length. The validation report
therefore shows fill-value-sized differences versus all-Fortran, while
`CPU hybrid vs CUDA hybrid` is exact.

Validation outputs:

```text
logs/fv_kernels_1day_model_validation.log
tests/reports/fv_advection_kernels_1day_model_validation_report.md
tests/reports/fv_advection_kernels_1day_model_validation_report.json
```

Use 30-day monthly outputs for the next all-Fortran-vs-hybrid numerical
comparison.

## Profiling Added

Runtime profiling has been added at the FV kernel-bundle C/CUDA ABI boundary.
It is disabled by default and enabled with:

```sh
export FV_KERNELS_PROFILE=1
```

Markers printed at process exit:

```text
PROFILE_FV_ADVECTION_KERNEL backend=<cpu|cuda> rank=<rank> name=<kernel> calls=<n> time=<seconds> avg=<seconds>
```

Kernels currently timed:

- `semi_x_3d`
- `slope_x`
- `integer_flux_x`
- `vanleer_x_3d`
- `slope_sphere`
- `vanleer_sphere_3d`

CPU timings include wrapper and C++ implementation time. CUDA timings include
wrapper, allocation, host/device copies, kernel launch, synchronization, and
copy-back time.

Rebuild the native executables before the 30-day profiled runs:

```sh
USE_CUDA_FV_ADVECTION_KERNELS=0 ./run_compile_fv_kernels.sh
USE_CUDA_FV_ADVECTION_KERNELS=1 ./run_compile_fv_kernels.sh
```

Then run:

```sh
FV_KERNELS_OVERWRITE=1 scripts/run_fv_kernels_cpu_30day.sh
FV_KERNELS_OVERWRITE=1 scripts/run_fv_kernels_cuda_30day.sh
```

The profiling plan is documented in:

```text
docs/fv_advection_kernel_bundle_profile_plan.md
```
