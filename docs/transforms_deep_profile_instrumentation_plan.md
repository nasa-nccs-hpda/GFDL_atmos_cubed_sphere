# Spectral Transforms Deep Profiling Instrumentation Plan

Date: 2026-07-22

## Goal

Design non-invasive deep profiling for the Held-Suarez spectral transforms
region. The current T85L25 broad dynamics profile shows:

| Region | Time (s) | Runtime % | Calls |
|---|---:|---:|---:|
| `transforms` | 142.453 | 46.54% | 43200 |
| `tracer_correction_diagnostics` | 65.415 | 21.37% | 8640 |
| `advection` | 33.061 | 10.80% | 8640 |
| `press_geopot` | 18.411 | 6.01% | 8640 |

The `transforms` timer is the primary performance target, but it is still too
coarse to select a translation or GPU strategy. The next step is to split it
into call-site and internal-stage timers without changing algorithms or
modifying production source files.

## Constraints

- Do not modify production Fortran source files under `src/atmos_spectral/`.
- Use overlay sources under `src/extra/local_overrides/`.
- Use native Isca `CodeBase.compile()` path.
- Keep all instrumentation behind a compile flag.
- Do not translate transform code yet.
- Do not change model numerics.
- Print reliable runtime markers at shutdown, using max reduction across MPI
  ranks where possible.

## Relevant Source Files

Production files:

```text
src/atmos_spectral/model/spectral_dynamics.F90
src/atmos_spectral/tools/transforms.F90
src/atmos_spectral/tools/grid_fourier.F90
src/atmos_spectral/tools/spherical_fourier.F90
src/atmos_spectral/tools/spherical.F90
src/atmos_spectral/tools/spec_mpp.F90
src/shared/fft/fft.F90
src/shared/fft/fft99.F90
```

Existing overlay:

```text
src/extra/local_overrides/spectral_dynamics/spectral_dynamics.F90
```

Recommended new overlay directory:

```text
src/extra/local_overrides/transforms_deep/
```

Recommended copied overlay files:

```text
src/extra/local_overrides/transforms_deep/transforms.F90
src/extra/local_overrides/transforms_deep/grid_fourier.F90
src/extra/local_overrides/transforms_deep/spherical_fourier.F90
```

Optional later overlays:

```text
src/extra/local_overrides/transforms_deep/spherical.F90
src/extra/local_overrides/transforms_deep/fft.F90
```

Start without `spherical.F90` and `fft.F90` unless the first transform-stage
profile shows that the remaining time is still too coarse.

## Current Call-Site Layer

The existing `PROFILE_DYNAMICS_DEEP` overlay already separates transform
call sites inside `spectral_dynamics.F90`:

```text
transform_dt_ln_ps
transform_dt_t
transform_vor_div_from_uv
transform_phis_plus_ke
transform_future_div
transform_future_vor
transform_future_uv_from_vor_div
transform_future_t
transform_future_ln_ps
tracer_grid_to_spectral
tracer_spectral_to_grid
```

This layer identifies which model variables call the transform stack. It does
not identify whether time is spent in FFT, Legendre transforms, transposes,
MPI/domain updates, truncation, or helper math.

## Transform Internals To Split

### `trans_grid_to_spherical_3d`

Source:

```text
src/atmos_spectral/tools/transforms.F90
```

Current stages:

1. Domain validation.
2. `mpp_get_compute_domain(grid_domain, x_is_global=...)`.
3. If X is not global:
   - copy local grid slab to `grid_xglobal(is:ie,:,:)`
   - `mpp_update_domains(grid_xglobal, grid_domain, XUPDATE)`
4. `trans_grid_to_fourier(...)`
5. Fourier truncation zeroing.
6. `transpose_fourier(fourier_g, fourier_s)`
7. `trans_fourier_to_spherical(fourier_s, spherical)`
8. Optional triangular or rhomboidal truncation.

Recommended timers:

```text
PROFILE_TRANSFORM_STAGE name=g2s_total
PROFILE_TRANSFORM_STAGE name=g2s_x_update
PROFILE_TRANSFORM_STAGE name=g2s_grid_to_fourier_fft
PROFILE_TRANSFORM_STAGE name=g2s_fourier_truncation
PROFILE_TRANSFORM_STAGE name=g2s_transpose_fourier
PROFILE_TRANSFORM_STAGE name=g2s_fourier_to_spherical_legendre
PROFILE_TRANSFORM_STAGE name=g2s_spectral_truncation
```

### `trans_spherical_to_grid_3d`

Current stages:

1. Domain validation.
2. `trans_spherical_to_fourier(spherical, fourier_s)`
3. If spectral Y is not global:
   - build spectral Y pelist
   - `mpp_sum(fourier_s, ..., pelist)`
