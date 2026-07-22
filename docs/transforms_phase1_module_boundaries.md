# Spectral Transforms Phase 1 Module Boundaries

Date: 2026-07-22

## Purpose

Locate the Held-Suarez spectral transform module boundaries before adding deep
profiling instrumentation. This phase does not modify production source and
does not start translation.

T85L25 broad profiling identified `transforms` as the primary measured
performance region:

```text
PROFILE_DYNAMICS_REGION name=transforms calls_max=43200 time_max=142.453 s
T85L25 MPP runtime fraction = 46.54%
```

## Files To Instrument

The Held-Suarez dry path uses the following transform stack entries from
`src/extra/model/dry/path_names`:

| Path Names Line | File | Module | Role | Instrument Now? |
|---:|---|---|---|---|
| 55 | `atmos_spectral/model/spectral_dynamics.F90` | `spectral_dynamics_mod` | Dynamics timestep, model-level transform call sites | Already overlaid; extend if needed |
| 58 | `atmos_spectral/tools/gauss_and_legendre.F90` | `gauss_and_legendre_mod` | Initializes Gaussian latitudes and Legendre tables | No, initialization only for first pass |
| 59 | `atmos_spectral/tools/grid_fourier.F90` | `grid_fourier_mod` | Grid/Fourier wrapper, longitude FFT entry | Yes |
| 60 | `atmos_spectral/tools/spec_mpp.F90` | `spec_mpp_mod` | Grid/spectral domain decomposition | No, inspect only unless communication dominates |
| 61 | `atmos_spectral/tools/spherical.F90` | `spherical_mod` | Spectral derivatives, vorticity/divergence helpers, truncation | Later if helper math dominates |
| 62 | `atmos_spectral/tools/spherical_fourier.F90` | `spherical_fourier_mod` | Fourier/spherical conversion, Legendre loops | Yes |
| 63 | `atmos_spectral/tools/transforms.F90` | `transforms_mod` | Public transform facade and transpose/MPI stages | Yes |
| 75 | `shared/fft/fft99.F90` | `fft99_mod` | Temperton FFT implementation | No initially, instrument only if FFT wrapper dominates |
| 76 | `shared/fft/fft.F90` | `fft_mod` | FFT public wrapper over Temperton/SGI/NAG paths | Later if needed |

Recommended overlay files for Phase 2:

```text
src/extra/local_overrides/transforms_deep/transforms.F90
src/extra/local_overrides/transforms_deep/grid_fourier.F90
src/extra/local_overrides/transforms_deep/spherical_fourier.F90
```

Existing call-site overlay:

```text
src/extra/local_overrides/spectral_dynamics/spectral_dynamics.F90
```

Do not overlay `fft.F90`, `fft99.F90`, `spherical.F90`, or `spec_mpp.F90` in
the first deep-transform pass unless the first results show the need.

## Module Inventory

### `spectral_dynamics_mod`

File:

```text
src/atmos_spectral/model/spectral_dynamics.F90
```

Important transform call sites during the timestep:

```text
trans_grid_to_spherical(dt_ln_psg, dt_ln_ps)
trans_grid_to_spherical(dt_tg_tmp, dt_ts)
vor_div_from_uv_grid(dt_ug_tmp, dt_vg_tmp, dt_vors, dt_divs)
trans_grid_to_spherical(phig_full_plus_ke, phis_plus_ke)
trans_spherical_to_grid(divs(:,:,:,future), divg)
trans_spherical_to_grid(vors(:,:,:,future), vorg)
uv_grid_from_vor_div(vors(:,:,:,future), divs(:,:,:,future), ug, vg)
trans_spherical_to_grid(ts(:,:,:,future), tg)
trans_spherical_to_grid(ln_ps(:,:,future), ln_psg)
```

Other transform calls occur in initialization, tracer update, diagnostics, and
helper routines, but the above are the main timestep transform region currently
wrapped by broad and deep dynamics timers.

### `transforms_mod`

File:

```text
src/atmos_spectral/tools/transforms.F90
```

Public facade for:

