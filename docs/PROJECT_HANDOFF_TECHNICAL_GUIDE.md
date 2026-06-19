# Held-Suarez Modernization Technical Guide

This guide is for a developer entering the project without prior Isca or project
history. It describes the current system, how it is built and validated, and the
constraints that must remain true.

## Repository Structure

### `src/`

The original Isca/FMS Fortran source tree and project-specific integration
support live here.

- `src/atmos_*`: production atmospheric source. Treat this as read-only for this
  project.
- `src/extra/local_overrides/`: non-invasive replacement sources selected by the
  native overlay build.
- `src/extra/env/hybrid/`: mixed-language build environment.
- `src/extra/python/isca/templates/`: linker/compiler templates for CPU and CUDA
  hybrid variants.

Current overlays include forcing, spectral-dynamics profiling, vertical-advection
profiling, standalone `semi_y_3d`, and the FV kernel bundle. The active FV bundle
overlay is `src/extra/local_overrides/fv_advection_kernels/fv_advection.F90`.

### `translated/`

Translated C++, CUDA, headers, C APIs, wrapper harnesses, Makefiles, and fixture
drivers.

Important paths:

```text
translated/held_suarez/cpp/forcing_module/
translated/held_suarez/cuda/forcing_module/
translated/held_suarez/cpp/fv_advection/semi_y_3d/
translated/held_suarez/cuda/fv_advection/semi_y_3d/
translated/held_suarez/cpp/fv_advection/kernels/
translated/held_suarez/cuda/fv_advection/kernels/
```

Static libraries in these trees are build artifacts. They must be rebuilt inside
the target container and architecture before native model linking.

### `hybrid_experiments/`

Native Isca build and runtime integration.

`hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py` is the main
build orchestrator. It defines separate `DryCodeBase` subclasses and executable
names, selects overlay source directories, builds translated static libraries,
and calls Isca `CodeBase.compile()`.

`run_hybrid_held_suarez.py` attaches a prebuilt executable to the original
Held-Suarez namelist, diagnostics, and resolution without changing the original
test case.

### `tests/`

Deterministic baselines and comparison programs.

- `tests/fortran_baseline/`: standalone Fortran fixtures and raw binary inputs and
  outputs.
- `tests/reports/`: machine-readable JSON and human-readable Markdown validation
  results.
- `tests/validate_T85L25_forcing_outputs.py`: general three-way NetCDF comparison
  tool used beyond its original forcing name.
- `tests/compare_hybrid_outputs.py`: earlier model-output comparison utility.

### `scripts/`

Reproducible build-adjacent, run, profile, and validation entry points. Prefer
these scripts over reconstructing long container commands by hand.

### `docs/`

Design decisions, feasibility studies, build diagnoses, experiment plans, and
performance reports. Later dated or architecture-specific reports supersede
early phase reports where they differ.

### `memory/`

Checkpoint documents for session and phase resumption. These preserve why a
decision was made, not only what files exist. Start with
`memory/FINAL_PROJECT_CHECKPOINT_2026-06-19.md`.

### `logs/`

Build, run, profile, and validation logs. Logs are evidence, not generated source.
Do not overwrite a useful comparison run unless the experiment explicitly uses a
new name or an overwrite flag.

### External Isca work and data trees

Builds and model outputs are outside this repository:

```text
GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
```

Executables are under a source-tokenized path below
`$GFDL_WORK/codebase/.../build/`. NetCDF output is under
`$GFDL_DATA/<experiment>/run0001/`.

## Architecture

### Scientific baseline

The original Fortran implementation is the source of truth. A deterministic
standalone harness captures inputs, dimensions, bounds, configuration, and
expected outputs. Raw binary fixture order follows Fortran column-major layout.

### Translation and ABI

The stable integration chain is:

```text
Fortran caller
  -> overlay Fortran module
  -> ISO_C_BINDING wrapper
  -> extern "C" function
  -> CPU C++ implementation or CUDA backend
```

The public Fortran-facing API should remain stable while backend selection and
device ownership evolve behind the C layer.

### Native overlay

The build does not manually invoke `mkmf`. `compile_native_overlay.py` constructs
an Isca `DryCodeBase`, adds custom source directories, removes or shadows the
original source path where required, supplies preprocessor flags, chooses an
`mkmf.template.*`, and calls `CodeBase.compile()`.

