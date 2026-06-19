# Full Held-Suarez CUDA Modernization Master Plan

Date: 2026-06-18

## Objective

Create an end-to-end CUDA modernization roadmap for the entire Held-Suarez
model while leaving the original production Fortran source tree untouched.

Hard constraint:

```text
Do not modify original production Fortran source files.
```

Allowed mechanisms:

- native Isca source overlays under `src/extra/local_overrides/`;
- Fortran `iso_c_binding` wrappers;
- C APIs;
- C++ and CUDA modules under `translated/held_suarez/`;
- custom mkmf templates under `src/extra/python/isca/templates/`;
- environment files under `src/extra/env/`;
- `CodeBase.compile()` integration through
  `hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py`.

## Current State

Completed:

- `hs_forcing` module translated to C++;
- `hs_forcing` exposed through C API and Fortran `iso_c_binding`;
- `hs_forcing` CUDA backend implemented as an optional runtime backend;
- native Isca overlay/hybrid build works through `CodeBase.compile()`;
- `held_suarez_hybrid.x` builds and runs;
- 1-day and 30-day hybrid runs completed;
- T85L25 forcing-performance comparison completed;
- next performance-driven target path selected:

```text
fv_advection_mod::a_grid_horiz_advection_3d
PARTIAL GO / Strategy 3
```

Strategy 3 means:

```text
Keep halo/domain/orchestration in Fortran.
Move local finite-volume kernels behind C/C++/CUDA APIs.
```

Selected first kernel:

```text
fv_advection_mod::semi_y_3d
```

## Inventory Strategy Classes

The module inventory is maintained in:

```text
docs/full_cuda_modernization_module_table.md
```

Classification:

```text
A. CUDA candidate now
   Local array loops, no MPI/domain handling, no I/O, good baseline harness candidate.

B. C++ first, CUDA later
   Moderate dependencies, stateful but isolatable, useful for workflow expansion.

C. Keep Fortran wrapper, CUDA inner kernels
   Contains MPI/halo/domain logic, but local computational kernels can be extracted.

D. Keep Fortran permanently for now
   FMS infrastructure, mpp/MPI, NetCDF/I/O, diagnostics, restart, build/system code.

E. External/library strategy
   FFT/spectral transforms better handled by vendor libraries, cuFFT, or broader redesign.
```

## Major Runtime Components

| Component | Source File | Module | Role | Runtime Evidence | CUDA Suitability | Dependency Risk | Proposed Strategy | Validation Strategy |
|---|---|---|---|---|---|---|---|---|
| Held-Suarez forcing | `src/extra/local_overrides/hs_forcing/hs_forcing.F90`, `translated/held_suarez/cpp/forcing_module/`, `translated/held_suarez/cuda/forcing_module/` | `hs_forcing_mod`, `hs_forcing_c_interface` | Newtonian temperature relaxation and Rayleigh drag | T85L25 CPU hybrid 1.031x; forcing about 4.23%; CUDA slowdown | CUDA architecture reference, weak speed target | Low now; completed | Phase 0 freeze | Existing unit/module/wrapper/1-day/30-day/T85 validation |
| Spectral dynamics driver | `src/atmos_spectral/model/spectral_dynamics.F90` | `spectral_dynamics_mod` | Timestep orchestration, transforms, advection, correction, diagnostics | Contains high-runtime regions; mixed profile | Mixed; wrapper/orchestrator only | Very high | Keep Fortran orchestration; overlay timers/wrappers | Whole-model output and timing |
| Finite-volume grid horizontal advection | `src/atmos_spectral/model/fv_advection.F90` | `fv_advection_mod` | Tracer grid advection and local FV kernels | `tracer_grid_horizontal_advection`: 12.04%; `update_tracers`: 17.55% | Strong for local kernels | High for whole routine due to halos/domains | Strategy 3: Fortran wrapper, CUDA local kernels | Unit kernels -> module fixture -> hybrid run |
| `semi_y_3d` | `src/atmos_spectral/model/fv_advection.F90` | private `fv_advection_mod` kernel | Y-direction semi-Lagrangian local update | Part of 12.04% region | High | Low-medium | First CUDA kernel workflow | Standalone baseline, C++/CUDA comparison |
| Other FV kernels | `fv_advection.F90` | private kernels | x/y semi-Lagrangian and Van Leer fluxes | Same measured FV path | High after decomposition | Medium-high | Expand after `semi_y_3d` | Kernel fixtures and captured production fixtures |
| Transform stack | `src/atmos_spectral/tools/transforms.F90`, `spherical*.F90`, `grid_fourier.F90`, `shared/fft/*` | `transforms_mod`, `spherical_mod`, `grid_fourier_mod`, FFT modules | Grid/spectral transforms | Broad transforms about 38.9%; deep transform aggregate about 35.6% | High runtime but algorithmically coupled | Very high | External/library strategy | Transform round-trip tests, vendor-library prototype |
| Pressure/geopotential | `src/atmos_spectral/model/press_and_geopot.F90` | `press_and_geopot_mod` | Pressure and geopotential calculation | Broad `press_geopot`: about 4.8% | Medium-high | Medium-high | Fallback C++ first, CUDA later | Standalone pressure/geopot fixtures |
| `four_in_one` | `src/atmos_spectral/model/spectral_dynamics.F90` | `spectral_dynamics_mod` | Combined dynamics tendency/update routine | about 2.6%, 4320 calls | Moderate | High | Not primary performance target | Defer or workflow-learning only |
| Vertical advection | `src/atmos_shared/vert_advection/vert_advection.F90` | `vert_advection_mod` | Vertical advection for u/v/t/tracers | u+v+t about 0.34% | Kernel-shaped but weak payoff | Medium | Do not target now | Revisit only for L50+ if profile changes |
| Diagnostics/I/O/FMS/mpp | `shared/diag_manager/*`, `shared/fms/*`, `shared/mpp/*` | many | Diagnostics, NetCDF, MPI, domains, reductions | Important infrastructure, not compute target | Low | Very high | Keep Fortran/C permanently for now | Existing model integration tests |

