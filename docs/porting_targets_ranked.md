# Held-Suarez Porting Targets: Ranked Analysis

Prioritized ranking of routines from `src/atmos_param/hs_forcing/hs_forcing.F90` for GPU porting, based on:
1. Importance in Held-Suarez runtime
2. Degree of array computations
3. GPU suitability
4. Number of dependencies
5. Difficulty of isolation

---

## Tier 1: Recommended First Targets (Low Risk, High Value)

### 1. `calc_ecc_anomaly`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Newton-Raphson solver for Kepler's equation: compute eccentric anomaly from mean anomaly |
| **Location** | Lines 864–890 |
| **Estimated LOC** | 27 |
| **Dependencies** | None — uses only Fortran intrinsics (`sin`, `cos`, `tan`, `abs`) |
| **GPU Suitability** | ★★★★★ (5/5) |
| **Recommended Order** | **1** |

**Why first:**
- Zero external dependencies
- Pure scalar computation — trivial to validate
- Known analytical solutions for testing
- Newton iteration maps directly to GPU kernel
- Builds confidence before tackling array kernels

---

### 2. `calc_hour_angle`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Compute solar hour angle from latitude and solar declination for diurnal cycle |
| **Location** | Lines 842–860 |
| **Estimated LOC** | 19 |
| **Dependencies** | None — uses only intrinsics (`tan`, `acos`) |
| **GPU Suitability** | ★★★★★ (5/5) |
| **Recommended Order** | **2** |

**Why second:**
- First 2D array kernel — introduces GPU parallelism patterns
- `where` construct maps cleanly to GPU conditional writes
- No FMS dependencies
- Natural follow-on after `calc_ecc_anomaly`

---

### 3. `update_orbit`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Compute current solar declination and orbital distance from time |
| **Location** | Lines 823–838 |
| **Estimated LOC** | 16 |
| **Dependencies** | Calls `calc_ecc_anomaly`; uses module constants (`orbital_period`, `ecc`, `obliq`) |
| **GPU Suitability** | ★★★★☆ (4/5) |
| **Recommended Order** | **3** |

**Why third:**
- Validates ported `calc_ecc_anomaly` in context
- Module constants can be passed as kernel parameters
- Scalar output — simple integration test

---

## Tier 2: Core Physics Kernels (High Impact)

### 4. `rayleigh_damping`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Apply boundary-layer friction to u, v winds (Held-Suarez Eq. 3) |
| **Location** | Lines 615–679 |
| **Estimated LOC** | 65 |
| **Dependencies** | `time_manager_mod` (for diagnostics timing only), `constants_mod` |
| **GPU Suitability** | ★★★★★ (5/5) |
| **Recommended Order** | **4** |

**Why prioritize:**
- **Runtime-critical:** Called every physics timestep
- Dense 3D array loops — high GPU parallelism
- Core physics: friction coefficient `kf * max(0, (σ - σ_b)/(1 - σ_b))`
- `where` constructs ideal for GPU
- Diagnostics can be stripped for isolated kernel

---

### 5. `newtonian_damping`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Relax temperature toward equilibrium profile (Held-Suarez Eq. 1–2) |
| **Location** | Lines 508–611 |
| **Estimated LOC** | 104 |
| **Dependencies** | `time_manager_mod`, `interpolator_mod` (for `from_file` option), `constants_mod` |
| **GPU Suitability** | ★★★★☆ (4/5) |
| **Recommended Order** | **5** |

**Why fifth:**
- **Most important physics routine** — defines Held-Suarez forcing
- Multiple `equilibrium_t_option` branches — needs careful extraction
- 3D array computation: `tdt = -kT * (T - Teq)`
- `Teq` calculation is pure arithmetic — highly parallelizable
- Interpolator dependency only for `from_file` option (can skip for default case)

**Porting strategy:** Extract the `equilibrium_t_option = 'hs'` branch first (~50 lines of pure computation).

---

### 6. `top_down_newtonian_damping`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Alternative temperature relaxation with tropopause-aware vertical structure |
| **Location** | Lines 894–1026 |
| **Estimated LOC** | 133 |
| **Dependencies** | `time_manager_mod`, module state (`tg_prev`) |
| **GPU Suitability** | ★★★☆☆ (3/5) |
| **Recommended Order** | **6** |

**Why sixth:**
- More complex vertical structure than `newtonian_damping`
- Module-level state (`tg_prev`) requires stateless refactoring
- 3D array computation with vertical dependencies
- Needed for advanced Held-Suarez configurations

---

## Tier 3: Support Routines (Lower Priority)

### 7. `local_heating`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Apply localized heating perturbation (optional forcing) |
| **Location** | Lines 728–769 |
| **Estimated LOC** | 42 |
| **Dependencies** | `interpolator_mod` (for `from_file` option) |
| **GPU Suitability** | ★★★☆☆ (3/5) |
| **Recommended Order** | **7** |

**Why lower priority:**
- Optional physics — not required for basic Held-Suarez
- Interpolator dependency for file-based heating
- Gaussian heating option is pure computation

---

### 8. `get_zonal_mean_flow` / `get_zonal_mean_temp`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Extract zonal-mean u, v, T from 3D fields |
| **Location** | Lines 776–811 |
| **Estimated LOC** | 33 (combined) |
| **Dependencies** | `interpolator_mod` |
| **GPU Suitability** | ★★☆☆☆ (2/5) |
| **Recommended Order** | **8** |