Overlay precedence is deliberate. Confirm the generated `path_names` whenever a
new source replacement is introduced. The intended overlay file must appear, and
the production copy must not be compiled into the same executable.

### Runtime backend selection

Forcing:

```bash
export HS_FORCE_BACKEND=cpu   # default
export HS_FORCE_BACKEND=cuda  # explicit; fails if CUDA is unavailable
export HS_PROFILE=1
```

FV kernel CUDA executable:

```bash
export FV_KERNELS_CUDA_MODE=stateless
export FV_KERNELS_CUDA_MODE=persistent
export FV_KERNELS_CUDA_MODE=resident
export FV_KERNELS_PROFILE=1
```

`stateless` remains the fallback. `persistent` reuses allocations. `resident`
uses the broader two-phase boundary around the existing Fortran halo exchange.

## Container Environment

Canonical container:

```text
/lscratch/jli30/isca-sandbox
```

Canonical launch prefix:

```bash
apptainer exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  /lscratch/jli30/isca-sandbox \
  bash -lc '<commands>'
```

Inside the container set:

```bash
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=hybrid
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd "$GFDL_BASE"
```

Preflight checks:

```bash
uname -m
command -v python3 mpifort mpicc nc-config nf-config g++ nvcc
nvidia-smi -L
```

Expected build architecture is `aarch64`. CUDA runs require a visible GPU, not
merely an installed `nvcc`.

## Build Workflow

### Baseline executable

The original test case can compile the stock Isca baseline. To create the
separately named custom baseline through the overlay orchestrator:

```bash
apptainer exec \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  /lscratch/jli30/isca-sandbox \
  bash -lc '
set -e
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=ubuntu_conda
cd "$GFDL_BASE"
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py fortran
'
```

As of this checkpoint, `held_suarez_fortran.x` is not present. Existing stock
all-Fortran output remains valid and should not be rerun without need.

### Forcing CPU hybrid

```bash
USE_CUDA_HS_FORCE=0 ./run_compile_hybrid.sh
```

Expected executable:

```text
.../build/held_suarez_hybrid/held_suarez_hybrid.x
```

### Forcing CUDA-capable hybrid

```bash
USE_CUDA_HS_FORCE=1 NVCC=/usr/local/cuda/bin/nvcc ./run_compile_hybrid.sh
```

CPU and CUDA-capable forcing builds use the same executable name and build
directory. A CUDA-capable binary can select CPU or CUDA at runtime. Do not assume
an old binary's linkage; retain the build log and inspect it.

### FV CPU hybrid

```bash
USE_CUDA_FV_ADVECTION_KERNELS=0 ./run_compile_fv_kernels.sh
```

Expected executable:

```text
.../build/held_suarez_fv_kernels/held_suarez_fv_kernels.x
```

### FV CUDA hybrid

```bash
USE_CUDA_FV_ADVECTION_KERNELS=1 \
NVCC=/usr/local/cuda/bin/nvcc \
./run_compile_fv_kernels.sh
```

Expected executable:

```text
.../build/held_suarez_fv_kernels_cuda/held_suarez_fv_kernels_cuda.x
```

The compile flow removes the old executable after replacing the static library,
forcing `mkmf` to relink. This avoids accidentally testing stale linked code.

## Validation Workflow

Advance only after the current gate passes.

### 1. Fortran fixture

Build and run the standalone test in `tests/fortran_baseline/<target>/`. Confirm
all expected input and output files exist and document dimensions and ordering.

### 2. CPU C++ fixture

Build the translated library and candidate fixture driver. Compare every output
against the Fortran fixture with max absolute error, RMSE, relative error, and
mismatch count.

### 3. CUDA fixture

Run the CUDA comparison for the selected mode. For the current resident bundle:

```bash
cd translated/held_suarez/cpp/fv_advection/kernels
make USE_CUDA_FV_ADVECTION_KERNELS=1 cuda_resident_check
```

Expected report:

```text
tests/reports/fv_advection_kernels_cuda_resident_compare_report.json
```

### 4. Fortran-to-C wrapper

