# Translation Specification: Held-Suarez Forcing Module

## Document Information

| Attribute | Value |
|-----------|-------|
| **Version** | 1.0 |
| **Date** | 2026-06-03 |
| **Status** | Draft |
| **Scope** | Module-level C++ translation of `hs_forcing_mod` |

---

## 1. Original Fortran Files

### 1.1 Primary Source

| File | Path | Lines | Description |
|------|------|-------|-------------|
| `hs_forcing.F90` | `src/atmos_param/hs_forcing/hs_forcing.F90` | 1028 | Complete Held-Suarez forcing module |

### 1.2 Dependency Files (Reference Only)

| File | Path | Usage |
|------|------|-------|
| `constants_mod` | FMS library | Physical constants: `KAPPA`, `CP_AIR`, `GRAV`, `PI`, etc. |
| `time_manager_mod` | FMS library | `time_type`, `get_time()` |
| `astronomy_mod` | FMS library | `obliq`, `ecc`, `diurnal_exoplanet()` |
| `interpolator_mod` | FMS library | File-based equilibrium profiles (deferred) |
| `diag_manager_mod` | FMS library | Diagnostic output (excluded) |

---

## 2. Purpose of the Module

### 2.1 Scientific Purpose

The `hs_forcing_mod` implements the **Held-Suarez (1994)** benchmark forcing for idealized atmospheric dynamics simulations. It provides:

1. **Thermal Forcing (Newtonian Damping):** Relaxes temperature toward a zonally symmetric equilibrium profile
2. **Mechanical Forcing (Rayleigh Damping):** Applies boundary layer friction to near-surface winds
3. **Optional Extensions:** Top-down tropopause model, local heating, tracer sources/sinks

### 2.2 Reference

> Held, I. M., and M. J. Suarez, 1994: A proposal for the intercomparison of the dynamical cores of atmospheric general circulation models. *Bull. Amer. Meteor. Soc.*, **75**, 1825–1830.

### 2.3 Physical Equations

**Held-Suarez Equation 1-2 (Equilibrium Temperature):**
```
T_eq(φ,p) = max{T_strat, [T* - Δθ_v·cos²φ·ln(p/p₀)] · (p/p₀)^κ}

where:
  T* = T₀ - Δθ_h·sin²φ - ε·sin(φ)
  T₀ = 315 K (equatorial temperature)
  T_strat = 200 K (stratospheric minimum)
  Δθ_h = 60 K (equator-pole difference)
  Δθ_v = 10 K (static stability)
  κ = R/c_p ≈ 2/7
```

**Held-Suarez Equation 3 (Rayleigh Friction):**
```
∂v/∂t = -k_v(σ) · v

where:
  k_v(σ) = k_f · max{0, (σ - σ_b)/(1 - σ_b)}
  k_f = 1 day⁻¹
  σ_b = 0.7
```

**Held-Suarez Equation 4 (Newtonian Relaxation):**
```
∂T/∂t = -k_T(φ,σ) · (T - T_eq)

where:
  k_T(φ,σ) = k_a + (k_s - k_a)·cos⁴φ·max{0, (σ - σ_b)/(1 - σ_b)}
  k_a = (40 days)⁻¹
  k_s = (4 days)⁻¹
```

---

## 3. Routine Call Graph

### 3.1 Main Driver Flow

```
hs_forcing()  [Main entry point]
    │
    ├── [1] Compute surface pressure from p_half
    │
    ├── [2] rayleigh_damping()
    │       ├── Compute σ = p_full / ps
    │       ├── Compute friction coefficient k_v(σ)
    │       └── Output: udt, vdt
    │
    ├── [3] Energy conservation (optional)
    │       └── ttnd = -((um + 0.5*utnd*dt)*utnd + ...)/CP_AIR
    │
    ├── [4] Thermal forcing (branch on equilibrium_t_option)
    │       │
    │       ├── 'Held_Suarez' ──► newtonian_damping()
    │       │       ├── Compute T_eq profile
    │       │       ├── Compute damping k_T(φ,σ)
    │       │       └── Output: tdt, teq
    │       │
    │       └── 'top_down' ──► top_down_newtonian_damping()
    │               ├── update_orbit()
    │               │       └── calc_ecc_anomaly()
    │               ├── calc_hour_angle()
    │               ├── Compute radiative balance
    │               ├── Compute tropopause height
    │               ├── Apply heat capacity
    │               └── Output: tdt, teq, h_trop, tg_new
    │
    ├── [5] local_heating() (optional)
    │       └── Output: additional tdt
    │
    └── [6] tracer_source_sink() (for each tracer)
            └── Output: rdt
```

### 3.2 Internal Routine Dependencies

```
hs_forcing
    ├── rayleigh_damping
    │       └── (optional) get_zonal_mean_flow [DEFERRED]
    │
    ├── newtonian_damping
    │       └── (optional) get_zonal_mean_temp [DEFERRED]
    │
    ├── top_down_newtonian_damping
    │       ├── update_orbit
    │       │       └── calc_ecc_anomaly
    │       └── calc_hour_angle
    │
    ├── local_heating
    │       └── (optional) interpolator [DEFERRED]
    │
    └── tracer_source_sink
```

### 3.3 Translation Status in Call Graph

```
hs_forcing ─────────────────────────────────── [ ] TO IMPLEMENT
    │
    ├── rayleigh_damping ───────────────────── [✓] TRANSLATED
    │
    ├── newtonian_damping ──────────────────── [✓] TRANSLATED
    │
    ├── top_down_newtonian_damping ─────────── [✓] TRANSLATED
    │       ├── update_orbit ───────────────── [✓] (embedded)
    │       │       └── calc_ecc_anomaly ───── [✓] TRANSLATED
    │       └── calc_hour_angle ────────────── [✓] TRANSLATED
    │
    ├── local_heating ──────────────────────── [ ] TO IMPLEMENT (Isidoro only)
    │
    └── tracer_source_sink ─────────────────── [ ] TO IMPLEMENT
```

---

## 4. Module-Level Inputs

### 4.1 Grid and Time

| Name | Fortran Type | Dimensions | Units | Description |
|------|--------------|------------|-------|-------------|
| `is`, `ie`, `js`, `je` | integer | scalar | — | Domain index bounds |
| `dt` | real | scalar | s | Physics timestep |
| `Time` | time_type | scalar | — | Current model time |

### 4.2 Coordinate Arrays

| Name | Fortran Type | Dimensions | Units | Description |
|------|--------------|------------|-------|-------------|
| `lon` | real | (nlon, nlat) | radians | Longitude |
| `lat` | real | (nlon, nlat) | radians | Latitude |

### 4.3 Pressure Fields

| Name | Fortran Type | Dimensions | Units | Description |
|------|--------------|------------|-------|-------------|
| `p_half` | real | (nlon, nlat, nlev+1) | Pa | Pressure at half (interface) levels |
| `p_full` | real | (nlon, nlat, nlev) | Pa | Pressure at full (mid) levels |

### 4.4 Prognostic Variables

| Name | Fortran Type | Dimensions | Units | Description |
|------|--------------|------------|-------|-------------|
| `u` | real | (nlon, nlat, nlev) | m/s | Zonal wind (current) |
| `v` | real | (nlon, nlat, nlev) | m/s | Meridional wind (current) |
| `t` | real | (nlon, nlat, nlev) | K | Temperature (current) |
| `um`, `vm`, `tm` | real | (nlon, nlat, nlev) | — | Previous timestep values (for energy conservation) |
| `r` | real | (nlon, nlat, nlev, ntracers) | kg/kg | Tracer mixing ratios |
| `rm` | real | (nlon, nlat, nlev, ntracers) | kg/kg | Previous tracer values |

### 4.5 Height Field (Top-Down Only)

| Name | Fortran Type | Dimensions | Units | Description |
|------|--------------|------------|-------|-------------|
| `zfull` | real | (nlon, nlat, nlev) | m | Height at full levels |

### 4.6 Optional Inputs

| Name | Fortran Type | Dimensions | Units | Description |
|------|--------------|------------|-------|-------------|
| `mask` | real | (nlon, nlat, nlev) | — | Land/sea mask (0 or 1) |
| `kbot` | integer | (nlon, nlat) | — | Bottom level index (for terrain) |

---

## 5. Module-Level Outputs

### 5.1 Tendency Fields (intent: inout, accumulated)

