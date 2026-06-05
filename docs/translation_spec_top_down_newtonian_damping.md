# Translation Specification: top_down_newtonian_damping

## Overview

| Attribute | Value |
|-----------|-------|
| **Source File** | `src/atmos_param/hs_forcing/hs_forcing.F90` |
| **Lines** | 894–1026 |
| **LOC** | 133 |
| **Purpose** | Temperature relaxation with tropopause-aware vertical structure |
| **Dependencies** | `update_orbit`, `calc_hour_angle`, module constants |
| **GPU Suitability** | ★★★☆☆ (3/5) |

## Algorithm Description

This routine computes thermal forcing using a "top-down" approach where the tropopause height is computed from radiative balance, and temperature is relaxed to an equilibrium profile defined relative to this tropopause.

### Key Steps

1. **Orbital Calculations**: Compute solar declination and orbital distance from time
2. **Hour Angle**: Compute solar hour angle for each grid point
3. **Radiative Balance**: Compute surface insolation and radiative balance temperature
4. **Tropopause Height**: Derive tropopause height from radiative balance
5. **Surface Temperature**: Apply heat capacity to compute surface/ground temperature
6. **Equilibrium Temperature**: Build vertical Teq profile with stratosphere options
7. **Damping Coefficient**: Compute latitude-dependent relaxation timescale
8. **Temperature Tendency**: Apply Newtonian relaxation

### Physical Formulas

**Solar Insolation:**
```
S = (solar_const/π) * (H*sin(lat)*sin(dec) + cos(lat)*cos(dec)*sin(H))
```
where H = hour_angle

**Radiative Balance Temperature:**
```
T_radbal = ((1-albedo)*S/σ)^0.25
```

**Tropopause Height:**
```
T_trop = T_radbal / 2^0.25
h_trop = (1/(16*Γ)) * (1.3863*T_trop + sqrt((1.3863*T_trop)^2 + 32*Γ*τ_s*h_a*T_trop))
```

**Surface Temperature Evolution (with heat capacity):**
```
T_surf = T_trop + h_trop * Γ
T_g = σ*dt/(ml*C_p) * (T_surf^4 - T_g_prev^4) + T_g_prev
```

**Equilibrium Temperature Profile:**
```
T_eq(k) = T_trop + Γ * (h_trop - z(k)/1000)
```
with stratosphere options: `c_above_tp`, `hs_like`, `extend_tp`

**Damping Coefficient:**
```
k_T = k_a + cos^4(lat) * (k_s - k_a)/(1 - σ_b) * max(0, σ - σ_b)
```

**Temperature Tendency:**
```
dT/dt = -k_T * (T - T_eq)
```

## Dependencies

### Internal Calls
- `update_orbit(current_time, dec, orb_dist)` — compute solar declination
- `calc_hour_angle(lat, dec, hour_angle)` — compute hour angle array

### Module Constants (from namelist/initialization)
| Constant | Default | Description |
|----------|---------|-------------|
| `t_strat` | 200 K | Stratospheric temperature |
| `eps` | 0 | Stratospheric temperature latitude variation |
| `sigma_b` | 0.7 | Boundary layer top |
| `tka` | -40 days → 1/s | Atmospheric relaxation coefficient |
| `tks` | -4 days → 1/s | Surface relaxation coefficient |
| `P00` | 1e5 Pa | Reference pressure |
| `solar_const` | from constants_mod | Solar constant |
| `stefan` | from constants_mod | Stefan-Boltzmann constant |
| `albedo` | 0.3 | Surface albedo |
| `lapse` | 6.5 K/km | Lapse rate |
| `h_a` | 2 | Scale height parameter |
| `tau_s` | 5 | Optical depth parameter |
| `heat_capacity` | 4.2e6 J/m³/K | Heat capacity |
| `ml_depth` | 1 m | Mixed layer depth |
| `orbital_period` | from constants_mod | Orbital period (days) |
| `ecc` | from astronomy_mod | Orbital eccentricity |
| `obliq` | from astronomy_mod | Obliquity (degrees) |
| `peri_time` | 0.25 | Perihelion time fraction |
| `smaxis` | 1.5e6 | Semi-major axis |

### Module State
- `tg_prev(nlon, nlat)` — previous ground temperature (persists between calls)

## Fortran Source Code (simplified)