## Performance-Driven Priorities

Use current profiling in this order:

1. Freeze forcing as completed architecture reference.
2. Modernize finite-volume local kernels, beginning with `semi_y_3d`.
3. Expand local FV kernel coverage until the measured
   `tracer_grid_horizontal_advection` region is meaningfully hybridized.
4. Re-evaluate `press_and_geopot` as fallback if FV kernel integration stalls.
5. Study the transform-heavy region separately as a vendor/library redesign,
   not as a direct one-routine translation.
6. Do not prioritize `four_in_one` or `vert_advection_3d` for performance.

## Phase 0: Freeze Forcing CUDA Hybrid

Purpose:

```text
Preserve the completed hs_forcing C++/CUDA hybrid as the reference architecture.
```

Deliverables:

- keep `translated/held_suarez/cpp/forcing_module/`;
- keep `translated/held_suarez/cuda/forcing_module/`;
- keep `src/extra/local_overrides/hs_forcing/`;
- keep `src/extra/python/isca/templates/mkmf.template.hybrid`;
- keep `src/extra/python/isca/templates/mkmf.template.hybrid_cuda`;
- keep `run_compile_hybrid.sh` and CUDA run wrappers.

Files to create or maintain:

- `tests/reports/hs_forcing_cuda_poc_report.md`;
- `docs/T85L25_forcing_performance_results.md`;
- `memory/T85L25_FORCING_PERFORMANCE_CHECKPOINT.md`.

Tests:

- standalone Fortran vs C++ forcing comparison;
- standalone CPU vs CUDA forcing comparison;
- `HS_FORCE_BACKEND=cpu` 1-day and 30-day hybrid runs;
- `HS_FORCE_BACKEND=cuda` smoke and 30-day runs when GPU is visible.

Pass/fail criteria:

- CPU path remains default;
- CUDA path fails clearly if requested but unavailable;
- CPU C++ outputs match reference tolerances;
- CUDA standalone validation passes;
- model produces `atmos_monthly.nc`.

Expected risks:

- CUDA path remains slower due to transfer/allocation overhead.

Rollback plan:

- unset `USE_CUDA_HS_FORCE`;
- use `HS_FORCE_BACKEND=cpu`;
- rebuild with `USE_CUDA_HS_FORCE=0 ./run_compile_hybrid.sh`;
- use original all-Fortran executable for science baseline.

## Phase 1: Complete `semi_y_3d` Workflow

Purpose:

```text
Validate the local finite-volume kernel modernization workflow.
```

Sequence:

```text
Fortran baseline -> C++ -> CUDA -> C API -> Fortran wrapper -> hybrid overlay -> validation
```

Deliverables:

- verified baseline outputs under `tests/fortran_baseline/semi_y_3d/`;
- C++ implementation under `translated/held_suarez/cpp/fv_advection/semi_y_3d/`
  or a shared FV module path;
- CUDA implementation under `translated/held_suarez/cuda/fv_advection/`;
- C API header/source for `semi_y_3d`;
- Fortran `iso_c_binding` wrapper;
- comparison script and report;
- optional overlay that calls the wrapper from a test-only FV path.

Files to create:

```text
translated/held_suarez/cpp/fv_advection/
translated/held_suarez/cuda/fv_advection/
translated/held_suarez/cpp/fv_advection/include/fv_advection_c_api.h
translated/held_suarez/cpp/fv_advection/fortran/fv_advection_c_interface.F90
tests/reports/semi_y_3d_compare_report.json
docs/semi_y_3d_cuda_report.md
```

