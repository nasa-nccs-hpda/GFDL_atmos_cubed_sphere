# FV Advection CUDA Resident-v3 Performance Results

## Result

Resident-v3 completed a 30-day T42L25 Held-Suarez run with 16 MPI ranks using
the CUDA resident FV advection executable.

Resident-v3 adds:

```text
FV_KERNELS_RESIDENT_STATIC_METRICS=1
FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only
```

The run completed successfully:

```text
Integration completed through 2000 Feb 1 0:0:0
Run 1 complete
atmos_monthly.nc combined and copied to data directory
```

Sources:

```text
logs/fv_kernels_cuda_resident_v3_30day.log
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_fv_kernels_cuda_resident_v3_30day/run0001/atmos_monthly.nc
docs/fv_advection_cuda_resident_v2_performance_results.md
docs/fv_advection_cuda_resident_performance_results.md
```

## Numerical Validation

NetCDF validation is pending. The local shell used for this report still lacks
`numpy`:

```text
ModuleNotFoundError: No module named 'numpy'
```

Run:

```bash
python3 tests/validate_T85L25_forcing_outputs.py \
  --fortran-exp held_suarez_default \
  --cpu-exp held_suarez_fv_kernels_30day \
  --cuda-exp held_suarez_fv_kernels_cuda_resident_v3_30day \
  --run 1 \
  --filename atmos_monthly.nc \
  --data-root /explore/nobackup/people/jli30/SystemTesting/Isca/isca_data \
  --markdown-out tests/reports/fv_advection_kernels_resident_v3_30day_model_validation.md \
  --json-out tests/reports/fv_advection_kernels_resident_v3_30day_model_validation.json
```

Expected pass condition: dimensions match and `temp`, `ucomp`, `vcomp`, and
`ps` agree with the all-Fortran and CPU C++ FV bundle references.

## End-To-End Runtime

| Backend | MPP runtime | Relative to CPU C++ |
|---|---:|---:|
| CPU C++ FV bundle | 25.546 s | 1.000x |
| Stateless CUDA | 132.355 s | 5.18x slower |
| Persistent CUDA mean | 127.173 s | 4.98x slower |
| Resident CUDA v1 | 108.505 s | 4.25x slower |
| Resident CUDA v2 | 108.794 s | 4.26x slower |
| Resident CUDA v3 | 51.997 s | 2.04x slower |

Resident-v3 is the first CUDA FV boundary optimization that produces a large
end-to-end runtime improvement.

## Speedups

| Comparison | MPP speedup | MPP runtime reduction |
|---|---:|---:|
| v3 vs stateless CUDA | 2.545x | 60.7% |
| v3 vs persistent CUDA mean | 2.446x | 59.1% |
| v3 vs resident-v1 | 2.087x | 52.1% |
| v3 vs resident-v2 | 2.092x | 52.2% |
| v3 vs CPU C++ | 0.491x | v3 is 2.04x slower |

## CUDA Region Breakdown

Resident-v3 profile markers report:

```text
resident_advection_begin calls/rank = 4320
resident_advection_finish calls/rank = 4320
CUDA resident phase calls/rank = 8640
```

Mean across 16 ranks:

| Phase | Resident-v2 | Resident-v3 | Change |
|---|---:|---:|---:|
| allocation | 1.393 s | 1.396 s | unchanged |
| H2D | 50.471 s | 1.195 s | 97.6% lower |
| kernel | 9.687 s | 11.669 s | 20.5% higher |
| synchronization | 19.259 s | 11.788 s | 38.8% lower |
| D2H | 0.100 s | 0.098 s | unchanged |
| measured CUDA region | 71.825 s | 15.098 s | 79.0% lower |

Slowest resident-v3 rank:

| Phase | Time | Fraction of CUDA region |
|---|---:|---:|
| allocation | 1.469 s | 7.52% |
| H2D | 1.193 s | 6.11% |
| kernel | 16.098 s | 82.40% |
| D2H | 0.100 s | 0.51% |
| total | 19.536 s | 100.00% |

The bottleneck shifted. Resident-v2 was dominated by H2D traffic; resident-v3
is no longer H2D-dominated. The slowest rank is now dominated by kernel/sync
time and rank imbalance.

## Interpretation

Resident-v3 validates the design hypothesis from
`docs/fv_advection_subroutine_residency_design.md`.

The two changes matter:

1. Static metric residency removes thousands of repeated small metric uploads.
2. Halo-only `q1` transfer avoids uploading the full corrected `q1` field after
   the CPU/MPI halo exchange.

The observed impact is much larger than resident-v2:

```text
resident-v2 MPP: 108.794 s
resident-v3 MPP:  51.997 s
```

This shows that transfer architecture, not individual kernel translation, was
the dominant performance issue.

## Remaining Gap

Resident-v3 is still about 2.04x slower than CPU C++ at T42L25:

```text
CPU C++:     25.546 s
resident-v3: 51.997 s
```

The remaining CUDA cost is no longer H2D. The next bottlenecks are:

- kernel/synchronization time;
- MPI rank imbalance in the resident CUDA region;
- continued CPU ownership of state arrays;
- repeated per-call launch boundaries;
- one GPU shared by 16 MPI ranks.

## Decision

**Resident-v3: strong performance GO, pending NetCDF validation.**

This is the first resident CUDA version that substantially reduces the
end-to-end runtime. It should replace resident-v2 as the current CUDA
architecture checkpoint once NetCDF validation passes.

## Recommended Next Step

1. Run NetCDF validation using the command above.
2. If validation passes, repeat resident-v3 once to estimate run-to-run noise.
3. Profile rank imbalance and kernel/sync time in resident-v3.
4. Consider one of these next optimizations:
   - fuse begin/finish kernels further to reduce launch/sync overhead;
   - reduce MPI-rank contention on one GPU;
   - move to a broader `a_grid_horiz_advection_3d` resident boundary;
   - test T85L25, where larger local work may improve GPU amortization.

Do not return to moving one isolated kernel at a time. Resident-v3 shows the
right direction is transfer residency and broader subroutine-level ownership.
