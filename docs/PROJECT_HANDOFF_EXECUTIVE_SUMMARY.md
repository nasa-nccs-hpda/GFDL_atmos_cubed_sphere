# Held-Suarez CUDA Modernization: Executive Handoff

Date: 2026-06-19
Branch: `perf/cuda-data-residency`

## Project Motivation

This project is a controlled prototype for modernizing legacy atmospheric-model
code toward C++ and GPU execution. The long-term motivation is future GEOS
modernization: establish a repeatable, evidence-driven method for translating
Fortran numerical kernels while preserving scientific behavior, MPI boundaries,
and the trusted production implementation.

Held-Suarez in Isca was selected as the prototype because it is a complete
atmospheric model with realistic build, runtime, diagnostics, and MPI behavior,
but is compact enough to investigate end to end. The work tests more than source
translation. It tests the full operational path:

```text
Fortran model
  -> ISO_C_BINDING wrapper
  -> stable C ABI
  -> C++ or CUDA implementation
  -> native Isca CodeBase.compile() build
  -> MPI model execution and NetCDF validation
```

The governing constraint has been maintained throughout: original production
Fortran source files are not edited. All integration is performed with source
overlays, wrappers, separate libraries, and separately named executables.

## Major Achievements

### A reusable modernization workflow now exists

The project has demonstrated the complete translation and validation ladder:

1. Map the source and runtime call path.
2. Write a translation specification.
3. Capture a deterministic Fortran baseline fixture.
4. Implement and compare a standalone C++ version.
5. Add a stable C API and Fortran `ISO_C_BINDING` wrapper.
6. Add an optional CUDA backend without changing the Fortran-facing ABI.
7. Replace source through an Isca overlay and build with `CodeBase.compile()`.
8. Validate at unit, wrapper, one-day, and 30-day model levels.
9. Profile before choosing the next performance target.

This workflow was first proven with the Held-Suarez forcing module and then
extended to finite-volume advection kernels.

### Held-Suarez forcing modernization is complete

The forcing module was translated to CPU C++, exposed through a C API, integrated
through a Fortran wrapper, and compiled through the native Isca build. An optional
CUDA backend was also implemented. The CPU and CUDA hybrid executable completes
one-day and 30-day runs. T85L25 runs compared all-Fortran, CPU C++, and CUDA under
matching model settings.

The forcing work is an architecture success, but not a strong GPU speed target.
At T85L25, forcing represented only about 4.23% of baseline runtime. CPU C++ gave
a small 1.031x model speedup. Fine-grained CUDA transfers and synchronization made
the CUDA version slower than both Fortran and CPU C++.

### Performance profiling redirected the project to dynamics

Broad T42L25 profiling found the following approximate runtime contributions:

| Region | Approximate model runtime |
|---|---:|
| Transform-heavy region | 38.9% |
| Tracer/correction/diagnostic region | 32.6% |
| `update_tracers` | 17.6% |
| Tracer grid horizontal advection | 12.0% |
| Advection aggregate | 7.9% |
| Pressure/geopotential | 4.8% |
| `four_in_one` | 2.6% |
| `vert_advection_3d` | 0.34% |

This evidence prevented investment in attractive but low-impact isolated
routines. The selected path became `fv_advection_mod::a_grid_horiz_advection_3d`,
using a hybrid boundary: keep MPI, halo, and domain logic in Fortran; move local
finite-volume loops to C++/CUDA.

### FV advection kernels are translated and validated

The following kernels have standalone Fortran fixtures, C++ implementations,
CUDA implementations, C interfaces, wrapper tests, and native overlay coverage:

- `semi_y_3d`
- `semi_x_3d`
- `slope_x`
- `slope_sphere`
- `vanleer_x_3d`
- `vanleer_sphere_3d`
- `integer_flux_x`
- `find_cell_x`

Standalone and wrapper comparisons are exact for the tested fixtures. CPU and
CUDA FV overlay executables build and run. Thirty-day model output for the latest
resident CUDA boundary agrees exactly with all-Fortran and CPU C++ for `temp`,
`ucomp`, `vcomp`, and `ps`.

### CUDA architecture evolved based on measurement

Three CUDA execution modes were evaluated:

1. **Stateless:** allocate, copy, launch, synchronize, copy back, and free on each
   fine-grained call.
2. **Persistent buffers:** allocate reusable device buffers once per MPI process,
   but retain per-call host/device transfers.
3. **Two-phase resident boundary:** combine pre-halo work and post-halo work into
   broader CUDA regions while preserving the Fortran/MPI halo exchange between
   phases.

The resident design is the first architecture change to produce a material,
repeatable CUDA improvement, although it is still slower than CPU C++.

## Key Performance Results

### T85L25 forcing study, 30 days, 16 MPI ranks

| Variant | MPP runtime | Shell real | Speedup vs Fortran |
|---|---:|---:|---:|
| All-Fortran | 206.761 s | 214.209 s | 1.000x |
| CPU C++ forcing | 200.475 s | 207.580 s | 1.031x |
| CUDA forcing POC | 320.956 s | 328.019 s | 0.644x |

The forcing-only Amdahl ceiling was about 1.044x. The CPU implementation captured
most of the available opportunity. CUDA was dominated by transfer, launch,
allocation, and synchronization overhead.