**Why lower priority:**
- Diagnostic/boundary condition routines
- Interpolator dependency
- Zonal averaging is reduction operation — less GPU-friendly than point-wise ops

---

### 9. `tracer_source_sink`

| Attribute | Value |
|-----------|-------|
| **Purpose** | Apply source/sink terms to passive tracers |
| **Location** | Lines 683–724 |
| **Estimated LOC** | 42 |
| **Dependencies** | Tracer framework coupling |
| **GPU Suitability** | ★★☆☆☆ (2/5) |
| **Recommended Order** | **9** |

**Why lowest priority:**
- Not needed for basic Held-Suarez (no tracers)
- Coupled to tracer management framework
- Only relevant for extended experiments

---

## Not Recommended for Porting

| Routine | Lines | Reason |
|---------|-------|--------|
| `hs_forcing` | 148–272 (125) | Main driver; orchestrates all physics; heavy FMS dependencies |
| `hs_forcing_init` | 276–470 (195) | Complex initialization; file I/O; namelist parsing; diagnostics registration |
| `hs_forcing_end` | 474–504 (31) | Cleanup routine; deallocations; no computation |

---

## Summary: Recommended Porting Order

| Order | Routine | LOC | GPU Suitability | Cumulative Value |
|-------|---------|-----|-----------------|------------------|
| 1 | `calc_ecc_anomaly` | 27 | ★★★★★ | Validation foundation |
| 2 | `calc_hour_angle` | 19 | ★★★★★ | 2D array patterns |
| 3 | `update_orbit` | 16 | ★★★★☆ | Orbital mechanics complete |
| 4 | `rayleigh_damping` | 65 | ★★★★★ | Core physics #1 |
| 5 | `newtonian_damping` | 104 | ★★★★☆ | Core physics #2 — **Held-Suarez complete** |
| 6 | `top_down_newtonian_damping` | 133 | ★★★☆☆ | Advanced configurations |
| 7 | `local_heating` | 42 | ★★★☆☆ | Optional physics |
| 8 | `get_zonal_mean_*` | 33 | ★★☆☆☆ | Diagnostics |
| 9 | `tracer_source_sink` | 42 | ★★☆☆☆ | Extended experiments |

**Milestone:** After completing orders 1–5 (~231 lines), a functional GPU-accelerated Held-Suarez physics package is achievable.

---

## GPU Porting Notes

- **Precision:** Default `real` is single precision; consider `real(kind=8)` for GPU targets
- **`where` constructs:** Map directly to GPU conditionals — no refactoring needed
- **Module state:** `tg_prev` in `top_down_newtonian_damping` requires stateless kernel design
- **FMS stubs:** `constants_mod` values can be inlined; `time_manager_mod` calls stripped for kernel isolation

---

## Integration Context

### Call Flow Position

```
atmosphere_mod (driver)
    └── spectral_dynamics_mod (time integration & spectral dynamics)
            └── hs_forcing_mod  ◄── THIS MODULE
                    ├── newtonian_damping()  → temperature relaxation
                    └── rayleigh_damping()   → boundary layer friction
```

The `hs_forcing_mod` is called from `spectral_dynamics_mod` after spectral-to-grid transforms. Physics tendencies are computed in grid space, then transformed back to spectral space for time integration.

### Data Structures

| Variable | Dimensions | Type | Description |
|----------|------------|------|-------------|
| `t`, `tdt` | (lon, lat, lev) | real | Temperature and tendency |
| `u, v`, `udt, vdt` | (lon, lat, lev) | real | Winds and tendencies |
| `p_full, p_half` | (lon, lat, lev) | real | Pressure at full/half levels |
| `ps` | (lon, lat) | real | Surface pressure |
| `lat, lon` | (lon, lat) | real | Grid coordinates (radians) |
| `teq` | (lon, lat, lev) | real | Equilibrium temperature |

### Namelist Parameters (`hs_forcing_nml`)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `t_zero` | 315 K | Equatorial equilibrium temperature |
| `t_strat` | 200 K | Stratospheric temperature |
| `delh` | 60 K | Equator-pole temperature difference |
| `delv` | 10 K | Static stability parameter |
| `sigma_b` | 0.7 | Boundary layer top (p/ps) |
| `ka` | -40 days | Atmospheric relaxation timescale |
| `ks` | -4 days | Surface relaxation timescale |
| `kf` | -1 day | Rayleigh friction timescale |

These parameters should be passed as kernel arguments rather than module state for GPU isolation.

---

## Alignment with Isolation Tiers

From the broader Held-Suarez porting strategy:

| Tier | Scope | Routines in This Document |
|------|-------|---------------------------|
| **Tier 1** | Pure grid-point physics (no transforms) | All 9 candidates |
| **Tier 2** | Spectral operators | — (in `spherical_mod`) |
| **Tier 3** | Time integration | — (in `leapfrog_mod`) |
| **Tier 4** | Transforms | — (in `transforms_mod`) |

All routines in `hs_forcing.F90` are **Tier 1** — they operate entirely in grid space with no spectral transforms, making them the natural starting point for GPU porting.
