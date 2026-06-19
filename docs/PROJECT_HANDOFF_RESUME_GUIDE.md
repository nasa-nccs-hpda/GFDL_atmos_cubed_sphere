# Held-Suarez Modernization Resume Guide

Use this document when restarting the project after a long pause. It identifies
what is complete, what evidence is authoritative, and the next bounded task.

## First Five Minutes

```bash
cd /explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
git branch --show-current
git status --short
```

Expected checkpoint state:

```text
branch: perf/cuda-data-residency
untracked: end2end_experiment/
```

Do not remove or add the untracked directory without establishing its ownership.

Read, in order:

```text
memory/FINAL_PROJECT_CHECKPOINT_2026-06-19.md
docs/PROJECT_HANDOFF_EXECUTIVE_SUMMARY.md
docs/fv_advection_cuda_resident_performance_results.md
docs/fv_advection_cuda_resident_boundary_report.md
docs/fv_advection_cuda_fused_boundary_design.md
```

## What Has Been Completed

### Build and integration foundation

- The successful Isca path is `CodeBase.compile()`, not manual `mkmf`.
- Source overlays replace selected production files without editing originals.
- CPU C++ and CUDA static libraries are built inside the target container.
- Mixed Fortran/C++/CUDA templates and link paths are established.
- Separately named `DryCodeBase` classes isolate build directories and
  executables.

### Forcing module

- Fortran baseline fixture.
- C++ module and C ABI.
- Fortran `ISO_C_BINDING` wrapper.
- CPU hybrid and optional CUDA backend.
- One-day and 30-day validation.
- T85L25 three-way performance experiment.

### Profiling and target selection

- Coarse dynamics regions.
- Deep dynamics regions.
- `four_in_one` and vertical-advection call-site timers.
- Target feasibility studies and module ranking.
- Decision to retain Fortran MPI/halo logic and modernize local FV kernels.

### FV advection

- `semi_y_3d` standalone-to-model workflow complete.
- Bundle implementation for `semi_x_3d`, slopes, Van Leer kernels,
  `integer_flux_x`, and `find_cell_x`.
- Exact CPU, CUDA, and wrapper fixture comparisons.
- CPU and CUDA native overlay executables.
- Exact 30-day model comparisons.
- Stateless, persistent-buffer, and two-phase resident CUDA modes.
- Repeat timing for persistent mode and measured resident improvement.

## What Is Validated

### Standalone and wrapper

The current authoritative reports are:

```text
tests/reports/fv_advection_kernels_cpp_compare_report.json
tests/reports/fv_advection_kernels_cuda_compare_report.json
tests/reports/fv_advection_kernels_cuda_persistent_compare_report.json
tests/reports/fv_advection_kernels_cuda_resident_compare_report.json
tests/reports/fv_advection_kernels_fortran_c_compare_report.json
tests/reports/fv_advection_kernels_fortran_cuda_c_compare_report.json
tests/reports/fv_advection_kernels_fortran_cuda_persistent_c_compare_report.json
```

The resident standalone report contains exact results at `1e-12`, including the
combined resident `q1` and tendency paths.

### Model level

Authoritative resident 30-day comparison:

```text
tests/reports/fv_advection_kernels_resident_30day_model_validation.md
tests/reports/fv_advection_kernels_resident_30day_model_validation.json
logs/fv_kernels_cuda_resident_30day_validation.log
```

`temp`, `ucomp`, `vcomp`, and `ps` agree exactly among all-Fortran, CPU C++, and
resident CUDA outputs.

### Current executable availability

Present on 2026-06-19:

```text
$GFDL_WORK/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_hybrid/held_suarez_hybrid.x
$GFDL_WORK/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_semi_y_3d/held_suarez_fv_semi_y_3d.x
$GFDL_WORK/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_semi_y_3d_cuda/held_suarez_fv_semi_y_3d_cuda.x
$GFDL_WORK/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_kernels/held_suarez_fv_kernels.x
$GFDL_WORK/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_kernels_cuda/held_suarez_fv_kernels_cuda.x
```

