# FV Advection CUDA Resident-Boundary Performance Results

## Result

The two-phase resident CUDA boundary completed a 30-day T42L25 Held-Suarez run
with 16 MPI ranks. The output agrees exactly with the all-Fortran and CPU C++
outputs for `temp`, `ucomp`, `vcomp`, and `ps`.

```text
FV_KERNELS_CUDA_MODE=resident
FV_KERNELS_PROFILE=1
calls per rank: 4320 begin + 4320 finish
```

Sources:

```text
logs/fv_kernels_cpu_30day.log
logs/fv_kernels_cuda_30day.log
logs/fv_kernels_cuda_persistent_30day.log
logs/fv_kernels_cuda_persistent_30day_repeat.log
logs/fv_kernels_cuda_resident_30day.log
tests/reports/fv_advection_kernels_resident_30day_model_validation.md
```

## Numerical Validation

| Comparison | Dimensions | `temp` | `ucomp` | `vcomp` | `ps` |
|---|---|---:|---:|---:|---:|
| Fortran vs resident CUDA | match | exact | exact | exact | exact |
| CPU C++ vs resident CUDA | match | exact | exact | exact | exact |

All maximum absolute errors and RMSE values are zero. The resident boundary is
accepted as numerically correct for the 30-day experiment.

## End-To-End Runtime

| Backend | MPP runtime | Shell real | Relative to CPU C++ |
|---|---:|---:|---:|
| CPU C++ | 25.546 s | 28.987 s | 1.000x |
| Stateless CUDA | 132.355 s | 136.048 s | 5.18x slower |
| Persistent CUDA, run 1 | 127.381 s | 131.038 s | 4.99x slower |
| Persistent CUDA, run 2 | 126.964 s | 130.936 s | 4.97x slower |
| Persistent CUDA mean | 127.173 s | 130.987 s | 4.98x slower |
| Resident CUDA | 108.505 s | 112.266 s | 4.25x slower |

## Speedups

| Comparison | MPP speedup | MPP reduction | Shell speedup |
|---|---:|---:|---:|
| Resident vs stateless | 1.220x | 18.0% | 1.212x |
| Resident vs persistent mean | 1.172x | 14.7% | 1.167x |
| Resident vs CPU C++ | 0.235x | resident is 4.25x slower | 0.258x |

Persistent repeat variability is only 0.33%, so the resident improvement is
well outside measured noise.

## CUDA Region Breakdown

Times below use the mean across 16 MPI ranks. Synchronization overlaps kernel
execution and is not added separately to the phase total.

| Phase | Persistent mean | Resident mean | Change |
|---|---:|---:|---:|
| allocation | 1.382 s | 1.388 s | unchanged |
| H2D | 59.365 s | 50.055 s | 15.7% lower |
| kernel | 28.544 s | 19.121 s | 33.0% lower |
| synchronization | 28.552 s | 19.088 s | 33.1% lower |
| D2H | 0.138 s | 0.098 s | 29.5% lower |
| measured CUDA region | 90.052 s | 71.221 s | 20.9% lower |

The slowest resident rank reports:

| Phase | Time | Fraction of resident CUDA region |
|---|---:|---:|
| allocation | 1.426 s | 1.88% |
| H2D | 54.406 s | 71.72% |
| kernel | 19.424 s | 25.61% |
| D2H | 0.094 s | 0.12% |
| total | 75.861 s | 100% |

The resident path reduces model-facing CUDA calls from 12,960 to 8,640 per
rank, a 33.3% reduction. The paired Van Leer kernels now share one tendency
upload, one device buffer, one synchronization boundary, and one download.

## Interpretation

The experiment validates the broader-boundary hypothesis:

- fewer Fortran/CUDA crossings improve end-to-end runtime;
- launching the two Van Leer operations as one staged region cuts measured
  kernel/synchronization time by about one third;
- eliminating one tendency round trip reduces D2H and part of H2D;
- retaining MPI halo exchange in Fortran is compatible with exact results.

The boundary is still dominated by dynamic H2D traffic. The pre-halo stage
uploads `ua` and `q`; the post-halo stage uploads `uc`, `vc`, corrected `q1`,
host-produced `q2`, and `dq_dt`. Metric arrays are also uploaded, although
their contribution is small. Persistent allocation alone cannot remove these
copies.

The resident CUDA region accounts for about 66% of the model MPP runtime by
mean rank timing. H2D alone is about 46% of model MPP runtime. This is now the
clear next architecture target.

## Performance Decision

**Two-phase resident boundary: performance GO, end-to-end CPU target not yet
met.**

The architecture produces a material and reproducible 1.17x improvement over
persistent CUDA without changing model results. It remains unsuitable as the
default performance backend because it is 4.25x slower than CPU C++ at T42L25.

## Recommended Next Step

Integrate the already translated `semi_y_3d` CUDA operation into the same
pre-halo resident context:

1. Upload `q` once and reuse it for both `semi_x_3d` and `semi_y_3d`.
2. Upload `va` and `dyy` in the pre-halo stage.
3. Form and retain `q2` on device instead of computing it in Fortran and
   uploading it during the finish stage.
4. Continue exporting `q1` for the existing Fortran/MPI halo exchange.
5. Preserve the current resident, persistent, and stateless modes as fallback.

This is not a new physics translation: `semi_y_3d` already has validated CPU
C++ and CUDA implementations. It removes another full-field H2D transfer and
one host computation/crossing while retaining the same MPI boundary.

After that increment passes the validation ladder, measure the value of
transferring only `q1` halo slabs rather than the full `q1` field. Full
`update_tracers` residency remains the long-term option, but it is not yet
needed to test the next measurable reduction.
