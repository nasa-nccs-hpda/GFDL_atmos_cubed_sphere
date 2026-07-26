# FV Resolution/GPU Matrix Completion Status

Date: 2026-07-26

Source logs:

```text
logs/matrix*.log
```

This status excludes `16gpu` logs, because the 16-GPU path is still being
handled separately as a launcher/infrastructure issue.

## Completion Definition

A run is marked complete only if the log contains:

- `Integration completed` markers for the requested simulation length;
- an MPP `Total runtime` table;
- an `output=.../atmos_monthly.nc` line.

CUDA runs are additionally checked for:

- `PROFILE_FV_GPU_MAPPING`;
- `PROFILE_FV_ADVECTION_CUDA`.

Nonfatal PMIx/munge warning messages are present in several successful logs and
are not treated as failures when the model completes and prints `Total runtime`.

## Completed Matrix

| Resolution | Days | Fortran 16 CPU | FV CUDA 1 GPU | FV CUDA 4 GPU |
|---|---:|---:|---:|---:|
| T42L25 | 30 | complete | complete | complete |
| T42L25 | 60 | complete | complete | complete |
| T42L25 | 90 | complete | complete | complete |
| T42L25 | 120 | complete | complete | complete |
| T85L25 | 30 | complete | complete | complete |
| T85L25 | 60 | complete | complete | complete |
| T85L25 | 90 | complete | complete | complete |
| T85L25 | 120 | complete | complete | complete |
| T170L25 | 30 | complete | complete | complete |
| T170L25 | 60 | complete | complete | partial: time limit |
| T170L25 | 90 | complete | complete | missing |
| T170L25 | 120 | missing | missing | missing |
| T340L25 | 30 | missing | missing | missing |
| T340L25 | 60 | missing | missing | missing |
| T340L25 | 90 | missing | missing | missing |
| T340L25 | 120 | missing | missing | missing |

## Runtime Summary

MPP `Total runtime` values are `tmax` in seconds.

