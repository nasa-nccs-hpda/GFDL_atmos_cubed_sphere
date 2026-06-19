# Read This First

Date: 2026-06-19
Branch at handoff: `perf/cuda-data-residency`

## What This Project Is

This repository uses Held-Suarez in Isca as a prototype for future GEOS
modernization. The objective is to move selected Fortran numerical work through
C++ and CUDA without changing the trusted production Fortran source tree.

The proven integration path is:

```text
Fortran model
  -> overlay Fortran source
  -> ISO_C_BINDING wrapper
  -> stable C ABI
  -> CPU C++ or CUDA backend
  -> native Isca CodeBase.compile()
  -> hybrid executable
```

**Non-negotiable rule:** do not modify original production files under
`src/atmos_*`. Use `src/extra/local_overrides/`, wrappers, translated modules,
and separate executables.

## Current State

### Completed and validated

- Held-Suarez forcing translated to CPU C++ and CUDA.
- Forcing C API, Fortran wrapper, native overlay, and 30-day runs completed.
- Runtime profiling completed from broad dynamics regions down to local kernels.
- FV advection selected as the performance path.
- These local FV kernels are translated and fixture-validated:
  `semi_y_3d`, `semi_x_3d`, `slope_x`, `slope_sphere`, `vanleer_x_3d`,
  `vanleer_sphere_3d`, `integer_flux_x`, and `find_cell_x`.
- CPU, stateless CUDA, persistent-buffer CUDA, and broader resident CUDA paths
  have been built and tested.
- The latest two-phase resident CUDA boundary completed a 30-day T42L25 run.
- Its `temp`, `ucomp`, `vcomp`, and `ps` outputs agree exactly with the
  all-Fortran and CPU C++ outputs.

### Key performance results

T85L25 forcing, 30 days, 16 MPI ranks:

| Variant | MPP runtime | Result vs Fortran |
|---|---:|---:|
| Fortran | 206.761 s | baseline |
| CPU C++ forcing | 200.475 s | 1.031x faster |
| CUDA forcing | 320.956 s | 0.644x; slower |

Forcing is a successful architecture prototype, not a useful isolated CUDA
speed target.

T42L25 FV bundle, 30 days, 16 MPI ranks:

| Backend | MPP runtime | Result |
|---|---:|---|
| CPU C++ | 25.546 s | current fastest |
| Stateless CUDA | 132.355 s | 5.18x slower than CPU |
| Persistent CUDA mean | 127.173 s | 1.039x faster than stateless |
| Resident CUDA | 108.505 s | 1.172x faster than persistent |

The resident boundary is a real improvement, but remains 4.25x slower than CPU
C++. Host-to-device transfer is now the main bottleneck: about 71.7% of the
slowest rank's measured CUDA region.

## The Decision That Matters

Do not translate more isolated kernels yet. Fine-grained CUDA calls are already
proven correct and proven slow. Performance now depends on keeping data resident
and widening the CUDA boundary while preserving the Fortran/MPI halo exchange.

The next task is to integrate the already translated CUDA `semi_y_3d` into the
current resident pre-halo phase:

1. Upload `q` once for both `semi_x_3d` and `semi_y_3d`.
2. Upload `va` and `dyy` in the same phase.
3. Form and retain `q2` on the device.
4. Export `q1` for the existing Fortran/MPI halo exchange.
5. Import corrected `q1`, run post-halo Van Leer work, and download the final
   tendency once.
6. Preserve stateless, persistent, and current resident modes as fallbacks.

This is an architecture change, not a new physics translation.

## Start Here

```bash
cd /explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
git branch --show-current
git status --short
```

At handoff, the branch was `perf/cuda-data-residency` and the only unrelated
worktree item was the untracked `end2end_experiment/` directory. Do not remove or
adopt it without checking its ownership.

Read these next only as needed:

1. `memory/FINAL_PROJECT_CHECKPOINT_2026-06-19.md` - exact restart state.
2. `docs/fv_advection_cuda_resident_performance_results.md` - latest result.
3. `docs/fv_advection_cuda_resident_boundary_report.md` - current design.
4. `docs/PROJECT_HANDOFF_TECHNICAL_GUIDE.md` - build and validation commands.
5. `docs/PROJECT_FILE_INDEX.md` - searchable artifact catalog.

Files central to the next implementation:

```text
src/extra/local_overrides/fv_advection_kernels/fv_advection.F90
translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu
translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.h
translated/held_suarez/cpp/fv_advection/kernels/
translated/held_suarez/cuda/fv_advection/semi_y_3d/
hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py
```

## Validation Ladder

Run inside the CUDA-enabled Isca container unless noted otherwise:

```bash
cd translated/held_suarez/cpp/fv_advection/kernels
make USE_CUDA_FV_ADVECTION_KERNELS=1 cuda_resident_check

cd "$GFDL_BASE"
USE_CUDA_FV_ADVECTION_KERNELS=1 \
NVCC=/usr/local/cuda/bin/nvcc \
./run_compile_fv_kernels.sh
```

Then use a **new experiment name** for the extended boundary so the accepted
resident reference is not overwritten. Run, in order:

1. standalone CUDA fixture comparison;
2. Fortran-to-C-to-CUDA wrapper comparison;
3. native overlay build;
4. one-day smoke test and backend-marker check;
5. 30-day model run;
6. host-side NetCDF comparison;
7. repeat timing to establish noise.

The current reference commands are:

```bash
scripts/run_fv_kernels_resident_1day.sh
scripts/run_fv_kernels_resident_30day.sh
scripts/validate_fv_kernels_resident_30day.sh
```

Copy or parameterize them for the new experiment instead of overwriting the
existing result.

## Important Traps

- Use Isca `CodeBase.compile()`; do not reconstruct manual `mkmf` builds.
- Build C++/CUDA libraries inside the same `aarch64` container used for linking.
- `nvcc` availability does not prove GPU visibility; check `nvidia-smi -L`.
- Record MPI-rank-to-GPU mapping in every performance experiment.
- A one-day run with production monthly diagnostics may contain fill values. It
  proves startup, not numerical agreement.
- Relink the model after replacing a static library; stale executables can hide
  new code.
- Never silently fall back to CPU when CUDA was explicitly requested.
- Compare model MPP runtime and shell real time, not kernel time alone.

## Definition Of Success

The next increment succeeds only if it:

- leaves production Fortran untouched;
- passes fixture and wrapper comparisons;
- completes one-day and 30-day model runs;
- preserves the current exact NetCDF agreement or documents an approved
  tolerance;
- demonstrably reduces H2D and total model runtime beyond measured noise;
- retains working rollback modes.

The project no longer needs proof that Fortran can call CUDA. It needs proof
that a sufficiently broad, scientifically safe resident boundary can outperform
the CPU path.