4. `reverse_transpose_fourier(fourier_s, fourier_g)`
5. Fourier truncation zeroing.
6. If grid X is not global:
   - `grid_xglobal = trans_fourier_to_grid(fourier_g)`
   - copy `grid_xglobal(is:ie,:,:)` to local grid
7. Else assign `grid = trans_fourier_to_grid(fourier_g)`.

Recommended timers:

```text
PROFILE_TRANSFORM_STAGE name=s2g_total
PROFILE_TRANSFORM_STAGE name=s2g_spherical_to_fourier_legendre
PROFILE_TRANSFORM_STAGE name=s2g_spectral_y_sum
PROFILE_TRANSFORM_STAGE name=s2g_reverse_transpose_fourier
PROFILE_TRANSFORM_STAGE name=s2g_fourier_truncation
PROFILE_TRANSFORM_STAGE name=s2g_fourier_to_grid_fft
PROFILE_TRANSFORM_STAGE name=s2g_grid_extract
```

### `vor_div_from_uv_grid_3d`

Current stages:

1. `grid_tmp = u_grid`
2. `divide_by_cos(grid_tmp)`
3. `trans_grid_to_spherical(grid_tmp, dx_spec, do_truncation=.false.)`
4. `grid_tmp = v_grid`
5. `divide_by_cos(grid_tmp)`
6. `trans_grid_to_spherical(grid_tmp, dy_spec, do_truncation=.false.)`
7. `compute_vor_div(dx_spec, dy_spec, vor_spec, div_spec)`
8. Optional truncation of `vor_spec` and `div_spec`.

Recommended timers:

```text
PROFILE_TRANSFORM_STAGE name=vor_div_total
PROFILE_TRANSFORM_STAGE name=vor_div_u_copy
PROFILE_TRANSFORM_STAGE name=vor_div_u_divide_by_cos
PROFILE_TRANSFORM_STAGE name=vor_div_u_g2s
PROFILE_TRANSFORM_STAGE name=vor_div_v_copy
PROFILE_TRANSFORM_STAGE name=vor_div_v_divide_by_cos
PROFILE_TRANSFORM_STAGE name=vor_div_v_g2s
PROFILE_TRANSFORM_STAGE name=vor_div_compute_vor_div
PROFILE_TRANSFORM_STAGE name=vor_div_truncation
```

### `uv_grid_from_vor_div_3d`

Current stages:

1. `compute_ucos_vcos(vor_spec, div_spec, dx_spec, dy_spec)`
2. `trans_spherical_to_grid(dx_spec, u_grid)`
3. `trans_spherical_to_grid(dy_spec, v_grid)`
4. `divide_by_cos(u_grid)`
5. `divide_by_cos(v_grid)`

Recommended timers:

```text
PROFILE_TRANSFORM_STAGE name=uv_from_vor_div_total
PROFILE_TRANSFORM_STAGE name=uv_compute_ucos_vcos
PROFILE_TRANSFORM_STAGE name=uv_dx_s2g
PROFILE_TRANSFORM_STAGE name=uv_dy_s2g
PROFILE_TRANSFORM_STAGE name=uv_u_divide_by_cos
PROFILE_TRANSFORM_STAGE name=uv_v_divide_by_cos
```

## Lower-Level Transform Modules

### `grid_fourier.F90`

This module wraps the longitude FFT path:

```text
trans_grid_to_fourier
trans_fourier_to_grid
```

Recommended timers:

```text
PROFILE_TRANSFORM_STAGE name=fft_forward_total
PROFILE_TRANSFORM_STAGE name=fft_forward_pack_or_shape
PROFILE_TRANSFORM_STAGE name=fft_forward_kernel
PROFILE_TRANSFORM_STAGE name=fft_inverse_total
PROFILE_TRANSFORM_STAGE name=fft_inverse_kernel
PROFILE_TRANSFORM_STAGE name=fft_inverse_unpack_or_shape
```

If the code path calls directly into `fft_grid_to_fourier` and
`fft_fourier_to_grid`, first time only around the wrapper calls. Add deeper
`fft.F90` timers only if FFT wrapper time remains dominant and unclear.

### `spherical_fourier.F90`

This module wraps the latitude/spherical harmonic path:

```text
trans_spherical_to_fourier_3d
trans_fourier_to_spherical_3d
```

Recommended timers:

```text
PROFILE_TRANSFORM_STAGE name=legendre_inverse_total
PROFILE_TRANSFORM_STAGE name=legendre_inverse_loop
PROFILE_TRANSFORM_STAGE name=legendre_forward_total
PROFILE_TRANSFORM_STAGE name=legendre_forward_loop
PROFILE_TRANSFORM_STAGE name=legendre_data_layout
```