| Resolution | Days | Config | Status | MPP tmax (s) | Integration Markers | GPU Mapping Markers | FV CUDA Total Max (s) | Log |
|---|---:|---|---|---:|---:|---:|---:|---|
| T42L25 | 30 | fortran_16cpu | complete | 24.165 | 30 | 0 |  | `logs/matrix_T42L25_fortran_16cpu_30day.log` |
| T42L25 | 30 | fv_cuda_a_grid_1gpu | complete | 48.609 | 30 | 16 | 20.573 | `logs/matrix_T42L25_fv_cuda_a_grid_1gpu_30day.log` |
| T42L25 | 30 | fv_cuda_a_grid_4gpu | complete | 83.238 | 30 | 16 | 4.758 | `logs/matrix_T42L25_fv_cuda_a_grid_4gpu_30day.log` |
| T42L25 | 60 | fortran_16cpu | complete | 48.302 | 60 | 0 |  | `logs/matrix_T42L25_fortran_16cpu_60day.log` |
| T42L25 | 60 | fv_cuda_a_grid_1gpu | complete | 95.246 | 60 | 16 | 37.334 | `logs/matrix_T42L25_fv_cuda_a_grid_1gpu_60day.log` |
| T42L25 | 60 | fv_cuda_a_grid_4gpu | complete | 167.116 | 60 | 16 | 8.298 | `logs/matrix_T42L25_fv_cuda_a_grid_4gpu_60day.log` |
| T42L25 | 90 | fortran_16cpu | complete | 72.853 | 90 | 0 |  | `logs/matrix_T42L25_fortran_16cpu_90day.log` |
| T42L25 | 90 | fv_cuda_a_grid_1gpu | complete | 142.029 | 90 | 16 | 47.904 | `logs/matrix_T42L25_fv_cuda_a_grid_1gpu_90day.log` |
| T42L25 | 90 | fv_cuda_a_grid_4gpu | complete | 248.005 | 90 | 16 | 12.262 | `logs/matrix_T42L25_fv_cuda_a_grid_4gpu_90day.log` |
| T42L25 | 120 | fortran_16cpu | complete | 96.888 | 120 | 0 |  | `logs/matrix_T42L25_fortran_16cpu_120day.log` |
| T42L25 | 120 | fv_cuda_a_grid_1gpu | complete | 188.706 | 120 | 16 | 70.380 | `logs/matrix_T42L25_fv_cuda_a_grid_1gpu_120day.log` |
| T42L25 | 120 | fv_cuda_a_grid_4gpu | complete | 327.697 | 120 | 16 | 16.640 | `logs/matrix_T42L25_fv_cuda_a_grid_4gpu_120day.log` |
| T85L25 | 30 | fortran_16cpu | complete | 207.173 | 30 | 0 |  | `logs/matrix_T85L25_fortran_16cpu_30day.log` |
| T85L25 | 30 | fv_cuda_a_grid_1gpu | complete | 264.731 | 30 | 16 | 40.183 | `logs/matrix_T85L25_fv_cuda_a_grid_1gpu_30day.log` |
| T85L25 | 30 | fv_cuda_a_grid_4gpu | complete | 287.123 | 30 | 16 | 6.698 | `logs/matrix_T85L25_fv_cuda_a_grid_4gpu_30day.log` |
| T85L25 | 60 | fortran_16cpu | complete | 410.925 | 60 | 0 |  | `logs/matrix_T85L25_fortran_16cpu_60day.log` |
| T85L25 | 60 | fv_cuda_a_grid_1gpu | complete | 525.309 | 60 | 16 | 68.282 | `logs/matrix_T85L25_fv_cuda_a_grid_1gpu_60day.log` |
| T85L25 | 60 | fv_cuda_a_grid_4gpu | complete | 611.814 | 60 | 16 | 12.650 | `logs/matrix_T85L25_fv_cuda_a_grid_4gpu_60day.log` |
| T85L25 | 90 | fortran_16cpu | complete | 619.364 | 90 | 0 |  | `logs/matrix_T85L25_fortran_16cpu_90day.log` |
| T85L25 | 90 | fv_cuda_a_grid_1gpu | complete | 789.872 | 90 | 16 | 100.079 | `logs/matrix_T85L25_fv_cuda_a_grid_1gpu_90day.log` |
| T85L25 | 90 | fv_cuda_a_grid_4gpu | complete | 868.299 | 90 | 16 | 19.510 | `logs/matrix_T85L25_fv_cuda_a_grid_4gpu_90day.log` |
| T85L25 | 120 | fortran_16cpu | complete | 825.386 | 120 | 0 |  | `logs/matrix_T85L25_fortran_16cpu_120day.log` |
| T85L25 | 120 | fv_cuda_a_grid_1gpu | complete | 1052.427 | 120 | 16 | 143.155 | `logs/matrix_T85L25_fv_cuda_a_grid_1gpu_120day.log` |
| T85L25 | 120 | fv_cuda_a_grid_4gpu | complete | 1146.068 | 120 | 16 | 24.700 | `logs/matrix_T85L25_fv_cuda_a_grid_4gpu_120day.log` |
| T170L25 | 30 | fortran_16cpu | complete | 2259.014 | 30 | 0 |  | `logs/matrix_T170L25_fortran_16cpu_30day.log` |
| T170L25 | 30 | fv_cuda_a_grid_1gpu | complete | 2349.298 | 30 | 16 | 68.932 | `logs/matrix_T170L25_fv_cuda_a_grid_1gpu_30day.log` |
| T170L25 | 30 | fv_cuda_a_grid_4gpu | complete | 11294.293 | 30 | 16 | 12.426 | `logs/matrix_T170L25_fv_cuda_a_grid_4gpu_30day.log` |
| T170L25 | 60 | fortran_16cpu | complete | 4535.960 | 60 | 0 |  | `logs/matrix_T170L25_fortran_16cpu_60day.log` |
| T170L25 | 60 | fv_cuda_a_grid_1gpu | complete | 4733.147 | 60 | 16 | 139.123 | `logs/matrix_T170L25_fv_cuda_a_grid_1gpu_60day.log` |
| T170L25 | 60 | fv_cuda_a_grid_4gpu | partial: time limit |  | 44 | 16 |  | `logs/matrix_T170L25_fv_cuda_a_grid_4gpu_60day.log` |
| T170L25 | 90 | fortran_16cpu | complete | 6641.085 | 90 | 0 |  | `logs/matrix_T170L25_fortran_16cpu_90day.log` |
| T170L25 | 90 | fv_cuda_a_grid_1gpu | complete | 7105.579 | 90 | 16 | 199.037 | `logs/matrix_T170L25_fv_cuda_a_grid_1gpu_90day.log` |

## T170 Corrections From Latest Log Check

The earlier status that `T170L25/fv_cuda_a_grid_4gpu/30day` was incomplete was
wrong. It did complete:

```text
Total runtime tmax: 11294.293 s
Output:
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_fv_cuda_a_grid_4gpu_T170L25_30day/run0001/atmos_monthly.nc
```

However, the runtime is much slower than both T170 Fortran and T170 1-GPU.
This should be treated as a valid but suspicious/outlier performance result
until checked against queue/node placement and validation output.

`T170L25/fv_cuda_a_grid_4gpu/60day` did not complete. It reached 44 integration
markers and was cancelled by the time limit:

```text
STEP ... CANCELLED ... DUE TO TIME LIMIT
```

No `Total runtime` or output line was produced for that run.

## Clean Figure Matrix Available Now

The fully complete matrix is:

```text
T42L25 and T85L25
x 30, 60, 90, 120 days
x fortran_16cpu, fv_cuda_a_grid_1gpu, fv_cuda_a_grid_4gpu
```

T170 can be plotted as a partial extension:

```text
T170L25:
  complete for fortran_16cpu at 30, 60, 90 days
  complete for fv_cuda_a_grid_1gpu at 30, 60, 90 days
  complete but outlier for fv_cuda_a_grid_4gpu at 30 days
  partial/time-limit for fv_cuda_a_grid_4gpu at 60 days
```

Recommended figure treatment:

- use T42/T85 for complete heatmaps;
- include T170 in line plots with missing-data markers;
- annotate T170 4-GPU 30-day as a valid outlier;
- exclude T170 4-GPU 60-day from speedup calculations.