| Name | Fortran Type | Dimensions | Units | Description |
|------|--------------|------------|-------|-------------|
| `udt` | real | (nlon, nlat, nlev) | m/s² | Zonal wind tendency |
| `vdt` | real | (nlon, nlat, nlev) | m/s² | Meridional wind tendency |
| `tdt` | real | (nlon, nlat, nlev) | K/s | Temperature tendency |
| `rdt` | real | (nlon, nlat, nlev, ntracers) | kg/kg/s | Tracer tendencies |

### 5.2 Diagnostic Fields (computed internally)

| Name | Fortran Type | Dimensions | Units | Description |
|------|--------------|------------|-------|-------------|
| `teq` | real | (nlon, nlat, nlev) | K | Equilibrium temperature |
| `h_trop` | real | (nlon, nlat) | km | Tropopause height (top_down only) |
| `utnd`, `vtnd`, `ttnd` | real | (nlon, nlat, nlev) | — | Internal tendencies before accumulation |

---

## 6. Shared State and Configuration

### 6.1 Namelist Parameters (hs_forcing_nml)

#### Equilibrium Temperature Parameters

| Parameter | Type | Default | Units | Description |
|-----------|------|---------|-------|-------------|
| `t_zero` | real | 315.0 | K | Equatorial equilibrium temperature |
| `t_strat` | real | 200.0 | K | Stratospheric temperature minimum |
| `delh` | real | 60.0 | K | Equator-pole temperature difference |
| `delv` | real | 10.0 | K | Static stability parameter |
| `eps` | real | 0.0 | K | Hemispheric asymmetry |
| `P00` | real | 1.0e5 | Pa | Reference pressure |

#### Damping Timescale Parameters

| Parameter | Type | Default | Units | Description |
|-----------|------|---------|-------|-------------|
| `ka` | real | -40.0 | days | Atmospheric relaxation timescale |
| `ks` | real | -4.0 | days | Surface relaxation timescale |
| `kf` | real | -1.0 | days | Rayleigh friction timescale |
| `sigma_b` | real | 0.7 | — | Boundary layer top sigma level |

#### Top-Down Forcing Parameters

| Parameter | Type | Default | Units | Description |
|-----------|------|---------|-------|-------------|
| `peri_time` | real | 0.25 | — | Perihelion time as fraction of orbital period |
| `smaxis` | real | 1.5e6 | m | Semi-major axis |
| `albedo` | real | 0.3 | — | Surface albedo |
| `lapse` | real | 6.5 | K/km | Lapse rate |
| `h_a` | real | 2.0 | — | Atmospheric scale height parameter |
| `tau_s` | real | 5.0 | — | Optical depth parameter |
| `heat_capacity` | real | 4.2e6 | J/m³/K | Heat capacity |
| `ml_depth` | real | 1.0 | m | Mixed layer depth |

#### Control Flags

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `no_forcing` | logical | .false. | Disable all forcing |
| `do_conserve_energy` | logical | .true. | Include energy conservation term |
| `equilibrium_t_option` | string | 'Held_Suarez' | Teq calculation method |
| `stratosphere_t_option` | string | 'extend_tp' | Stratosphere handling (top_down) |

### 6.2 Derived Coefficients (Computed in Init)

| Variable | Type | Derivation | Units |
|----------|------|------------|-------|
| `tka` | real | `1/(86400*abs(ka))` | 1/s |
| `tks` | real | `1/(86400*abs(ks))` | 1/s |
| `vkf` | real | `1/(86400*abs(kf))` | 1/s |

### 6.3 Persistent Module State

| Variable | Type | Dimensions | Purpose |
|----------|------|------------|---------|
| `tg_prev` | real, allocatable | (nlon, nlat) | Previous ground temperature (top_down) |
| `module_is_initialized` | logical | scalar | Initialization guard |

---

## 7. Array Dimensions and Memory Layout

### 7.1 Dimension Conventions

| Symbol | Meaning | Typical Range |
|--------|---------|---------------|
| `nlon` | Longitude points | 64–256 |
| `nlat` | Latitude points | 32–128 |
| `nlev` | Vertical levels | 20–40 |
| `ntracers` | Number of tracers | 0–10 |

### 7.2 Fortran Array Layout (Column-Major)

```fortran
! 2D arrays: (lon, lat)
real :: ps(nlon, nlat)       ! Memory: ps(1,1), ps(2,1), ..., ps(nlon,1), ps(1,2), ...

! 3D arrays: (lon, lat, lev)
real :: t(nlon, nlat, nlev)  ! Memory: t(1,1,1), t(2,1,1), ..., t(nlon,nlat,nlev)

! 4D arrays: (lon, lat, lev, tracer)
real :: r(nlon, nlat, nlev, ntracers)
```

### 7.3 C++ Array Layout (Preserving Fortran Order)

For validation, C++ translations preserve Fortran column-major order:

```cpp
// 2D index: arr[i + nlon * j]
int idx_2d(int i, int j, int nlon) {
    return i + nlon * j;
}

// 3D index: arr[i + nlon * (j + nlat * k)]
int idx_3d(int i, int j, int k, int nlon, int nlat) {
    return i + nlon * (j + nlat * k);
}
```

### 7.4 Vertical Level Ordering

- Level `k=1` (Fortran) / `k=0` (C++): **Top of atmosphere** (lowest pressure)
- Level `k=nlev`: **Near surface** (highest pressure)
- `p_half(k)` < `p_full(k)` < `p_half(k+1)`

---

## 8. Initialization Sequence

### 8.1 Fortran Initialization (`hs_forcing_init`)

```
1. Read namelist (hs_forcing_nml)
2. Allocate tg_prev array
3. If top_down mode:
   a. If restart file exists: read tg_prev
   b. Else: spin up heat capacity (spinup_time iterations)
4. Convert namelist values to derived coefficients:
   - tka = 1/(86400*|ka|)
   - tks = 1/(86400*|ks|)
   - vkf = 1/(86400*|kf|)
   - xwidth, ywidth, etc. → radians
5. Initialize interpolators (if from_file options)
6. Initialize astronomy module
7. Register diagnostic fields
8. Set module_is_initialized = .true.
```

### 8.2 C++ Initialization (Simplified)

```cpp
// C++ uses explicit parameter passing instead of namelist
// Initialization is replaced by:
// 1. Config struct populated by caller
// 2. Derived coefficients computed in config constructor
// 3. tg_prev passed as input array (caller manages persistence)
// 4. No diagnostic registration (outputs are arrays)

HeldSuarezConfig config;
config.set_defaults();
config.compute_derived_coefficients();  // tka, tks, vkf
```

---

## 9. Numerical Formulas

### 9.1 Rayleigh Damping

```cpp
// Input: ps[nlon,nlat], p_full[nlon,nlat,nlev], u[nlon,nlat,nlev], v[nlon,nlat,nlev]
// Output: udt[nlon,nlat,nlev], vdt[nlon,nlat,nlev]

double vcoeff = -vkf / (1.0 - sigma_b);

for (k = 0; k < nlev; ++k) {
    for (j = 0; j < nlat; ++j) {
        for (i = 0; i < nlon; ++i) {
            double sigma = p_full[i,j,k] / ps[i,j];
            
            if (sigma > sigma_b && sigma <= 1.0) {
                double vfactr = vcoeff * (sigma - sigma_b);
                udt[i,j,k] = vfactr * u[i,j,k];
                vdt[i,j,k] = vfactr * v[i,j,k];
            } else {
                udt[i,j,k] = 0.0;
                vdt[i,j,k] = 0.0;
            }
        }
    }
}
```

### 9.2 Newtonian Damping (Held-Suarez)

```cpp
// Precompute latitude terms (2D)
for (j = 0; j < nlat; ++j) {
    for (i = 0; i < nlon; ++i) {
        sin_lat[i,j] = sin(lat[i,j]);
        cos_lat[i,j] = cos(lat[i,j]);
        sin_lat_2[i,j] = sin_lat[i,j] * sin_lat[i,j];
        cos_lat_2[i,j] = 1.0 - sin_lat_2[i,j];
        cos_lat_4[i,j] = cos_lat_2[i,j] * cos_lat_2[i,j];
        
        t_star[i,j] = t_zero - delh * sin_lat_2[i,j] - eps * sin_lat[i,j];
        tstr[i,j] = t_strat - eps * sin_lat[i,j];
    }
}

double tcoeff = (tks - tka) / (1.0 - sigma_b);

for (k = 0; k < nlev; ++k) {
    for (j = 0; j < nlat; ++j) {
        for (i = 0; i < nlon; ++i) {
            // Equilibrium temperature
            double p_norm = p_full[i,j,k] / P00;
            double the = t_star[i,j] - delv * cos_lat_2[i,j] * log(p_norm);
            teq[i,j,k] = max(the * pow(p_norm, kappa), tstr[i,j]);
            
            // Damping coefficient
            double sigma = p_full[i,j,k] / ps[i,j];
            double tdamp;
            if (sigma > sigma_b && sigma <= 1.0) {
                double tfactr = tcoeff * (sigma - sigma_b);
                tdamp = tka + cos_lat_4[i,j] * tfactr;
            } else {
                tdamp = tka;
            }
            
            // Temperature tendency
            tdt[i,j,k] = -tdamp * (t[i,j,k] - teq[i,j,k]);
        }
    }
}
```

