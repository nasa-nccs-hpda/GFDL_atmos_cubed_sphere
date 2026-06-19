# Full CUDA Modernization Checkpoint

Date: 2026-06-18

## Objective

Create and maintain a full CUDA modernization roadmap for the Held-Suarez model
without modifying original production Fortran source files.

Allowed integration pattern:

```text
Fortran model
-> overlay Fortran wrapper
-> ISO_C_BINDING
-> C API
-> C++/CUDA module
-> native Isca CodeBase.compile()
```

Production source policy:

```text
Do not modify original production Fortran source.
Use overlays, wrappers, C APIs, CUDA/C++ modules, and native Isca build integration.
```

## Current Completed State

Held-Suarez forcing:

- `hs_forcing` translated to C++.
- C API validated.
- Fortran `iso_c_binding` wrapper validated.
- CUDA backend implemented.
- Native Isca overlay build works.
- `held_suarez_hybrid.x` builds.
- 1-day and 30-day CPU hybrid runs completed.
- CUDA hybrid backend completed as proof of architecture.
- T85L25 forcing-performance experiment completed.

T85L25 forcing-performance result:

```text
Fortran MPP runtime:     206.761 s
CPU hybrid MPP runtime:  200.475 s
CUDA hybrid MPP runtime: 320.956 s
CPU hybrid speedup:      1.031x
CUDA hybrid speedup:     0.644x
```

Conclusion:

- CPU C++ forcing is a small positive speedup.
- CUDA forcing is architecture validation only in its current design.
- Next performance work should target larger dynamics/advection/transform
  regions, not forcing alone.

## Profiling Conclusions

Completed profiling:

- T42 forcing-module profiling.
- `four_in_one` profiling.
- `vert_advection_3d` profiling.
- broad dynamics-region profiling.
- dynamics-deep profiling.
- T85L25 forcing-performance study.

Measured conclusions:

```text
four_in_one: about 2.6% runtime -> do not target next for performance
vert_advection_3d u+v+t: about 0.34% runtime -> no-go for performance
transforms broad region: about 38.9% -> high runtime but coupled
tracer/correction diagnostics broad region: about 32.6% -> split deeper
update_tracers: 17.55% -> strong region
tracer_grid_horizontal_advection: 12.04% -> promising concrete path
press_geopot: about 4.8% -> fallback
```

## Selected Modernization Path

Selected candidate:

```text
fv_advection_mod::a_grid_horiz_advection_3d
```

Decision:

```text
PARTIAL GO / Strategy 3
```

Strategy:

- keep `fv_advection_mod` orchestration in Fortran;
- keep halo/domain handling in Fortran;
- keep `mpp_update_domains` and polar boundary handling in Fortran;
- modernize local finite-volume kernels behind C APIs and CUDA/C++ modules.

Selected first kernel:

```text
fv_advection_mod::semi_y_3d
```

Reason:

- part of measured `tracer_grid_horizontal_advection` path;
- no callees;
- no MPI;
- no halo update;
- no spectral transforms;
- regular 3D array loop;
- best first candidate for the local FV kernel workflow.

## Created Planning Documents

Master plan:

```text
docs/full_held_suarez_cuda_modernization_master_plan.md
```

Module inventory and strategy table:

```text
docs/full_cuda_modernization_module_table.md
```

This checkpoint:

```text
memory/FULL_CUDA_MODERNIZATION_CHECKPOINT.md
```

Related checkpoints:

```text
memory/T85L25_FORCING_PERFORMANCE_CHECKPOINT.md
memory/PERFORMANCE_MODERNIZATION_CHECKPOINT.md
memory/SEMI_Y_3D_PHASE1_CHECKPOINT.md
```

Related decision docs:

```text
docs/dynamics_deep_profile_recommendation.md
docs/a_grid_horiz_advection_3d_feasibility_analysis.md
docs/fv_advection_kernel_modernization_plan.md
docs/translation_spec_semi_y_3d.md
docs/semi_y_3d_baseline_harness_report.md
```

## Roadmap Phases

Phase 0:

```text
Freeze current hs_forcing CUDA hybrid as reference implementation.
```

Phase 1:

```text
Complete semi_y_3d workflow:
Fortran baseline -> C++ -> CUDA -> C API -> hybrid overlay -> validation.
```

Phase 2:

```text
Expand to additional fv_advection kernels:
semi_x_3d, vanleer_x_3d, vanleer_sphere_3d, slope_x, slope_sphere,
integer_flux_x, find_cell_x.
```

Phase 3:

```text
Hybridize a_grid_horiz_advection_3d by keeping domain/halo logic in Fortran
and moving local kernels to CUDA.
```

Phase 4:

```text
Evaluate press_and_geopot.
```

Phase 5:

```text
Study transform-heavy region separately with vendor/library strategy.
```

Phase 6:

```text
Build cumulative hybrid Held-Suarez executable with multiple CUDA modules.
```

Phase 7:

```text
Run validation ladder:
unit -> module -> wrapper -> 1-day -> 30-day -> T85/T170 scaling.
```

## Current Concrete State

Fortran baseline harness exists:

```text
tests/fortran_baseline/semi_y_3d/
```

Contains:

```text
test_semi_y_3d.F90
Makefile
README.md
inputs/
outputs/
```

Important details:

- `semi_y_3d` is private inside `fv_advection_mod`.
- Harness uses a test-only copy of the routine body and minimal module state.
- Production source has not been modified.
- Baseline harness has not yet been run successfully in this shell because the
  host environment did not expose a Fortran compiler.

## Next Concrete Action

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

Only after the baseline outputs exist:

```text
Start C++ translation of semi_y_3d.
```

## Guardrails

- Do not translate code before baseline fixtures exist.
- Do not modify original production Fortran source.
- Use overlays for model integration.
- Keep Fortran around MPI/domain/halo/diagnostic/I/O logic.
- Keep CUDA optional and fail clearly if requested but unavailable.
- Preserve CPU fallback for every new CUDA backend.
- Validate one kernel/module at a time.

# Resume instructions

If resuming full CUDA modernization:

1. Read this checkpoint.
2. Read `docs/full_held_suarez_cuda_modernization_master_plan.md`.
3. Read `docs/full_cuda_modernization_module_table.md`.
4. Read `docs/translation_spec_semi_y_3d.md`.
5. Verify the `semi_y_3d` baseline harness inside the container.
6. Start C++ translation only after baseline outputs exist.
