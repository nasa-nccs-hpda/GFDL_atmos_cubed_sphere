# Next Module Performance Decision

Date: 2026-06-15

## Purpose

The Held-Suarez forcing-module hybrid workflow is complete.  The next target
should prioritize wall-clock runtime improvement rather than simply proving
that another isolated routine can be translated.

This decision re-ranks the previous candidates with performance as the primary
criterion:

- Called every timestep.
- Expensive numerical kernels.
- Large array loops.
- Likely to dominate or materially affect wall-clock time.
- Scales with horizontal resolution and vertical levels.
- GPU-relevant computation pattern.
- Minimal I/O, diagnostics, and configuration code.

The ranking combines static evidence from the successful `held_suarez_hybrid`
`path_names`, call sites in the timestep path, and the profiling strategy in
`docs/profiling_plan_for_module_selection.md`.

Successful hybrid build path list:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_hybrid/path_names
```

## Static Evidence

The successful hybrid executable includes the major dynamics candidates:

```text
src/atmos_spectral/model/spectral_dynamics.F90
src/atmos_spectral/model/press_and_geopot.F90
src/atmos_shared/vert_advection/vert_advection.F90
src/atmos_spectral/model/leapfrog.F90
src/atmos_spectral/model/spectral_damping.F90
src/atmos_spectral/model/implicit.F90
src/atmos_spectral/tools/transforms.F90
```

Inside `spectral_dynamics`, the every-timestep path calls:

```text
pressure_variables
compute_pressure_gradient
four_in_one
compute_geopotential
trans_grid_to_spherical
vert_advection for u, v, and temperature
horizontal_advection
vor_div_from_uv_grid
implicit_correction when enabled
compute_spectral_damping_vor/div/temp
leapfrog or leapfrog_2level_A
trans_spherical_to_grid and uv_grid_from_vor_div for future-state update
```

The profiling plan recommends confirming the static ranking with coarse timers
around these same blocks before committing to a large port.

## Performance-Oriented Ranking

| Rank | Candidate | Expected Runtime Contribution | GPU Suitability | Translation Difficulty | Validation Difficulty | Risk |
|---:|---|---|---|---|---|---|
| 1 | `spectral_dynamics.F90::four_in_one` | Medium-high | High | Medium-high | Medium | Medium |
| 2 | `vert_advection.F90::vert_advection_3d` | Medium-high | High | High | High | Medium-high |
| 3 | `press_and_geopot.F90::{pressure_variables, compute_geopotential, compute_pressures_and_heights}` | Medium | High | Medium | Medium | Medium |
| 4 | `transforms.F90` transform stack | High | Medium-high in principle | Very high | Very high | Very high |
| 5 | `spectral_damping.F90` damping kernels | Medium | Medium-high | Medium | Medium | Medium |
| 6 | `leapfrog.F90` update/filter kernels | Low-medium | Medium | Low | Low-medium | Low |
| 7 | `implicit.F90::implicit_correction` | Configuration-dependent medium | Medium | High | High | High |

The transform stack may be the largest runtime component, but it is not the
best next translation target.  It is tightly coupled to spectral algorithms,
domain decomposition, and transform-library design.  It should be measured and
planned as a later redesign, not used as the first post-forcing hybrid module.

## Top 3 Performance-Impact Candidates

### 1. `four_in_one`

Source file:

```text
src/atmos_spectral/model/spectral_dynamics.F90
```

Module and routines:

```text
spectral_dynamics_mod
four_in_one
```

Why it may be expensive:

`four_in_one` performs column/grid-level dynamics work over all horizontal
cells and vertical levels.  It computes pressure-gradient tendency terms,
temperature tendency terms, surface-pressure tendency, and hybrid-coordinate
vertical mass fluxes.  It updates several large arrays:

```text
dt_psg
wg
wg_full
dt_tg
dt_ug
dt_vg
```

It is called inside the main `spectral_dynamics` timestep loop immediately
after pressure variables and pressure gradients are computed.

Called every timestep: yes.

Expected runtime contribution: medium-high.

GPU suitability: high.  The kernel is dominated by regular array expressions
and vertical loops over independent horizontal columns.  The `dmean_tot`
vertical accumulation introduces a column dependency over `k`, but horizontal
columns remain independent and map naturally to GPU parallelism.

Translation difficulty: medium-high.  The routine is internal to
`spectral_dynamics_mod` and depends on initialized module state such as
`rdgas`, `cp_air`, `dpk`, `dbk`, `bk`, `num_levels`, and
`vert_difference_option`.

Validation difficulty: medium.  A standalone harness can capture the input
arrays and compare all updated tendencies and flux arrays.  Bit-level agreement
may require preserving vertical operation order.

Risk: medium.  The routine directly affects prognostic tendencies, so small
errors propagate quickly.  Its dependency surface is still much smaller than
the full dynamics or transform stack.

### 2. Vertical advection

Source file:

```text
src/atmos_shared/vert_advection/vert_advection.F90
```

Module and routines:

```text
vert_advection_mod
vert_advection_3d
slope_z
compute_weights
```

Why it may be expensive:

`spectral_dynamics` calls `vert_advection` every timestep for zonal wind,
meridional wind, and temperature, and also for tracers when active.  The module
contains multiple advection schemes, limiters, flux calculations, and vertical
stencils.  Runtime should scale with grid size, vertical levels, and number of
advected fields.

Called every timestep: yes.

Expected runtime contribution: medium-high.

GPU suitability: high.  The core work is regular column/level stencil and flux
computation with substantial array traffic.

Translation difficulty: high.  The implementation has many scheme branches,
optional masks, optional flags, and limiter details.

Validation difficulty: high.  Each scheme and option combination needs a
focused baseline harness.  Validation should begin with the exact
Held-Suarez-selected schemes before expanding coverage.

Risk: medium-high.  Advection limiter details are numerically sensitive.

### 3. Pressure and geopotential

Source file:

```text
src/atmos_spectral/model/press_and_geopot.F90
```

Module and routines:

```text
press_and_geopot_mod
pressure_variables
compute_geopotential
compute_pressures_and_heights
```

Why it may be expensive:

These routines compute half-level/full-level pressure, log pressure,
geopotential, and height arrays.  `spectral_dynamics` calls
`pressure_variables` and `compute_geopotential` during every dynamics step, and
the atmosphere driver calls `compute_pressures_and_heights` after the future
state is generated.

Called every timestep: yes.

Expected runtime contribution: medium.

GPU suitability: high.  The routines are column-wise, regular, and mostly free
of I/O and MPI.  `compute_geopotential` includes vertical hydrostatic
integration, which maps well to one thread block or warp per column in a later
CUDA design.

Translation difficulty: medium.  The routines are compact and physically clear
but depend on module initialization and vertical-coordinate state.

Validation difficulty: medium.  Outputs are well-defined arrays and can be
compared directly.  Small differences can propagate downstream.

Risk: medium.  Pressure and geopotential feed many later dynamics terms.

## Final Recommendation

Choose `four_in_one` in `src/atmos_spectral/model/spectral_dynamics.F90` as the
next module-level modernization target.

Why this is the best next performance target:

- It is in the every-timestep dynamics path.
- It directly updates prognostic tendencies and vertical mass fluxes.
- It has large, regular array loops.
- It is more likely to affect wall-clock time than leapfrog or the completed
  forcing module.
- It avoids I/O, diagnostics, MPI, and transform-stack complexity.
- It is a realistic stepping stone toward larger dynamics/state-update GPU
  work.

The first implementation should still begin with profiling.  Before translating
`four_in_one`, add coarse timers around the major `spectral_dynamics` regions
listed in `docs/profiling_plan_for_module_selection.md`.  If those timers show
vertical advection or transforms dominate overwhelmingly, use that evidence to
adjust the target.  Without that measured counter-evidence, `four_in_one` is
the best balance of performance relevance and feasible isolation.

