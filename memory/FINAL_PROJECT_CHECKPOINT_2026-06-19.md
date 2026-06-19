# Final Project Checkpoint - 2026-06-19

## Objective

Use Held-Suarez/Isca as a safe prototype for future GEOS modernization:

```text
Fortran baseline -> C++ -> CUDA -> hybrid model -> performance-driven residency
```

Production Fortran must remain untouched. Integration uses overlays, C APIs,
`ISO_C_BINDING`, separate libraries, and native Isca `CodeBase.compile()`.

## Branch Status

- Branch: `perf/cuda-data-residency`
- Worktree at checkpoint: one untracked directory, `end2end_experiment/`
- No tracked source modifications were made while producing this checkpoint.
- Do not delete, add, or reinterpret `end2end_experiment/` without first checking
  its ownership and purpose.

## Completed Milestones

### Forcing module

- Forcing routines mapped, specified, and translated to C++.
- Full forcing module validated against deterministic Fortran fixtures.
- Stable C ABI and Fortran `ISO_C_BINDING` wrapper validated.
- Native source overlay and mixed-language Isca build established.
- Optional CPU and CUDA runtime backends implemented.
- One-day and 30-day hybrid runs completed.
- T85L25 all-Fortran, CPU hybrid, and CUDA hybrid performance study completed.

### Performance target selection

- `four_in_one`: about 2.6% of model MPP runtime; not selected.
- `vert_advection_3d`: about 0.34%; not selected.
- Broad profiling found transforms about 38.9%, tracer/correction about 32.6%,
  advection about 7.9%, and pressure/geopotential about 4.8%.
- Deep profiling found `update_tracers` about 17.6% and tracer grid horizontal
  advection about 12.0%.
- Selected `fv_advection` Strategy 3: retain Fortran domain/halo handling and
  modernize local kernels.

### FV advection

- `semi_y_3d` completed through Fortran fixture, C++, CUDA, C API, wrapper,
  overlay, one-day, and 30-day validation.
- Kernel bundle completed for `semi_x_3d`, `slope_x`, `slope_sphere`,
  `vanleer_x_3d`, `vanleer_sphere_3d`, `integer_flux_x`, and `find_cell_x`.
- CPU and CUDA fixture comparisons are exact.
- Fortran-to-C CPU and Fortran-to-C CUDA comparisons are exact.
- Native CPU and CUDA overlay executables build and run.
- Thirty-day model outputs are exact for the checked state fields.

### CUDA architecture experiments

- Stateless fine-grained wrappers established the correct but slow baseline.
- Persistent reusable per-rank device buffers removed repeated allocation.
- Persistent timing was repeated; variability was 0.33%.
- Two-phase resident boundary retained the Fortran/MPI halo exchange while
  broadening pre-halo and post-halo CUDA work.
- Resident 30-day output agrees exactly with all-Fortran and CPU C++ for `temp`,
  `ucomp`, `vcomp`, and `ps`.

## Validated Executables

Base directory:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build
```

Present on 2026-06-19:

```text
held_suarez_hybrid/held_suarez_hybrid.x
held_suarez_fv_semi_y_3d/held_suarez_fv_semi_y_3d.x
held_suarez_fv_semi_y_3d_cuda/held_suarez_fv_semi_y_3d_cuda.x
held_suarez_fv_kernels/held_suarez_fv_kernels.x
held_suarez_fv_kernels_cuda/held_suarez_fv_kernels_cuda.x
```

The CUDA FV executable selects behavior at runtime with:

```text
FV_KERNELS_CUDA_MODE=stateless
FV_KERNELS_CUDA_MODE=persistent
FV_KERNELS_CUDA_MODE=resident
```

The custom build artifact below is not currently present:

```text
held_suarez_fortran/held_suarez_fortran.x
```

The stock all-Fortran model and its validated NetCDF baseline remain available;
rebuild the custom executable only if a workflow specifically requires that name.

## Current Performance Numbers

### T85L25 forcing, 30 days, 16 ranks

| Variant | MPP | Shell real | Speedup vs Fortran |
|---|---:|---:|---:|
| Fortran | 206.761 s | 214.209 s | 1.000x |
| CPU C++ forcing | 200.475 s | 207.580 s | 1.031x |
| CUDA forcing | 320.956 s | 328.019 s | 0.644x |

Forcing fraction was about 4.23%; ideal forcing-only speedup ceiling was 1.044x.

### T42L25 FV bundle, 30 days, 16 ranks

| Backend | MPP | Shell real |
|---|---:|---:|
| CPU C++ | 25.546 s | 28.987 s |
| Stateless CUDA | 132.355 s | 136.048 s |
| Persistent CUDA mean | 127.173 s | 130.987 s |
| Resident CUDA | 108.505 s | 112.266 s |

Resident is 1.220x faster than stateless and 1.172x faster than persistent, but
is still 4.25x slower than CPU C++. H2D transfer is 71.7% of the slowest rank's
resident CUDA region.

## Validated Outputs

Important current output files include:

```text
$GFDL_DATA/held_suarez_default/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_hybrid_cpu_T85L25/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_hybrid_cuda_T85L25/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_fv_kernels_30day/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_fv_kernels_cuda_30day/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_fv_kernels_cuda_persistent_30day/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_fv_kernels_cuda_persistent_30day_repeat/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_fv_kernels_cuda_resident_30day/run0001/atmos_monthly.nc
```

Authoritative resident validation:

```text
tests/reports/fv_advection_kernels_cuda_resident_compare_report.json
tests/reports/fv_advection_kernels_resident_30day_model_validation.md
tests/reports/fv_advection_kernels_resident_30day_model_validation.json
```

Do not use the resident one-day production-diagnostic comparison as a numerical
gate; its 30-day diagnostic cadence produced fill values.

## Next Recommended Task

Integrate the already translated CUDA `semi_y_3d` operation into the resident
pre-halo phase:

1. Reuse one `q` upload for `semi_x_3d` and `semi_y_3d`.
2. Upload `va` and `dyy` in that phase.
3. Form and retain `q2` on device.
4. Continue exporting `q1` for the existing Fortran/MPI halo exchange.
5. Preserve stateless, persistent, and current resident modes as fallbacks.
6. Run fixture, wrapper, one-day, 30-day, repeat timing, and NetCDF gates.

This is an architecture extension, not a new kernel translation.

## Resume Instructions

1. Read `docs/PROJECT_HANDOFF_EXECUTIVE_SUMMARY.md`.
2. Read `docs/PROJECT_HANDOFF_TECHNICAL_GUIDE.md`.
3. Read `docs/PROJECT_HANDOFF_RESUME_GUIDE.md`.
4. Read `docs/fv_advection_cuda_resident_performance_results.md`.
5. Read `docs/fv_advection_cuda_resident_boundary_report.md`.
6. Confirm branch and worktree before editing:

   ```bash
   git branch --show-current
   git status --short
   ```

7. Verify the current CUDA regression before broadening the boundary:

   ```bash
   cd translated/held_suarez/cpp/fv_advection/kernels
   make USE_CUDA_FV_ADVECTION_KERNELS=1 cuda_resident_check
   ```

   Run this in the CUDA-enabled Isca container.

8. Keep production `src/atmos_*` files untouched. Make integration changes only
   in `src/extra/local_overrides/`, translated sources, wrappers, scripts, and
   reports.
9. After implementation, use `run_compile_fv_kernels.sh`, then the resident
   one-day and 30-day scripts, and finally the resident validation script.
10. Update this checkpoint or create a dated successor after the next measured
    architecture increment.