```text
trans_grid_to_spherical
trans_spherical_to_grid
vor_div_from_uv_grid
uv_grid_from_vor_div
horizontal_advection
divide_by_cos
divide_by_cos2
trans_filter
```

Important internal stages:

```text
mpp_update_domains(..., XUPDATE)
trans_grid_to_fourier
transpose_fourier
trans_fourier_to_spherical
trans_spherical_to_fourier
mpp_sum
reverse_transpose_fourier
trans_fourier_to_grid
triangular_truncation / rhomboidal_truncation
mpp_transmit
mpp_sync / mpp_sync_self
```

### `grid_fourier_mod`

File:

```text
src/atmos_spectral/tools/grid_fourier.F90
```

Public interface:

```text
trans_grid_to_fourier
trans_fourier_to_grid
```

Uses:

```text
use fft_mod, only: fft_init, fft_grid_to_fourier, fft_fourier_to_grid
```

This is the first clean boundary for longitude FFT timing.

### `spherical_fourier_mod`

File:

```text
src/atmos_spectral/tools/spherical_fourier.F90
```

Public interface:

```text
trans_spherical_to_fourier
trans_fourier_to_spherical
```

Important loops:

```text
trans_spherical_to_fourier_3d:
  DOMAIN_LOOP over mirrored latitude domains
    j loop
      k vertical level loop
        m Fourier wavenumber loop
          n spherical wavenumber accumulation

trans_fourier_to_spherical_3d:
  DOMAIN_LOOP over mirrored latitude domains
    j loop
      k vertical level loop
        m Fourier wavenumber loop
          n spherical wavenumber accumulation using legendre_wts
```

This is the first clean boundary for Legendre-transform timing.

### `spherical_mod`

File:

```text
src/atmos_spectral/tools/spherical.F90
```

Important routines used by transform wrappers:

```text
compute_ucos_vcos
compute_vor_div
compute_laplacian
triangular_truncation
rhomboidal_truncation
compute_gradient_cos
```

This module is not the first instrumentation target. Add timers here only if
`vor_div_from_uv_grid`, `uv_grid_from_vor_div`, truncation, or derivative helper
stages dominate after Phase 2.

### `spec_mpp_mod`

File:

```text
src/atmos_spectral/tools/spec_mpp.F90
```

Defines grid and spectral domains:

```text
grid_domain
spectral_domain
global_spectral_domain
atmosphere_domain
```

The transform stack calls MPP/domain routines through these domains. This is
not a numerical transform target, but it is important for interpreting
communication and transpose timings.

### FFT Modules

Files:

```text
src/shared/fft/fft.F90
src/shared/fft/fft99.F90
```

Modules:

```text
fft_mod
fft99_mod
```

`fft_mod` exposes:

```text
fft_init
fft_grid_to_fourier
fft_fourier_to_grid
```

`fft99_mod` provides the Temperton FFT routines:

```text
fft991
set99
```

The expected default path in the current container is the custom Temperton FFT
branch, not vendor FFT:

```text
fft_grid_to_fourier -> fft991(..., isign=-1)
fft_fourier_to_grid -> fft991(..., isign=+1)
```

Conditional vendor branches exist for SGI/Cray and NAG:

```text
SGICRAY: scfftm / csfftm
NAGFFT: NAG path
default: Temperton fft991
```

No evidence in the current build path suggests SGICRAY or NAGFFT is used.

## Call Tree Diagram

Main timestep transform path:

