# FV Advection Kernel Bundle Checkpoint

Date: 2026-06-18

# Objective

Modernize the local finite-volume kernels used by
`fv_advection_mod::a_grid_horiz_advection_3d` while leaving the production
Fortran source tree untouched.

The selected integration strategy is:

```text
Fortran model and halo/domain handling
-> Fortran ISO_C_BINDING wrapper
-> C ABI
-> CPU C++ or CUDA local kernels
```

This follows Strategy 3 from the feasibility analysis: retain orchestration,
MPI/domain decomposition, halo updates, and boundary control in Fortran while
moving local numerical loops behind C/CUDA interfaces.

# Starting Point

Before this phase, `semi_y_3d` had completed the full modernization ladder:

```text
Fortran baseline
-> CPU C++
-> CUDA
-> C API
-> Fortran wrapper
-> native Isca overlay
-> 1-day validation
-> 30-day validation
```

The `semi_y_3d` CPU and CUDA model outputs matched the all-Fortran baseline
exactly for `ps`, `temp`, `ucomp`, and `vcomp` in the 30-day comparison.

# Kernel Bundle Completed

The next requested kernels were implemented together as a dependency-aware
bundle:

- `semi_x_3d`
- `slope_x`
- `slope_sphere`
- `vanleer_x_3d`
- `vanleer_sphere_3d`

Required helpers included in the bundle:

- `find_cell_x`
- `integer_flux_x`

The top-level kernels called by the model-facing C ABI are:

- `semi_x_3d`
- `vanleer_x_3d`
- `vanleer_sphere_3d`

`slope_x`, `slope_sphere`, `integer_flux_x`, and `find_cell_x` are internal
helpers in the translated top-level implementations.

# Files And Layout

Planning and reports:

```text
docs/fv_advection_kernel_bundle_plan.md
docs/fv_advection_kernel_bundle_translation_report.md
docs/fv_advection_kernel_bundle_profile_plan.md
docs/fv_advection_kernel_bundle_performance_results.md
```

Fortran baseline fixture:

```text
tests/fortran_baseline/fv_advection_kernels/
```

CPU C++ implementation and C/Fortran integration:

```text
translated/held_suarez/cpp/fv_advection/kernels/
translated/held_suarez/cpp/fv_advection/kernels/fortran/
```

CUDA implementation:

```text
translated/held_suarez/cuda/fv_advection/kernels/
```

Native Isca overlay:

```text
src/extra/local_overrides/fv_advection_kernels/fv_advection.F90
```

Hybrid link templates:

```text
src/extra/python/isca/templates/mkmf.template.fv_kernels_hybrid
src/extra/python/isca/templates/mkmf.template.fv_kernels_hybrid_cuda
```

Build and run scripts:

```text
run_compile_fv_kernels.sh
scripts/run_fv_kernels_1day_smoke.sh
scripts/run_fv_kernels_cpu_30day.sh
scripts/run_fv_kernels_cuda_30day.sh
scripts/validate_fv_kernels_1day.sh
```

# Correctness Validation

The production body of `vanleer_sphere_3d` was rechecked during integration.
The first fixture used an older metric form, so the fixture, C++, CUDA, and ABI
were corrected to match production:

```text
flux = vc * cc * (...)
dq_dt -= (flux(j+1) - flux(j)) / (dy * c)
```

`dy(js-1:je+1)` is passed through the C/CUDA ABI as an array.

After that correction, the full standalone validation ladder passed:

```text
CPU C++ fixture: PASS
CUDA fixture: PASS
Fortran -> C -> CPU C++: PASS
Fortran -> C -> CUDA: PASS
```

All reported fields had zero mismatches. Key reports:

```text
tests/reports/fv_advection_kernels_cpp_compare_report.json
tests/reports/fv_advection_kernels_cuda_compare_report.json
tests/reports/fv_advection_kernels_fortran_c_compare_report.json
tests/reports/fv_advection_kernels_fortran_cuda_c_compare_report.json
```

# Native Build Results

Both native Isca overlay executables build successfully:

CPU C++:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_kernels/held_suarez_fv_kernels.x
```

CUDA:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_kernels_cuda/held_suarez_fv_kernels_cuda.x
```

Latest build logs:

```text
logs/fv_kernels_compile_latest.log
logs/fv_kernels_cuda_compile_latest.log
```

The build flow now removes an existing kernel-bundle executable after replacing
the static library so `mkmf` must relink the executable. This prevents a newly
built `libfv_advection_kernels.a` from being ignored as `up to date`.

# Model Runs

The CPU and CUDA executables both passed 1-day smoke tests.

Smoke log:

```text
logs/fv_kernels_1day_smoke.log
```

