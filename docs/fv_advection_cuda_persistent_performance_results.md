# FV Advection CUDA Persistent Performance Results

## Summary

The persistent-buffer CUDA run completed successfully for 30 days with 16 MPI
ranks and profiling enabled.

```text
FV_KERNELS_CUDA_MODE=persistent
FV_KERNELS_PROFILE=1
dt_atmos=600 s
production monthly diagnostics
```

Source logs:

```text
logs/fv_kernels_cpu_30day.log
logs/fv_kernels_cuda_30day.log
logs/fv_kernels_cuda_persistent_30day.log
```

Persistent output:

```text
$GFDL_DATA/held_suarez_fv_kernels_cuda_persistent_30day/run0001/atmos_monthly.nc
```

## Model Runtime

| Backend | MPP Runtime | Shell Real | Relative To CPU C++ |
|---|---:|---:|---:|
| CPU C++ | 25.546 s | 28.987 s | 1.000x |
| CUDA stateless | 132.355 s | 136.048 s | 0.193x MPP |
| CUDA persistent | 127.381 s | 131.038 s | 0.201x MPP |

Persistent versus stateless CUDA:

```text
MPP speedup:         1.0391x
MPP time reduction:  4.974 s, or 3.76%
Real-time speedup:   1.0382x
Real-time reduction: 5.010 s, or 3.68%
```

Persistent CUDA remains approximately 4.99x slower than CPU C++ by model MPP
runtime and 4.52x slower by shell real time.

This is one run per backend, so the 3.8% improvement is provisional until
repeated runs establish run-to-run variability.

## Kernel Timing

Each model-facing kernel was called 4320 times per MPI rank.

| Kernel | Stateless Mean Across Ranks | Persistent Mean Across Ranks | Change |
|---|---:|---:|---:|
| `semi_x_3d` | 21.327 s | 16.615 s | 1.284x faster |
| `vanleer_x_3d` | 15.981 s | 15.978 s | effectively unchanged |
| `vanleer_sphere_3d` | 56.445 s | 57.465 s | 1.8% slower |
| Combined | 93.752 s | 90.058 s | 1.041x faster |

Same-rank combined maxima:

```text
CUDA stateless:  95.273 s
CUDA persistent: 95.853 s
```

The mean region improves, but the maximum rank does not. Persistent allocation
reduces average lifecycle cost without resolving rank contention or imbalance.

## Persistent Phase Breakdown

The maximum-total rank reported:

| Phase | Time | Fraction Of Persistent CUDA Region |
|---|---:|---:|
| allocation | 1.446 s | 1.51% |
| H2D | 64.778 s | 67.59% |
| kernel | 28.941 s | 30.20% |
| D2H | 0.137 s | 0.14% |
| free/finalize | 0.020 s | 0.02% |
| total | 95.847 s | 100% |

Host synchronization was 28.916 s and overlaps kernel execution, so it is not
added to the phase percentages.

Allocation is now a one-time setup cost rather than a per-call cost. The
remaining boundary is dominated by synchronous H2D copies. This is the expected
limit of reusable allocations that retain per-call transfers.

## Host CPU Accounting

| Backend | User Time | System Time |
|---|---:|---:|
| CUDA stateless | 30m13.280s | 4m10.269s |
| CUDA persistent | 31m24.469s | 2m16.108s |

Persistent buffers reduce system time by about 46%, consistent with removing
repeated allocation/free activity. User time increased by about 4%, reinforcing
the need for repeated controlled measurements.

## Interpretation

The experiment validates the persistent-buffer architecture and produces a
small end-to-end improvement. It does not make fine-grained CUDA competitive
with CPU C++.

- Reusable allocations help.
- Allocation/free is no longer the dominant steady-state cost.
- Per-call H2D transfers are now the clear bottleneck.
- Isolated wrapper optimization has reached diminishing returns.
- Material speedup requires data residency, fusion, or a broader CUDA boundary.

## Numerical Validation Status

Standalone direct CUDA and Fortran-to-C-to-CUDA persistent validation passed
with exact agreement. The 30-day `atmos_monthly.nc` output exists, but its
duration-matched model comparison must still pass before the persistent backend
is accepted as model-validated.

## Recommendation

1. Compare persistent 30-day NetCDF output against CPU C++ and stateless CUDA.
2. Repeat stateless and persistent 30-day runs at least three times under the
   same GPU/node conditions and compare medians.
3. If numerical comparison passes, retain persistent buffers as the CUDA
   default candidate while keeping stateless mode as fallback.
4. Make the next architecture experiment a fused or broader advection boundary
   that eliminates repeated H2D transfers. Do not add more isolated wrappers.

## Performance Decision

**Persistent buffers are a correctness and architecture GO, but only a modest
performance improvement.**

Observed stateless-to-persistent model speedup: **1.039x**. The next performance
target must reduce the approximately 68% H2D contribution.