```text
spectral_dynamics_mod::spectral_dynamics
|
|-- trans_grid_to_spherical(dt_ln_psg, dt_ln_ps)
|   `-- transforms_mod::trans_grid_to_spherical_2d/3d
|       |-- mpp_update_domains(..., XUPDATE)          [if grid X is not global]
|       |-- grid_fourier_mod::trans_grid_to_fourier
|       |   `-- fft_mod::fft_grid_to_fourier
|       |       `-- fft99_mod::fft991                 [default Temperton FFT]
|       |-- transforms_mod::transpose_fourier
|       |   |-- mpp_transmit
|       |   `-- mpp_sync
|       |-- spherical_fourier_mod::trans_fourier_to_spherical
|       |   `-- Legendre accumulation loops
|       `-- spherical_mod::triangular_truncation or rhomboidal_truncation
|
|-- trans_grid_to_spherical(dt_tg_tmp, dt_ts)
|   `-- same grid -> Fourier -> spherical path
|
|-- vor_div_from_uv_grid(dt_ug_tmp, dt_vg_tmp, dt_vors, dt_divs)
|   `-- transforms_mod::vor_div_from_uv_grid_3d
|       |-- copy u_grid to grid_tmp
|       |-- transforms_mod::divide_by_cos
|       |-- trans_grid_to_spherical(grid_tmp, dx_spec, do_truncation=.false.)
|       |-- copy v_grid to grid_tmp
|       |-- transforms_mod::divide_by_cos
|       |-- trans_grid_to_spherical(grid_tmp, dy_spec, do_truncation=.false.)
|       |-- spherical_mod::compute_vor_div
|       `-- spherical_mod::triangular_truncation / rhomboidal_truncation
|
|-- trans_grid_to_spherical(phig_full_plus_ke, phis_plus_ke)
|   `-- same grid -> Fourier -> spherical path
|
|-- trans_spherical_to_grid(divs_future, divg)
|   `-- transforms_mod::trans_spherical_to_grid_3d
|       |-- spherical_fourier_mod::trans_spherical_to_fourier
|       |   `-- inverse Legendre accumulation loops
|       |-- mpp_sum(fourier_s, pelist)                [if spectral Y not global]
|       |-- transforms_mod::reverse_transpose_fourier
|       |   |-- mpp_transmit
|       |   `-- mpp_sync
|       |-- grid_fourier_mod::trans_fourier_to_grid
|       |   `-- fft_mod::fft_fourier_to_grid
|       |       `-- fft99_mod::fft991                 [default Temperton FFT]
|       `-- local grid extraction                     [if grid X not global]
|
|-- trans_spherical_to_grid(vors_future, vorg)
|   `-- same spherical -> Fourier -> grid path
|
|-- uv_grid_from_vor_div(vors_future, divs_future, ug_future, vg_future)
|   `-- transforms_mod::uv_grid_from_vor_div_3d
|       |-- spherical_mod::compute_ucos_vcos
|       |-- trans_spherical_to_grid(dx_spec, u_grid)
|       |-- trans_spherical_to_grid(dy_spec, v_grid)
|       |-- transforms_mod::divide_by_cos(u_grid)
|       `-- transforms_mod::divide_by_cos(v_grid)
|
|-- trans_spherical_to_grid(ts_future, tg_future)
|   `-- same spherical -> Fourier -> grid path
|
`-- trans_spherical_to_grid(ln_ps_future, ln_psg)
    `-- same spherical -> Fourier -> grid path
```

Initialization and diagnostics also call transform routines. The Phase 2 timers
should keep initialization separate where possible by using the existing
simulation shutdown aggregate, then interpreting call counts carefully.

## Existing Timer Infrastructure

### FMS/MPP Clocks

FMS exposes:

```text
mpp_clock_id
mpp_clock_begin
mpp_clock_end
MPP_CLOCK_SYNC
MPP_CLOCK_DETAILED
CLOCK_COMPONENT
CLOCK_SUBCOMPONENT
CLOCK_MODULE_DRIVER
CLOCK_MODULE
CLOCK_ROUTINE
CLOCK_LOOP
CLOCK_INFRA
```

Examples exist in:

```text
src/atmos_solo/atmos_model.F90
src/atmos_param/ras/moist_processes.f90
src/shared/horiz_interp/horiz_interp.F90
src/shared/mpp/include/*.inc
```

The MPP runtime summary is already generated through this system:

```text
Total runtime ...
Tabulating mpp_clock statistics across ...
```

### Transform-Specific Existing Timers

No dedicated `mpp_clock_id` timers were found in:

```text
src/atmos_spectral/tools/transforms.F90
src/atmos_spectral/tools/grid_fourier.F90
src/atmos_spectral/tools/spherical_fourier.F90
src/atmos_spectral/tools/spherical.F90
src/shared/fft/fft.F90
src/shared/fft/fft99.F90
```

