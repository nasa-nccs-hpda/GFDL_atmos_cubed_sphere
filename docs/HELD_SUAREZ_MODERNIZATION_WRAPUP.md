# Held-Suarez Fortran-to-C++/CUDA Modernization Exercise Summary

Date: 2026-08-05

## Executive Summary

This exercise used the Held-Suarez atmospheric model in Isca as a prototype for
incremental Fortran modernization toward future GEOS GPU portability.

The main workflow tested was:

```text
Fortran model
-> Fortran ISO_C_BINDING wrapper
-> C API
-> C++ implementation
-> optional CUDA backend
-> native Isca source overlay
-> hybrid executable through CodeBase.compile()
```

The modernization workflow succeeded technically. We translated and validated
the Held-Suarez forcing module, then moved to performance-driven FV advection
kernels. The hybrid executables built through the native Isca build system, ran
1-day and 30-day simulations, and produced validated NetCDF output.

The performance conclusion is more nuanced. The project demonstrated a reliable
translation and integration method, but small isolated kernels did not deliver
end-to-end speedup. CUDA correctness was achievable; performance depended on
choosing a sufficiently broad computational boundary and avoiding repeated
CPU/GPU data movement. Later profiling showed that spectral transforms dominate
T85 runtime, but the largest transform cost is distributed transpose/MPI
communication rather than FFT alone.

The strongest outcome is a reusable modernization playbook:

```text
profile first
choose a meaningful computational boundary
preserve production Fortran with overlays
build baseline harnesses
translate incrementally
validate at every layer
measure performance with matrix experiments
```

## Project Motivation

The long-term motivation is GEOS modernization:

- improve GPU portability;
- establish a safe AI-assisted translation workflow;
- identify where C++/CUDA replacement is useful;
- preserve scientific correctness while changing implementation language;
- avoid disruptive rewrites of production Fortran.

Held-Suarez was selected as a tractable prototype. It exercises real model
build, runtime, MPI, diagnostics, spectral dynamics, forcing, and advection
paths, but is smaller and easier to validate than the full GEOS system.

## Scope

The exercise covered:

- Held-Suarez forcing module translation;
- C++ and CUDA forcing backends;
- native Isca overlay builds;
- FV advection local kernel translation;
- FV CUDA stateless, persistent, resident, and broad `a_grid` boundary modes;
- multi-GPU mapping experiments;
- broad and deep dynamics profiling;
- spectral transform wrapper profiling;
- resolution/GPU/duration performance matrix setup.

The exercise intentionally did not:

- modify production Fortran source files directly;
- rewrite the full model;
- port the full spectral transform stack to GPU;
- redesign MPI/domain decomposition;
- claim speedup without NetCDF validation and runtime evidence.

## Modernization Workflow Demonstrated

The workflow that proved most reliable was:

1. Map the original Fortran code and dependencies.
2. Select a routine or module boundary.
3. Build a standalone Fortran baseline harness.
4. Write deterministic input/output fixtures.
5. Translate the routine to C++.
6. Compare Fortran and C++ outputs.
7. Add a stable C API.
8. Add a Fortran `ISO_C_BINDING` wrapper.
9. Build through native Isca `CodeBase.compile()`.
10. Use overlays to replace source files without touching production source.
11. Run a 1-day smoke test.
12. Run a 30-day model test.
13. Compare NetCDF outputs.
14. Profile runtime contribution.
15. Only then decide whether CUDA optimization is worth expanding.

This ladder was essential. It avoided large, ambiguous failures and made each
layer debuggable.

## Major Milestones

### Held-Suarez Forcing

The Held-Suarez forcing module was translated to C++ and integrated through:

```text
Fortran -> ISO_C_BINDING -> C API -> C++
```

A CUDA backend was also added behind a runtime switch. The forcing module was
validated through standalone tests, wrapper tests, hybrid executable builds,
1-day runs, and 30-day runs.

Performance profiling showed that forcing is too small to justify CUDA for
end-to-end speedup. It remains valuable as a clean architecture prototype.

### FV Advection Kernels

The next performance-driven target was the FV advection path:

```text
fv_advection_mod::a_grid_horiz_advection_3d
```

The selected strategy was to keep domain/halo/MPI handling in Fortran and move
local finite-volume kernels behind a C/CUDA boundary.

Translated and validated kernel work included:

- `semi_y_3d`
- `semi_x_3d`
- `slope_x`
- `slope_sphere`
- `vanleer_x_3d`
- `vanleer_sphere_3d`
- `integer_flux_x`
- `find_cell_x`

Correctness passed at the fixture level and through model-level validation.

### CUDA FV Architecture

Several CUDA modes were implemented:

- stateless: allocate/copy/run/copy/free every call;
- persistent: reuse allocations;
- resident: keep selected buffers live across phases;
- broad `a_grid` resident boundary: move a larger local advection region behind
  the CUDA boundary.

The broad boundary dramatically reduced data-transfer overhead compared with
fine-grained CUDA calls, but current tested configurations still did not beat
the CPU baseline.