Experiments:

```text
held_suarez_fv_kernels_1day
held_suarez_fv_kernels_cuda_1day
```

CPU and CUDA 1-day monthly outputs were bitwise identical. The 1-day
all-Fortran monthly comparison was not meaningful because a one-day run does
not populate monthly diagnostics; the file contains NetCDF fill values.

Both 30-day profiled runs completed successfully:

```text
held_suarez_fv_kernels_30day
held_suarez_fv_kernels_cuda_30day
```

Logs:

```text
logs/fv_kernels_cpu_30day.log
logs/fv_kernels_cuda_30day.log
```

Output files:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_fv_kernels_30day/run0001/atmos_monthly.nc
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_fv_kernels_cuda_30day/run0001/atmos_monthly.nc
```

# Profiling Added

Runtime profiling is enabled with:

```bash
export FV_KERNELS_PROFILE=1
```

Markers:

```text
PROFILE_FV_ADVECTION_KERNEL backend=<cpu|cuda> rank=<rank> name=<kernel> calls=<n> time=<seconds> avg=<seconds>
```

Timing is recorded at the model-facing C/CUDA ABI. CPU timing covers the C ABI
and C++ implementation. CUDA timing includes allocation, H2D copies, launch,
synchronization, D2H copies, and free.

# Performance Results

Run configuration:

```text
default Held-Suarez T42L25-style configuration
30 days
dt_atmos = 600 s
16 MPI ranks
production monthly diagnostics
```

Model runtime:

| Variant | MPP Runtime | Shell Real |
|---|---:|---:|
| CPU C++ bundle | 25.546 s | 28.987 s |
| CUDA bundle | 132.355 s | 136.048 s |

Observed comparison:

```text
CUDA vs CPU C++ MPP speedup: 0.193x
CUDA runtime penalty: about 5.18x slower
```

Each top-level kernel was called 4320 times per MPI rank.

Max-rank kernel timing:

| Backend | Kernel | Time Max | Fraction of Model MPP Runtime |
|---|---|---:|---:|
| CPU C++ | `semi_x_3d` | 0.214 s | 0.84% |
| CPU C++ | `vanleer_x_3d` | 0.768 s | 3.01% |
| CPU C++ | `vanleer_sphere_3d` | 0.560 s | 2.19% |
| CUDA | `semi_x_3d` | 22.566 s | 17.05% |
| CUDA | `vanleer_x_3d` | 17.089 s | 12.91% |
| CUDA | `vanleer_sphere_3d` | 56.754 s | 42.88% |

Total timed top-level region:

```text
CPU C++ max rank: 1.542 s, 6.04% of model runtime
CUDA max rank:   95.273 s, 72.84% of model runtime
```

The largest CUDA hotspot is `vanleer_sphere_3d`, but optimizing it alone is
unlikely to yield model speedup while every call performs local allocation,
copies, synchronization, and copy-back.

# Conclusions

- The kernel-bundle modernization workflow is validated end to end.
- Original production Fortran source remains untouched.
- CPU C++ implementations are correct and inexpensive.
- CUDA implementations are correct architecture prototypes.
- Fine-grained CUDA wrappers are not a performance path in their current form.
- Per-call GPU orchestration turns a roughly 6% CPU region into roughly 73% of
  CUDA model runtime.
- Further isolated wrapper conversions should not be prioritized for speedup.
- The next performance design must reduce Fortran/CUDA crossings through
  persistent device data, reusable buffers, and/or broader kernel fusion.

# Remaining Work

1. Produce a duration-matched all-Fortran T42L25 30-day output if one is not
   already available.
2. Compare all-Fortran, CPU C++, and CUDA 30-day `atmos_monthly.nc` outputs.
3. Decide whether to add internal CUDA phase timing for allocation, H2D,
   kernel, D2H, and free.
4. Design a broader GPU-resident boundary around the advection/update path.
5. Avoid adding more isolated CUDA wrappers until the data-residency design is
   settled.

# Resume Instructions

When resuming the FV kernel-bundle work:

1. Read this checkpoint.
2. Read `docs/fv_advection_kernel_bundle_performance_results.md`.
3. Read `docs/fv_advection_kernel_bundle_translation_report.md`.
4. Verify the latest build and run logs listed above still correspond to the
   current source revision.
5. Complete the duration-matched 30-day NetCDF comparison if it is still open.
6. Before writing more CUDA kernels, choose between:
   - phase-level CUDA profiling;
   - persistent/reusable GPU buffers;
   - a broader fused advection/update integration boundary.
7. Preserve the production Fortran source and continue using overlays and
   native `CodeBase.compile()` integration.

