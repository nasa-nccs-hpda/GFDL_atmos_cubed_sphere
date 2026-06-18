# Performance Modernization Checkpoint

## Goal

Select the next performance-driven Held-Suarez modernization target after the
forcing-module hybrid workflow.

The project direction is:

```text
Fortran baseline
-> C++ translation
-> C API
-> Fortran ISO_C_BINDING wrapper
-> native Isca overlay integration
-> validation
-> eventual GPU-aware redesign
```

## Completed

- Held-Suarez forcing-module modernization.
- CPU C++ forcing module.
- CUDA forcing proof of concept.
- Fortran -> C API -> C++ hybrid executable.
- T42 forcing-module profiling.
- T42 `four_in_one` profiling.
- T42 `vert_advection_3d` profiling.
- Broad dynamics-region profiling.
- Second-level dynamics-deep profiling.
- `a_grid_horiz_advection_3d` feasibility analysis.
- finite-volume local-kernel ranking.
- `semi_y_3d` translation spec.
- `semi_y_3d` Fortran baseline harness.

## Measured Conclusions

### Forcing Module

The Held-Suarez forcing module is a successful architecture prototype but a
weak speedup target.

T85L25 forcing-performance result:

```text
Fortran MPP runtime:     206.761 s
CPU hybrid MPP runtime:  200.475 s
CUDA hybrid MPP runtime: 320.956 s
```

Speedups:

```text
CPU hybrid vs Fortran:  1.031x
CUDA hybrid vs Fortran: 0.644x
CUDA hybrid vs CPU:     0.625x
```

Estimated CPU forcing fraction of Fortran runtime:

```text
about 4.23%
```

Conclusion:

- CPU C++ replacement gives a small measurable improvement.
- CUDA forcing is architecture validation only in the current design.
- Larger dynamics/advection/transform regions are better performance targets.

### four_in_one

Measured result:

```text
four_in_one max PE time: about 0.632 s
runtime fraction: about 2.6% of model MPP time
calls: 4320
```

Decision:

```text
Do not translate four_in_one next for performance.
```

It remains a possible workflow-learning target but is too small for the next
performance-driven translation.

### vert_advection_3d

Measured result:

```text
vert_advection_3d u+v+t: about 0.34% runtime
```

Decision:

```text
Do not translate vert_advection_3d next for performance.
```

The isolated vertical advection calls are too small to justify direct
translation as the next performance target.

### Broad Dynamics Regions

Broad-region profile showed:

```text
transforms:                      about 38.9%
tracer_correction_diagnostics:   about 32.6%
advection:                       about 7.9%
press_geopot:                    about 4.8%
```

Decision:

- Do not translate immediately.
- Split large mixed regions into deeper timers.

### Dynamics Deep Profile

Second-level profile showed the strongest concrete call sites:

```text
update_tracers:                    17.55% of model MPP runtime
tracer_grid_horizontal_advection:  12.04% of model MPP runtime
compute_corrections:                9.43% of model MPP runtime
transform_vor_div_from_uv:          7.42% of model MPP runtime
horizontal_advection_temperature:   7.25% of model MPP runtime
transform_future_uv_from_vor_div:   7.03% of model MPP runtime
transform_future_div:               6.71% of model MPP runtime
tracer_vertical_advection:          5.03% of model MPP runtime
```

Conclusion:

- Transform work remains the largest aggregate, but it is distributed and
  coupled.
- `update_tracers` and `tracer_grid_horizontal_advection` expose a stronger,
  more concrete finite-volume advection path.
- Choose a finite-volume local-kernel strategy before attempting broad
  transform modernization.

## Selected Candidate Path

Selected path:

```text
fv_advection_mod::a_grid_horiz_advection_3d
```

Result:

```text
PARTIAL GO / Strategy 3
```

Strategy:

- keep `fv_advection_mod` orchestration in Fortran;
- keep halo/domain handling in Fortran;
- keep `mpp_update_domains` and polar boundary handling in Fortran;
- modernize local finite-volume kernels behind a C API.

Reason:

- `a_grid_horiz_advection_3d` is reached by the measured
  `tracer_grid_horizontal_advection` path.