This is the most likely place to expose whether the dominant cost is associated
Legendre work rather than FFT or communication.

## Timer Mechanism

Use the same lightweight style as existing profiling overlays:

```fortran
call system_clock(t0, rate)
...
call system_clock(t1)
seconds = seconds + real(t1 - t0) / real(rate)
calls = calls + 1
```

At shutdown, use:

```fortran
call mpp_max(seconds_max)
call mpp_max(calls_max)
```

Print from root PE only.

Preferred output marker:

```text
PROFILE_TRANSFORM_STAGE name=<stage> calls_max=... time_max=... avg_max=...
```

Optional second marker for call sites:

```text
PROFILE_TRANSFORM_CALLSITE name=<callsite> calls_max=... time_max=... avg_max=...
```

If both `PROFILE_DYNAMICS_DEEP` and `PROFILE_TRANSFORMS_DEEP` are enabled,
keep marker names distinct.

## Compile Flags

Recommended new compile flag:

```text
-DPROFILE_TRANSFORMS_DEEP
```

Recommended combined profiling executable:

```text
held_suarez_profile_transforms_deep.x
```

This executable should include:

```text
-DPROFILE_DYNAMICS_DEEP
-DPROFILE_TRANSFORMS_DEEP
```

Reason: `PROFILE_DYNAMICS_DEEP` tells which model-level transform call sites
matter. `PROFILE_TRANSFORMS_DEEP` tells which internal transform stages matter.

## Build-System Plan

Add a new `DryCodeBase` subclass in:

```text
hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py
```

Suggested name:

```text
HeldSuarezTransformsDeepProfileCodeBase
```

Suggested target:

```text
profile_transforms_deep
```

Suggested executable:

```text
held_suarez_profile_transforms_deep.x
```

The subclass should replace these path_names entries:

```text
atmos_spectral/model/spectral_dynamics.F90
atmos_spectral/tools/transforms.F90
atmos_spectral/tools/grid_fourier.F90
atmos_spectral/tools/spherical_fourier.F90
```

with:

```text
extra/local_overrides/spectral_dynamics/spectral_dynamics.F90
extra/local_overrides/transforms_deep/transforms.F90
extra/local_overrides/transforms_deep/grid_fourier.F90
extra/local_overrides/transforms_deep/spherical_fourier.F90
```

Add compile flags:

```text
-DPROFILE_DYNAMICS_DEEP
-DPROFILE_TRANSFORMS_DEEP
```

Do not modify mkmf manually.

## Step-By-Step Implementation Plan

### Step 1: Confirm Current Call-Site Timing

Run or reuse a T85L25 `PROFILE_DYNAMICS_DEEP` run before adding internals.

Expected markers:

```text
PROFILE_DYNAMICS_DEEP name=transform_dt_ln_ps
PROFILE_DYNAMICS_DEEP name=transform_dt_t
PROFILE_DYNAMICS_DEEP name=transform_vor_div_from_uv
PROFILE_DYNAMICS_DEEP name=transform_phis_plus_ke
PROFILE_DYNAMICS_DEEP name=transform_future_div
PROFILE_DYNAMICS_DEEP name=transform_future_vor
PROFILE_DYNAMICS_DEEP name=transform_future_uv_from_vor_div
PROFILE_DYNAMICS_DEEP name=transform_future_t
PROFILE_DYNAMICS_DEEP name=transform_future_ln_ps
```

Pass condition:

```text
Call-site timers roughly sum to the broad transforms timer.
```

If they do not, add missing transform call-site timers before instrumenting
internal modules.

### Step 2: Create Overlay Copies

Copy production files into a new overlay directory:

```text
src/extra/local_overrides/transforms_deep/transforms.F90
src/extra/local_overrides/transforms_deep/grid_fourier.F90
src/extra/local_overrides/transforms_deep/spherical_fourier.F90
```

No changes to production source.

### Step 3: Add Local Timer State

In each overlay module, add module-level arrays guarded by:

```fortran
#ifdef PROFILE_TRANSFORMS_DEEP
...
#endif
```

Recommended shared stage list should live in `transforms.F90` first. If
`grid_fourier.F90` and `spherical_fourier.F90` need independent local state,
use the same output marker but distinct stage names.

Avoid cross-module timer dependencies at first. Duplicate tiny timer helpers in
each overlay module if that keeps compile/link risk lower.

### Step 4: Instrument `transforms.F90`

Add timers around the stages listed above in:

```text
trans_grid_to_spherical_3d
trans_spherical_to_grid_3d
vor_div_from_uv_grid_3d
uv_grid_from_vor_div_3d
```

