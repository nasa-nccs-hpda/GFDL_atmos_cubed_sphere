# Resolution Scaling Matrix

Date: 2026-06-17

This matrix tracks how Held-Suarez hotspot rankings change with resolution.
Rows marked `TBD` should be filled after running:

```bash
scripts/run_resolution_scaling_profiles.sh
```

## Primary Matrix

| Resolution | Grid Size | 3D State Cells | Memory Scale | Wall Clock | Transforms % | Advection % | Press_geopot % | four_in_one % | vert_advection % | hs_forcing_time | hs_forcing_percent | forcing_cpp_hybrid_runtime | forcing_fortran_runtime | forcing_speedup | Notes |
|---|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| T42L25 | 128x64x25 | 204,800 | 1x | measured logs vary by profile build; deep profile MPP tmax 24.136 s | ~39% | ~8% | ~5% | ~2.6% | ~0.34% | TBD from `HS_PROFILE` rerun | TBD | TBD | not yet instrumented | TBD | Current baseline. |
| T85L25 | 256x128x25 | 819,200 | 4x | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | not yet instrumented | TBD | Recommended first scaling target. |
| T170L25 | 512x256x25 | 3,276,800 | 16x | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | not yet instrumented | TBD | Confirmation case if T85L25 is informative. |

## Optional Vertical Scaling Matrix

| Resolution | Grid Size | 3D State Cells | Memory Scale | Wall Clock | Transforms % | Advection % | Press_geopot % | four_in_one % | vert_advection % | hs_forcing_time | hs_forcing_percent | forcing_cpp_hybrid_runtime | forcing_fortran_runtime | forcing_speedup | Notes |
|---|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| T42L50 | 128x64x50 | 409,600 | 2x | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | not yet instrumented | TBD | Tests vertical sensitivity at baseline horizontal resolution. |
| T85L50 | 256x128x50 | 1,638,400 | 8x | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | not yet instrumented | TBD | Tests combined horizontal and vertical scaling. |

## Existing T42L25 Evidence

Existing profile recommendations report:

```text
transforms: about 39%
tracer/correction region: about 33%
advection: about 8%
press_geopot: about 5%
four_in_one: about 2.6%
vert_advection_3d u+v+t: about 0.34%
```

Held-Suarez forcing timing should be filled from the hybrid C++ forcing logs:

```text
logs/scaling_T42L25_forcing_profile.log
logs/scaling_T85L25_forcing_profile.log
logs/scaling_T170L25_forcing_profile.log
```

Use the `HS_PROFILE` summaries to fill:

```text
hs_forcing_time
hs_forcing_percent
forcing_cpp_hybrid_runtime
```

Leave these fields as `TBD` until an all-Fortran forcing timer exists:

```text
forcing_fortran_runtime
forcing_speedup
```

Deep-profile highlights:

| Region | T42L25 Runtime Fraction |
|---|---:|
| `update_tracers` | 17.55% |
| `tracer_grid_horizontal_advection` | 12.04% |
| `compute_corrections` | 9.43% |
| `transform_vor_div_from_uv` | 7.42% |
| `horizontal_advection_temperature` | 7.25% |
| `transform_future_uv_from_vor_div` | 7.03% |
| `transform_future_div` | 6.71% |
| `tracer_vertical_advection` | 5.03% |

## Expected Scaling Hypotheses

Before measurement:

- transform aggregate may remain the largest region and may grow with
  horizontal resolution faster than simple grid loops;
- finite-volume tracer horizontal advection should scale close to horizontal
  grid size times timestep count;
- pressure/geopotential and `four_in_one` may grow with 3D state size but are
  unlikely to overtake transforms unless transform cost is hidden by MPI or
  implementation details;
- `vert_advection_3d` is unlikely to become a top target unless vertical levels
  increase substantially.
- Held-Suarez forcing should scale with grid-cell count and timestep count, but
  previous profiling/source inspection suggests it is unlikely to become a
  large end-to-end speedup target unless higher resolution changes its fraction
  substantially.

## Recommendation Field

After T85L25 runs, update this section with one of:

```text
A. Choose a specific module/routine for translation.
B. Add deeper timers under the new top region.
C. Target a broader region rather than one routine.
D. Stop Held-Suarez performance-targeted translation and use it as architecture
   prototype only.
```

Current recommendation before new measurements:

```text
Run T85L25 first.  Use T170L25 only after T85L25 confirms that hotspot ranking
changes enough to justify the larger run cost.
```