### Transform Profiling

T85L25 profiling showed transforms are a major runtime region. Deep profiling
split the transform path into top-level, FFT/Legendre, and wrapper timers.

Important result:

```text
T85L25 30-day, 16 ranks:
Total runtime:                 ~306.7 s
Transform non-overlap total:   ~180.7 s
FFT total:                      ~15.1 s
Legendre total:                 ~60.6 s
Wrapper/transpose gap:         ~105.0 s
```

The wrapper gap is dominated by distributed transpose/MPI communication and
synchronization. Therefore, porting only FFT or Legendre is not enough for a
strong transform speedup.

## Validation Summary

Validation proceeded through:

- routine-level fixture comparisons;
- Fortran baseline harnesses;
- C++ standalone comparisons;
- CUDA standalone comparisons;
- Fortran-to-C API-to-C++ comparisons;
- native hybrid executable smoke tests;
- 30-day model runs;
- NetCDF comparisons of model output.

This produced a useful rule:

```text
Do not optimize a translated kernel until it has passed the validation ladder.
```

Known remaining validation gaps:

- remaining T170/T340 matrix outputs are incomplete;
- 16-GPU model runs are launcher/infrastructure blocked;
- transform GPU implementation has not been started;
- arbitrary matrix-output validation should be automated more cleanly.

## Build And Integration Lessons

The biggest build-system lesson was:

```text
Use CodeBase.compile(), not manual mkmf.
```

Manual `mkmf` experiments were useful diagnostically, but the reliable path was
to use Isca's native build system and inject changes through source overlays.

Other build lessons:

- Keep original source untouched.
- Use overlay directories for modified Fortran wrappers.
- Build C++/CUDA libraries inside the same container and architecture used by
  the model.
- Keep CPU fallbacks available.
- Add runtime backend switches instead of hard-coding backends.
- Keep compile logs and runtime logs separate.
- Use clear executable names and experiment names.
- Treat `path_names`, mkmf templates, and library link order as first-class
  integration artifacts.

## Code Translation Lessons

Translation was most successful for routines with:

- local array loops;
- deterministic inputs and outputs;
- limited module global state;
- no MPI/domain ownership;
- no I/O;
- simple derived-type dependencies.

Translation became riskier when routines included:

- halo exchange;
- domain decomposition;
- spectral transforms;
- implicit global state;
- diagnostics;
- restart/I/O behavior.

Important practical lessons:

- Build the Fortran baseline harness first.
- Document Fortran array ordering explicitly.
- Preserve public Fortran/C APIs where possible.
- Translate small routines to learn, but choose broad boundaries for speed.
- Use exact or near-exact comparisons before integrating into the model.
- Keep wrapper boundaries stable until correctness is proven.

## CUDA Architecture Lessons

The project confirmed that correct CUDA is not the same as useful CUDA.

Fine-grained CUDA wrappers were slow because each call paid for:

- allocation;
- host-to-device copy;
- kernel launch;
- synchronization;
- device-to-host copy;
- free.

Persistent buffers reduced allocation overhead but did not solve data motion.
Broader resident boundaries reduced transfer overhead substantially, but the
rest of the model remained CPU-resident, so each boundary still had to cross
CPU/GPU memory space.

The main CUDA architecture lesson is:

```text
Move data residency up the call tree.
```

For future work, the useful boundary is unlikely to be one small kernel. It is
more likely to be a full local update region or a multi-operation timestep
subregion where data can stay resident across many operations.

## Profiling Lessons

Profiling changed the target selection several times:

- Held-Suarez forcing was correct but too small for speedup.
- `four_in_one` was measurable but not large enough as an isolated target.
- `vert_advection_3d` was too small.
- FV advection was useful for CUDA architecture experiments.
- Spectral transforms dominate T85 runtime, but mostly through distributed
  transpose/MPI wrapper cost.

The lesson for GEOS is clear:

```text
Do not choose translation targets from code intuition alone.
Profile first, then translate.
```

## Performance Summary

### Forcing Module

The forcing CUDA path is validated but has negligible expected end-to-end
speedup impact. It should be treated as an interface and architecture prototype.

### FV Advection CUDA

The FV CUDA path is correct and increasingly architecture-aware, but current
tested cases do not yet beat the CPU baseline.

Performance matrix logs currently support this clean matrix:

```text
T42L25 and T85L25
x 30, 60, 90, 120 days
x fortran_16cpu, fv_cuda_a_grid_1gpu, fv_cuda_a_grid_4gpu
```

T170 is a partial extension:

```text
T170L25 fortran_16cpu: 30, 60, 90 complete
T170L25 fv_cuda_a_grid_1gpu: 30, 60, 90 complete
T170L25 fv_cuda_a_grid_4gpu: 30 complete but outlier
T170L25 fv_cuda_a_grid_4gpu: 60 partial/time-limit
```

Important current observations:

- T42 CUDA is slower than Fortran.
- T85 CUDA is still slower, though the gap narrows.
- T170 1-GPU is close to Fortran but not faster in current logs.
- T170 4-GPU 30-day completed but is a severe outlier.
- 16-GPU runs are not yet reliable because of launcher/MPI/container issues.

The performance-analysis workspace is:

```text
performance_analysis/
```

It contains:

```text
performance_analysis/parse_matrix_logs.py
performance_analysis/fv_matrix_figures.ipynb
performance_analysis/data/matrix_runs.csv
performance_analysis/data/matrix_runs.json
performance_analysis/data/matrix_completion.csv
```

Recommended figures:

- completion matrix;
- MPP runtime heatmaps;
- speedup vs Fortran heatmaps;
- runtime per simulated day;
- CUDA phase stacked bars;
- 30-day resolution scaling.

## Current Artifacts

Important source and integration files:

```text
hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py
src/extra/local_overrides/hs_forcing/hs_forcing.F90
src/extra/local_overrides/fv_advection_kernels/fv_advection.F90
src/extra/local_overrides/transforms_top/
translated/held_suarez/cpp/forcing_module/
translated/held_suarez/cuda/forcing_module/
translated/held_suarez/cpp/fv_advection/
translated/held_suarez/cuda/fv_advection/
```

Important run/analysis scripts:

```text
scripts/prepare_matrix_case.sh
scripts/run_matrix_case.sh
scripts/run_matrix_sweep.sh
build_sandbox.sh
performance_analysis/parse_matrix_logs.py
```

Important documents:

```text
docs/READ_THIS_FIRST.md
docs/PROJECT_HANDOFF_EXECUTIVE_SUMMARY.md
docs/PROJECT_HANDOFF_TECHNICAL_GUIDE.md
docs/PROJECT_HANDOFF_RESUME_GUIDE.md
docs/fv_matrix_experiment_completion_status.md
docs/fv_resolution_gpu_experiment_plan.md
docs/T85L25_transforms_top_profile_recommendation.md
docs/transform_gpu_architecture_analysis.md
```

## Open Issues

Current unresolved items:

- 16-GPU runs are blocked by MPI/container launcher reliability.
- `T170L25/fv_cuda_a_grid_4gpu/30day` is a completed but suspicious outlier.
- `T170L25/fv_cuda_a_grid_4gpu/60day` hit the time limit.
- No `T340L25` matrix data has been collected yet.
- Transform GPU conversion has not been implemented.
- Validation scripts should be generalized for arbitrary matrix cases.
- Multi-node GPU launch needs a cluster-supported recipe before large matrix
  runs should rely on it.

## Recommendations For GEOS Code Conversion

If applying this workflow to GEOS, start with profiling and boundary selection,
not translation.

Recommended approach:

1. Profile representative GEOS cases before choosing targets.
2. Rank targets by measured runtime, array intensity, call frequency, and
   isolation risk.
3. Avoid tiny kernels as performance targets unless they are part of a broader
   resident region.
4. Preserve production Fortran initially with overlays, wrappers, and C APIs.
5. Build Fortran baseline harnesses before translating.
6. Use stable C interfaces around computational boundaries.
7. Keep MPI/domain/halo ownership explicit.
8. Move data residency up the call tree.
9. Add CUDA only after CPU C++ correctness is proven.
10. Validate progressively from unit tests to full-model outputs.
11. Measure performance with resolution and duration matrices, not one-off runs.

Best early GEOS candidates should have:

- large repeated array loops;
- limited I/O;
- limited MPI ownership;
- clear inputs and outputs;
- strong runtime contribution;
- enough computation per call to amortize GPU overhead.

Avoid starting with:

- diagnostics;
- restart/I/O;
- tiny physics helpers;
- routines dominated by MPI communication;
- transform libraries without a communication/layout plan.

## Recommended Next Steps

Short term:

1. Generate and review the six performance figures in `performance_analysis/`.
2. Validate the completed T170 outputs.
3. Decide whether to rerun or exclude the T170 4-GPU outlier.
4. Decide whether T340 is worth the queue cost.
5. Mark 16-GPU as infrastructure-blocked until a reliable launcher is available.

Medium term:

1. Generalize matrix validation scripts.
2. Improve matrix plot/report automation.
3. Explore broader CPU/GPU residency boundaries if continuing FV work.
4. Evaluate whether transform work should remain CPU-side unless GPU-aware
   distributed transpose support is available.

For GEOS:

1. Run a profiling-first candidate selection phase.
2. Select one high-runtime, low-I/O, array-heavy target.
3. Reuse the validation ladder proven here.
4. Treat CUDA performance as a data-residency and communication-design problem,
   not only a kernel translation problem.

## Final Takeaway

This exercise proved that incremental AI-assisted Fortran modernization can be
done safely when it is wrapped in strong validation and native build-system
integration.

The biggest technical lesson is that translation is not the hard part by
itself. The hard part is choosing the right computational boundary. Correct
C++/CUDA kernels are useful only when the boundary is large enough to amortize
data motion, preserve model semantics, and interact cleanly with MPI/domain
decomposition.
