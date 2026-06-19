# semi_y_3d C++ Translation Report

Date: 2026-06-18

## Objective

Start the C++ translation workflow for:

```text
src/atmos_spectral/model/fv_advection.F90
fv_advection_mod::semi_y_3d
```

Production Fortran source was not modified.

## Files Added

```text
translated/held_suarez/cpp/fv_advection/semi_y_3d/README.md
translated/held_suarez/cpp/fv_advection/semi_y_3d/Makefile
translated/held_suarez/cpp/fv_advection/semi_y_3d/include/semi_y_3d.hpp
translated/held_suarez/cpp/fv_advection/semi_y_3d/src/semi_y_3d.cpp
translated/held_suarez/cpp/fv_advection/semi_y_3d/tests/run_semi_y_3d_fixture.cpp
translated/held_suarez/cpp/fv_advection/semi_y_3d/compare_outputs.py
```

## Implementation

The C++ kernel preserves the Fortran branch and operation order:

```text
if va >= 0:
  dq = va * dt * (qx(j-1) - qx(j)) / dyy(j)
else:
  dq = va * dt * (qx(j) - qx(j+1)) / dyy(j+1)
```

Array indexing is Fortran-contiguous with `i` as the fastest dimension.
The standalone fixture assumes the same bounds as the baseline harness:

```text
va, dq: nx x (js:je) x nz
qx:     nx x (js-2:je+2) x nz
dyy:    js:je+1
```

The C++ package also provides the eventual stable C symbol:

```c
fv_semi_y_3d_c(...)
```

No Fortran wrapper or hybrid overlay has been added yet.

## Commands

```bash
cd translated/held_suarez/cpp/fv_advection/semi_y_3d
make check
```

This builds the library and fixture runner, writes:

```text
translated/held_suarez/cpp/fv_advection/semi_y_3d/outputs/output_dq_cpp.bin
```

and writes the comparison report:

```text
tests/reports/semi_y_3d_cpp_compare_report.json
```

## Status

Completed local CPU C++ build and fixture comparison.

Result:

```text
overall_pass: true
dq count: 120
max_abs_error: 0.0
max_rel_error: 0.0
rmse: 0.0
mismatches_above_tolerance: 0
atol: 1e-13
rtol: 1e-13
```

Generated report:

```text
tests/reports/semi_y_3d_cpp_compare_report.json
```

## Next Step

Proceed to CUDA implementation for the same fixture before adding any hybrid
overlay integration.