Tests:

- run baseline harness:

```bash
cd tests/fortran_baseline/semi_y_3d
make FC=mpifort
./test_semi_y_3d
```

- compare C++ against `outputs/output_dq.bin`;
- compare CUDA against C++ and Fortran;
- include positive, negative, and zero `va` cases;
- include synthetic and captured model fixtures when available.

Pass/fail criteria:

- dimensions and binary fixture metadata match;
- max abs/RMSE within tolerance, preferably exact for CPU;
- CUDA within double-precision tolerance;
- no production Fortran source modified.

Expected risks:

- test-only copy may drift from production routine body;
- boundary index assumptions may be incomplete;
- first kernel alone will not produce meaningful whole-model speedup.

Rollback plan:

- keep `semi_y_3d` calls in Fortran;
- remove only overlay/wrapper path from hybrid path_names;
- retain standalone tests for future work.

## Phase 2: Expand FV Local Kernels

Purpose:

```text
Move additional local finite-volume kernels behind validated C++/CUDA APIs.
```

Kernel order:

1. `semi_x_3d`
2. `find_cell_x`
3. `slope_x`
4. `slope_sphere`
5. `vanleer_sphere_3d`
6. `vanleer_x_3d`
7. `integer_flux_x`

Deliverables:

- shared FV C++/CUDA library;
- per-kernel baseline fixtures;
- per-kernel comparison reports;
- cumulative FV kernel API;
- captured production fixtures around `advection_sphere_3d`.

Files to create:

```text
tests/fortran_baseline/fv_advection_kernels/
translated/held_suarez/cpp/fv_advection/
translated/held_suarez/cuda/fv_advection/
tests/reports/fv_advection_kernel_compare_report.json
docs/fv_advection_kernel_cuda_report.md
```

Tests:

- per-kernel synthetic tests;
- realistic captured input tests;
- combined `advection_sphere_3d` fixture tests;
- CPU vs CUDA comparison.

Pass/fail criteria:

- each kernel passes standalone tolerance;
- cumulative local-kernel path matches Fortran `advection_sphere_3d` fixture;
- performance overhead does not dominate kernel runtime.

Expected risks:

- `vanleer_x_3d` and `integer_flux_x` contain branchy periodic logic;
- limiter kernels may be numerically sensitive;
- data layout and halo-ready bounds must be exact.

Rollback plan:

- enable kernels one at a time behind compile-time/runtime switches;
- keep a Fortran fallback for each kernel;
- revert path_names overlay to previous validated subset.

## Phase 3: Hybridize `a_grid_horiz_advection_3d`

Purpose:

```text
Keep domain/halo logic in Fortran while executing local kernels through CUDA.
```

Deliverables:

- overlay for `fv_advection.F90` or a narrower wrapper path;
- Fortran calls to C API only inside local compute sections;
- Fortran-owned halo updates remain untouched;
- cumulative hybrid executable with FV CUDA kernels enabled.

Files to create:

```text
src/extra/local_overrides/fv_advection/fv_advection.F90
translated/held_suarez/cpp/fv_advection/fortran/fv_advection_c_interface.F90
src/extra/python/isca/templates/mkmf.template.hybrid_fv_cuda
docs/fv_advection_hybrid_integration_report.md
```

Tests:

- build through `CodeBase.compile()`;
- 1-day smoke test;
- 30-day T42L25 validation;
- T85L25 validation;
- profile `tracer_grid_horizontal_advection` before/after.

Pass/fail criteria:

- no production Fortran modified;
- `atmos_monthly.nc` dimensions and variables match;
- numerical differences within agreed tolerances;
- measured region time improves or overhead is understood.

Expected risks:

- halo/pole boundary handling may interact with local kernel outputs;
- multiple kernel launches per timestep may introduce overhead;
- GPU memory management must move from per-call allocation to persistent or
  pooled storage if performance matters.

Rollback plan:

- disable FV CUDA path with compile flag/runtime flag;
- fall back to Fortran local kernels in overlay;
- use previous `held_suarez_hybrid.x` forcing-only executable.

## Phase 4: Evaluate `press_and_geopot`

Purpose:

```text
Assess pressure/geopotential as a fallback moderate-performance target.
```

Deliverables:

- feasibility analysis update;
- coarse and deep timers for `press_and_geopot`;
- standalone baseline harness;
- C++ first implementation if isolation is reasonable.

Files to create:

```text
docs/press_and_geopot_feasibility_analysis.md
docs/press_and_geopot_modernization_plan.md
tests/fortran_baseline/press_and_geopot/
translated/held_suarez/cpp/press_and_geopot/
```

Tests:

- pressure/geopotential unit fixtures;
- model-captured column fixtures;
- compare pressure arrays, geopotential, and downstream model outputs.

Pass/fail criteria:

