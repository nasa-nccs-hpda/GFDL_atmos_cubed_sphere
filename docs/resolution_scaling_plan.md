# Resolution Scaling Profiling Plan

Date: 2026-06-17

## Objective

Evaluate how Held-Suarez hotspot rankings change as model resolution increases.

Current baseline:

```text
T42L25
lon_max = 128
lat_max = 64
num_levels = 25
dt_atmos = 600 s
```

Existing T42L25 profiling summary:

```text
transforms: about 39%
tracer/correction region: about 33%
advection: about 8%
press_geopot: about 5%
four_in_one: about 2.6%
vert_advection_3d: about 0.34%
```

The scaling study also tracks the already-modernized Held-Suarez forcing
module through the hybrid path:

```text
Fortran model -> ISO_C_BINDING wrapper -> C interface -> C++ forcing module
```

That forcing path is controlled at runtime with:

```text
HS_PROFILE=1
HS_FORCE_BACKEND=cpu
```

The goal is not translation yet.  The goal is to determine whether higher
resolution makes a different region the best GPU modernization target.

## Resolution Set

Recommended primary set:

| Resolution | lon_max | lat_max | levels | Horizontal Points | 3D State Cells | Memory Scale Vs T42L25 |
|---|---:|---:|---:|---:|---:|---:|
| T42L25 | 128 | 64 | 25 | 8,192 | 204,800 | 1x |
| T85L25 | 256 | 128 | 25 | 32,768 | 819,200 | 4x |
| T170L25 | 512 | 256 | 25 | 131,072 | 3,276,800 | 16x |

Optional vertical-scaling set:

| Resolution | lon_max | lat_max | levels | Horizontal Points | 3D State Cells | Memory Scale Vs T42L25 |
|---|---:|---:|---:|---:|---:|---:|
| T42L50 | 128 | 64 | 50 | 8,192 | 409,600 | 2x |
| T85L50 | 256 | 128 | 50 | 32,768 | 1,638,400 | 8x |

These grid sizes come from Isca's built-in `Experiment.RESOLUTIONS` table:

```text
T42:  lon_max=128, lat_max=64,  num_fourier=42,  num_spherical=43
T85:  lon_max=256, lat_max=128, num_fourier=85,  num_spherical=86
T170: lon_max=512, lat_max=256, num_fourier=170, num_spherical=171
```

## Runtime Scaling Estimate

There are two useful estimates:

1. Fixed timestep estimate: assumes `dt_atmos = 600 s` at all resolutions.
2. CFL-adjusted estimate: halves `dt_atmos` for each horizontal doubling.

Recommended stable profiling timestep plan:

| Resolution | Suggested dt_atmos | Timesteps Per 30 Days | Step Count Scale |
|---|---:|---:|---:|
| T42L25 | 600 s | 4,320 | 1x |
| T85L25 | 300 s | 8,640 | 2x |
| T170L25 | 150 s | 17,280 | 4x |
| T42L50 | 600 s | 4,320 | 1x |
| T85L50 | 300 s | 8,640 | 2x |

Expected wall-clock increase relative to T42L25:

| Resolution | Fixed-dt Estimate | CFL-adjusted Estimate | Notes |
|---|---:|---:|---|
| T42L25 | 1x | 1x | Current baseline. |
| T85L25 | 4-5x | 8-10x | 4x more grid cells plus about 2x more steps if dt is halved. |
| T170L25 | 16-22x | 64-88x | 16x more grid cells plus about 4x more steps if dt is quartered. |
| T42L50 | 1.6-2.2x | 1.6-2.2x | Vertical work doubles; some 2D/transform overhead does not. |
| T85L50 | 7-11x | 14-22x | Combined horizontal and vertical growth. |

These are planning estimates, not measured results.  Spectral transforms may
scale somewhat worse than pure grid-cell count because Fourier/spherical
transform work grows superlinearly with horizontal resolution.

## Profiling Workflow Per Resolution

For each resolution, run:

1. All-Fortran baseline executable.
2. Held-Suarez forcing-module profile through the hybrid C++ executable.
3. Dynamics-region profile executable.
4. Dynamics-deep profile executable.
5. `four_in_one` profile executable.
6. `vert_advection` call-site profile executable.

