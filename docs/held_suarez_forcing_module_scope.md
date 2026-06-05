# Held-Suarez Forcing Module Scope Analysis

**Document Purpose:** Define the scope for a module-level C++ translation of `hs_forcing_mod` that can be tested standalone and later integrated with Fortran via `iso_c_binding`.

**Source File:** `src/atmos_param/hs_forcing/hs_forcing.F90` (1028 lines)

---

## 1. Module Overview

### 1.1 Public Interface

The Fortran module exposes three public routines:

| Routine | Lines | Purpose | Complexity |
|---------|-------|---------|------------|
| `hs_forcing` | 148–272 (125) | Main driver: orchestrates physics, diagnostics, tracers | High |
| `hs_forcing_init` | 276–470 (195) | Initialization: namelist, spinup, diagnostics registration | High |
| `hs_forcing_end` | 474–504 (31) | Cleanup: deallocate, write restart | Low |

### 1.2 Internal Routines

| Routine | Lines | LOC | Purpose | Translation Status |
|---------|-------|-----|---------|-------------------|
| `newtonian_damping` | 508–611 | 104 | Standard HS temperature relaxation | ✅ **TRANSLATED** |
| `rayleigh_damping` | 615–679 | 65 | Boundary layer wind friction | ✅ **TRANSLATED** |
| `tracer_source_sink` | 683–724 | 42 | Tracer source/sink terms | ❌ Not started |
| `local_heating` | 728–769 | 42 | Optional localized heating | ❌ Not started |
| `get_zonal_mean_flow` | 776–793 | 18 | Zonal mean u,v from file | ❌ Deferred (interpolator) |
| `get_zonal_mean_temp` | 796–811 | 16 | Zonal mean T from file | ❌ Deferred (interpolator) |
| `update_orbit` | 823–838 | 16 | Compute solar declination | ✅ Embedded in `top_down` |
| `calc_hour_angle` | 842–860 | 19 | Solar hour angle | ✅ **TRANSLATED** |
| `calc_ecc_anomaly` | 864–890 | 27 | Kepler equation solver | ✅ **TRANSLATED** |
| `top_down_newtonian_damping` | 894–1026 | 133 | Tropopause-aware forcing | ✅ **TRANSLATED** |

---

## 2. Translation Status Summary

### 2.1 Already Translated (5 routines, 348 LOC)

| Routine | LOC | Validation | Notes |
|---------|-----|------------|-------|
| `calc_ecc_anomaly` | 27 | Exact match | Pure scalar Newton-Raphson |
| `calc_hour_angle` | 19 | Exact match | 2D array, `where` → clamp |
| `rayleigh_damping` | 65 | Exact match | 3D array, boundary layer physics |
| `newtonian_damping` | 104 | Exact match | 3D array, Held-Suarez Teq |
| `top_down_newtonian_damping` | 133 | rel_diff < 1e-14 | Complex, embeds orbital mechanics |

### 2.2 Remaining to Translate

| Routine | LOC | Priority | Blocking Issue |
|---------|-----|----------|----------------|
| `update_orbit` | 16 | Low | Already embedded in `top_down` |
| `local_heating` | 42 | Medium | Two branches: `Isidoro` (pure) and `from_file` (interpolator) |
| `tracer_source_sink` | 42 | Low | Only needed for tracer experiments |
| `get_zonal_mean_flow` | 18 | Deferred | Requires `interpolator_mod` |
| `get_zonal_mean_temp` | 16 | Deferred | Requires `interpolator_mod` |
| `hs_forcing` (driver) | 125 | High | Main entry point, needs all above |
| `hs_forcing_init` | 195 | Deferred | Heavy FMS dependencies |
| `hs_forcing_end` | 31 | Deferred | I/O, restart files |

---

## 3. Module Variables

### 3.1 Namelist Parameters (`hs_forcing_nml`)

These are read from namelist and control physics behavior:

| Variable | Type | Default | Category |
|----------|------|---------|----------|
| `no_forcing` | logical | `.false.` | Control |
| `t_zero` | real | 315.0 | Teq |
| `t_strat` | real | 200.0 | Teq |
| `delh` | real | 60.0 | Teq |
| `delv` | real | 10.0 | Teq |
| `eps` | real | 0.0 | Teq |
| `sigma_b` | real | 0.7 | Damping |
| `P00` | real | 1.0e5 | Reference |
| `ka` | real | -40.0 | Damping (days) |
| `ks` | real | -4.0 | Damping (days) |
| `kf` | real | -1.0 | Damping (days) |
| `equilibrium_t_option` | string | `'Held_Suarez'` | Teq branch |
| `stratosphere_t_option` | string | `'extend_tp'` | Top-down only |
| `local_heating_option` | string | `''` | Local heating branch |
| `relax_to_specified_wind` | logical | `.false.` | Wind relaxation branch |
| `do_conserve_energy` | logical | `.true.` | Energy conservation |
| `peri_time` | real | 0.25 | Orbital |
| `smaxis` | real | 1.5e6 | Orbital |
| `albedo` | real | 0.3 | Top-down |
| `lapse` | real | 6.5 | Top-down |
| `h_a` | real | 2.0 | Top-down |
| `tau_s` | real | 5.0 | Top-down |
| `heat_capacity` | real | 4.2e6 | Top-down |
| `ml_depth` | real | 1.0 | Top-down |
| `spinup_time` | real | 10800.0 | Top-down |
| `trflux` | real | 1.0e-5 | Tracer |
| `trsink` | real | -4.0 | Tracer |

### 3.2 Derived Module Variables

Computed during initialization from namelist values:

| Variable | Type | Derivation | Used By |
|----------|------|------------|---------|
| `tka` | real | `1/(86400*abs(ka))` | `newtonian_damping`, `top_down` |
| `tks` | real | `1/(86400*abs(ks))` | `newtonian_damping`, `top_down` |
| `vkf` | real | `1/(86400*abs(kf))` | `rayleigh_damping` |
| `trdamp` | real | `1/trsink` (converted) | `tracer_source_sink` |
| `twopi` | real | `2*PI` | Various |
| `xwidth`, `ywidth`, `xcenter`, `ycenter` | real | Degrees → radians | `local_heating` |
| `srfamp` | real | `local_heating_srfamp/SECONDS_PER_DAY` | `local_heating` |

### 3.3 Module State (Persistent)

| Variable | Type | Purpose | Handling in C++ |
|----------|------|---------|-----------------|
| `tg_prev(nlon,nlat)` | real, allocatable | Previous ground temperature | Pass as input/output |
| `module_is_initialized` | logical | Init guard | Not needed in stateless C++ |
| `heating_source_interp` | interpolate_type | File interpolator | Defer (infrastructure) |
| `u_interp`, `v_interp` | interpolate_type | Wind file interpolators | Defer (infrastructure) |
| `temp_interp` | interpolate_type | Temp file interpolator | Defer (infrastructure) |
| `id_teq`, `id_tdt`, etc. | integer | Diagnostic field IDs | Defer (diag_manager) |

---

## 4. Dependency Classification

### Category A: Already Translated

| Dependency | Location | Status |
|------------|----------|--------|
| `calc_ecc_anomaly` | Internal | ✅ Standalone C++ |
| `calc_hour_angle` | Internal | ✅ Standalone C++ |
| `update_orbit` | Internal | ✅ Embedded in `top_down` C++ |

### Category B: Easy Pure Functions

| Dependency | Source | Action |
|------------|--------|--------|
| `sin`, `cos`, `tan`, `acos`, `asin`, `atan` | Intrinsic | Use `std::` |
| `log`, `exp`, `sqrt`, `pow`, `abs`, `max`, `min` | Intrinsic | Use `std::` |

### Category C: Constants/Config Only

| Dependency | Source | Action |
|------------|--------|--------|
| `KAPPA` | `constants_mod` | Inline as `2.0/7.0` or parameter |
| `CP_AIR` | `constants_mod` | Inline value (~1004 J/kg/K) |
| `GRAV` | `constants_mod` | Inline value (9.8 m/s²) |
| `PI` | `constants_mod` | Use `M_PI` or inline |
| `SECONDS_PER_DAY` | `constants_mod` | Inline as `86400.0` |
| `orbital_period` | `constants_mod` | Pass as parameter |
| `stefan` | `constants_mod` | Inline Stefan-Boltzmann constant |
| `solar_const` | `constants_mod` | Pass as parameter |
| `obliq`, `ecc` | `astronomy_mod` | Pass as parameters |

### Category D: Infrastructure to Mock

| Dependency | Source | Action |
|------------|--------|--------|
| `time_type` | `time_manager_mod` | Replace with `int current_time` (seconds) |
| `get_time()` | `time_manager_mod` | Already handled in `top_down` |
| `error_mesg()` | `fms_mod` | Replace with `throw` or error code |
| `send_data()` | `diag_manager_mod` | Remove for standalone C++ |
| `register_diag_field()` | `diag_manager_mod` | Remove for standalone C++ |
| `grid_domain` | `transforms_mod` | Remove (use explicit dimensions) |

