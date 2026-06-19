# FV Advection CUDA Persistent Buffer Report

## Scope

This phase implements reusable device allocations for the existing FV
advection CUDA bundle. It does not add kernels, change production Fortran, or
make model arrays device-resident.

## Files Changed

```text
translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu
translated/held_suarez/cpp/fv_advection/kernels/Makefile
translated/held_suarez/cpp/fv_advection/kernels/fortran/Makefile
docs/fv_advection_cuda_persistent_buffer_plan.md
docs/fv_advection_cuda_persistent_buffer_report.md
```

## Implementation

- Added `FV_KERNELS_CUDA_MODE=stateless|persistent`.
- Kept `stateless` as the default.
- Added one process-local eight-slot device buffer pool.
- Added capacity-based reuse and resize behavior.
- Added process-shutdown cleanup.
- Retained H2D, launch, synchronization, and D2H on every call.
- Preserved all existing C and Fortran signatures.
- Added backend-specific phase profiling.
- Reused CUDA timing events when profiling to avoid per-call event allocation.

The persistent pool covers:

- `semi_x_3d`
- `slope_x`
- `integer_flux_x`
- `vanleer_x_3d`
- `slope_sphere`
- `vanleer_sphere_3d`

## Validation Status

| Stage | Status |
|---|---|
| Source implementation | complete |
| Direct persistent CUDA fixture | **PASS** |
| Fortran -> C -> persistent CUDA fixture | **PASS** |
| Stateless regression fixture | **PASS** |
| Native Isca overlay build | **PASS** |
| One-day model smoke test | **PASS** |
| One-day NetCDF physics comparison | not meaningful with monthly diagnostics |
| 30-day persistent performance run | **PASS** |
| 30-day performance analysis | **complete; 1.039x vs stateless CUDA** |
| 30-day NetCDF comparison | pending |

No performance improvement is claimed before the standalone and model
validation ladder passes.

The direct persistent CUDA fixture passed all six fields with zero maximum
absolute error, zero RMSE, and zero mismatches at `1e-12` absolute and relative
tolerance:

```text
semi_x_dq
slope_x
integer_flux_x
vanleer_x_dq_dt
slope_sphere
vanleer_sphere_dq_dt
```

Result:

```text
tests/reports/fv_advection_kernels_cuda_persistent_compare_report.json
```

The Fortran-to-C-to-persistent-CUDA fixture also passed all six fields with
zero maximum absolute error, zero RMSE, and zero mismatches:

```text
tests/reports/fv_advection_kernels_fortran_cuda_persistent_c_compare_report.json
```

The default stateless CUDA fixture was rebuilt after the persistent changes and
also passed all six fields exactly:

```text
tests/reports/fv_advection_kernels_cuda_compare_report.json
logs/fv_kernels_stateless_regression.log
```

The existing native CUDA overlay was rebuilt successfully with the updated
library:

```text
$GFDL_WORK/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_fv_kernels_cuda/held_suarez_fv_kernels_cuda.x
```

Dedicated one-day persistent smoke script:

```text
scripts/run_fv_kernels_persistent_1day.sh
```

Dedicated profiled 30-day script:

```text
scripts/run_fv_kernels_persistent_30day.sh
```

The smoke log confirms the intended runtime configuration on all 16 MPI
ranks:

```text
FV_KERNELS_CUDA_MODE=persistent
FV_KERNELS_PROFILE=1
PROFILE_FV_ADVECTION_KERNEL backend=cuda_persistent
PROFILE_FV_ADVECTION_CUDA backend=cuda_persistent
```

Each rank reported 144 calls each to `semi_x_3d`, `vanleer_x_3d`, and
`vanleer_sphere_3d`, for 432 persistent CUDA calls per rank. The model reported
integration through day 1 and `Run 1 complete`.

```text
logs/fv_kernels_cuda_persistent_1day.log
$GFDL_DATA/held_suarez_fv_kernels_cuda_persistent_1day/run0001/
```

The only NetCDF product is `atmos_monthly.nc`. Because the run is shorter than
the monthly diagnostic interval, the log states that fill values were written.
It can verify file structure but cannot provide a meaningful one-day physics
comparison. Numerical model-output validation should use a 30-day run or a
separate daily diagnostic configuration.

The profiled 30-day persistent run completed successfully. Detailed results:

```text
docs/fv_advection_cuda_persistent_performance_results.md
```

Model MPP runtime improved from 132.355 s for stateless CUDA to 127.381 s for
persistent CUDA, a provisional 1.039x speedup. H2D copies now dominate the
persistent region, so further performance work requires transfer reduction or
a broader/fused CUDA boundary.

The Makefile command graph and changed-file whitespace checks pass in the host
shell. The direct fixture was not compiled here because this shell has neither
`/usr/local/cuda/bin/nvcc` nor an Apptainer executable. This is an environment
stop, not a reported validation pass or source compile result.

The first container compile found an NVCC type-deduction error in three
range-based loops over mixed braced initializer lists. Those lists were
replaced with explicitly typed `std::pair<std::size_t, std::size_t>` arrays.
Persistent validation must now be rerun; no numerical test executed during the
failed compile.

## Standalone Commands

Direct CUDA fixture:

```bash
cd translated/held_suarez/cpp/fv_advection/kernels
make NVCC=/usr/local/cuda/bin/nvcc cuda_persistent_check
```

This command completed successfully in the CUDA-capable Isca container.

Fortran-to-C-to-CUDA fixture:

```bash
cd translated/held_suarez/cpp/fv_advection/kernels/fortran
make FC=mpifort BACKEND=cuda CUDA_MODE=persistent check
```

## Original Stop Condition

The original implementation turn stopped after standalone validation. The user
then explicitly continued through wrapper validation, native build, one-day
smoke testing, and the profiled 30-day run recorded above.