### 9.3 Top-Down Newtonian Damping

```cpp
// Time extraction
int current_time = days * 86400 + seconds;

// Orbital calculations
double mean_anomaly = 2*PI / (orbital_period*86400) * 
                      (current_time - peri_time*orbital_period*86400);
calc_ecc_anomaly(mean_anomaly, ecc, ecc_anomaly);
double true_anomaly = 2*atan(sqrt((1+ecc)/(1-ecc)) * tan(ecc_anomaly/2));
double orb_dist = smaxis * (1 - ecc*ecc) / (1 + ecc*cos(true_anomaly));
double theta = 2*PI * current_time / (orbital_period*86400);
double dec = asin(sin(obliq*PI/180) * sin(theta));

// Hour angle
calc_hour_angle(nlon, nlat, lat, dec, hour_angle);

// Solar insolation
for (j = 0; j < nlat; ++j) {
    for (i = 0; i < nlon; ++i) {
        s[i,j] = solar_const/PI * (hour_angle[i,j]*sin_lat[i,j]*sin(dec) + 
                                   cos_lat[i,j]*cos(dec)*sin(hour_angle[i,j]));
    }
}

// Radiative balance temperature
for (idx = 0; idx < nlon*nlat; ++idx) {
    t_radbal[idx] = pow((1-albedo)*s[idx]/stefan, 0.25);
}

// Tropopause height
for (idx = 0; idx < nlon*nlat; ++idx) {
    t_trop[idx] = t_radbal[idx] / pow(2.0, 0.25);
    h_trop[idx] = 1.0/(16*lapse) * (1.3863*t_trop[idx] + 
                  sqrt(pow(1.3863*t_trop[idx], 2) + 32*lapse*tau_s*h_a*t_trop[idx]));
}

// Surface temperature with heat capacity
for (idx = 0; idx < nlon*nlat; ++idx) {
    t_surf[idx] = t_trop[idx] + h_trop[idx] * lapse;
    tg[idx] = stefan*dt/(ml_depth*heat_capacity) * 
              (pow(t_surf[idx],4) - pow(tg_prev[idx],4)) + tg_prev[idx];
    tg_new[idx] = tg[idx];  // Output for caller to persist
    t_trop[idx] = tg[idx] - h_trop[idx] * lapse;
}

// Equilibrium temperature profile (similar to standard HS but using t_trop, h_trop)
for (k = 0; k < nlev; ++k) {
    for (j = 0; j < nlat; ++j) {
        for (i = 0; i < nlon; ++i) {
            teq[i,j,k] = t_trop[i,j] + lapse * (h_trop[i,j] - zfull[i,j,k]/1000);
            
            // Apply stratosphere option
            if (stratosphere_t_option == STRAT_HS_LIKE) {
                teq[i,j,k] = max(teq[i,j,k], tstr[i,j]);
            }
            // ... other options ...
        }
    }
}
```

### 9.4 Energy Conservation Term

```cpp
if (do_conserve_energy) {
    for (k = 0; k < nlev; ++k) {
        for (j = 0; j < nlat; ++j) {
            for (i = 0; i < nlon; ++i) {
                double u_avg = um[i,j,k] + 0.5 * udt[i,j,k] * dt;
                double v_avg = vm[i,j,k] + 0.5 * vdt[i,j,k] * dt;
                tdt[i,j,k] += -(u_avg * udt[i,j,k] + v_avg * vdt[i,j,k]) / CP_AIR;
            }
        }
    }
}
```

---

## 10. Side Effects

### 10.1 Module State Modifications

| Operation | Side Effect | C++ Handling |
|-----------|-------------|--------------|
| `tg_prev = tg` | Updates ground temperature state | Return `tg_new` as output |
| `module_is_initialized = .true.` | Sets init flag | Not needed (stateless) |

### 10.2 External Side Effects (Excluded from C++)

| Operation | Side Effect | C++ Handling |
|-----------|-------------|--------------|
| `send_data()` | Writes to diagnostic output | Return arrays instead |
| `interpolator()` | Reads from file | Deferred |
| `write_data()` | Writes restart file | Caller responsibility |

### 10.3 Accumulation Pattern

The Fortran driver **accumulates** tendencies:
```fortran
udt = udt + utnd  ! Not overwrite!
vdt = vdt + vtnd
tdt = tdt + ttnd
```

C++ must preserve this pattern or document that outputs are **increments only**.

---

## 11. Assumptions

### 11.1 Physical Assumptions

1. **Hydrostatic atmosphere:** Pressure decreases monotonically with height
2. **Ideal gas:** κ = R/c_p = 2/7
3. **Zonally symmetric equilibrium:** T_eq depends only on latitude and pressure
4. **No orography:** Surface pressure ps is smooth (unless kbot provided)
5. **Earth-like orbit:** Orbital parameters are Earth defaults

### 11.2 Numerical Assumptions

1. **Double precision:** All calculations use 64-bit floating point
2. **Column-major arrays:** C++ preserves Fortran memory layout for validation
3. **σ ∈ (0, 1]:** Sigma coordinate is bounded
4. **cos⁴φ ∈ [0, 1]:** Latitude-dependent damping is bounded

### 11.3 Configuration Assumptions

1. **Default branch:** `equilibrium_t_option = 'Held_Suarez'` is the primary target
2. **No file I/O:** `from_file` options are deferred
3. **No tracers initially:** Tracer handling is optional
4. **No MPI:** Single-threaded, explicit dimensions

---

## 12. Dependencies

### 12.1 Dependency Matrix

| Dependency | Type | Action | Priority |
|------------|------|--------|----------|
| `sin`, `cos`, `tan`, `acos`, `asin`, `atan` | Intrinsic | `std::` | Required |
| `log`, `exp`, `sqrt`, `pow`, `abs`, `max`, `min` | Intrinsic | `std::` | Required |
| `KAPPA` | Constant | Inline `2.0/7.0` | Required |
| `CP_AIR` | Constant | Inline `1004.0` | Required |
| `GRAV` | Constant | Inline `9.80665` | Required |
| `PI` | Constant | `M_PI` or inline | Required |
| `SECONDS_PER_DAY` | Constant | Inline `86400.0` | Required |
| `stefan` | Constant | Inline `5.670374419e-8` | Required |
| `solar_const` | Parameter | Pass via config | Required |
| `orbital_period` | Parameter | Pass via config | Required |
| `obliq`, `ecc` | Parameter | Pass via config | Required |
| `time_type` | Type | Replace with `int` (seconds) | Required |
| `get_time()` | Function | Inline: `days*86400 + seconds` | Required |
| `error_mesg()` | Function | `throw` or error code | Optional |
| `interpolator()` | Module | Defer | Deferred |
| `send_data()` | Function | Remove | Excluded |
| `register_diag_field()` | Function | Remove | Excluded |
| `mpp_*` | Module | Remove | Excluded |

### 12.2 Header Dependencies (C++)

```cpp
#include <cmath>      // sin, cos, tan, acos, asin, atan, log, exp, sqrt, pow, abs
#include <algorithm>  // std::max, std::min
#include <cstddef>    // size_t
#include <vector>     // std::vector (for temporaries)
#include <stdexcept>  // std::runtime_error (optional)
```

---

## 13. Proposed C++ File Structure

