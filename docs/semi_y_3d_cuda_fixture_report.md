# semi_y_3d CUDA Fixture Report

Date: 2026-06-18

## Objective

Add a minimal CUDA fixture implementation for:

```text
src/atmos_spectral/model/fv_advection.F90
fv_advection_mod::semi_y_3d
```

Production Fortran source was not modified.

## Files Added

```text
translated/held_suarez/cuda/fv_advection/semi_y_3d/semi_y_3d_cuda.h
translated/held_suarez/cuda/fv_advection/semi_y_3d/semi_y_3d_cuda.cu
translated/held_suarez/cuda/fv_advection/semi_y_3d/validate_semi_y_3d_cuda.cpp
```

## Files Updated

```text
translated/held_suarez/cpp/fv_advection/semi_y_3d/Makefile
translated/held_suarez/cpp/fv_advection/semi_y_3d/README.md
```

## Implementation

The CUDA backend uses one flat 1D kernel over `nx * (je-js+1) * nz`
cells.  It preserves the same branch condition and operation order as the
Fortran and CPU C++ implementation:

```text
if va >= 0:
  dq = va * dt * (qx(j-1) - qx(j)) / dyy(j)
else:
  dq = va * dt * (qx(j) - qx(j+1)) / dyy(j+1)
```

The first CUDA version intentionally uses per-call local device allocation and
copies:

```text
cudaMalloc
cudaMemcpy host -> device
kernel launch
cudaDeviceSynchronize
cudaMemcpy device -> host
cudaFree
```

This is an architecture-validation fixture, not a performance-optimized
implementation.

## Validation Command

Run inside a CUDA-enabled container:

```bash
cd translated/held_suarez/cpp/fv_advection/semi_y_3d
make cuda_check
```

Use `make cuda_check`, not `make USE_CUDA_SEMI_Y_3D=1 cuda_check_impl`.
The public target cleans stale host/container objects before rebuilding the
CUDA fixture archive.

Expected generated files:

```text
translated/held_suarez/cpp/fv_advection/semi_y_3d/outputs/output_dq_cuda.bin
tests/reports/semi_y_3d_cuda_compare_report.json
```

The validator compares:

```text
Fortran baseline dq vs CUDA dq
CPU C++ dq vs CUDA dq
```

with:

```text
atol = 1e-13
rtol = 1e-13
```

## Local Verification

The CPU fixture regression still passes in the current shell:

```text
make check
overall_pass: true
max_abs_error: 0.0
rmse: 0.0
```

CUDA validation was not run in this shell because `nvcc` is not available
outside the CUDA container.

## Next Step

Run the CUDA fixture validation inside the CUDA-enabled Isca/container
environment.  If it passes, proceed to the Fortran wrapper/C API integration
design for `semi_y_3d`.