The separately named `held_suarez_fortran.x` is not currently present. Use the
stock Isca baseline or rebuild the custom baseline only when required.

## What Should Not Be Repeated

- Do not rediscover manual `mkmf` arguments or source roots. Native
  `CodeBase.compile()` and overlay mechanics are solved.
- Do not modify original production Fortran files.
- Do not retranslate the forcing module, `semi_y_3d`, or the completed FV bundle.
- Do not repeat `four_in_one` or `vert_advection_3d` profiling at T42L25; their
  measured contributions are already known.
- Do not add another per-kernel stateless CUDA wrapper as a performance strategy.
- Do not treat persistent allocation alone as sufficient; it yielded only 1.039x
  over stateless.
- Do not use the resident one-day production-diagnostic report as a numerical
  gate. Its monthly variables can be fill values.
- Do not rebuild or overwrite 30-day outputs merely to verify that files exist.
- Do not build static libraries on the host and link them in the aarch64
  container.

## Current Performance Conclusions

### Forcing

T85L25, 30 days, 16 ranks:

| Variant | MPP | Result |
|---|---:|---|
| Fortran | 206.761 s | baseline |
| CPU C++ | 200.475 s | 1.031x speedup |
| CUDA | 320.956 s | 0.644x; slowdown |

Forcing is a successful interface prototype, not a useful isolated CUDA target.

### FV bundle

T42L25, 30 days, 16 ranks:

| Backend | MPP | Relative result |
|---|---:|---|
| CPU C++ | 25.546 s | fastest current implementation |
| Stateless CUDA | 132.355 s | 5.18x slower |
| Persistent CUDA mean | 127.173 s | 1.039x over stateless |
| Resident CUDA | 108.505 s | 1.172x over persistent; 4.25x slower than CPU |

The resident architecture is a measured improvement. H2D transfer remains the
dominant bottleneck, accounting for 71.7% of the slowest rank's measured resident
CUDA region.

## Current Bottlenecks

1. Host/device copies occur at every model-facing resident begin/finish cycle.
2. `q` and related full fields cross the boundary more often than necessary.
3. `semi_y_3d` is already translated but still sits outside the shared resident
   pre-halo context.
4. The existing Fortran MPI halo exchange requires `q1` to return to host.
5. Sixteen MPI ranks may contend for GPU resources and inflate launch/copy cost.
6. T42 local domains are small for GPU amortization.
7. Transform-heavy work is large but requires a vendor-library or redesign study,
   not a direct translation sprint.

## Current Open Questions

- How much H2D time is removed by computing and retaining `q2` on device?
- Can only `q1` halo slabs be exchanged without disturbing FMS decomposition and
  polar correction semantics?
- At what horizontal resolution does resident CUDA begin to amortize overhead?
- What MPI-rank-to-GPU mapping gives a fair comparison on H100 nodes?
- Can state remain device-resident across multiple tracer updates or timesteps?
- Which transform implementation and data layout best map to cuFFT or another
  accelerator library?
- Is exact agreement required for all future kernels, or will a documented
  tolerance become necessary after more aggressive fusion/reordering?

## Recommended Next Task

### A. Highest Priority

Integrate the existing `semi_y_3d` CUDA implementation into the current resident
pre-halo FV boundary. Do not translate a new kernel.

Target behavior:

```text
upload q once
  -> semi_x_3d on device -> q1
  -> semi_y_3d on device -> q2
  -> retain q2 on device
  -> export q1 for Fortran/MPI halo exchange
  -> import corrected q1
  -> run post-halo Van Leer work
  -> download final tendency once
```

Files to inspect before editing:

```text
src/extra/local_overrides/fv_advection_kernels/fv_advection.F90
translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu
translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.h
translated/held_suarez/cpp/fv_advection/kernels/src/fv_advection_kernels.cpp
translated/held_suarez/cpp/fv_advection/kernels/include/fv_advection_kernels.hpp
translated/held_suarez/cpp/fv_advection/kernels/fortran/fv_advection_kernels_c_interface.F90
translated/held_suarez/cuda/fv_advection/semi_y_3d/semi_y_3d_cuda.cu
docs/fv_advection_cuda_resident_boundary_report.md
docs/fv_advection_cuda_resident_performance_results.md
```