- routine boundary avoids global/MPI side effects;
- C++ output within tolerance;
- expected runtime fraction justifies integration.

Expected risks:

- state coupling and vertical coordinate assumptions;
- downstream sensitivity in dynamics.

Rollback plan:

- keep `press_and_geopot` in Fortran;
- retain only standalone translation artifacts.

## Phase 5: Transform-Heavy Region Study

Purpose:

```text
Treat transforms as a library/redesign project, not direct manual translation.
```

Targets:

```text
transforms_mod
spherical_mod
spherical_fourier_mod
grid_fourier_mod
shared/fft/fft.F90
shared/fft/fft99.F90
```

Deliverables:

- transform benchmark harness;
- grid-to-spectral and spectral-to-grid round-trip tests;
- cuFFT/vendor-library feasibility note;
- GPU data-residency design.

Files to create:

```text
docs/transform_cuda_library_strategy.md
tests/fortran_baseline/transforms/
translated/held_suarez/cpp/transforms/
translated/held_suarez/cuda/transforms/
```

Tests:

- spectral/grid round-trip error;
- conservation/energy diagnostics;
- isolated transform timing;
- model-level 1-day and 30-day validation.

Pass/fail criteria:

- transform numerics stay within spectral tolerance;
- library strategy handles MPI/domain decomposition or clearly scopes around it;
- performance improvement exceeds transfer overhead.

Expected risks:

- highest dependency and algorithm risk;
- distributed spectral transforms may need broader architecture redesign;
- vendor library integration may conflict with FMS/mpp assumptions.

Rollback plan:

- keep transform stack in Fortran;
- use transform study only to guide future GEOS/GPU architecture.

## Phase 6: Cumulative Hybrid Held-Suarez Executable

Purpose:

```text
Build one native Isca executable containing multiple validated CUDA modules.
```

Deliverables:

- cumulative `CodeBase.compile()` target;
- combined C++/CUDA static libraries;
- runtime backend selection;
- consolidated mkmf template;
- module-by-module enable flags.

Possible executable:

```text
held_suarez_cuda_hybrid.x
```

Files to create:

```text
hybrid_experiments/held_suarez_cpp_force/compile_cuda_hybrid.py
src/extra/env/hybrid_cuda
src/extra/python/isca/templates/mkmf.template.full_hybrid_cuda
docs/cumulative_cuda_hybrid_build_report.md
```

Tests:

- build on CPU-only path with CUDA disabled where possible;
- CUDA build inside GPU-capable container;
- 1-day smoke;
- 30-day T42 and T85;
- compare against all-Fortran and forcing-only hybrid.

Pass/fail criteria:

- every module can be enabled/disabled independently;
- failure messages are clear for missing CUDA;
- numerical validation passes at each enablement step;
- performance improves only after enough work is moved to GPU.

Expected risks:

- link-order and runtime library complexity;
- GPU memory ownership across modules;
- duplicated transfer overhead if modules are not fused or data-resident.

Rollback plan:

- use per-module flags to disable new CUDA modules;
- rebuild last known-good forcing-only hybrid;
- keep all-Fortran stock executable as baseline.

## Phase 7: Validation Ladder

Validation must progress in this order for every module or kernel family:

```text
unit -> module -> wrapper -> 1-day -> 30-day -> T85/T170 scaling
```

Unit:

- synthetic deterministic fixtures;
- exact metadata and shape checks;
- max abs/RMSE/relative error.

Module:

- model-captured fixtures;
- compare full routine outputs.

Wrapper:

- Fortran -> C API -> C++/CUDA harness;
- verify Fortran kinds, array order, and pointer lifetimes.

1-day:

- smoke test;
- output file creation;
- no fatal runtime errors.

30-day:

- `atmos_monthly.nc`;
- restart archive;
- compare primary fields.

T85/T170 scaling:

- runtime fraction;
- end-to-end wall-clock;
- speedup vs Fortran and prior hybrid;
- numerical agreement.

Pass/fail criteria:

- no production Fortran modifications;
- every overlay is reversible;
- output variables and dimensions match;
- numerical tolerances documented before integration;
- performance claims based on model MPP runtime and shell real time.

## Modernization Rules

1. Preserve original source.
2. Prefer overlays over direct edits.
3. Use `CodeBase.compile()` rather than manual `mkmf`.
4. Build C++/CUDA libraries inside the same container/architecture as the model.
5. Keep Fortran orchestration around MPI, domains, halos, diagnostics, and I/O.
6. Move only local kernels first.
7. Add one kernel/module at a time.
8. Preserve CPU fallback.
9. Fail clearly when CUDA is requested but unavailable.
10. Record every run with `tee`.

## Immediate Next Action

Resume the selected finite-volume path:

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

Only after these baseline outputs exist should C++ translation of `semi_y_3d`
begin.
