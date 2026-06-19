# fv_advection Kernel Bundle Performance Results

Date: 2026-06-18

## Inputs

Log files used:

```text
logs/fv_kernels_cpu_30day.log
logs/fv_kernels_cuda_30day.log
logs/fv_kernels_compile_latest.log
logs/fv_kernels_cuda_compile_latest.log
```

Run configuration from the logs:

```text
experiment_cpu = held_suarez_fv_kernels_30day
experiment_cuda = held_suarez_fv_kernels_cuda_30day
duration = 30 days
dt_atmos = 600 s
MPI ranks = 16
diagnostics = production Held-Suarez monthly diagnostics
resolution = default Held-Suarez T42L25-style configuration
profiling = FV_KERNELS_PROFILE=1
```

Output files:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_fv_kernels_30day/run0001/atmos_monthly.nc
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_fv_kernels_cuda_30day/run0001/atmos_monthly.nc
```

Both runs completed through:

```text
2000 Feb 1 00:00:00
```

## Runtime Summary

Primary speedup numbers use the model MPP `Total runtime` from the FMS timing
table. Shell `real` time is included as an end-to-end launch measurement.

| Variant | Backend | MPP Runtime (s) | Shell Real (s) | Shell User (s) | Shell Sys (s) |
|---|---|---:|---:|---:|---:|
| FV kernel bundle | CPU C++ | 25.546 | 28.987 | 373.360 | 37.819 |
| FV kernel bundle | CUDA | 132.355 | 136.048 | 1813.280 | 250.269 |

## Observed Speedups

The table compares the two FV kernel-bundle variants. A duration-matched
all-Fortran 30-day baseline for this exact default-resolution run was not part
of this log set, so CPU-vs-Fortran speedup is not reported here.

| Comparison | MPP Speedup | Shell Real Speedup | Interpretation |
|---|---:|---:|---|
| CUDA vs CPU C++ | 0.193x | 0.213x | CUDA is slower |
| CPU C++ vs CUDA | 5.181x | 4.693x | CPU C++ run is much faster |

The CUDA FV kernel-bundle run is about 5.18x slower than the CPU C++ bundle by
model MPP runtime, or a 418% runtime increase relative to CPU C++.

## Kernel Timing Summary

Profiling markers were emitted by all 16 MPI ranks:

```text
PROFILE_FV_ADVECTION_KERNEL backend=<cpu|cuda> rank=<rank> name=<kernel> calls=<n> time=<seconds> avg=<seconds>
```

The current model-facing ABI calls are:

- `semi_x_3d`
- `vanleer_x_3d`
- `vanleer_sphere_3d`

The helper kernels `slope_x`, `integer_flux_x`, and `slope_sphere` are folded
inside the top-level C++/CUDA implementations and are not timed separately in
this model-level profile.

The table uses the maximum rank time for runtime-fraction estimates, since the
slowest MPI rank controls elapsed model progress.

| Backend | Kernel | Calls / Rank | Time Min (s) | Time Mean (s) | Time Max (s) | Avg at Max Rank (s/call) | Fraction of MPP Runtime |
|---|---|---:|---:|---:|---:|---:|---:|
| CPU C++ | `semi_x_3d` | 4320 | 0.164 | 0.174 | 0.214 | 4.955e-05 | 0.84% |
| CPU C++ | `vanleer_x_3d` | 4320 | 0.573 | 0.678 | 0.768 | 1.779e-04 | 3.01% |
| CPU C++ | `vanleer_sphere_3d` | 4320 | 0.431 | 0.504 | 0.560 | 1.295e-04 | 2.19% |
| CUDA | `semi_x_3d` | 4320 | 19.498 | 21.327 | 22.566 | 5.224e-03 | 17.05% |
| CUDA | `vanleer_x_3d` | 4320 | 14.868 | 15.981 | 17.089 | 3.956e-03 | 12.91% |
| CUDA | `vanleer_sphere_3d` | 4320 | 56.121 | 56.445 | 56.754 | 1.314e-02 | 42.88% |

## Total Timed FV Kernel Region

Summing the three model-facing timed kernels by MPI rank:

| Backend | Total Time Min (s) | Total Time Mean (s) | Total Time Max (s) | Max-Rank Fraction of MPP Runtime |
|---|---:|---:|---:|---:|
| CPU C++ | 1.175 | 1.356 | 1.542 | 6.04% |
| CUDA | 90.945 | 93.752 | 95.273 | 72.84% |

The CPU C++ FV kernel bundle accounts for about 6.0% of the CPU hybrid model
runtime on the max rank. The CUDA FV kernel bundle accounts for about 72.8% of
the CUDA hybrid model runtime on the max rank.

## CUDA vs CPU Per-Kernel Cost

| Kernel | CUDA / CPU Max-Time Ratio | Interpretation |
|---|---:|---|
| `semi_x_3d` | 105.4x | CUDA wrapper overhead dominates this small kernel |
| `vanleer_x_3d` | 22.2x | CUDA remains much slower despite larger loop body |
| `vanleer_sphere_3d` | 101.4x | dominant CUDA cost and largest end-to-end contributor |

The most important CUDA hotspot is `vanleer_sphere_3d`:

```text
time_max = 56.754 s
fraction_of_cuda_mpp_runtime = 42.88%
```

The next largest CUDA cost is `semi_x_3d`:

```text
time_max = 22.566 s
fraction_of_cuda_mpp_runtime = 17.05%
```

Together, the three timed CUDA calls explain most of the CUDA slowdown.

## Amdahl Interpretation

Using the CPU C++ timed FV region as the useful acceleration opportunity:

```text
f_cpu_fv_bundle = 1.542 / 25.546 = 6.04%
```

If this entire region became free, the theoretical maximum speedup for this
specific partial-kernel replacement would be:

```text
S_max = 1 / (1 - 0.0604) = 1.064x
```

The current CUDA implementation is far from that ceiling because it makes the
FV kernel region much slower, not faster:

```text
CPU C++ timed FV region max = 1.542 s
CUDA timed FV region max    = 95.273 s
```

## Why CUDA Is Slower Here

This CUDA path is still an architecture proof of concept rather than an
optimized GPU-resident model path. The measured timings include:

- C ABI wrapper time;
- per-call device allocation and free;
- host-to-device copies;
- CUDA kernel launches;
- device synchronization;
- device-to-host copies;
- repeated calls from 16 MPI ranks.

The rest of the spectral model remains CPU-resident, so every GPU call pays data
movement and launch overhead without amortizing that cost across a larger
device-resident dynamics step.

The profiling also shows that the current CUDA wrappers are too fine-grained.
Even `vanleer_sphere_3d`, the largest of the three timed kernels, is much slower
than the CPU C++ implementation because transfer/allocation/synchronization
costs dominate the local arithmetic.

## Recommendations

Do not treat the current FV kernel-bundle CUDA implementation as a speedup path
yet. It is useful as an integration and validation milestone, but performance
work should move in one of these directions:

1. Fuse a broader advection/update region so fewer host/device boundaries are
   crossed.
2. Keep arrays resident on the GPU across multiple finite-volume kernels.
3. Allocate GPU buffers once and reuse them across timesteps.
4. Time internal CUDA phases separately: allocation, H2D, kernel, D2H, free.
5. Continue expanding the Strategy 3 boundary only if it reduces crossings
   between Fortran and CUDA.

The highest-priority CUDA tuning target from this run is:

```text
vanleer_sphere_3d
```

But optimizing it in isolation is unlikely to produce end-to-end speedup unless
the data movement model changes.

## Conclusion

Current result:

```text
FV kernel-bundle CUDA expected speedup impact: negative.
```

The CPU C++ bundle remains fast and small, accounting for about 6% of runtime.
The CUDA bundle turns that same region into about 73% of runtime because each
small model-facing kernel pays heavy GPU orchestration overhead. The next
performance milestone should be a broader, more persistent GPU-resident
advection/update region rather than more one-call-at-a-time CUDA wrappers.