Keep 2D wrapper routines uninstrumented initially because they call the 3D
routines. This avoids double counting.

### Step 5: Instrument `grid_fourier.F90`

Add timers around:

```text
trans_grid_to_fourier
trans_fourier_to_grid
```

If there is a clear single FFT library call inside each routine, add one inner
timer around that call. Do not instrument every inner loop yet.

### Step 6: Instrument `spherical_fourier.F90`

Add timers around:

```text
trans_spherical_to_fourier_3d
trans_fourier_to_spherical_3d
```

Then add inner timers around the dominant loop blocks that perform Legendre
projection/reconstruction, if the code structure makes those blocks clear.

### Step 7: Add Reliable Printing

Printing options:

1. Preferred: print from `transforms_end`, `grid_fourier_end`, and
   `spherical_fourier_end` if those finalizers are reliably called.
2. Fallback: expose small public report subroutines and call them from
   `spectral_dynamics_end` in the overlay.

Use fallback if finalizers are uncertain. This project already saw one case
where a module finalizer did not print in the Held-Suarez shutdown path.

Recommended public report routine names:

```fortran
call transforms_profile_report()
call grid_fourier_profile_report()
call spherical_fourier_profile_report()
```

Guard imports and calls with `#ifdef PROFILE_TRANSFORMS_DEEP`.

### Step 8: Add Native Build Target

Add `profile_transforms_deep` to `compile_native_overlay.py`.

Verify generated `path_names` contains overlay versions of:

```text
spectral_dynamics.F90
transforms.F90
grid_fourier.F90
spherical_fourier.F90
```

Pass condition:

```text
mkmf Makefile is populated and held_suarez_profile_transforms_deep.x builds.
```

### Step 9: Run Short Smoke Test

Run T42L25 or T85L25 for 1 day first.

Expected markers:

```text
PROFILE_DYNAMICS_DEEP name=...
PROFILE_TRANSFORM_STAGE name=...
Integration completed through 2000 Jan  2
```

Pass condition:

```text
Run completes and transform stage timers print once.
```

### Step 10: Run T85L25 30-Day Profile

Use the same external `srun` pattern that worked for the T85L25 broad profile.

Recommended log:

```text
logs/T85L25_transforms_deep_profile_16node_30day.log
```

Pass condition:

```text
Run completes through 2000 Feb 1 and prints all expected markers.
```

### Step 11: Analyze Results

Create:

```text
docs/T85L25_transforms_deep_profile_recommendation.md
```

Report:

- total model MPP runtime;
- model-level transform call-site ranking;
- transform internal-stage ranking;
- estimated fraction of broad `transforms` time explained by stages;
- FFT vs Legendre vs communication vs transposition split;
- best next modernization boundary.

## Expected Decisions After Profiling

### If Legendre dominates

Likely next strategy:

```text
Study GPU/vendor/library spherical harmonic transform path.
```

This is high payoff but likely high coupling.

### If FFT dominates

Likely next strategy:

```text
Prototype cuFFT replacement or batched FFT microbenchmark.
```

This may be cleaner than full transform translation if data layout is regular.

### If transposes or MPI reductions dominate

Likely next strategy:

```text
Do not translate local kernels first. Study decomposition, communication,
packing, and memory layout.
```

GPU kernel translation alone will not solve the bottleneck.

### If one model call site dominates

Likely next strategy:

```text
Build a baseline harness for that call-site boundary and translate only the
required helper stack.
```

Candidate call sites include:

```text
transform_vor_div_from_uv
transform_future_uv_from_vor_div
transform_dt_t
```

## Risks

- Overlaying tool modules may change compile order or expose hidden path_names
  assumptions.
- Finalizer-based printing may not run; use `spectral_dynamics_end` fallback.
- Stage timers can double count nested routines if call-site and internal
  timers are summed blindly.
- `system_clock` overhead should be small relative to T85L25 transform cost,
  but tiny stage timers may be noisy.
- Transform routines use automatic arrays; timing may include stack allocation
  costs, which is useful but should be labeled as wrapper/stage overhead.
- MPI warnings in Slurm/PMIx logs may be noisy but are acceptable if the model
  completes and markers print.

## Success Criteria

The instrumentation phase succeeds when:

1. `held_suarez_profile_transforms_deep.x` builds through `CodeBase.compile()`.
2. A 1-day smoke test completes and prints `PROFILE_TRANSFORM_STAGE` markers.
3. A T85L25 30-day run completes.
4. The report can rank:
   - model-level transform call sites;
   - FFT time;
   - Legendre time;
   - transpose/packing time;
   - MPI/domain update or reduction time;
   - truncation/helper math time.

Only after those criteria are met should the project choose a transform
modernization strategy.