- The measured path is about 12.04% of model MPP runtime.
- The whole routine is coupled to domain/halo behavior, so translating it
  directly is too risky as a first step.
- Local kernels provide a lower-risk modernization boundary.

## Kernel Ranking Work Completed

Kernel ranking was completed in:

```text
docs/fv_advection_kernel_modernization_plan.md
```

Local finite-volume kernels considered:

- `advection_sphere_3d`
- `semi_x_3d`
- `semi_y_3d`
- `vanleer_x_3d`
- `vanleer_sphere_3d`
- `slope_x`
- `slope_sphere`
- `find_cell_x`
- `integer_flux_x`

Ranking criteria:

- call frequency;
- array size;
- arithmetic intensity;
- GPU suitability;
- ease of isolation;
- dependency complexity;
- validation difficulty.

## Selected First Kernel

Selected first kernel:

```text
fv_advection_mod::semi_y_3d
```

Why:

- part of the measured finite-volume advection path;
- no callees;
- no MPI;
- no `mpp_update_domains`;
- no spectral transforms;
- regular 3D array loop;
- simple y-direction upwind branch;
- easiest local kernel to isolate and validate first.

Expected scope:

- This single kernel will not capture the full 12.04% measured region.
- It validates the local finite-volume kernel modernization workflow.
- Later kernels can expand coverage toward `semi_x_3d`,
  `vanleer_sphere_3d`, `vanleer_x_3d`, and helpers.

## Documents

Core decision and planning docs:

```text
docs/a_grid_horiz_advection_3d_feasibility_analysis.md
docs/fv_advection_kernel_modernization_plan.md
docs/translation_spec_semi_y_3d.md
docs/semi_y_3d_baseline_harness_report.md
```

Related profiling docs:

```text
docs/four_in_one_profile_recommendation.md
docs/vert_advection_profile_recommendation.md
docs/dynamics_region_profile_recommendation.md
docs/dynamics_deep_profile_recommendation.md
docs/next_module_performance_decision.md
```

Forcing-performance docs:

```text
docs/T85L25_forcing_performance_results.md
memory/T85L25_FORCING_PERFORMANCE_CHECKPOINT.md
```

## Current State

Fortran baseline harness exists:

```text
tests/fortran_baseline/semi_y_3d/
```

Contains:

```text
tests/fortran_baseline/semi_y_3d/test_semi_y_3d.F90
tests/fortran_baseline/semi_y_3d/Makefile
tests/fortran_baseline/semi_y_3d/README.md
tests/fortran_baseline/semi_y_3d/inputs/
tests/fortran_baseline/semi_y_3d/outputs/
```

Important:

- `semi_y_3d` is private inside `fv_advection_mod`.
- The harness uses a test-only copy of the routine body and minimal module
  state.
- Production source was not modified.
- The host shell did not have a Fortran compiler, so the harness was not run
  there.

## Next Milestone

Run baseline harness inside the Isca container:

```bash
cd tests/fortran_baseline/semi_y_3d
make FC=mpifort
./test_semi_y_3d
```

Expected outputs:

```text
tests/fortran_baseline/semi_y_3d/inputs/*.bin
tests/fortran_baseline/semi_y_3d/outputs/output_dq.bin
```

After baseline succeeds:

```text
Fortran baseline
-> C++ implementation
-> comparison
-> C API
-> Fortran wrapper
-> hybrid integration
```

## Risks

- The standalone harness uses a test-only copy of a private routine, so it must
  be kept synchronized with the original Fortran routine body.
- Hidden assumptions may exist in production module state, index bounds, or
  boundary handling.
- Synthetic fixtures may not expose all production path behavior.
- Later kernels such as `vanleer_x_3d` and `integer_flux_x` are more branchy
  and harder to validate.
- Translating only one local kernel will not provide full-region speedup until
  enough neighboring kernels are modernized and integrated.

# Resume instructions

If resuming modernization:

1. Read this checkpoint.
2. Read `docs/translation_spec_semi_y_3d.md`.
3. Verify baseline harness.
4. Start C++ translation only after baseline outputs exist.
