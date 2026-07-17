# FV Advection CUDA `a_grid` Resident Boundary Performance Results

## Result

The broader `a_grid_horiz_advection_3d` resident CUDA boundary completed a
30-day T42L25 Held-Suarez run with 16 MPI ranks.

Configuration:

```text
FV_KERNELS_CUDA_MODE=resident
FV_KERNELS_RESIDENT_BOUNDARY=a_grid
FV_KERNELS_RESIDENT_STATIC_METRICS=1
FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only
FV_KERNELS_PROFILE=1
```

Run log:

```text
logs/fv_kernels_cuda_a_grid_30day.log
```

Output:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_fv_kernels_cuda_a_grid_30day/run0001/atmos_monthly.nc
```

The run completed successfully:

```text
Integration completed through 2000 Feb 1 0:0:0
Run 1 complete
```

NetCDF validation was run separately and reported as passing.

## Runtime Summary

| Backend | MPP runtime | Relative to CPU C++ |
|---|---:|---:|
| CPU C++ FV bundle | 25.546 s | 1.000x |
| Stateless CUDA | 132.355 s | 5.18x slower |
| Persistent CUDA mean | 127.173 s | 4.98x slower |
| Resident CUDA v1 | 108.505 s | 4.25x slower |
| Resident CUDA v2 | 108.794 s | 4.26x slower |
| Resident CUDA v3 | 51.997 s | 2.04x slower |
| `a_grid` resident CUDA | 51.000 s | 2.00x slower |

The broader `a_grid` boundary is a small runtime improvement over resident-v3:

| Comparison | Speedup | Runtime change |
|---|---:|---:|
| `a_grid` vs stateless CUDA | 2.595x | 61.5% lower |
| `a_grid` vs persistent CUDA mean | 2.494x | 59.9% lower |
| `a_grid` vs resident-v1 | 2.127x | 53.0% lower |
| `a_grid` vs resident-v2 | 2.133x | 53.1% lower |
| `a_grid` vs resident-v3 | 1.020x | 1.9% lower |
| `a_grid` vs CPU C++ | 0.501x | CUDA remains 2.00x slower |

## CUDA Region Breakdown

The run printed CUDA resident profile markers for all 16 ranks:

```text
resident_advection_begin calls/rank = 4320
resident_advection_finish calls/rank = 4320
CUDA resident phase calls/rank = 8640
```

Mean across 16 ranks:

| Phase | Resident-v3 | `a_grid` resident | Change |
|---|---:|---:|---:|
| allocation | 1.396 s | 1.388 s | 0.6% lower |
| H2D | 1.195 s | 1.138 s | 4.8% lower |
| kernel | 11.669 s | 11.936 s | 2.3% higher |
| synchronization | 11.788 s | 12.036 s | 2.1% higher |
| D2H | 0.098 s | 0.097 s | unchanged |
| measured CUDA region | 15.098 s | 15.277 s | 1.2% higher |

Slowest `a_grid` rank:

| Phase | Time | Fraction of CUDA region |
|---|---:|---:|
| allocation | 1.313 s | 6.47% |
| H2D | 1.229 s | 6.05% |
| kernel | 16.894 s | 83.23% |
| D2H | 0.098 s | 0.48% |
| total | 20.298 s | 100.00% |

The important result is that H2D traffic remains controlled. The `a_grid`
boundary keeps the resident-v3 transfer improvements:

```text
resident-v2 mean H2D: 50.471 s
resident-v3 mean H2D:  1.195 s
a_grid mean H2D:       1.138 s
```

## Interpretation

The broader `a_grid_horiz_advection_3d` boundary is correct and preserves the
large transfer reduction from resident-v3. It gives a modest end-to-end runtime
improvement:

```text
resident-v3 MPP: 51.997 s
a_grid MPP:      51.000 s
speedup:          1.020x
```

This confirms that lifting the boundary into `a_grid_horiz_advection_3d` is a
sound architecture step, but it is not enough by itself to beat CPU C++ at
T42L25. The remaining CUDA cost is dominated by kernel/synchronization time and
rank imbalance, not host-to-device transfer.

The current performance story is now:

1. Fine-grained CUDA wrappers were transfer dominated and much slower than CPU.
2. Persistent buffers reduced allocation overhead but did not fix H2D traffic.
3. Resident-v3 fixed most H2D traffic and cut runtime by about 2x.
4. The broader `a_grid` boundary slightly improves total runtime and gives a
   cleaner integration point for future work.

## Current Bottlenecks

The `a_grid` run is still about 2.00x slower than CPU C++:

```text
CPU C++ FV bundle: 25.546 s
a_grid CUDA:       51.000 s
```

Remaining likely bottlenecks:

- one GPU shared by 16 MPI ranks;
- kernel launch and synchronization overhead across 8640 CUDA resident phases
  per rank;
- rank imbalance in CUDA region time;
- CPU-owned state arrays outside the advection boundary;
- remaining Fortran/MPI halo exchange requiring synchronization with CPU memory.

## Decision

**`a_grid` resident boundary: correctness PASS, performance PARTIAL GO.**

This should become the preferred CUDA FV advection architecture checkpoint over
resident-v3 because it has the same correctness and transfer behavior, slightly
better MPP runtime, and a broader subroutine-level boundary.

However, it is not yet a speedup over CPU C++ at T42L25.

## Recommended Next Step

Do not return to isolated kernel-by-kernel CUDA wrappers. The transfer problem
has mostly been solved for this boundary; the next experiments should address
kernel/synchronization overhead and MPI-rank contention.

Recommended order:

1. Repeat the `a_grid` 30-day run once to estimate noise.
2. Test the `a_grid` resident boundary at T85L25, where larger local work may
   amortize kernel launch/synchronization overhead better.
3. Add deeper CUDA profiling inside the `a_grid` resident path to separate
   individual kernel launches and synchronization points.
4. Evaluate MPI/GPU layout: fewer ranks per GPU, one rank per GPU, or larger
   per-rank subdomains.
5. Consider fusing the resident begin/finish kernels further only after the
   rank/GPU layout is understood.

The next performance question is no longer whether H2D dominates. It is whether
the resident `a_grid` CUDA path can scale favorably at larger resolution or with
a better MPI-to-GPU mapping.
