# Performance Modernization Checkpoint

Date: 2026-06-18

# Objective

Modernize Held-Suarez as a prototype for eventual GEOS GPU portability using a
measured, validation-first workflow while leaving production Fortran untouched.

Architecture:

```text
Fortran baseline
-> C++ translation
-> C API
-> Fortran ISO_C_BINDING wrapper
-> native Isca overlay
-> CUDA backend
-> unit/module/model validation
-> measured performance decision
```

# Earlier Completed Work

The Held-Suarez forcing module completed the full CPU C++ and CUDA hybrid path.
At T85L25:

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

Conclusion: forcing is a successful architecture prototype but too small for
large end-to-end speedup.

Performance profiling also established:

```text
four_in_one:                         about 2.6%
vert_advection_3d:                  about 0.34%
transforms aggregate:               about 38.9%
tracer/correction/diagnostic region: about 32.6%
advection broad region:              about 7.9%
press_geopot:                        about 4.8%
```

Deep profiling selected the finite-volume tracer-advection path:

```text
update_tracers:                    17.55%
tracer_grid_horizontal_advection:  12.04%
```

The selected strategy for `a_grid_horiz_advection_3d` was PARTIAL GO /
Strategy 3: keep halo/domain logic in Fortran and modernize local kernels.

# semi_y_3d Milestone

`semi_y_3d` completed:

```text
Fortran fixture
-> CPU C++
-> CUDA
-> C API
-> Fortran wrappers
-> CPU/CUDA native overlays
-> 1-day validation
-> 30-day validation
```

The 30-day comparison was exact for `ps`, `temp`, `ucomp`, and `vcomp` across
all-Fortran, CPU C++, and CUDA variants.

# Today: FV Kernel Bundle

Today completed the bundled modernization of:

- `semi_x_3d`
- `slope_x`
- `slope_sphere`
- `vanleer_x_3d`
- `vanleer_sphere_3d`
- helper `find_cell_x`
- helper `integer_flux_x`

Completed stages:

- deterministic Fortran baseline fixture;
- CPU C++ implementations;
- CUDA implementations;
- Fortran `ISO_C_BINDING` wrappers and stable C ABI;
- standalone CPU and CUDA comparisons;
- Fortran-to-C CPU and CUDA comparisons;
- native Isca CPU and CUDA overlay builds;
- 1-day CPU and CUDA model smoke tests;
- 30-day CPU and CUDA model runs;
- per-rank model-facing kernel profiling;
- performance analysis and recommendation.

All standalone and wrapper validations passed with zero mismatches after the
`vanleer_sphere_3d` fixture was corrected to match the production metric form.

# Current Executables

CPU C++ bundle:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_kernels/held_suarez_fv_kernels.x
```

CUDA bundle:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_kernels_cuda/held_suarez_fv_kernels_cuda.x
```

# Current Performance Result

Default T42L25-style, 30-day, 16-rank run:

| Variant | MPP Runtime | Shell Real |
|---|---:|---:|
| CPU C++ FV bundle | 25.546 s | 28.987 s |
| CUDA FV bundle | 132.355 s | 136.048 s |

```text
CUDA vs CPU speedup: 0.193x
CUDA is about 5.18x slower than CPU C++.
```

Max-rank timed top-level FV region:

```text
CPU C++: 1.542 s, 6.04% of model runtime
CUDA:   95.273 s, 72.84% of model runtime
```

Largest CUDA hotspot:

```text
vanleer_sphere_3d: 56.754 s, 42.88% of CUDA model runtime
```

# Performance Decision

The current fine-grained CUDA wrapper design is a NO-GO for model speedup.

It remains a successful correctness and architecture milestone, but the
per-call cost of allocation, transfers, kernel launch, synchronization, and
copy-back dominates the numerical work.

Do not continue adding isolated CUDA wrappers as the primary performance
strategy.

Recommended next direction:

```text
Broader fused advection/update boundary
+ persistent device-resident arrays
+ reusable GPU buffers
+ fewer Fortran/CUDA crossings
```

Transform modernization remains a future high-impact path, but it should be
treated as a separate vendor-library/redesign study rather than routine-by-
routine translation.

# Important Documents

Forcing reference:

```text
memory/T85L25_FORCING_PERFORMANCE_CHECKPOINT.md
docs/T85L25_forcing_performance_results.md
docs/end_to_end_hybrid_modernization_workflow.md
```

Performance selection:

```text
docs/dynamics_deep_profile_recommendation.md
docs/a_grid_horiz_advection_3d_feasibility_analysis.md
docs/fv_advection_kernel_modernization_plan.md
```

`semi_y_3d` reference:

```text
docs/translation_spec_semi_y_3d.md
docs/semi_y_3d_native_overlay_integration_report.md
tests/reports/semi_y_3d_30day_model_validation_report.md
```

FV bundle:

```text
memory/FV_ADVECTION_KERNEL_BUNDLE_CHECKPOINT.md
docs/fv_advection_kernel_bundle_plan.md
docs/fv_advection_kernel_bundle_translation_report.md
docs/fv_advection_kernel_bundle_profile_plan.md
docs/fv_advection_kernel_bundle_performance_results.md
```

Key FV validation reports:

```text
tests/reports/fv_advection_kernels_cpp_compare_report.json
tests/reports/fv_advection_kernels_cuda_compare_report.json
tests/reports/fv_advection_kernels_fortran_c_compare_report.json
tests/reports/fv_advection_kernels_fortran_cuda_c_compare_report.json
```

Key logs:

```text
logs/fv_kernels_compile_latest.log
logs/fv_kernels_cuda_compile_latest.log
logs/fv_kernels_1day_smoke.log
logs/fv_kernels_cpu_30day.log
logs/fv_kernels_cuda_30day.log
```

# Open Items

1. Complete a duration-matched all-Fortran vs CPU vs CUDA 30-day NetCDF
   comparison for the FV kernel-bundle experiments.
2. Decide whether internal CUDA phase timing is needed before redesign.
3. Define a persistent GPU data ownership model for advection arrays.
4. Select a broader integration boundary that amortizes GPU overhead.
5. Revisit T85/T170 scaling only after the CUDA data-residency architecture
   changes; the current fine-grained design is already overhead-dominated at
   T42L25.

# Resume Instructions

If resuming performance modernization:

1. Read this checkpoint.
2. Read `memory/FV_ADVECTION_KERNEL_BUNDLE_CHECKPOINT.md`.
3. Read `docs/fv_advection_kernel_bundle_performance_results.md`.
4. Confirm whether the all-Fortran 30-day NetCDF comparison is complete.
5. Do not start another isolated CUDA wrapper conversion by default.
6. Draft the next implementation around persistent allocations/data residency
   or a broader fused advection/update region.
7. Keep production Fortran untouched; use overlays, wrappers, C APIs, and
   native Isca `CodeBase.compile()` integration.

