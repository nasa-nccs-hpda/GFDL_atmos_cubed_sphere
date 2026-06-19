# FV Advection Kernel Bundle Plan

## Objective

Convert the next finite-volume advection kernels as one dependency-aware bundle:

- `semi_x_3d`
- `slope_x`
- `slope_sphere`
- `vanleer_x_3d`
- `vanleer_sphere_3d`

The bundle also includes required helper routines:

- `find_cell_x`
- `integer_flux_x`

`semi_y_3d` remains the validated reference workflow and is not modified by this bundle.

## Why Bundle These Routines

The requested routines are not independent leaf kernels. In `src/atmos_spectral/model/fv_advection.F90`:

- `semi_x_3d` calls `find_cell_x`.
- `vanleer_x_3d` calls `integer_flux_x`, `slope_x`, and `find_cell_x`.
- `vanleer_sphere_3d` calls `slope_sphere`.

Bundling the helpers with the top-level kernels avoids duplicated helper implementations and keeps CPU/CUDA validation aligned with the Fortran behavior.

## Implementation Boundary

Keep the production `fv_advection_mod` and model integration in Fortran. Modernize only local array kernels behind a C++/CUDA library and, later, a Fortran `iso_c_binding` wrapper.

This preserves:

- original production source tree
- domain/halo handling
- module initialization and metric setup
- native Isca `CodeBase.compile()` workflow

## Phase 1: Baseline Fixture

Created under:

`tests/fortran_baseline/fv_advection_kernels/`

The fixture uses a test-only copy of the kernel bodies with minimal module state:

- `nx`, `ny`, `js`, `je`, `nz`
- `dx`, `dy`
- `c`, `cc`
- `dy_plus`, `dy_minus`
- `monotone`

It writes deterministic raw binary inputs and Fortran reference outputs.

## Phase 2: CPU C++ Translation

Created under:

`translated/held_suarez/cpp/fv_advection/kernels/`

The C++ fixture reads the Fortran baseline inputs, runs the translated kernels, and compares against Fortran outputs.

## Phase 3: CUDA Fixture

Next step after CPU validation:

`translated/held_suarez/cuda/fv_advection/kernels/`

The first CUDA version should use explicit `cudaMalloc`, `cudaMemcpy`, and `cudaFree` per call. This is an architecture-validation path, not a final performance implementation.

## Phase 4: Native Overlay

After standalone CPU and CUDA validation, create a Fortran overlay that replaces the private kernel bodies with calls through the C API while preserving the rest of `fv_advection_mod`.

## Pass Criteria

Standalone CPU C++ validation:

- max absolute error: `0` or near machine precision
- RMSE: `0` or near machine precision
- no mismatches above tolerance

Standalone CUDA validation:

- same tolerances unless operation order changes

Model validation:

- 1-day smoke test succeeds
- 30-day NetCDF comparison matches all-Fortran baseline for selected prognostic fields

## Current Status

Phase 1 and Phase 2 scaffolding are prepared. The Fortran baseline fixture must be run inside the Isca container because this shell does not expose `mpifort` or `gfortran`.