```
translated/held_suarez/cpp/
│
├── include/                              # Shared headers
│   ├── hs_forcing_types.hpp              # Common type definitions
│   └── hs_forcing_constants.hpp          # Physical constants
│
├── hs_forcing/                           # Unified module
│   ├── hs_forcing.hpp                    # Main include (aggregates all)
│   ├── hs_forcing_config.hpp             # Configuration struct
│   ├── hs_forcing_driver.hpp             # Driver implementation
│   ├── hs_forcing_c_api.h                # C-compatible API header
│   ├── hs_forcing_c_api.cpp              # C-compatible API implementation
│   ├── test_driver.cpp                   # Standalone test
│   ├── test_hybrid.F90                   # Fortran calling C++ (future)
│   ├── Makefile
│   └── README.md
│
├── calc_ecc_anomaly/                     # ✅ EXISTS
│   └── calc_ecc_anomaly.hpp
│
├── calc_hour_angle/                      # ✅ EXISTS
│   └── calc_hour_angle.hpp
│
├── rayleigh_damping/                     # ✅ EXISTS
│   └── rayleigh_damping.hpp
│
├── newtonian_damping/                    # ✅ EXISTS
│   └── newtonian_damping.hpp
│
└── top_down_newtonian_damping/           # ✅ EXISTS
    └── top_down_newtonian_damping.hpp
```

---

## 14. Proposed C++ Namespace Design

### 14.1 Namespace Hierarchy

```cpp
namespace hs_forcing {

    // Physical constants
    namespace constants {
        constexpr double KAPPA = 2.0 / 7.0;
        constexpr double CP_AIR = 1004.0;
        constexpr double GRAV = 9.80665;
        constexpr double PI = 3.14159265358979323846;
        constexpr double SECONDS_PER_DAY = 86400.0;
        constexpr double STEFAN = 5.670374419e-8;
    }

    // Enumeration types
    enum class EquilibriumOption {
        HeldSuarez = 0,
        TopDown = 1
    };

    enum class StratosphereOption {
        Default = 0,
        ConstantAboveTropopause = 1,
        HeldSuarezLike = 2,
        ExtendTropopause = 3
    };

    // Configuration
    struct Config { ... };

    // Individual kernels (existing)
    void calc_ecc_anomaly(...);
    void calc_hour_angle(...);
    void rayleigh_damping(...);
    void newtonian_damping(...);
    void top_down_newtonian_damping(...);

    // Module driver
    void forcing_driver(...);

    // Optional routines
    void local_heating_isidoro(...);
    void tracer_source_sink(...);

}  // namespace hs_forcing
```

### 14.2 Configuration Struct

```cpp
namespace hs_forcing {

struct Config {
    //--- Equilibrium temperature parameters ---
    double t_zero = 315.0;          // K
    double t_strat = 200.0;         // K
    double delh = 60.0;             // K
    double delv = 10.0;             // K
    double eps = 0.0;               // K
    double P00 = 1.0e5;             // Pa
    double kappa = constants::KAPPA;

    //--- Damping timescales (in 1/s) ---
    double tka = 0.0;               // Computed from ka_days
    double tks = 0.0;               // Computed from ks_days
    double vkf = 0.0;               // Computed from kf_days
    double sigma_b = 0.7;

    //--- Raw timescales (in days, for initialization) ---
    double ka_days = 40.0;
    double ks_days = 4.0;
    double kf_days = 1.0;

    //--- Orbital parameters (top_down) ---
    double orbital_period = 365.25; // days
    double ecc = 0.0167;
    double obliq = 23.44;           // degrees
    double peri_time = 0.25;
    double smaxis = 1.496e11;       // m
    double solar_const = 1360.0;    // W/m²
    double stefan = constants::STEFAN;
    double albedo = 0.3;
    double lapse = 6.5;             // K/km
    double h_a = 2.0;
    double tau_s = 5.0;
    double heat_capacity = 4.2e6;   // J/m³/K
    double ml_depth = 1.0;          // m

    //--- Control flags ---
    bool no_forcing = false;
    bool do_conserve_energy = true;
    EquilibriumOption equilibrium_option = EquilibriumOption::HeldSuarez;
    StratosphereOption stratosphere_option = StratosphereOption::HeldSuarezLike;

    //--- Methods ---
    void compute_derived_coefficients() {
        tka = 1.0 / (constants::SECONDS_PER_DAY * ka_days);
        tks = 1.0 / (constants::SECONDS_PER_DAY * ks_days);
        vkf = 1.0 / (constants::SECONDS_PER_DAY * kf_days);
    }

    static Config defaults() {
        Config cfg;
        cfg.compute_derived_coefficients();
        return cfg;
    }
};

}  // namespace hs_forcing
```

### 14.3 Driver Function

```cpp
namespace hs_forcing {

struct ForcingOutput {
    double* udt;      // [nlon, nlat, nlev] - wind tendency (accumulated)
    double* vdt;      // [nlon, nlat, nlev] - wind tendency (accumulated)
    double* tdt;      // [nlon, nlat, nlev] - temperature tendency (accumulated)
    double* teq;      // [nlon, nlat, nlev] - equilibrium temperature
    double* h_trop;   // [nlon, nlat] - tropopause height (top_down only, may be nullptr)
    double* tg_new;   // [nlon, nlat] - new ground temperature (top_down only, may be nullptr)
};

void forcing_driver(
    // Grid dimensions
    int nlon, int nlat, int nlev,
    
    // Time
    int current_time,               // seconds since epoch
    double dt,                      // timestep (seconds)
    
    // Coordinate arrays
    const double* lon,              // [nlon, nlat]
    const double* lat,              // [nlon, nlat]
    
    // Pressure fields
    const double* ps,               // [nlon, nlat]
    const double* p_full,           // [nlon, nlat, nlev]
    const double* p_half,           // [nlon, nlat, nlev+1] (for energy conservation)
    
    // Prognostic variables
    const double* u,                // [nlon, nlat, nlev]
    const double* v,                // [nlon, nlat, nlev]
    const double* t,                // [nlon, nlat, nlev]
    
    // Previous timestep (for energy conservation)
    const double* um,               // [nlon, nlat, nlev] (nullptr if !do_conserve_energy)
    const double* vm,               // [nlon, nlat, nlev] (nullptr if !do_conserve_energy)
    
    // Top-down specific inputs
    const double* zfull,            // [nlon, nlat, nlev] (nullptr if HeldSuarez)
    const double* tg_prev,          // [nlon, nlat] (nullptr if HeldSuarez)
    
    // Configuration
    const Config& config,
    
    // Outputs (modified in-place)
    ForcingOutput& output,
    
    // Optional mask
    const double* mask = nullptr    // [nlon, nlat, nlev]
);

}  // namespace hs_forcing
```

---

## 15. Proposed C-Compatible Wrapper Design

### 15.1 C API Header (`hs_forcing_c_api.h`)