Run CPU and CUDA wrapper checks. These validate array order, scalar types, ABI,
and wrapper behavior separately from the model.

### 5. One-day smoke test

Build the native executable and verify startup, backend marker, MPI completion,
and output creation. Current resident command:

```bash
FV_KERNELS_OVERWRITE=1 scripts/run_fv_kernels_resident_1day.sh
```

One-day runs using `--production-diag` have a 30-day output cadence. Fill values
in such output do not establish numerical agreement. Use the smoke test for
runtime integrity only, or configure a one-day diagnostic cadence.

### 6. Thirty-day model test

```bash
FV_KERNELS_OVERWRITE=1 FV_KERNELS_PROFILE=1 \
  scripts/run_fv_kernels_resident_30day.sh
```

Then validate outside the container if local `xarray`/NetCDF support is present:

```bash
scripts/validate_fv_kernels_resident_30day.sh
```

Authoritative current result:

```text
tests/reports/fv_advection_kernels_resident_30day_model_validation.md
```

### Acceptance metrics

- Dimensions and variables match.
- `temp`, `ucomp`, `vcomp`, and `ps` match at the chosen tolerance.
- Fixture results currently match exactly at `1e-12` tolerances.
- No silent fallback to CPU occurred.
- Logs contain the expected backend/profile markers on all ranks.
- Timing comparisons use identical resolution, levels, timestep, diagnostics,
  MPI rank count, GPU allocation, and overwrite policy.

## Profiling Workflow

### Region profiling

`PROFILE_DYNAMICS_REGIONS` overlays measured major spectral/dynamics regions.
Use `scripts/run_resolution_scaling_profiles.sh` or the documented targets in
`compile_native_overlay.py`. Markers begin with `PROFILE_DYNAMICS_REGION`.

### Deep profiling

`PROFILE_DYNAMICS_DEEP` splits transforms, tracer/update, diagnostics, and
advection call sites. Markers begin with `PROFILE_DYNAMICS_DEEP`.

### Isolated routine profiling

`PROFILE_FOUR_IN_ONE` and `PROFILE_VERT_ADVECTION` established that these
routines were weak individual performance targets. Do not repeat those studies
unless resolution or algorithm changes materially.

### Kernel and CUDA phase profiling

Set `FV_KERNELS_PROFILE=1`. Current markers distinguish backend and phase,
including allocation, H2D, kernel, synchronization, D2H, free/finalization, and
total time. Aggregate across ranks and use maximum-rank time for the critical
path. Also report min/mean/max to expose imbalance.

Never add synchronization solely for a timer without documenting its effect.
Current wrappers already synchronize at their model boundary.

## Current CUDA Architecture

### Stateless CUDA

Each wrapper allocates device buffers, copies inputs, launches a kernel,
synchronizes, copies outputs, and frees buffers. It is the simplest correctness
reference and fallback, but is not viable for model performance.

### Persistent-buffer CUDA

Reusable device buffers are owned in the CUDA/C layer per MPI process. Buffers
resize only when needed and are freed at shutdown. This removes repeated
allocation but retains per-call transfers and synchronization. It improved MPP
runtime only 1.039x versus stateless.

### Broader two-phase resident CUDA

The `resident` mode places a wider computation boundary around the required
Fortran/MPI halo exchange:

```text
pre-halo CUDA work
  -> return q1 to Fortran
  -> mpp_update_domains and polar correction in Fortran
  -> post-halo CUDA work
```

The post-halo Van Leer work shares one tendency upload, device buffer,
synchronization boundary, and download. This mode reduced CUDA crossings and
improved model MPP time 1.172x over persistent, while preserving exact 30-day
results. It remains 4.25x slower than CPU C++ because H2D traffic dominates.

## Important Documents: Recommended Reading Order

1. `memory/FINAL_PROJECT_CHECKPOINT_2026-06-19.md` - current factual restart
   point.
2. `docs/PROJECT_HANDOFF_EXECUTIVE_SUMMARY.md` - purpose, outcomes, and decisions.
3. `docs/PROJECT_HANDOFF_RESUME_GUIDE.md` - next task and exact continuation path.
4. `docs/end_to_end_hybrid_modernization_workflow.md` - reusable translation
   workflow.
5. `docs/fv_advection_cuda_resident_performance_results.md` - latest performance
   result.