Executable mapping:

| Variant | Build Target | Executable |
|---|---|---|
| all-Fortran baseline | `fortran` | `held_suarez_fortran.x` |
| forcing-module hybrid C++ profile | `hybrid` | `held_suarez_hybrid.x` |
| dynamics-region profile | `profile_dynamics_regions` | `held_suarez_profile_dynamics_regions.x` |
| dynamics-deep profile | `profile_dynamics_deep` | `held_suarez_profile_dynamics_deep.x` |
| four_in_one profile | `profile_four_in_one` | `held_suarez_profile_four_in_one.x` |
| vert_advection profile | `profile_vert_advection` | `held_suarez_profile_vert_advection.x` |

Build path:

```bash
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py <target>
```

The hybrid executable must be built with:

```bash
GFDL_ENV=hybrid python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py hybrid
```

The scaling script handles this automatically.

## Forcing-Module Timing

Forcing timing is currently available for the hybrid C++ path through
`HS_PROFILE=1`.  This reports:

```text
HS_PROFILE Fortran wrapper profile summary
HS_PROFILE C++ forcing profile summary
```

The scaling run records this as:

```text
hs_forcing_time
hs_forcing_percent
forcing_cpp_hybrid_runtime
```

Fortran forcing-specific timing is not currently available in the unchanged
all-Fortran production executable.  The all-Fortran baseline still records
whole-model runtime, and `forcing_fortran_runtime` / `forcing_speedup` should
remain `TBD` until a non-invasive Fortran forcing timer is added.

Run path:

```bash
scripts/run_resolution_scaling_profiles.sh
```

## Recommended Pilot

Run a short pilot before launching the full matrix:

```bash
SCALING_DAYS=1 SCALING_RESOLUTIONS="T42:25:600 T85:25:300" \
  scripts/run_resolution_scaling_profiles.sh
```

Then run the full 30-day primary matrix:

```bash
SCALING_DAYS=30 SCALING_RESOLUTIONS="T42:25:600 T85:25:300 T170:25:150" \
  scripts/run_resolution_scaling_profiles.sh
```

Run optional vertical-scaling cases separately:

```bash
SCALING_DAYS=30 SCALING_RESOLUTIONS="T42:50:600 T85:50:300" \
  scripts/run_resolution_scaling_profiles.sh
```

## Output Logs

Logs are written under:

```text
logs/resolution_scaling/
```

Expected log naming:

```text
logs/resolution_scaling/build_<target>.log
logs/resolution_scaling/<resolution>_<variant>.log
logs/scaling_<resolution>_forcing_profile.log
```

Examples:

```text
logs/resolution_scaling/T85L25_dynamics_deep.log
logs/resolution_scaling/T170L25_four_in_one.log
logs/scaling_T42L25_forcing_profile.log
logs/scaling_T85L25_forcing_profile.log
logs/scaling_T170L25_forcing_profile.log
```

## How To Compare Hotspots

For each log, extract:

- model MPP wall-clock time;
- shell `real`, `user`, `sys`;
- `PROFILE_DYNAMICS_REGION` markers;
- `PROFILE_DYNAMICS_DEEP` markers;
- `PROFILE_FOUR_IN_ONE` marker;
- `PROFILE_VERT_ADVECTION_CALLSITE` markers.
- `HS_PROFILE` Fortran wrapper and C++ forcing summaries.

Then update:

```text
docs/resolution_scaling_matrix.md
```

with measured percentages for each resolution.

## Best Resolution For Future GPU Target Selection

Recommended target for the next selection pass:

```text
T85L25
```

Rationale:

- 4x larger state than T42L25, so scaling effects should become visible.
- Much cheaper and less risky than T170L25.
- Keeps vertical structure fixed, so changes mostly reflect horizontal scaling.
- More likely to amplify transform and grid-advection costs without making the
  profiling matrix prohibitively expensive.

Use T170L25 as a confirmation case after T85L25 shows a clear change in hotspot
ranking or exposes a promising GPU target.