```c
#ifndef HS_FORCING_C_API_H
#define HS_FORCING_C_API_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Held-Suarez Forcing C API
 * 
 * This API provides C-compatible wrappers for calling the C++ implementation
 * from Fortran via iso_c_binding.
 */

/* Equilibrium temperature options */
#define HS_EQUILIBRIUM_HELD_SUAREZ 0
#define HS_EQUILIBRIUM_TOP_DOWN    1

/* Stratosphere options */
#define HS_STRATOSPHERE_DEFAULT        0
#define HS_STRATOSPHERE_CONST_ABOVE_TP 1
#define HS_STRATOSPHERE_HS_LIKE        2
#define HS_STRATOSPHERE_EXTEND_TP      3

/* Error codes */
#define HS_SUCCESS                0
#define HS_ERROR_NULL_POINTER    -1
#define HS_ERROR_INVALID_DIMS    -2
#define HS_ERROR_INVALID_CONFIG  -3

/*
 * Main forcing driver
 * 
 * All arrays use Fortran column-major layout.
 * Tendency arrays (udt, vdt, tdt) are ACCUMULATED (added to), not overwritten.
 */
int hs_forcing_driver_c(
    /* Grid dimensions */
    int nlon, int nlat, int nlev,
    
    /* Time */
    int current_time,               /* seconds since epoch */
    double dt,                      /* timestep (seconds) */
    
    /* Coordinate arrays [nlon, nlat] */
    const double* lon,
    const double* lat,
    
    /* Pressure fields */
    const double* ps,               /* [nlon, nlat] */
    const double* p_full,           /* [nlon, nlat, nlev] */
    const double* p_half,           /* [nlon, nlat, nlev+1] or NULL */
    
    /* Prognostic variables [nlon, nlat, nlev] */
    const double* u,
    const double* v,
    const double* t,
    
    /* Previous timestep [nlon, nlat, nlev] or NULL if !do_conserve_energy */
    const double* um,
    const double* vm,
    
    /* Top-down specific inputs (NULL if HeldSuarez) */
    const double* zfull,            /* [nlon, nlat, nlev] */
    const double* tg_prev,          /* [nlon, nlat] */
    
    /* Configuration parameters (flat, for C interop) */
    double t_zero, double t_strat, double delh, double delv, double eps,
    double P00, double kappa,
    double tka, double tks, double vkf, double sigma_b,
    double orbital_period, double ecc, double obliq, double peri_time,
    double smaxis, double solar_const, double stefan, double albedo,
    double lapse, double h_a, double tau_s, double heat_capacity, double ml_depth,
    int do_conserve_energy,
    int equilibrium_option,
    int stratosphere_option,
    
    /* Outputs [accumulated, except teq/h_trop/tg_new] */
    double* udt,                    /* [nlon, nlat, nlev] */
    double* vdt,                    /* [nlon, nlat, nlev] */
    double* tdt,                    /* [nlon, nlat, nlev] */
    double* teq,                    /* [nlon, nlat, nlev] */
    double* h_trop,                 /* [nlon, nlat] or NULL */
    double* tg_new,                 /* [nlon, nlat] or NULL */
    
    /* Optional mask [nlon, nlat, nlev] or NULL */
    const double* mask
);

/*
 * Individual kernel wrappers (for testing)
 */
int hs_rayleigh_damping_c(
    int nlon, int nlat, int nlev,
    const double* ps,
    const double* p_full,
    const double* u,
    const double* v,
    double vkf, double sigma_b,
    double* udt,
    double* vdt,
    const double* mask
);

int hs_newtonian_damping_c(
    int nlon, int nlat, int nlev,
    const double* lat,
    const double* ps,
    const double* p_full,
    const double* t,
    double t_zero, double t_strat, double delh, double delv, double eps,
    double P00, double kappa,
    double tka, double tks, double sigma_b,
    double* tdt,
    double* teq,
    const double* mask
);

#ifdef __cplusplus
}
#endif

#endif /* HS_FORCING_C_API_H */
```

### 15.2 Fortran Interface Module (`hs_forcing_c_interface.F90`)

```fortran
module hs_forcing_c_interface
  use iso_c_binding
  implicit none

  ! Equilibrium options
  integer(c_int), parameter :: HS_EQUILIBRIUM_HELD_SUAREZ = 0
  integer(c_int), parameter :: HS_EQUILIBRIUM_TOP_DOWN    = 1

  ! Stratosphere options
  integer(c_int), parameter :: HS_STRATOSPHERE_DEFAULT        = 0
  integer(c_int), parameter :: HS_STRATOSPHERE_CONST_ABOVE_TP = 1
  integer(c_int), parameter :: HS_STRATOSPHERE_HS_LIKE        = 2
  integer(c_int), parameter :: HS_STRATOSPHERE_EXTEND_TP      = 3

  interface
    integer(c_int) function hs_forcing_driver_c( &
        nlon, nlat, nlev, &
        current_time, dt, &
        lon, lat, &
        ps, p_full, p_half, &
        u, v, t, &
        um, vm, &
        zfull, tg_prev, &
        t_zero, t_strat, delh, delv, eps, &
        P00, kappa, &
        tka, tks, vkf, sigma_b, &
        orbital_period, ecc, obliq, peri_time, &
        smaxis, solar_const, stefan, albedo, &
        lapse, h_a, tau_s, heat_capacity, ml_depth, &
        do_conserve_energy, &
        equilibrium_option, &
        stratosphere_option, &
        udt, vdt, tdt, teq, &
        h_trop, tg_new, &
        mask &
    ) bind(C, name='hs_forcing_driver_c')
      import :: c_int, c_double, c_ptr
      integer(c_int), value :: nlon, nlat, nlev
      integer(c_int), value :: current_time
      real(c_double), value :: dt
      type(c_ptr), value :: lon, lat
      type(c_ptr), value :: ps, p_full, p_half
      type(c_ptr), value :: u, v, t
      type(c_ptr), value :: um, vm
      type(c_ptr), value :: zfull, tg_prev
      real(c_double), value :: t_zero, t_strat, delh, delv, eps
      real(c_double), value :: P00, kappa
      real(c_double), value :: tka, tks, vkf, sigma_b
      real(c_double), value :: orbital_period, ecc, obliq, peri_time
      real(c_double), value :: smaxis, solar_const, stefan, albedo
      real(c_double), value :: lapse, h_a, tau_s, heat_capacity, ml_depth
      integer(c_int), value :: do_conserve_energy
      integer(c_int), value :: equilibrium_option
      integer(c_int), value :: stratosphere_option
      type(c_ptr), value :: udt, vdt, tdt, teq
      type(c_ptr), value :: h_trop, tg_new
      type(c_ptr), value :: mask
    end function hs_forcing_driver_c
  end interface

contains

  subroutine hs_forcing_cpp(nlon, nlat, nlev, current_time, dt, &
                            lon, lat, ps, p_full, u, v, t, &
                            udt, vdt, tdt, teq)
    ! Simplified Fortran wrapper for common case
    integer, intent(in) :: nlon, nlat, nlev, current_time
    real(8), intent(in) :: dt
    real(8), intent(in), target :: lon(nlon,nlat), lat(nlon,nlat)
    real(8), intent(in), target :: ps(nlon,nlat), p_full(nlon,nlat,nlev)
    real(8), intent(in), target :: u(nlon,nlat,nlev), v(nlon,nlat,nlev), t(nlon,nlat,nlev)
    real(8), intent(inout), target :: udt(nlon,nlat,nlev), vdt(nlon,nlat,nlev)
    real(8), intent(inout), target :: tdt(nlon,nlat,nlev)
    real(8), intent(out), target :: teq(nlon,nlat,nlev)

    integer(c_int) :: ierr

    ierr = hs_forcing_driver_c( &
        int(nlon,c_int), int(nlat,c_int), int(nlev,c_int), &
        int(current_time,c_int), dt, &
        c_loc(lon), c_loc(lat), &
        c_loc(ps), c_loc(p_full), c_null_ptr, &
        c_loc(u), c_loc(v), c_loc(t), &
        c_null_ptr, c_null_ptr, &
        c_null_ptr, c_null_ptr, &
        315.0_c_double, 200.0_c_double, 60.0_c_double, 10.0_c_double, 0.0_c_double, &
        1.0e5_c_double, 2.0_c_double/7.0_c_double, &
        2.893518e-7_c_double, 2.893518e-6_c_double, 1.157407e-5_c_double, 0.7_c_double, &
        365.25_c_double, 0.0167_c_double, 23.44_c_double, 0.25_c_double, &
        1.496e11_c_double, 1360.0_c_double, 5.67e-8_c_double, 0.3_c_double, &
        6.5_c_double, 2.0_c_double, 5.0_c_double, 4.2e6_c_double, 1.0_c_double, &
        1_c_int, &
        HS_EQUILIBRIUM_HELD_SUAREZ, &
        HS_STRATOSPHERE_HS_LIKE, &
        c_loc(udt), c_loc(vdt), c_loc(tdt), c_loc(teq), &
        c_null_ptr, c_null_ptr, &
        c_null_ptr &
    )

  end subroutine hs_forcing_cpp

end module hs_forcing_c_interface
```

---

## 16. Standalone Test Strategy

### 16.1 Test Levels

| Level | Scope | Data Source | Validation |
|-------|-------|-------------|------------|
| Unit | Individual kernels | Synthetic | Analytical solutions |
| Integration | Combined kernels | Fortran baseline | Bit-reproducible |
| Module | Full driver | Fortran baseline | Tolerance-based |
| Configuration | Multiple configs | Multiple baselines | Per-config comparison |

### 16.2 Unit Tests (Existing)

| Test | Kernel | Status | Tolerance |
|------|--------|--------|-----------|
| `test_calc_ecc_anomaly` | `calc_ecc_anomaly` | ✅ PASS | Exact |
| `test_calc_hour_angle` | `calc_hour_angle` | ✅ PASS | Exact |
| `test_rayleigh_damping` | `rayleigh_damping` | ✅ PASS | Exact |
| `test_newtonian_damping` | `newtonian_damping` | ✅ PASS | Exact |
| `test_top_down` | `top_down_newtonian_damping` | ✅ PASS | rel < 1e-14 |

### 16.3 Module Integration Tests (To Create)