```fortran
subroutine top_down_newtonian_damping(Time, lat, ps, p_full, p_half, t, tdt, teq, dt, h_trop, zfull, mask)

  ! 1. Get time in seconds
  call get_time(Time, seconds, days)
  dt_integer = 86400*days + seconds

  ! 2. Latitudinal constants
  sin_lat = sin(lat)
  cos_lat = cos(lat)
  sin_lat_2 = sin_lat*sin_lat
  cos_lat_2 = 1.0 - sin_lat_2
  cos_lat_4 = cos_lat_2*cos_lat_2

  ! 3. Orbital calculations
  call update_orbit(dt_integer, dec, orb_dist)
  call calc_hour_angle(lat, dec, hour_angle)

  ! 4. Solar insolation
  s = solar_const/pi * (hour_angle*sin_lat*sin(dec) + cos_lat*cos(dec)*sin(hour_angle))

  ! 5. Radiative balance temperature
  t_radbal = ((1-albedo)*s/stefan)**0.25

  ! 6. Tropopause height
  t_trop = t_radbal / 2**0.25
  h_trop = 1/(16*lapse) * (1.3863*t_trop + sqrt((1.3863*t_trop)**2 + 32*lapse*tau_s*h_a*t_trop))

  ! 7. Surface temperature with heat capacity
  t_surf = t_trop + h_trop*lapse
  tg = stefan*dt/(ml_depth*heat_capacity)*(t_surf**4 - tg_prev**4) + tg_prev
  tg_prev = tg
  t_trop = tg - h_trop*lapse

  ! 8. Stratosphere temperature
  tstr = t_strat - eps*sin_lat

  ! 9. Damping coefficient setup
  tcoeff = (tks-tka)/(1.0-sigma_b)
  rps = 1./ps

  ! 10. Vertical loop
  do k = 1, nlev
    ! Equilibrium temperature
    teq(:,:,k) = t_trop + lapse*(h_trop - zfull(:,:,k)/1000)
    ! Apply stratosphere option
    if (stratosphere_t_option == 'hs_like') then
      teq(:,:,k) = max(teq(:,:,k), tstr)
    endif
    ! Damping coefficient
    sigma = p_full(:,:,k)*rps
    where (sigma <= 1.0 .and. sigma > sigma_b)
      tfactr = tcoeff*(sigma-sigma_b)
      tdamp(:,:,k) = tka + cos_lat_4*tfactr
    elsewhere
      tdamp(:,:,k) = tka
    endwhere
  enddo

  ! 11. Temperature tendency
  do k = 1, nlev
    tdt(:,:,k) = -tdamp(:,:,k)*(t(:,:,k) - teq(:,:,k))
  enddo

  ! 12. Apply mask if present
  if (present(mask)) then
    tdt = tdt * mask
    teq = teq * mask
  endif

end subroutine
```

## C++ Translation Strategy

### Stateless Design

The module state `tg_prev` must be passed explicitly to the C++ kernel:
- Input: `tg_prev` (previous ground temperature)
- Output: `tg_new` (updated ground temperature, caller stores for next call)

### Signature

```cpp
namespace hs_forcing {

struct TopDownParams {
    // Physical constants
    double solar_const;
    double stefan;
    double pi;
    
    // Orbital parameters
    double orbital_period;  // days
    double ecc;             // eccentricity
    double obliq;           // obliquity (degrees)
    double peri_time;       // perihelion time fraction
    double smaxis;          // semi-major axis
    
    // Thermal parameters
    double albedo;
    double lapse;           // K/km
    double h_a;
    double tau_s;
    double heat_capacity;
    double ml_depth;
    
    // Held-Suarez parameters
    double t_strat;
    double eps;
    double sigma_b;
    double tka;             // 1/s
    double tks;             // 1/s
    double P00;
    
    // Stratosphere option: 0=default, 1=c_above_tp, 2=hs_like, 3=extend_tp
    int stratosphere_t_option;
};

void top_down_newtonian_damping(
    int nlon, int nlat, int nlev,
    int current_time,           // seconds since epoch
    double dt,                  // timestep (seconds)
    const double* lat,          // [nlon, nlat]
    const double* ps,           // [nlon, nlat]
    const double* p_full,       // [nlon, nlat, nlev]
    const double* zfull,        // [nlon, nlat, nlev] heights in meters
    const double* t,            // [nlon, nlat, nlev]
    const double* tg_prev,      // [nlon, nlat] previous ground temp
    const TopDownParams& params,
    double* tdt,                // [nlon, nlat, nlev] output tendency
    double* teq,                // [nlon, nlat, nlev] output equilibrium temp
    double* h_trop,             // [nlon, nlat] output tropopause height
    double* tg_new,             // [nlon, nlat] output new ground temp
    const double* mask = nullptr
);

}
```

### Internal Helper Functions

The C++ implementation will include:
- `update_orbit()` — already translated as `calc_ecc_anomaly` dependency
- `calc_hour_angle()` — already translated

## Test Strategy

### Test Grid

- `nlon = 8`: longitude points
- `nlat = 6`: latitude points (-80° to +80°)
- `nlev = 5`: vertical levels

### Test Parameters

Use default Held-Suarez-like parameters:
- `solar_const = 1360 W/m²`
- `stefan = 5.67e-8 W/m²/K⁴`
- `albedo = 0.3`
- `lapse = 6.5 K/km`
- `stratosphere_t_option = 'hs_like'`

### Test Cases

1. **Summer solstice**: `current_time` corresponding to summer
2. **Varying latitudes**: Polar to equatorial
3. **Multiple vertical levels**: Troposphere to stratosphere

### Validation Criteria

- **Relative tolerance**: 1e-14
- **Absolute tolerance**: 1e-20
- **Goal**: Bit-reproducible where possible; small tolerance for accumulated operations

## File Locations

### Fortran Baseline
```
tests/fortran_baseline/top_down_newtonian_damping/
├── top_down_newtonian_damping_standalone.F90
├── test_harness.F90
├── Makefile
├── input_*.bin
└── output_*.bin
```

### C++ Translation
```
translated/held_suarez/cpp/top_down_newtonian_damping/
├── top_down_newtonian_damping.hpp
├── test_driver.cpp
├── Makefile
└── README.md
```

## Notes

- Most complex routine in the translation sequence
- Demonstrates stateful → stateless conversion pattern
- Integrates previously translated `calc_ecc_anomaly` and `calc_hour_angle`
- Multiple stratosphere options require branching logic
