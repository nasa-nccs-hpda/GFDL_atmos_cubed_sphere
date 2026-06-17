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

Fortran baseline harness exists:

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

# Next command to run

Inside Isca container:

```bash
cd tests/fortran_baseline/semi_y_3d
make FC=mpifort
./test_semi_y_3d
```

Expected output:

```text
inputs/*.bin
outputs/output_dq.bin
```

# Next milestone

Validate Fortran baseline harness.

Then:

```text
Fortran baseline
-> C++ implementation
-> output comparison
-> C API
-> Fortran wrapper
-> hybrid integration
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
   `docs/translation_spec_semi_y_3d.md`

3. Read:
   `docs/semi_y_3d_baseline_harness_report.md`

4. Verify baseline harness runs.

5. Start C++ translation only after baseline outputs are generated.