```
tests/fortran_baseline/hs_forcing_module/
├── generate_baseline.F90      # Fortran program to generate reference data
├── Makefile
├── config_held_suarez.nml     # Standard HS configuration
├── config_top_down.nml        # Top-down configuration
├── input_*.bin                # Input arrays
├── output_held_suarez_*.bin   # Reference outputs (HS mode)
└── output_top_down_*.bin      # Reference outputs (top_down mode)
```

### 16.4 Test Cases

| Test Case | equilibrium_option | do_conserve_energy | Description |
|-----------|-------------------|-------------------|-------------|
| HS_basic | Held_Suarez | false | Minimal standard HS |
| HS_energy | Held_Suarez | true | HS with energy conservation |
| TD_basic | top_down | false | Minimal top-down |
| TD_energy | top_down | true | Top-down with energy conservation |
| HS_polar | Held_Suarez | false | Extreme polar latitudes |
| HS_tropical | Held_Suarez | false | Tropical latitudes only |

### 16.5 Test Driver Structure

```cpp
// test_hs_forcing_module.cpp

#include "hs_forcing/hs_forcing.hpp"
#include <cassert>
#include <cmath>
#include <fstream>
#include <iostream>
#include <vector>

// File I/O helpers
std::vector<double> read_binary(const std::string& filename, size_t count);
void write_binary(const std::string& filename, const std::vector<double>& data);

// Comparison helpers
struct CompareResult {
    double max_abs_diff;
    double max_rel_diff;
    bool passed;
};

CompareResult compare_arrays(const std::vector<double>& computed,
                             const std::vector<double>& reference,
                             double rtol = 1e-14,
                             double atol = 1e-20);

int main(int argc, char* argv[]) {
    std::string config_name = "held_suarez";
    if (argc > 1) config_name = argv[1];
    
    std::string data_dir = "../../../../tests/fortran_baseline/hs_forcing_module/";
    
    // 1. Read configuration
    hs_forcing::Config config = read_config(data_dir + "config_" + config_name + ".txt");
    
    // 2. Read input arrays
    auto lon = read_binary(data_dir + "input_lon.bin", nlon * nlat);
    auto lat = read_binary(data_dir + "input_lat.bin", nlon * nlat);
    // ... etc.
    
    // 3. Allocate output arrays
    std::vector<double> udt(nlon * nlat * nlev, 0.0);
    std::vector<double> vdt(nlon * nlat * nlev, 0.0);
    std::vector<double> tdt(nlon * nlat * nlev, 0.0);
    std::vector<double> teq(nlon * nlat * nlev, 0.0);
    
    // 4. Call C++ driver
    hs_forcing::ForcingOutput output{
        udt.data(), vdt.data(), tdt.data(), teq.data(),
        nullptr, nullptr  // h_trop, tg_new (for HS mode)
    };
    
    hs_forcing::forcing_driver(
        nlon, nlat, nlev,
        current_time, dt,
        lon.data(), lat.data(),
        ps.data(), p_full.data(), nullptr,
        u.data(), v.data(), t.data(),
        nullptr, nullptr,  // um, vm
        nullptr, nullptr,  // zfull, tg_prev
        config,
        output,
        nullptr  // mask
    );
    
    // 5. Read reference outputs
    auto udt_ref = read_binary(data_dir + "output_" + config_name + "_udt.bin", nlon * nlat * nlev);
    auto vdt_ref = read_binary(data_dir + "output_" + config_name + "_vdt.bin", nlon * nlat * nlev);
    auto tdt_ref = read_binary(data_dir + "output_" + config_name + "_tdt.bin", nlon * nlat * nlev);
    auto teq_ref = read_binary(data_dir + "output_" + config_name + "_teq.bin", nlon * nlat * nlev);
    
    // 6. Compare
    auto udt_cmp = compare_arrays(udt, udt_ref);
    auto vdt_cmp = compare_arrays(vdt, vdt_ref);
    auto tdt_cmp = compare_arrays(tdt, tdt_ref);
    auto teq_cmp = compare_arrays(teq, teq_ref);
    
    // 7. Report
    std::cout << "Configuration: " << config_name << std::endl;
    std::cout << "udt: " << (udt_cmp.passed ? "PASS" : "FAIL") << std::endl;
    std::cout << "vdt: " << (vdt_cmp.passed ? "PASS" : "FAIL") << std::endl;
    std::cout << "tdt: " << (tdt_cmp.passed ? "PASS" : "FAIL") << std::endl;
    std::cout << "teq: " << (teq_cmp.passed ? "PASS" : "FAIL") << std::endl;
    
    bool all_passed = udt_cmp.passed && vdt_cmp.passed && tdt_cmp.passed && teq_cmp.passed;
    return all_passed ? 0 : 1;
}
```

---

## 17. Hybrid Integration Test Strategy

### 17.1 Integration Levels

| Level | Description | Purpose |
|-------|-------------|---------|
| L1 | C++ standalone | Verify C++ correctness |
| L2 | C API wrapper | Verify C interop |
| L3 | Fortran calling C | Verify iso_c_binding |
| L4 | Mixed computation | Verify hybrid workflow |

### 17.2 L2: C API Test

```c
// test_c_api.c
#include "hs_forcing_c_api.h"
#include <stdio.h>
#include <stdlib.h>

int main() {
    int nlon = 8, nlat = 6, nlev = 5;
    
    // Allocate arrays
    double* lon = malloc(nlon * nlat * sizeof(double));
    double* lat = malloc(nlon * nlat * sizeof(double));
    // ... initialize ...
    
    double* udt = calloc(nlon * nlat * nlev, sizeof(double));
    double* vdt = calloc(nlon * nlat * nlev, sizeof(double));
    double* tdt = calloc(nlon * nlat * nlev, sizeof(double));
    double* teq = malloc(nlon * nlat * nlev * sizeof(double));
    
    int result = hs_forcing_driver_c(
        nlon, nlat, nlev,
        7776000, 1200.0,  // current_time, dt
        lon, lat,
        ps, p_full, NULL,
        u, v, t,
        NULL, NULL,  // um, vm
        NULL, NULL,  // zfull, tg_prev
        // Config params...
        315.0, 200.0, 60.0, 10.0, 0.0,
        1.0e5, 2.0/7.0,
        2.893518e-7, 2.893518e-6, 1.157407e-5, 0.7,
        365.25, 0.0167, 23.44, 0.25,
        1.496e11, 1360.0, 5.67e-8, 0.3,
        6.5, 2.0, 5.0, 4.2e6, 1.0,
        1,  // do_conserve_energy
        HS_EQUILIBRIUM_HELD_SUAREZ,
        HS_STRATOSPHERE_HS_LIKE,
        udt, vdt, tdt, teq,
        NULL, NULL,  // h_trop, tg_new
        NULL  // mask
    );
    
    printf("Result: %s\n", result == HS_SUCCESS ? "SUCCESS" : "FAILURE");
    
    // Cleanup
    free(lon); free(lat); /* ... */
    
    return result;
}
```

### 17.3 L3: Fortran Calling C++ Test

```fortran
! test_fortran_c_interop.F90
program test_fortran_c_interop
  use iso_c_binding
  use hs_forcing_c_interface
  implicit none

  integer, parameter :: nlon = 8, nlat = 6, nlev = 5
  real(8), target :: lon(nlon,nlat), lat(nlon,nlat)
  real(8), target :: ps(nlon,nlat), p_full(nlon,nlat,nlev)
  real(8), target :: u(nlon,nlat,nlev), v(nlon,nlat,nlev), t(nlon,nlat,nlev)
  real(8), target :: udt(nlon,nlat,nlev), vdt(nlon,nlat,nlev)
  real(8), target :: tdt(nlon,nlat,nlev), teq(nlon,nlat,nlev)

  integer :: i, j, k, current_time
  real(8) :: dt

  ! Initialize test data (same as standalone Fortran baseline)
  call initialize_test_data(lon, lat, ps, p_full, u, v, t)

  current_time = 7776000  ! 90 days
  dt = 1200.0d0

  ! Zero tendency arrays (they are accumulated)
  udt = 0.0d0
  vdt = 0.0d0
  tdt = 0.0d0

  ! Call C++ implementation via wrapper
  call hs_forcing_cpp(nlon, nlat, nlev, current_time, dt, &
                      lon, lat, ps, p_full, u, v, t, &
                      udt, vdt, tdt, teq)

  ! Compare against reference (loaded from file)
  call compare_and_report(udt, vdt, tdt, teq)

end program test_fortran_c_interop
```