### T42L25 FV kernel-bundle study, 30 days, 16 MPI ranks

| Backend | MPP runtime | Shell real | Relative to CPU C++ |
|---|---:|---:|---:|
| CPU C++ | 25.546 s | 28.987 s | 1.00x |
| Stateless CUDA | 132.355 s | 136.048 s | 5.18x slower |
| Persistent CUDA, mean of two runs | 127.173 s | 130.987 s | 4.98x slower |
| Two-phase resident CUDA | 108.505 s | 112.266 s | 4.25x slower |

Resident CUDA improved MPP time by 1.220x versus stateless and 1.172x versus
persistent. The result is outside timing noise: persistent repeat variability was
only 0.33%. The broader boundary reduced model-facing CUDA calls by 33.3%, H2D
time by 15.7%, and measured CUDA-region time by 20.9%.

The remaining problem is clear. On the slowest resident rank, H2D transfer is
71.7% of the measured CUDA region, and the measured CUDA region is roughly 66%
of model MPP runtime. More isolated kernels will not solve this.

## Current Status

- The original production Fortran tree remains untouched.
- The forcing CPU/CUDA hybrid path is complete and validated.
- The FV kernel bundle is translated and exactly validated through 30-day runs.
- Stateless, persistent-buffer, and two-phase resident CUDA modes remain
  available as comparison and rollback paths.
- The resident architecture is validated but is not yet a performance win over
  CPU C++.
- The active branch is `perf/cuda-data-residency`.
- The worktree has one untracked directory, `end2end_experiment/`; it was not
  inspected or modified as part of this handoff.
- Hybrid executables are currently present in the Isca work tree. The custom
  `held_suarez_fortran.x` build artifact is not currently present; the stock
  all-Fortran output remains available as the scientific baseline.

## Major Findings

1. **Translation correctness is tractable.** Deterministic fixtures, exact binary
   comparisons, and staged model validation have kept numerical risk controlled.
2. **The integration boundary determines GPU performance.** Fine-grained CUDA
   wrappers are correct but structurally slow.
3. **Persistent allocation is necessary but insufficient.** It improved the model
   by only about 3.9%; per-call H2D remained dominant.
4. **Broader residency works.** The two-phase boundary delivered a reproducible
   17.2% speedup over persistent CUDA while retaining the Fortran MPI halo step.
5. **Profiling must precede translation.** `four_in_one` and vertical advection
   looked central in the source but were weak measured targets.
6. **Transforms are important but need a library strategy.** Their runtime share
   is high, but direct line-by-line translation is unlikely to be the right path;
   cuFFT, vendor libraries, or a broader redesign should be evaluated separately.

## Recommended Future Direction

The immediate recommendation is to extend the existing two-phase resident FV
boundary with the already translated `semi_y_3d` CUDA operation. Upload `q` once,
reuse it for `semi_x_3d` and `semi_y_3d`, form and retain `q2` on device, and keep
only the required `q1` exchange through the existing Fortran/MPI halo path. This
is the highest-value next experiment because it reduces another full-field H2D
transfer without translating new physics.

After that result is validated and measured:

1. Evaluate transferring only `q1` halo slabs rather than the full field.
2. Move toward `update_tracers`-level device residency across multiple local
   kernels.
3. Repeat at T85L25 and T170L25 to test whether larger local domains amortize GPU
   overhead.
4. Run a separate transform-library feasibility study.

The project should not add more isolated CUDA wrappers unless they participate in
a broader resident region.

## Risks

- H2D traffic may remain dominant until model state stays resident across more of
  the timestep.
- Sixteen MPI ranks may contend for limited GPU resources; rank-to-device mapping
  must be explicit in performance studies.
- Halo and array-bound semantics are easy to damage when broadening the boundary.
- T42 results may understate GPU potential, while T85/T170 increase memory and
  queue requirements.
- One-day production diagnostics use a 30-day cadence and can contain fill values;
  they must not be treated as numerical validation.
- Builds are container- and architecture-dependent (`aarch64`, MPI, NetCDF,
  CUDA). Host-built static libraries are not portable into the container build.
- The project has extensive manual validation but no single automated CI pipeline
  covering container build, GPU execution, and NetCDF comparison.

## Estimated Next Milestones

These are engineering estimates, excluding batch-queue delays and container/GPU
availability.

| Milestone | Estimated effort | Exit criterion |
|---|---:|---|
| Integrate `semi_y_3d` into resident pre-halo phase | 3-5 developer days | Standalone and wrapper tests exact |
| Native build, one-day, and 30-day validation | 2-4 developer days | NetCDF exact; no fallback used |
| Repeat timing and architecture decision | 1-2 developer days | Reproducible speedup/slowdown measured |
| `q1` halo-only transfer prototype | 1-2 weeks | Exact 30-day output and lower H2D time |
| T85/T170 FV scaling study | 3-5 developer days | Comparable validated timing matrix |
| `update_tracers` residency prototype | 3-6 weeks | Stable broader API and model validation |
| Transform vendor-library study | 4-8 weeks | Feasibility, correctness, and cost decision |

The detailed continuation path is in
`docs/PROJECT_HANDOFF_RESUME_GUIDE.md`; implementation mechanics are in
`docs/PROJECT_HANDOFF_TECHNICAL_GUIDE.md`.
