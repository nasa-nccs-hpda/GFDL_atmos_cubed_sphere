# Objective

Modernize `fv_advection_mod::semi_y_3d` using the same staged workflow
previously used for `hs_forcing`.

# Why semi_y_3d was selected

* Derived from profiling.
* `tracer_grid_horizontal_advection` ≈ 12.04% of model MPP runtime.
* `a_grid_horiz_advection_3d` identified as hotspot path.
* Strategy 3 selected:
  keep halo/domain handling in Fortran,
  modernize local finite-volume kernels.

# Completed work

* dynamics profiling completed
* deep profiling completed
* feasibility analysis completed
* kernel ranking completed
* `semi_y_3d` selected
* translation spec created
* Fortran baseline harness created

Files:

* `docs/a_grid_horiz_advection_3d_feasibility_analysis.md`
* `docs/fv_advection_kernel_modernization_plan.md`
* `docs/translation_spec_semi_y_3d.md`
* `docs/semi_y_3d_baseline_harness_report.md`

# Current status

`semi_y_3d` has completed the full modernization ladder through native model
integration and 30-day validation.

Validated ladder:

```text
Fortran baseline fixture
-> CPU C++ kernel
-> CUDA kernel
-> Fortran ISO_C_BINDING -> C++ kernel
-> Fortran ISO_C_BINDING -> CUDA kernel
-> native Isca fv_advection overlay, CPU C++ backend
-> native Isca fv_advection overlay, CUDA backend
-> 1-day model validation
-> 30-day model validation
```

Fortran baseline harness:

```text
tests/fortran_baseline/semi_y_3d/
```

Contains:

* `test_semi_y_3d.F90`
* `Makefile`
* `inputs/`
* `outputs/`

`semi_y_3d` is private inside `fv_advection_mod`.

Test harness uses a test-only copy of the routine body and minimal module
state.

Production source was not modified.

# Key reports

```text
tests/reports/semi_y_3d_cpp_compare_report.json
tests/reports/semi_y_3d_cuda_compare_report.json
tests/reports/semi_y_3d_fortran_c_compare_report.json
tests/reports/semi_y_3d_fortran_cuda_c_compare_report.json
tests/reports/semi_y_3d_1day_model_validation_report.md
tests/reports/semi_y_3d_30day_model_validation_report.md
docs/semi_y_3d_native_overlay_integration_report.md
```

# Next milestone

Select the next finite-volume local kernel and repeat the workflow.

Likely candidates:

```text
semi_x_3d
slope_sphere
slope_x
vanleer_sphere_3d
vanleer_x_3d
```

# Risks

* test harness correctness
* hidden module state
* boundary-condition assumptions
* array ordering

# Resume instructions

If resuming later:

1. Read:
   `memory/SEMI_Y_3D_PHASE1_CHECKPOINT.md`

2. Read:
   `docs/semi_y_3d_native_overlay_integration_report.md`

3. Read:
   `docs/fv_advection_kernel_modernization_plan.md`

4. Select the next FV local kernel.

5. Create its Fortran baseline fixture before C++ translation.