6. `docs/fv_advection_cuda_resident_boundary_report.md` - current resident design
   and validation.
7. `docs/fv_advection_cuda_fused_boundary_design.md` - alternatives and rationale
   for the broader boundary.
8. `memory/FV_ADVECTION_KERNEL_BUNDLE_CHECKPOINT.md` - kernel-bundle state before
   residency work.
9. `memory/PERFORMANCE_MODERNIZATION_CHECKPOINT_2026-06-18.md` - profiling-driven
   target selection.
10. `docs/fv_advection_kernel_bundle_translation_report.md` - translated kernels
    and native integration.
11. `docs/fv_advection_kernel_bundle_performance_results.md` - stateless CPU/CUDA
    baseline.
12. `docs/fv_advection_cuda_persistent_performance_results.md` - persistent-buffer
    result.
13. `docs/fv_advection_cuda_microbenchmark_results.md` - unit-level overhead
    evidence.
14. `docs/dynamics_deep_profile_recommendation.md` - hotspot evidence leading to
    FV advection.
15. `docs/a_grid_horiz_advection_3d_feasibility_analysis.md` - chosen hybrid
    boundary.
16. `docs/fv_advection_kernel_modernization_plan.md` - local-kernel dependency and
    ranking plan.
17. `docs/T85L25_forcing_performance_results.md` - forcing performance and Amdahl
    result.
18. `memory/T85L25_FORCING_PERFORMANCE_CHECKPOINT.md` - forcing experiment restart
    details.
19. `docs/isca_overlay_strategy.md` - source precedence and native build mechanics.
20. `docs/full_held_suarez_cuda_modernization_master_plan.md` - longer-range module
    roadmap.

Use `docs/PROJECT_FILE_INDEX.md` for a broader searchable catalog.

## Known Pitfalls

### Container and Python environment

Running project scripts directly on the host can fail with missing `isca`,
`jinja2`, MPI, or NetCDF dependencies. Build and model execution belong inside
the Isca container. NetCDF comparison can run on the host when `xarray` and a
NetCDF backend are installed.

### Architecture mismatch

The production container is `aarch64`. A static library built on x86_64 causes
`ld` to skip it as incompatible. Build C++ and CUDA libraries inside the same
container used for final linking.

### CUDA compiler versus GPU visibility

`nvcc` present does not mean a GPU is visible. Use `apptainer exec --nv` and
check `nvidia-smi -L`. Explicit CUDA selection must fail clearly rather than
silently use CPU.

### MPI rank-to-GPU mapping

Sixteen ranks sharing one GPU can make timings misleading. Record node, visible
devices, rank count, and mapping. Compare runs under identical allocation.

### NetCDF dependencies

`xarray` needs `netCDF4`, `h5netcdf`, or another compatible backend. A Python
environment with `xarray` alone may fail to open model files.

### Overlay mechanics

- Do not edit production `src/atmos_*` sources.
- Ensure `path_names` contains the overlay and not both overlay and original.
- A private Fortran routine may require a test-only copy or wrapper for fixture
  generation.
- Keep `USE` statements before declarations.
- Avoid duplicate included helper bodies.
- Relink after replacing a static library; an up-to-date executable can otherwise
  hide new code.

### Build templates and link order

Mixed C++/Fortran builds require the correct hybrid template and `-lstdc++`.
CUDA builds also require CUDA runtime search paths and correct library order.
Use the existing templates; do not reimplement the build with manual `mkmf`.

### Diagnostics cadence

Production monthly output is written every 30 days. A one-day production-diag run
may contain fill values. Successful file creation is not proof of numerical
agreement.

### Stale checkpoints

Early build-phase documents describe blockers that have since been solved. Use
the dated final checkpoint and latest performance reports as authority, then use
old documents for historical diagnosis only.

## Non-Negotiable Practices

- Preserve the all-Fortran baseline.
- Keep public ABI changes minimal and explicit.
- Add runtime switches for experimental backends and retain a fallback.
- Validate before profiling; profile before selecting a translation target.
- Store logs and reports with unique experiment names.
- Report both model MPP runtime and shell real time.
- Do not claim GPU speedup from kernel-only timing when transfer and model runtime
  disagree.