### 17.4 L4: Mixed Computation Test

```fortran
! test_hybrid_workflow.F90
!
! This test verifies that:
! 1. Fortran can call C++ for forcing computation
! 2. Results match pure Fortran implementation
! 3. State can be passed back and forth correctly
!
program test_hybrid_workflow
  use hs_forcing_mod         ! Original Fortran module
  use hs_forcing_c_interface ! C++ interface
  implicit none

  ! Run both Fortran and C++ implementations
  ! Compare results
  ! Report differences

  ! Step 1: Run original Fortran
  call hs_forcing_init(...)
  call hs_forcing(...)
  ! Save results: udt_fortran, vdt_fortran, tdt_fortran

  ! Step 2: Run C++ via interface
  call hs_forcing_cpp(...)
  ! Save results: udt_cpp, vdt_cpp, tdt_cpp

  ! Step 3: Compare
  max_diff_udt = maxval(abs(udt_fortran - udt_cpp))
  max_diff_vdt = maxval(abs(vdt_fortran - vdt_cpp))
  max_diff_tdt = maxval(abs(tdt_fortran - tdt_cpp))

  print *, 'Max diff udt:', max_diff_udt
  print *, 'Max diff vdt:', max_diff_vdt
  print *, 'Max diff tdt:', max_diff_tdt

  if (max_diff_udt < 1e-14 .and. max_diff_vdt < 1e-14 .and. max_diff_tdt < 1e-14) then
    print *, 'HYBRID TEST: PASS'
  else
    print *, 'HYBRID TEST: FAIL'
  endif

end program test_hybrid_workflow
```

### 17.5 Test Matrix

| Test | L1 | L2 | L3 | L4 |
|------|----|----|----|----|
| Held-Suarez basic | ✓ | ✓ | ✓ | ✓ |
| Held-Suarez + energy | ✓ | ✓ | ✓ | ✓ |
| Top-down basic | ✓ | ✓ | ✓ | ✓ |
| Top-down + energy | ✓ | ✓ | ✓ | ✓ |
| With mask | ✓ | ✓ | ✓ | — |
| Polar latitudes | ✓ | — | — | — |
| High resolution | ✓ | — | — | — |

---

## 18. Success Criteria

### 18.1 Functional Requirements

| Requirement | Criterion |
|-------------|-----------|
| F1 | C++ compiles without Fortran dependencies |
| F2 | C++ produces identical output to Fortran baseline |
| F3 | Both Held-Suarez and top-down modes work |
| F4 | Energy conservation option works |
| F5 | Mask handling works |

### 18.2 Accuracy Requirements

| Output | Tolerance |
|--------|-----------|
| `udt` | rel_diff < 1e-14 |
| `vdt` | rel_diff < 1e-14 |
| `tdt` | rel_diff < 1e-14 |
| `teq` | rel_diff < 1e-14 |
| `h_trop` | rel_diff < 1e-14 |
| `tg_new` | rel_diff < 1e-14 |

### 18.3 Interface Requirements

| Requirement | Criterion |
|-------------|-----------|
| I1 | C API compiles with C99 |
| I2 | Fortran interface compiles with gfortran |
| I3 | Fortran can call C++ and get correct results |
| I4 | No memory leaks in hybrid calls |

### 18.4 Documentation Requirements

| Requirement | Criterion |
|-------------|-----------|
| D1 | All public functions documented |
| D2 | Build instructions provided |
| D3 | Test instructions provided |
| D4 | Example usage code provided |

---

## 19. Standalone Test Plan: Synthetic Grid

### 19.1 Test Grid Specification

A small synthetic grid for rapid validation:

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `nlon` | 4 | Minimum to test longitude variation |
| `nlat` | 3 | Minimum to test latitude variation (including equator/poles) |
| `nlev` | 5 | Minimum to test vertical structure (surface to TOA) |

Total array sizes:
- 2D arrays: 12 elements
- 3D arrays: 60 elements

### 19.2 Input Arrays

#### 19.2.1 Coordinate Arrays

```
Latitude (3 bands, replicated across 4 longitudes):
  lat[i,j] = lat_values[j]  for all i ∈ [0, nlon)

  j=0: -45° (-π/4)  — Southern midlatitude
  j=1:   0° (0)     — Equator
  j=2: +45° (+π/4)  — Northern midlatitude

Longitude (4 points):
  lon[i,j] = i * 2π/4  for all j ∈ [0, nlat)

  i=0: 0°    (0)
  i=1: 90°   (π/2)
  i=2: 180°  (π)
  i=3: 270°  (3π/2)
```

#### 19.2.2 Pressure Arrays

```
Surface pressure (uniform):
  ps[i,j] = 1.0e5 Pa  for all i,j

Pressure at full levels (typical sigma values):
  sigma_levels = [0.1, 0.3, 0.5, 0.7, 0.9]  (TOA to surface)
  p_full[i,j,k] = ps[i,j] * sigma_levels[k]

  k=0: 10000 Pa  (100 hPa, ~16 km)
  k=1: 30000 Pa  (300 hPa, ~9 km)
  k=2: 50000 Pa  (500 hPa, ~5.5 km)
  k=3: 70000 Pa  (700 hPa, ~3 km)
  k=4: 90000 Pa  (900 hPa, ~1 km)

Pressure at half levels (for energy conservation):
  sigma_half = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
  p_half[i,j,k] = ps[i,j] * sigma_half[k]
```

#### 19.2.3 Temperature Array

```
Realistic atmospheric temperature profile:
  T_surface = 288 K (equator) to 250 K (poles)
  Lapse rate ≈ 6.5 K/km in troposphere

  For synthetic test:
    t[i,j,k] = T0(lat[j]) - 6.5 * z_approx[k]

  Where:
    T0(lat) = 288 - 30*sin²(lat)  — surface temp by latitude
    z_approx[k] = 16*(1 - sigma[k])  — approximate height in km

  Resulting temperatures (K):
    Level k=0 (σ=0.1): 200–220 K (stratosphere)
    Level k=1 (σ=0.3): 220–240 K (upper troposphere)
    Level k=2 (σ=0.5): 240–260 K (mid troposphere)
    Level k=3 (σ=0.7): 260–280 K (lower troposphere)
    Level k=4 (σ=0.9): 275–295 K (boundary layer)
```

#### 19.2.4 Wind Arrays

```
Zonal wind (jet structure):
  u[i,j,k] = u_max * cos²(lat) * f(sigma)

  Where:
    u_max = 30 m/s (peak jet speed)
    f(sigma) = 4*sigma*(1-sigma)  — parabolic profile, max at σ=0.5

  Resulting u (m/s):
    k=0: 5.4   at equator, 2.7  at ±45°
    k=1: 12.6  at equator, 6.3  at ±45°
    k=2: 15.0  at equator, 7.5  at ±45° (jet core)
    k=3: 12.6  at equator, 6.3  at ±45°
    k=4: 5.4   at equator, 2.7  at ±45°

Meridional wind (weak):
  v[i,j,k] = 2.0 * sin(2*lat) * f(sigma)

  Resulting v (m/s): ±1.4 at k=2, weaker elsewhere
```

#### 19.2.5 Height Array (Top-Down Mode)

```
Geopotential height (hydrostatic):
  z[i,j,k] = -H * ln(sigma[k])

  Where H = 8 km (scale height)

  Resulting heights (m):
    k=0 (σ=0.1): 18420 m
    k=1 (σ=0.3):  9630 m
    k=2 (σ=0.5):  5540 m
    k=3 (σ=0.7):  2850 m
    k=4 (σ=0.9):   840 m
```

#### 19.2.6 Ground Temperature (Top-Down Mode)

```
Previous ground temperature (for heat capacity):
  tg_prev[i,j] = T0(lat[j])  — same as surface T profile

  tg_prev = [273, 288, 273, 273, 288, 273, 273, 288, 273, 273, 288, 273] K
            (replicated for each longitude)
```

### 19.3 Configuration Parameters

#### 19.3.1 Standard Held-Suarez Configuration