### Category E: Defer for Now

| Dependency | Source | Reason |
|------------|--------|--------|
| `interpolator()` | `interpolator_mod` | Complex file I/O, used only for `from_file` options |
| `interpolator_init/end()` | `interpolator_mod` | Complex file I/O |
| `diurnal_exoplanet()` | `astronomy_mod` | Only for `exoplanet` option |
| `read_data()`, `write_data()` | `fms_mod` | Restart file I/O |
| `query_method()` | `tracer_manager_mod` | Tracer framework |
| `get_number_tracers()` | `tracer_manager_mod` | Tracer framework |
| `mpp_pe()`, `mpp_root_pe()` | `fms_mod` | MPI parallelization |

---

## 5. C++ Module Design

### 5.1 Proposed Namespace Structure

```cpp
namespace hs_forcing {

// Parameters structures (already defined in individual translations)
struct NewtonianParams { ... };
struct RayleighParams { ... };
struct TopDownParams { ... };

// New unified config struct for entire module
struct HeldSuarezConfig {
    // Equilibrium temperature
    double t_zero = 315.0;
    double t_strat = 200.0;
    double delh = 60.0;
    double delv = 10.0;
    double eps = 0.0;
    double P00 = 1.0e5;
    double kappa = 2.0/7.0;
    
    // Damping timescales (already in 1/s)
    double tka;    // ~2.89e-7 (40 days)
    double tks;    // ~2.89e-6 (4 days)
    double vkf;    // ~1.16e-5 (1 day)
    double sigma_b = 0.7;
    
    // Orbital (for top_down only)
    double orbital_period = 365.25;
    double ecc = 0.0167;
    double obliq = 23.44;
    double peri_time = 0.25;
    double smaxis = 1.496e11;
    double solar_const = 1360.0;
    double stefan = 5.67e-8;
    double albedo = 0.3;
    double lapse = 6.5;
    double h_a = 2.0;
    double tau_s = 5.0;
    double heat_capacity = 4.2e6;
    double ml_depth = 1.0;
    
    // Control flags
    bool no_forcing = false;
    bool do_conserve_energy = true;
    int equilibrium_t_option = 0;  // 0=HS, 1=top_down
    int stratosphere_t_option = 2; // 0=default, 1=c_above_tp, 2=hs_like, 3=extend_tp
};

}  // namespace hs_forcing
```

### 5.2 Proposed C++ Module Interface

```cpp
namespace hs_forcing {

// Already implemented (standalone kernels)
void calc_ecc_anomaly(double mean_anomaly, double ecc, double& ecc_anomaly);
void calc_hour_angle(int nlon, int nlat, const double* lat, double dec, double* hour_angle);
void rayleigh_damping(int nlon, int nlat, int nlev, ...);
void newtonian_damping(int nlon, int nlat, int nlev, ...);
void top_down_newtonian_damping(int nlon, int nlat, int nlev, ...);

// To implement: Unified driver
void hs_forcing_driver(
    int nlon, int nlat, int nlev,
    int current_time,              // replaces time_type
    double dt,
    const double* lon,             // [nlon, nlat]
    const double* lat,             // [nlon, nlat]
    const double* ps,              // [nlon, nlat]
    const double* p_full,          // [nlon, nlat, nlev]
    const double* p_half,          // [nlon, nlat, nlev+1]
    const double* zfull,           // [nlon, nlat, nlev] (for top_down)
    const double* u,               // [nlon, nlat, nlev]
    const double* v,               // [nlon, nlat, nlev]
    const double* t,               // [nlon, nlat, nlev]
    const double* tg_prev,         // [nlon, nlat] (for top_down, nullptr if HS)
    const HeldSuarezConfig& config,
    double* udt,                   // [nlon, nlat, nlev] output
    double* vdt,                   // [nlon, nlat, nlev] output
    double* tdt,                   // [nlon, nlat, nlev] output
    double* teq,                   // [nlon, nlat, nlev] output (diagnostic)
    double* h_trop,                // [nlon, nlat] output (top_down only, nullptr if HS)
    double* tg_new,                // [nlon, nlat] output (top_down only, nullptr if HS)
    const double* mask = nullptr   // [nlon, nlat, nlev] optional
);

}  // namespace hs_forcing
```

### 5.3 iso_c_binding Interface (Future)