Required properties:

- Production Fortran untouched.
- Existing stateless, persistent, and current resident modes remain functional.
- Explicit errors; no silent fallback.
- Per-rank reusable memory ownership remains in CUDA/C layer.
- Existing Fortran/MPI halo exchange remains between phases.

Validation ladder:

```bash
# In CUDA-enabled Isca container
cd "$GFDL_BASE/translated/held_suarez/cpp/fv_advection/kernels"
make clean
make USE_CUDA_FV_ADVECTION_KERNELS=1 cuda_resident_check

# Rebuild native overlay from repository root
cd "$GFDL_BASE"
USE_CUDA_FV_ADVECTION_KERNELS=1 \
NVCC=/usr/local/cuda/bin/nvcc \
./run_compile_fv_kernels.sh

# Runtime gates
FV_KERNELS_OVERWRITE=1 scripts/run_fv_kernels_resident_1day.sh
FV_KERNELS_OVERWRITE=1 FV_KERNELS_PROFILE=1 \
  scripts/run_fv_kernels_resident_30day.sh

# Host-side NetCDF gate
scripts/validate_fv_kernels_resident_30day.sh
```

Use a new experiment and log name for the extended resident mode until it is
accepted; do not overwrite the current reference run. The existing scripts may
be copied or parameterized in a new script rather than changing historical
experiment identity.

Pass criteria:

- Fixture and wrapper reports pass at existing tolerances.
- One-day log shows the intended backend on all ranks.
- Thirty-day `temp`, `ucomp`, `vcomp`, and `ps` match baseline.
- Repeat timing confirms the result is larger than run-to-run noise.
- H2D and total CUDA-region time decrease; otherwise stop and diagnose before
  broadening further.

### B. Medium Priority

After the `semi_y_3d` resident increment:

1. Prototype host exchange of only `q1` halo slabs.
2. Repeat FV performance at T85L25 with controlled MPI/GPU mapping.
3. Consolidate build/test commands into one validation-ladder driver with unique
   experiment names and artifact checks.
4. Add CI or a reproducible batch workflow for CPU fixture tests and report
   schema validation.

### C. Future Research

1. Move `update_tracers`-level state residency behind a broader API.
2. Evaluate T170L25/T85L50 memory and performance scaling.
3. Study transform replacement with cuFFT/vendor libraries and compatible data
   layouts.
4. Develop a cumulative multi-module CUDA executable after each boundary is
   independently validated.
5. Transfer the proven workflow to a GEOS-relevant production kernel.

## Exact Reference Logs

Latest architecture sequence:

```text
logs/fv_advection_cuda_microbenchmark.log
logs/fv_kernels_cuda_30day.log
logs/fv_kernels_cuda_persistent_30day.log
logs/fv_kernels_cuda_persistent_30day_repeat.log
logs/fv_kernels_cuda_resident_1day.log
logs/fv_kernels_cuda_resident_30day.log
logs/fv_kernels_cuda_resident_30day_validation.log
```

Profiling history:

```text
logs/four_in_one_profile_30day.log
logs/vert_advection_profile_30day_callsite.log
logs/dynamics_region_profile_30day.log
logs/dynamics_deep_profile_30day.log
```

Forcing reference:

```text
logs/hybrid_hs_profile_30day.log
logs/T85L25_fortran_30day.log
logs/T85L25_hybrid_cpu_30day.log
logs/T85L25_hybrid_cuda_30day.log
```

## Stop Conditions

Stop the next implementation at the first of:

- first standalone compile or validation failure;
- first wrapper ABI failure;
- first model compile/link failure;
- first one-day runtime failure;
- first 30-day numerical mismatch;
- successful repeatable performance measurement.

Capture the complete log with `2>&1 | tee <unique-log>` before diagnosing.