```cpp
// Equilibrium temperature
double t_zero = 315.0;      // K
double t_strat = 200.0;     // K
double delh = 60.0;         // K
double delv = 10.0;         // K
double eps = 0.0;           // K (no hemispheric asymmetry)
double P00 = 1.0e5;         // Pa
double kappa = 2.0/7.0;     // R/cp

// Damping timescales (already converted to 1/s)
double tka = 2.893519e-7;   // 1/(40 days in seconds)
double tks = 2.893519e-6;   // 1/(4 days in seconds)
double vkf = 1.157407e-5;   // 1/(1 day in seconds)
double sigma_b = 0.7;       // Boundary layer top

// Control
int do_conserve_energy = 0; // Disabled for baseline comparison
int equilibrium_option = 0; // HS_EQUILIBRIUM_HELD_SUAREZ
```

#### 19.3.2 Top-Down Configuration

```cpp
// All HS parameters plus:
int current_time = 7776000; // 90 days in seconds
double dt = 1200.0;         // 20 minutes timestep

// Orbital
double orbital_period = 365.25;  // days
double ecc = 0.0167;
double obliq = 23.44;           // degrees
double peri_time = 0.25;
double smaxis = 1.496e11;       // m

// Radiative
double solar_const = 1360.0;    // W/m²
double stefan = 5.670374419e-8; // W/(m²K⁴)
double albedo = 0.3;

// Tropopause/heat capacity
double lapse = 6.5;             // K/km
double h_a = 2.0;
double tau_s = 5.0;
double heat_capacity = 4.2e6;   // J/(m³K)
double ml_depth = 1.0;          // m

int stratosphere_option = 2;    // HS_STRATOSPHERE_HS_LIKE
```

### 19.4 Expected Outputs

#### 19.4.1 Temperature Tendency (tdt)

```
For standard HS:
  tdt[i,j,k] = -k_T(lat,sigma) * (t[i,j,k] - teq[i,j,k])

  Expected order of magnitude:
    Troposphere: |tdt| ~ 1e-5 to 1e-4 K/s
    Stratosphere: |tdt| ~ 1e-6 to 1e-5 K/s

  Key features:
    - Negative tdt where t > teq (cooling)
    - Positive tdt where t < teq (heating)
    - Stronger damping near surface (larger |k_T|)
    - Latitude dependence via cos⁴(lat) term
```

#### 19.4.2 Wind Tendencies (udt, vdt)

```
For Rayleigh damping:
  udt[i,j,k] = -k_v(sigma) * u[i,j,k]
  vdt[i,j,k] = -k_v(sigma) * v[i,j,k]

  Where k_v(σ) = vkf * max(0, (σ - σ_b)/(1 - σ_b))

  Expected features:
    - Zero for σ < σ_b (k=0,1,2,3)
    - Non-zero only at k=4 (σ=0.9 > σ_b=0.7)
    - At k=4: k_v = 1.157e-5 * (0.9-0.7)/(1-0.7) = 7.7e-6 s⁻¹
    - udt magnitude ~ -7.7e-6 * u ~ -4e-5 m/s² at equator
```

#### 19.4.3 Equilibrium Temperature (teq)

```
For standard HS:
  teq[i,j,k] = max(tstr, the * (p/P00)^κ)

  Where:
    t_star = t_zero - delh*sin²(lat) - eps*sin(lat)
    the = t_star - delv*cos²(lat)*ln(p/P00)
    tstr = t_strat - eps*sin(lat)

  Expected teq profile (at equator, lat=0):
    k=0: 200 K (capped at t_strat)
    k=1: ~215 K
    k=2: ~250 K
    k=3: ~280 K
    k=4: ~305 K
```

#### 19.4.4 Top-Down Specific Outputs

```
Tropopause height (h_trop):
  h_trop[i,j] ~ 10-16 km depending on latitude and time of year

Ground temperature (tg_new):
  tg_new[i,j] = tg_prev + adjustment from heat capacity
  Change ~ 0.01-0.1 K per timestep
```

### 19.5 Test File Format

#### 19.5.1 Binary Format (Fortran-compatible)

All arrays written as raw binary, double precision (8 bytes per value), in column-major order:

```
File: params.bin
  int32: nlon, nlat, nlev (3 * 4 bytes)
  int32: current_time (4 bytes)
  double: dt, config values...

File: input_lat.bin
  double[nlon*nlat]: latitude array (96 bytes)

File: input_ps.bin
  double[nlon*nlat]: surface pressure (96 bytes)

File: input_p_full.bin
  double[nlon*nlat*nlev]: pressure at full levels (480 bytes)

... etc.
```

#### 19.5.2 Reference Outputs

```
File: output_tdt.bin
  double[nlon*nlat*nlev]: temperature tendency (480 bytes)

File: output_teq.bin
  double[nlon*nlat*nlev]: equilibrium temperature (480 bytes)

File: output_udt.bin
  double[nlon*nlat*nlev]: zonal wind tendency (480 bytes)

File: output_vdt.bin
  double[nlon*nlat*nlev]: meridional wind tendency (480 bytes)
```

### 19.6 Validation Criteria

| Output | Absolute Tolerance | Relative Tolerance | Notes |
|--------|-------------------|--------------------|-------|
| `tdt` | 1e-20 K/s | 1e-14 | Temperature tendency |
| `teq` | 1e-20 K | 1e-14 | Equilibrium temperature |
| `udt` | 1e-20 m/s² | 1e-14 | Wind tendency |
| `vdt` | 1e-20 m/s² | 1e-14 | Wind tendency |
| `h_trop` | 1e-20 km | 1e-14 | Tropopause height (top-down) |
| `tg_new` | 1e-20 K | 1e-14 | Ground temperature (top-down) |

### 19.7 Intermediate Debugging Arrays

For debugging, the following intermediate values can be output:

| Array | Dimensions | Description |
|-------|------------|-------------|
| `sigma` | (nlon, nlat, nlev) | σ = p_full / ps |
| `sin_lat_2` | (nlon, nlat) | sin²(lat) |
| `cos_lat_4` | (nlon, nlat) | cos⁴(lat) |
| `t_star` | (nlon, nlat) | T* = T₀ - Δθ_h sin²φ |
| `k_v` | (nlon, nlat, nlev) | Rayleigh damping coefficient |
| `k_T` | (nlon, nlat, nlev) | Newtonian damping coefficient |
| `t_radbal` | (nlon, nlat) | Radiative balance temperature (top-down) |
| `t_trop` | (nlon, nlat) | Tropopause temperature (top-down) |
| `hour_angle` | (nlon, nlat) | Solar hour angle (top-down) |
| `dec` | scalar | Solar declination (top-down) |

### 19.8 Test Execution Workflow

```
1. Generate Fortran baseline:
   $ cd tests/fortran_baseline/synthetic_grid
   $ make
   $ ./generate_baseline

2. Build C++ test:
   $ cd translated/held_suarez/cpp/forcing_module
   $ make test

3. Run C++ test:
   $ ./driver_forcing_module ../../../tests/fortran_baseline/synthetic_grid/

4. Compare outputs:
   - tdt: PASS if rel_diff < 1e-14
   - teq: PASS if rel_diff < 1e-14
   - udt: PASS if rel_diff < 1e-14
   - vdt: PASS if rel_diff < 1e-14
   - (top-down) h_trop: PASS if rel_diff < 1e-14
   - (top-down) tg_new: PASS if rel_diff < 1e-14
```

---

## Appendix A: Fortran-to-C++ Type Mapping

| Fortran | C++ | Notes |
|---------|-----|-------|
| `real` (with `-fdefault-real-8`) | `double` | 64-bit |
| `integer` | `int` | 32-bit |
| `logical` | `bool` | |
| `character(len=*)` | `std::string` or `const char*` | |
| `real, dimension(:,:)` | `double*` + dims | Column-major |
| `real, dimension(:,:,:)` | `double*` + dims | Column-major |
| `type(time_type)` | `int` (seconds) | Simplified |
| `intent(in)` | `const` | |
| `intent(out)` | non-const | |
| `intent(inout)` | non-const | |
| `optional` | `nullptr` check | |
| `where` | `if`/ternary | Per-element |

---

## Appendix B: Glossary

| Term | Definition |
|------|------------|
| **Held-Suarez** | 1994 benchmark for idealized atmospheric GCM testing |
| **Newtonian damping** | Linear relaxation of temperature toward equilibrium |
| **Rayleigh damping** | Linear friction applied to wind components |
| **σ (sigma)** | Pressure-based vertical coordinate: p/p_surface |
| **T_eq** | Equilibrium temperature profile |
| **κ (kappa)** | R/c_p ≈ 2/7 for dry air |
| **Tropopause** | Boundary between troposphere and stratosphere |
| **iso_c_binding** | Fortran standard for C interoperability |
