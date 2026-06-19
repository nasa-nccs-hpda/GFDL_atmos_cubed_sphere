# semi_y_3d C++ Translation

This directory contains the first C++ translation of the local finite-volume
advection kernel:

```text
src/atmos_spectral/model/fv_advection.F90
fv_advection_mod::semi_y_3d
```

Production Fortran source is not modified.  The implementation reads the
standalone Fortran baseline fixture from:

```text
tests/fortran_baseline/semi_y_3d/
```

## Build And Run

```bash
cd translated/held_suarez/cpp/fv_advection/semi_y_3d
make run
make compare
```

Or run the full local check:

```bash
make check
```

## CUDA Fixture Validation

The optional CUDA fixture implementation lives in:

```text
translated/held_suarez/cuda/fv_advection/semi_y_3d/
```

Run it from a CUDA-enabled container or shell:

```bash
cd translated/held_suarez/cpp/fv_advection/semi_y_3d
make cuda_check
```

This builds the CPU library with the CUDA object, runs the same baseline
fixture, writes:

```text
outputs/output_dq_cuda.bin
```

and writes:

```text
tests/reports/semi_y_3d_cuda_compare_report.json
```

## Outputs

Candidate output:

```text
outputs/output_dq_cpp.bin
```

Comparison report:

```text
tests/reports/semi_y_3d_cpp_compare_report.json
```

## Status

The CPU C++ translation has exact agreement with the Fortran baseline fixture.
The CUDA fixture backend has been added as an optional validation target:

```text
Fortran baseline -> C++ implementation -> CUDA implementation -> comparison
```

Fortran wrapper and hybrid overlay integration are intentionally left for later
phases after the CUDA fixture comparison passes inside the CUDA container.

## Fortran C-Wrapper Fixture Validation

The standalone `iso_c_binding` wrapper lives in:

```text
fortran/semi_y_3d_c_interface.F90
fortran/run_on_baseline.F90
```

CPU wrapper validation:

```bash
cd translated/held_suarez/cpp/fv_advection/semi_y_3d/fortran
make FC=mpifort check
```

CUDA wrapper validation:

```bash
cd translated/held_suarez/cpp/fv_advection/semi_y_3d/fortran
make FC=mpifort BACKEND=cuda check
```

Expected reports:

```text
tests/reports/semi_y_3d_fortran_c_compare_report.json
tests/reports/semi_y_3d_fortran_cuda_c_compare_report.json
```