### Project Profiling Convention

The existing modernization overlays use explicit `system_clock` timers guarded
by compile flags. They accumulate module-level seconds and call counts, then
print greppable markers at shutdown with `mpp_max`.

Existing compile flags:

```text
-DPROFILE_FOUR_IN_ONE
-DPROFILE_VERT_ADVECTION
-DPROFILE_DYNAMICS_REGIONS
-DPROFILE_DYNAMICS_DEEP
```

Existing marker conventions:

```text
PROFILE_FOUR_IN_ONE calls_max=... seconds_max=... avg_seconds_per_call_max=...
PROFILE_VERT_ADVECTION_CALLSITE field=u calls_max=... time_max=... avg_max=...
PROFILE_DYNAMICS_REGION name=<region> calls_max=... time_max=... avg_max=...
PROFILE_DYNAMICS_DEEP name=<region> calls_max=... time_max=... avg_max=...
```

Recommended transform marker convention:

```text
PROFILE_TRANSFORM_STAGE name=<stage> calls_max=... time_max=... avg_max=...
```

Recommended compile flag:

```text
-DPROFILE_TRANSFORMS_DEEP
```

## Existing Dynamics Deep Timer IDs

The existing `src/extra/local_overrides/spectral_dynamics/spectral_dynamics.F90`
defines transform-related call-site IDs:

```text
profile_deep_transform_dt_ln_ps
profile_deep_transform_dt_t
profile_deep_transform_vor_div_from_uv
profile_deep_transform_phis_plus_ke
profile_deep_transform_future_div
profile_deep_transform_future_vor
profile_deep_transform_future_uv
profile_deep_transform_future_t
profile_deep_transform_future_ln_ps
profile_deep_tracer_grid_to_spectral
profile_deep_tracer_spectral_to_grid
```

These are call-site timers, not internal transform-stage timers.

## Recommended Phase 2 Instrumentation Boundary

Instrument these three overlay files first:

```text
src/extra/local_overrides/transforms_deep/transforms.F90
src/extra/local_overrides/transforms_deep/grid_fourier.F90
src/extra/local_overrides/transforms_deep/spherical_fourier.F90
```

Do not instrument `fft99.F90` first. The `grid_fourier_mod` wrapper can time
the FFT library call at a cleaner boundary. If FFT wrapper time dominates and
is still ambiguous, then overlay `shared/fft/fft.F90` in a later phase.

Do not instrument `gauss_and_legendre.F90` first. It builds tables during
initialization, not every timestep.

Do not instrument `spec_mpp.F90` first. Its domain definitions are important,
but runtime communication is visible through `mpp_update_domains`, `mpp_sum`,
`mpp_transmit`, and `mpp_sync` calls in `transforms.F90`.

## Key Questions Phase 2 Should Answer

1. Is transform time dominated by Legendre loops in `spherical_fourier_mod`?
2. Is transform time dominated by FFT calls in `grid_fourier_mod`/`fft_mod`?
3. Is transform time dominated by transpose communication in
   `transpose_fourier` / `reverse_transpose_fourier`?
4. Is there significant time in `mpp_update_domains` or `mpp_sum`?
5. Which model-level transform call site contributes the most?
6. Is the best next path:
   - cuFFT/vendor FFT prototype;
   - GPU Legendre transform prototype;
   - communication/decomposition redesign;
   - a narrower call-site translation;
   - or a broader transform-library strategy?

## Phase 1 Conclusion

The transform region is not a single routine. It is a coupled stack:

```text
spectral_dynamics_mod
  -> transforms_mod
    -> grid_fourier_mod -> fft_mod -> fft99_mod
    -> spherical_fourier_mod -> Legendre loops
    -> spherical_mod helper math/truncation
    -> MPP domain/transpose communication
```

The safest next step is a non-invasive overlay profile of
`transforms_mod`, `grid_fourier_mod`, and `spherical_fourier_mod`, preserving
the original source tree and using the existing greppable `PROFILE_*` marker
style.