```cpp
extern "C" {

void c_hs_forcing_driver(
    int nlon, int nlat, int nlev,
    int current_time,
    double dt,
    const double* lon,
    const double* lat,
    const double* ps,
    const double* p_full,
    const double* p_half,
    const double* zfull,
    const double* u,
    const double* v,
    const double* t,
    const double* tg_prev,
    // Config as flat scalars for C interop
    double t_zero, double t_strat, double delh, double delv,
    double eps, double P00, double kappa,
    double tka, double tks, double vkf, double sigma_b,
    int equilibrium_t_option,
    // ... additional params ...
    double* udt,
    double* vdt,
    double* tdt,
    double* teq,
    double* h_trop,
    double* tg_new,
    const double* mask
);

}
```

---

## 6. Staged Implementation Plan

### Stage 1: Consolidate Existing Translations (Current)
- [x] `calc_ecc_anomaly` — validated
- [x] `calc_hour_angle` — validated
- [x] `rayleigh_damping` — validated
- [x] `newtonian_damping` — validated
- [x] `top_down_newtonian_damping` — validated

### Stage 2: Create Unified C++ Module Header
- [ ] Create `hs_forcing.hpp` that includes all kernel headers
- [ ] Define `HeldSuarezConfig` struct
- [ ] Add helper to convert namelist values to derived coefficients

### Stage 3: Implement Driver Routine
- [ ] Create `hs_forcing_driver()` that orchestrates:
  1. Call `rayleigh_damping` → `udt`, `vdt`
  2. Branch on `equilibrium_t_option`:
     - `0` (HS): Call `newtonian_damping` → `tdt`, `teq`
     - `1` (top_down): Call `top_down_newtonian_damping` → `tdt`, `teq`, `h_trop`, `tg_new`
  3. Optionally add energy conservation term

### Stage 4: Create Standalone Test Driver
- [ ] Test driver that:
  1. Reads inputs from Fortran baseline files
  2. Calls `hs_forcing_driver`
  3. Compares outputs against Fortran reference
- [ ] Validate with multiple configurations:
  - Standard Held-Suarez (`equilibrium_t_option='Held_Suarez'`)
  - Top-down (`equilibrium_t_option='top_down'`)

### Stage 5: Add Optional Routines
- [ ] `local_heating` (Isidoro branch only, defer `from_file`)
- [ ] `tracer_source_sink` (simple source/sink, no tracer manager)

### Stage 6: iso_c_binding Integration (Future)
- [ ] Create C-compatible wrapper functions
- [ ] Fortran interface module (`hs_forcing_c.F90`)
- [ ] Hybrid build: Fortran calls C++ kernel

---

## 7. Files to Create

```
translated/held_suarez/cpp/
├── calc_ecc_anomaly/           # ✅ EXISTS
├── calc_hour_angle/            # ✅ EXISTS
├── rayleigh_damping/           # ✅ EXISTS
├── newtonian_damping/          # ✅ EXISTS
├── top_down_newtonian_damping/ # ✅ EXISTS
├── hs_forcing/                 # TO CREATE - unified module
│   ├── hs_forcing.hpp          # Unified header
│   ├── hs_forcing_driver.hpp   # Driver implementation
│   ├── hs_forcing_config.hpp   # Config struct
│   ├── test_driver.cpp         # Validation driver
│   ├── Makefile
│   └── README.md
└── include/                    # TO CREATE - shared headers
    └── hs_forcing_types.hpp    # Common type definitions
```

---

## 8. Exclusions (Explicitly Out of Scope)

The following are **not** included in this translation scope:

1. **`hs_forcing_init`** — Heavy FMS dependencies, namelist parsing, diagnostic registration
2. **`hs_forcing_end`** — I/O, restart file writing
3. **`from_file` branches** — Require `interpolator_mod`
4. **`exoplanet` branches** — Require `astronomy_mod` diurnal routines
5. **`relax_to_specified_wind`** — Requires file interpolation
6. **Diagnostic output** — No `send_data`, diagnostics are output arrays
7. **MPI parallelization** — Single-threaded, explicit dimensions
8. **NetCDF I/O** — Binary files for testing only
9. **Tracer framework integration** — Simple sink term only, no tracer manager

---

## 9. Success Criteria

1. **Standalone testability**: C++ module compiles and runs without Fortran
2. **Bit-reproducibility**: Outputs match Fortran baseline within tolerance (rel_diff < 1e-14)
3. **Configuration coverage**: Both `Held_Suarez` and `top_down` options validated
4. **Clean interface**: Single entry point (`hs_forcing_driver`) with clear parameters
5. **No hidden state**: All persistent state passed explicitly
6. **Future-ready**: Design supports `iso_c_binding` without refactoring
