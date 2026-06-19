# semi_y_3d Fortran/C Integration Report

Date: 2026-06-18

## Objective

Add a standalone Fortran `iso_c_binding` validation path for the translated
`semi_y_3d` kernel:

```text
Fortran fixture driver -> C ABI -> C++ semi_y_3d
Fortran fixture driver -> C ABI -> CUDA semi_y_3d
```

Production Fortran source was not modified.

## Files Added

```text
translated/held_suarez/cpp/fv_advection/semi_y_3d/fortran/semi_y_3d_c_interface.F90
translated/held_suarez/cpp/fv_advection/semi_y_3d/fortran/run_on_baseline.F90
translated/held_suarez/cpp/fv_advection/semi_y_3d/fortran/Makefile
```

## Files Updated

```text
translated/held_suarez/cpp/fv_advection/semi_y_3d/compare_outputs.py
translated/held_suarez/cpp/fv_advection/semi_y_3d/README.md
```

## Wrapper Design

The wrapper module declares the stable C symbols:

```text
fv_semi_y_3d_c
fv_semi_y_3d_cuda_c
```

and exposes Fortran wrappers:

```text
semi_y_3d_cpp_wrapper
semi_y_3d_cuda_wrapper
```

The CUDA wrapper is guarded by:

```text
-DUSE_CUDA_SEMI_Y_3D
```

so a CPU-only wrapper build does not require CUDA symbols or `libcudart`.

## Validation Commands

Run inside the Isca/CUDA container, where `mpifort`, `g++`, and optionally
`nvcc` are available.

CPU C-wrapper validation:

```bash
cd /explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/translated/held_suarez/cpp/fv_advection/semi_y_3d/fortran
make FC=mpifort check 2>&1 | tee ../../../../../../logs/semi_y_3d_fortran_c_check.log
```

CUDA C-wrapper validation:

```bash
cd /explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/translated/held_suarez/cpp/fv_advection/semi_y_3d/fortran
make FC=mpifort BACKEND=cuda check 2>&1 | tee ../../../../../../logs/semi_y_3d_fortran_cuda_c_check.log
```

Expected reports:

```text
tests/reports/semi_y_3d_fortran_c_compare_report.json
tests/reports/semi_y_3d_fortran_cuda_c_compare_report.json
```

## Local Verification

Checks completed before container wrapper validation:

```text
CPU/CUDA preprocessed Fortran source inspected successfully.
CPU C++ fixture regression still passes with exact agreement.
```

## Container Validation Results

Both Fortran wrapper paths have been validated inside the container.

CPU C-wrapper:

```text
log:    logs/semi_y_3d_fortran_c_check.log
report: tests/reports/semi_y_3d_fortran_c_compare_report.json
pass:   true
count:  120
max_abs_error: 0.0
max_rel_error: 0.0
rmse: 0.0
mismatches_above_tolerance: 0
```

CUDA C-wrapper:

```text
log:    logs/semi_y_3d_fortran_cuda_c_check.log
report: tests/reports/semi_y_3d_fortran_cuda_c_compare_report.json
pass:   true
count:  120
max_abs_error: 0.0
max_rel_error: 0.0
rmse: 0.0
mismatches_above_tolerance: 0
```

## Next Step

Proceed to the non-invasive `fv_advection.F90` overlay design that replaces
only the local `semi_y_3d` body with a wrapper call while leaving halo exchange
and domain logic in Fortran.
