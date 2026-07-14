# FV Advection CUDA Resident-v2 Performance Results

## Result

Resident-v2 completed a 30-day T42L25 Held-Suarez run with 16 MPI ranks using:

```text
FV_KERNELS_CUDA_MODE=resident
FV_KERNELS_PROFILE=1
executable=held_suarez_fv_kernels_cuda.x
experiment=held_suarez_fv_kernels_cuda_resident_v2_30day
```

Resident-v2 moved `semi_y_3d` into the CUDA pre-halo phase and keeps `q2`
resident on device. The CPU still performs `mpp_update_domains(q1)` and polar
boundary corrections.

Sources:

```text
logs/fv_kernels_cuda_resident_v2_30day.log
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_fv_kernels_cuda_resident_v2_30day/run0001/atmos_monthly.nc
docs/fv_advection_cuda_resident_performance_results.md
docs/fv_advection_cuda_persistent_performance_results.md
```

## Completion

The run completed successfully:

```text
Integration completed through 2000 Feb 1 0:0:0
Run 1 complete
atmos_monthly.nc combined and copied to data directory
```

Output:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_fv_kernels_cuda_resident_v2_30day/run0001/atmos_monthly.nc
```

## Numerical Validation

NetCDF validation still needs to be run in an environment with `numpy`/NetCDF
Python dependencies available. The local shell used for this report failed at:

```text
ModuleNotFoundError: No module named 'numpy'
```

Use:

```bash
python3 tests/validate_T85L25_forcing_outputs.py \
  --fortran-exp held_suarez_default \
  --cpu-exp held_suarez_fv_kernels_30day \
  --cuda-exp held_suarez_fv_kernels_cuda_resident_v2_30day \
  --run 1 \
  --filename atmos_monthly.nc \
  --data-root /explore/nobackup/people/jli30/SystemTesting/Isca/isca_data \
  --markdown-out tests/reports/fv_advection_kernels_resident_v2_30day_model_validation.md \
  --json-out tests/reports/fv_advection_kernels_resident_v2_30day_model_validation.json
```

Expected pass condition: `temp`, `ucomp`, `vcomp`, and `ps` match the
all-Fortran baseline and CPU C++ FV bundle to the same tolerances used by the
previous resident validation.

## End-To-End Runtime

| Backend | MPP runtime | Relative to CPU C++ |
|---|---:|---:|
| CPU C++ FV bundle | 25.546 s | 1.000x |
| Stateless CUDA | 132.355 s | 5.18x slower |
| Persistent CUDA mean | 127.173 s | 4.98x slower |
| Resident CUDA v1 | 108.505 s | 4.25x slower |
| Resident CUDA v2 | 108.794 s | 4.26x slower |

Resident-v2 MPP runtime is effectively unchanged from resident-v1:

```text
resident-v1: 108.505 s
resident-v2: 108.794 s
change: +0.289 s, 0.27% slower
```

This is within the range where a repeat run would be useful before treating the
difference as meaningful.

## CUDA Region Breakdown

Resident-v2 profile markers report 4320 begin calls and 4320 finish calls per
rank, for 8640 resident CUDA phase calls per rank.

Mean across 16 ranks:

| Phase | Time |
|---|---:|
| allocation | 1.393 s |
| H2D | 50.471 s |
| kernel | 9.687 s |
| synchronization | 19.259 s |
| D2H | 0.100 s |
| free | 0.000 s |
| measured CUDA region total | 71.825 s |

Slowest rank:

| Phase | Time | Fraction of CUDA region |
|---|---:|---:|
| allocation | 1.444 s | 1.91% |
| H2D | 54.131 s | 71.43% |
| kernel | 9.826 s | 12.97% |
| synchronization | 19.557 s | 25.81% |
| D2H | 0.097 s | 0.13% |
| total | 75.782 s | 100.00% |

The resident-v2 CUDA region remains dominated by host-to-device transfer.

## Comparison With Resident-v1

| Metric | Resident-v1 | Resident-v2 | Change |
|---|---:|---:|---:|
| MPP runtime | 108.505 s | 108.794 s | 0.27% slower |
| Mean H2D | 50.055 s | 50.471 s | 0.83% higher |
| Mean kernel | 19.121 s | 9.687 s | 49.3% lower |
| Mean sync | 19.088 s | 19.259 s | 0.90% higher |
| Mean D2H | 0.098 s | 0.100 s | 1.5% higher |
| Mean CUDA region | 71.221 s | 71.825 s | 0.85% higher |

Resident-v2 successfully moved work from the post-halo side into the pre-halo
device-resident path, and measured kernel time dropped. However, this did not
translate into end-to-end speedup because H2D traffic and synchronization still
dominate the CUDA region.

## Interpretation

Resident-v2 is architecturally cleaner but not a performance win at T42L25.
Keeping `q2` resident removes one intended host-to-device upload, but the new
pre-halo phase also uploads `va`, haloed `q`, and `dyy` so it can execute
`semi_y_3d` on GPU. The transfer balance is therefore nearly unchanged.

The result confirms the broader conclusion from the persistent and resident-v1
experiments:

- isolated CUDA kernels are correct;
- reusable buffers reduce allocation overhead;
- broader boundaries reduce some launch/crossing overhead;
- performance remains limited by CPU-owned model state and repeated H2D copies;
- moving one more local kernel behind the same boundary is not enough.

## Decision

**Resident-v2: correctness pending NetCDF validation, performance NO-GO as a
standalone optimization.**

Do not spend more time moving individual FV kernels into this same boundary
unless the goal is architectural coverage rather than speedup.

## Recommended Next Step

Run the NetCDF validation command above. If it passes, freeze resident-v2 as an
architecture checkpoint.

For performance, the next meaningful step is a larger data-residency boundary,
not another fine-grained kernel move:

1. Keep tracer/advection working arrays resident across more of
   `a_grid_horiz_advection_3d` or `update_tracers`.
2. Avoid full-field H2D uploads of `q`, `q_halo`, velocities, and tendency every
   advection phase.
3. Investigate copying only halo-required `q1` regions for the CPU MPI exchange.
4. Consider whether GPU-aware halo exchange or a broader model data-residency
   redesign is needed before CUDA can beat CPU C++.

Resident-v2 is useful evidence: it shows that adding more translated kernels is
not enough while the model state remains CPU-owned.
