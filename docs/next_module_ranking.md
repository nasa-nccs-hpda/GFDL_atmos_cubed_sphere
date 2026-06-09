# Next Held-Suarez Module Ranking

Date: 2026-06-08

## Purpose

The Held-Suarez forcing-module hybrid path is now validated through C++ module
translation, C API validation, native Isca overlay integration, executable
generation, and successful hybrid runs.  The next module should move closer to
dynamics, state update, and timestep integration while still being small enough
to isolate and validate.

This ranking uses the successful `held_suarez_hybrid` build `path_names` as the
source boundary.  Files that are not compiled into the working Held-Suarez
hybrid executable are treated as future GEOS/FV3 relevance, not immediate
prototype candidates.

Successful hybrid build `path_names`:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_hybrid/path_names
```

Excluded for this pass:

- NetCDF and file I/O.
- `diag_manager` and diagnostic-output infrastructure.
- `mpp`/MPI infrastructure and domain-decomposition support code.
- Restart handling.
- Test-only files.
- The already translated Held-Suarez forcing module.

## Scoring Model

Importance score:

- Called every timestep: `+5`
- Directly updates prognostic variables: `+5`
- Large array loops: `+4`
- Central to dynamics/timestep: `+4`
- Many downstream dependencies: `+2`
- Close to GEOS-relevant pattern: `+3`

Penalty:

- MPI/domain decomposition: `-4`
- Heavy I/O/diagnostics: `-5`
- Spectral transform complexity: `-3`
- Too many global side effects: `-3`
- Hard to isolate: `-3`

Scores are static estimates from source inspection.  They should be refined
with profiling before starting a larger translation.

## Ranked Candidates

| Rank | Score | Candidate | Module | Every timestep | Difficulty | GPU suitability | Risk |
|---:|---:|---|---|---|---|---|---|
| 1 | 20 | `src/atmos_spectral/model/spectral_dynamics.F90` local kernel `four_in_one` | `spectral_dynamics_mod` | Yes | Medium-high | High | Medium |
| 2 | 20 | `src/atmos_spectral/model/leapfrog.F90` | `leapfrog_mod` | Yes | Low | Medium | Low |
| 3 | 18 | `src/atmos_spectral/model/press_and_geopot.F90` | `press_and_geopot_mod` | Yes | Medium | High | Medium |
| 4 | 15 | `src/atmos_shared/vert_advection/vert_advection.F90` | `vert_advection_mod` | Yes | High | High | Medium-high |
| 5 | 15 | `src/atmos_spectral/model/spectral_damping.F90` | `spectral_damping_mod` | Yes | Medium | Medium-high | Medium |
| 6 | 13 | `src/atmos_spectral/model/spectral_dynamics.F90` full dynamics routine | `spectral_dynamics_mod` | Yes | Very high | High | High |
| 7 | 9 | `src/atmos_spectral/model/implicit.F90` | `implicit_mod` | Usually | High | Medium | High |
| 8 | 8 | `src/atmos_spectral/tools/transforms.F90` and transform stack | `transforms_mod` | Yes | Very high | Medium | Very high |
| 9 | 8 | `src/atmos_spectral/driver/solo/atmosphere.F90` | `atmosphere_mod` | Yes | High | Low | High |
| 10 | 6 | `src/atmos_spectral/init/vert_coordinate.F90` | `vert_coordinate_mod` | No | Low | Low | Low |
| 11 | 4 | `src/atmos_spectral/model/fv_advection.F90` | `fv_advection_mod` | Tracer-dependent | High | Medium-high | Medium-high |

## Candidate Details

### 1. `spectral_dynamics.F90` local kernel `four_in_one`

File path: `src/atmos_spectral/model/spectral_dynamics.F90`

Module name: `spectral_dynamics_mod`

Key routines:

- `four_in_one`
- Caller: `spectral_dynamics`

Role in Held-Suarez runtime:

`four_in_one` is an internal dynamics kernel called during each spectral
dynamics step.  It computes pressure-gradient/tendency terms, vertical mass
fluxes, surface-pressure tendency, temperature tendency, and wind tendencies.
It is much closer to dynamical-core state update than the forcing module.

Dependencies:

- Module state from `spectral_dynamics_mod`: `rdgas`, `cp_air`, `dpk`, `dbk`,
  `bk`, `num_levels`, `vert_difference_option`, and local grid bounds.
- Inputs from the caller: divergence, winds, temperature, surface pressure,
  pressure/log-pressure arrays, pressure-gradient arrays, and tendency arrays.
- No direct I/O, no MPI calls, no diagnostics.

Called every timestep: yes.

Estimated difficulty: medium-high.  The kernel is compact, but it lives inside a
large module and depends on initialized module state and array lower bounds.

GPU suitability: high.  The work is dominated by vertical-level loops and
grid-array operations over independent columns/cells.

Risk level: medium.  The main risk is preserving exact numerical ordering and
the inout tendency semantics.

Score:

- `+5` every timestep.
- `+5` directly updates prognostic tendencies.
- `+4` large array loops.
- `+4` central to dynamics/timestep.
- `+3` GEOS-relevant pressure-gradient/mass-flux pattern.
- `-1` estimated isolation friction inside a large module.
- Total: `20`.

### 2. `leapfrog.F90`

File path: `src/atmos_spectral/model/leapfrog.F90`

Module name: `leapfrog_mod`

Key routines:

- `leapfrog`
- `leapfrog_2level_A`
- `leapfrog_2level_B`
- `leapfrog_3d_complex`
- `leapfrog_3d_real`
- `leapfrog_2level_A_3d_complex`
- `leapfrog_2level_B_3d_complex`

Role in Held-Suarez runtime:

This module performs the leapfrog update and Robert/RAW filter pieces for
spectral prognostic variables.  `spectral_dynamics` calls it every timestep for
surface pressure, vorticity, divergence, and temperature spectral fields, with
additional tracer use when tracers are active.

Dependencies:

- Minimal dependency surface: primarily `fms_mod` for version/error handling.
- Operates on arrays passed by the caller.
- No I/O, no MPI, no spectral transform calls.

Called every timestep: yes.

Estimated difficulty: low.  This is the cleanest dynamics-adjacent helper in
the Held-Suarez path.

GPU suitability: medium.  The operations are array updates and filters, but the
kernel is relatively small compared with advection, pressure/geopotential, and
transform work.

Risk level: low.  It is highly isolatable and has a small dependency surface.

Score:

- `+5` every timestep.
- `+5` directly updates prognostic spectral coefficients.
- `+4` array loops.
- `+4` central to time integration.
- `+3` GEOS-relevant time-integration pattern.
- Total: `20`.

### 3. `press_and_geopot.F90`

File path: `src/atmos_spectral/model/press_and_geopot.F90`

Module name: `press_and_geopot_mod`

Key routines:

- `pressure_variables`
- `half_level_pressures`
- `compute_geopotential`
- `compute_pressures_and_heights`
- `compute_z_bot`

Role in Held-Suarez runtime:

This module computes half-level and full-level pressures, log-pressure arrays,
geopotential, and heights.  It is called during initialization and repeatedly
during timestep execution.  `spectral_dynamics` calls `pressure_variables` and
`compute_geopotential`; the atmosphere driver also calls
`compute_pressures_and_heights` after the future state is produced.

Dependencies:

- `fms_mod` for error/version handling.
- `constants_mod` for `grav`, `rdgas`, and `rvgas`.
- Module state initialized from vertical-coordinate arrays `pk` and `bk`.
- Optional humidity input for virtual temperature.

Called every timestep: yes.

Estimated difficulty: medium.  The routines are compact and physically clear,
but depend on module initialization and vertical-coordinate state.

GPU suitability: high.  The core work is column-wise pressure and hydrostatic
vertical integration over regular arrays.

Risk level: medium.  Exact comparison should be tractable, but this feeds many
downstream dynamics calculations, so small differences can propagate.

Score:

- `+5` every timestep.
- `+4` large array loops.
- `+4` central to dynamics/timestep.
- `+2` many downstream dependencies.
- `+3` GEOS-relevant pressure/geopotential pattern.
- Total: `18`.

### 4. `vert_advection.F90`

File path: `src/atmos_shared/vert_advection/vert_advection.F90`

Module name: `vert_advection_mod`

Key routines:

- `vert_advection`
- `vert_advection_3d`
- `slope_z`
- `compute_weights`

Role in Held-Suarez runtime:

`spectral_dynamics` calls `vert_advection` every timestep for zonal wind,
meridional wind, and temperature tendencies.  It is also used for tracers when
tracers are active.  It implements centered, van Leer, and PPM-style vertical
advection options.

Dependencies:

- `fms_mod` for error/version handling.
- `mpp_mod` for CFL diagnostic aggregation at module end.
- Inputs and outputs are mostly explicit arrays and scheme flags.

Called every timestep: yes.

Estimated difficulty: high.  The routine contains many schemes, limiters,
optional masks, optional flags, and CFL bookkeeping.

GPU suitability: high.  The core schemes are regular column/level loops with
substantial arithmetic intensity.

Risk level: medium-high.  The scheme branches and limiter details increase the
chance of subtle numerical mismatches.

Score:

- `+5` every timestep.
- `+4` large array loops.
- `+4` central to dynamics/timestep.
- `+3` GEOS-relevant vertical transport pattern.
- `-4` MPI-related diagnostic dependency.
- `-1` isolation friction from many schemes/options.
- Total: `15`.

### 5. `spectral_damping.F90`

File path: `src/atmos_spectral/model/spectral_damping.F90`

Module name: `spectral_damping_mod`

Key routines:

- `compute_spectral_damping`
- `compute_spectral_damping_vor`
- `compute_spectral_damping_div`
- `spectral_damping_init`

Role in Held-Suarez runtime:

`spectral_dynamics` calls spectral damping every timestep for vorticity,
divergence, and temperature tendency fields.  It applies scale-dependent
damping to spectral coefficients.

Dependencies:

- `fms_mod`.
- `transforms_mod` during initialization for spectral domain and Laplacian
  eigenvalues.
- Internal damping arrays initialized once.

Called every timestep: yes.

Estimated difficulty: medium.  The timestep kernels are relatively clean, but
their meaning is tied to spectral-space indexing and initialized damping state.

GPU suitability: medium-high.  The kernel is mostly coefficient-wise operations,
but spectral-array layout and small spectral dimensions may limit payoff.

Risk level: medium.  It is less tangled than full transforms, but the spectral
indexing must remain exact.

Score:

- `+5` every timestep.
- `+4` large array loops.
- `+4` central to numerical stability.
- `+3` GEOS-relevant damping/diffusion pattern.
- `-3` spectral-space complexity.
- `-1` initialized-state friction.
- Total: `15`.

### 6. Full `spectral_dynamics`

File path: `src/atmos_spectral/model/spectral_dynamics.F90`

Module name: `spectral_dynamics_mod`

Key routines:

- `spectral_dynamics`
- `compute_pressure_gradient`
- `update_tracers`
- `initialize_corrections`
- `compute_corrections`
- `complete_robert_filter`
- `complete_update_of_future`

Role in Held-Suarez runtime:

This is the main spectral dynamical-core routine.  It coordinates pressure
variables, pressure gradients, vertical advection, horizontal advection,
spectral transforms, implicit correction, damping, leapfrog updates, and
conversion back to grid state.

Dependencies:

- `transforms_mod`, `vert_advection_mod`, `implicit_mod`,
  `press_and_geopot_mod`, `spectral_damping_mod`, `leapfrog_mod`,
  `fv_advection_mod`, diagnostics, global integrals, FMS and MPP support.

Called every timestep: yes.

Estimated difficulty: very high.

GPU suitability: high in principle, but the routine is a coordinator around
many kernels rather than a clean standalone kernel.

Risk level: high.  It has many module variables, time-level side effects,
diagnostics, spectral transforms, and restart/correction machinery nearby.

Score:

- `+5` every timestep.
- `+5` directly updates prognostic state.
- `+4` large array loops.
- `+4` central to dynamics/timestep.
- `+2` many downstream dependencies.
- `+3` GEOS-relevant dynamical-core pattern.
- `-3` spectral transform complexity.
- `-3` too many global side effects.
- `-3` hard to isolate.
- Total: `13`.

### 7. `implicit.F90`

File path: `src/atmos_spectral/model/implicit.F90`

Module name: `implicit_mod`

Key routines:

- `implicit_correction`
- `implicit_init`
- `linear_geopotential`
- `linear_tp_tendency`
- `pres_grad_funct`

Role in Held-Suarez runtime:

When `use_implicit` is enabled, `spectral_dynamics` calls
`implicit_correction` each timestep to apply a semi-implicit correction in
spectral space.

Dependencies:

- `press_and_geopot_mod`
- `matrix_invert_mod`
- `transforms_mod`
- spectral-domain state, reference profiles, wave matrices, and initialized
  vertical-coordinate arrays.

Called every timestep: usually, depending on namelist configuration.

Estimated difficulty: high.

GPU suitability: medium.  There are array operations and per-wavenumber
vertical solves, but the algorithm is more matrix/spectral-control heavy than a
straight grid kernel.

Risk level: high.  This is numerically sensitive and has substantial initialized
module state.

Score:

- `+5` usually every timestep.
- `+4` central to dynamics/timestep when enabled.
- `+4` array/matrix loops.
- `+2` downstream impact.
- `+3` GEOS-relevant implicit dynamics pattern.
- `-3` spectral transform/spectral-space complexity.
- `-3` global initialized state.
- `-3` hard to isolate.
- `-1` configuration dependence.
- Total: `9`.

### 8. `transforms.F90` and transform stack

File path: `src/atmos_spectral/tools/transforms.F90`

Module name: `transforms_mod`

Related files in the successful build:

- `src/atmos_spectral/tools/spherical.F90`
- `src/atmos_spectral/tools/spherical_fourier.F90`
- `src/atmos_spectral/tools/grid_fourier.F90`
- `src/atmos_spectral/tools/gauss_and_legendre.F90`
- `src/atmos_spectral/tools/spec_mpp.F90`

Key routines:

- `trans_spherical_to_grid`
- `trans_grid_to_spherical`
- `uv_grid_from_vor_div`
- `vor_div_from_uv_grid`
- `horizontal_advection`
- `compute_laplacian`
- `compute_gradient_cos`

Role in Held-Suarez runtime:

The transform stack is called many times per timestep and is central to the
spectral dynamical core.

Dependencies:

- Spectral and grid domains.
- Fourier/spherical transform implementation files.
- `spec_mpp` and domain-decomposition support.

Called every timestep: yes.

Estimated difficulty: very high.

GPU suitability: medium in this prototype.  Transforms are important, but the
best modernization route may be a library/algorithm redesign rather than a
direct routine translation.

Risk level: very high.

Score:

- `+5` every timestep.
- `+4` large transform work.
- `+4` central to dynamics/timestep.
- `+2` many downstream dependencies.
- `+3` GEOS-relevant transform/operator pattern.
- `-4` MPI/domain decomposition.
- `-3` spectral transform complexity.
- `-3` global initialized state.
- `-3` hard to isolate.
- Total: `8`.

### 9. `atmosphere.F90`

File path: `src/atmos_spectral/driver/solo/atmosphere.F90`

Module name: `atmosphere_mod`

Key routines:

- `atmosphere_init`
- `atmosphere`
- `atmosphere_end`

Role in Held-Suarez runtime:

The atmosphere driver initializes spectral dynamics and forcing, calls forcing,
calls `spectral_dynamics`, recomputes future pressure/height fields, sends
diagnostics, and rotates time levels.

Dependencies:

- `spectral_dynamics_mod`
- `press_and_geopot_mod`
- `hs_forcing_mod`
- diagnostics, tracer manager, constants, time manager, and FMS support.

Called every timestep: yes.

Estimated difficulty: high.

GPU suitability: low.  It is orchestration rather than a compute kernel.

Risk level: high.  It has broad control-flow and global-state side effects.

Score:

- `+5` every timestep.
- `+4` central to timestep orchestration.
- `+2` many downstream dependencies.
- `-5` diagnostic/I/O adjacency.
- `-3` too many global side effects.
- `-1` low compute-kernel value.
- Total: `8`.

### 10. `vert_coordinate.F90`

File path: `src/atmos_spectral/init/vert_coordinate.F90`

Module name: `vert_coordinate_mod`

Key routines:

- `compute_vert_coord`
- `compute_even_sigma`
- `compute_uneven_sigma`
- `compute_v197_sigma`
- `compute_old_model_sigma`

Role in Held-Suarez runtime:

This module computes the vertical-coordinate arrays used by pressure,
geopotential, implicit dynamics, and dynamics kernels.  It is important setup
logic but not an every-timestep kernel.

Dependencies:

- FMS namelist/version/error support.
- Vertical-coordinate configuration.

Called every timestep: no.

Estimated difficulty: low.

GPU suitability: low.  Initialization-only work is not a GPU-portability
priority.

Risk level: low.

Score:

- `+2` downstream dependencies.
- `+3` GEOS-relevant vertical-coordinate pattern.
- `+1` easy validation/setup value.
- Total: `6`.

### 11. `fv_advection.F90`

File path: `src/atmos_spectral/model/fv_advection.F90`

Module name: `fv_advection_mod`

Key routines:

- Horizontal finite-volume advection routines used by tracer update paths.

Role in Held-Suarez runtime:

This is relevant for tracer advection, but default dry Held-Suarez dynamics do
not make it the next best prototype target.

Dependencies:

- Domain-decomposition and halo-update machinery.
- Tracer update paths in `spectral_dynamics_mod`.

Called every timestep: tracer-dependent.

Estimated difficulty: high.

GPU suitability: medium-high.

Risk level: medium-high.

Score:

- `+4` large array loops.
- `+3` GEOS-relevant advection pattern.
- `-4` MPI/domain decomposition.
- `-3` hard to isolate.
- Total: `4`.

## Top 3 Recommendations

### 1. Best modernization target: `four_in_one`

Translate the `four_in_one` kernel inside
`src/atmos_spectral/model/spectral_dynamics.F90`.

Why:

- It is every-timestep dynamics logic.
- It updates pressure, temperature, wind, and vertical mass-flux tendencies.
- It is much closer to dynamical-core state update than the completed forcing
  module.
- It has high GPU suitability because its core work is regular grid/vertical
  array computation.
- It avoids direct I/O, diagnostics, MPI, and transform-library complexity.

Main caution:

It is not a public module routine today.  The cleanest next experiment is likely
to extract or wrap this kernel through an overlay source while preserving the
original source tree, then validate exact Fortran-to-C++ agreement with a
standalone harness before building a hybrid executable.

### 2. Safest dynamics-helper target: `leapfrog_mod`

Translate `src/atmos_spectral/model/leapfrog.F90`.

Why:

- It is every-timestep time-integration logic.
- It directly updates spectral prognostic arrays.
- It is highly isolatable with minimal dependencies.
- It should be straightforward to validate bitwise or near-bitwise.

Main caution:

It is an excellent low-risk first dynamics-helper translation, but it is a
small arithmetic/update helper and may not teach as much about larger GEOS-like
physics/dynamics kernels as `four_in_one`.

### 3. Best pressure/geopotential target: `press_and_geopot_mod`

Translate `src/atmos_spectral/model/press_and_geopot.F90`.

Why:

- It is physically meaningful and called repeatedly during timestep execution.
- It computes pressure, log-pressure, geopotential, and height fields that feed
  dynamics.
- Its kernels are regular vertical-column computations with high GPU relevance.
- It is more module-contained than `spectral_dynamics_mod`.

Main caution:

Differences can propagate quickly because downstream dynamics use its outputs.
Validation should therefore include isolated routine tests and executable-level
short-run comparisons.

## Final Recommendation

Choose `four_in_one` in `src/atmos_spectral/model/spectral_dynamics.F90` as the
next translation target.

This is the best balance between ambition and containment.  It advances from a
physics-forcing replacement into true dynamical-core update logic without taking
on the full spectral transform/MPI stack.  It also creates a useful pattern for
future GEOS modernization: identify a high-value timestep kernel, validate it in
isolation, expose a C API, call it from a Fortran overlay, and build through the
native Isca `CodeBase.compile()` workflow.

Recommended immediate next action before translation:

Run the profiling plan in `docs/profiling_plan_for_module_selection.md` to
confirm whether `four_in_one`, pressure/geopotential, vertical advection,
leapfrog, damping, or transforms dominate wall-clock time in the 30-day
all-Fortran and hybrid Held-Suarez runs.
