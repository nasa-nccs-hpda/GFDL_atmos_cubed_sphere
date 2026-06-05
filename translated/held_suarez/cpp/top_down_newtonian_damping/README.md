# top_down_newtonian_damping C++ Translation

C++ translation of the `top_down_newtonian_damping` routine from `hs_forcing_mod`.

## Source

- **Original**: `src/atmos_param/hs_forcing/hs_forcing.F90` lines 894-1026
- **LOC**: 133

## Purpose

Temperature relaxation with tropopause-aware vertical structure. This is an alternative to the standard Held-Suarez `newtonian_damping` that:

1. Computes tropopause height from radiative balance
2. Applies heat capacity to evolve ground temperature
3. Builds equilibrium temperature profile relative to the tropopause
4. Supports multiple stratosphere temperature options

## Algorithm Overview

1. **Orbital calculations**: Compute solar declination from time
2. **Hour angle**: Compute solar hour angle at each grid point
3. **Radiative balance**: Compute surface insolation and T_radbal
4. **Tropopause height**: Derive h_trop from radiative balance
5. **Surface temperature**: Apply heat capacity to evolve ground temperature
6. **Equilibrium profile**: Build T_eq profile with stratosphere options
7. **Damping**: Compute latitude-dependent relaxation coefficient
8. **Temperature tendency**: Apply Newtonian relaxation

## Embedded Dependencies

This kernel includes internal implementations of:
- `calc_ecc_anomaly` — Newton-Raphson solver for Kepler's equation
- `update_orbit` — Compute solar declination from time
- `calc_hour_angle` — Compute hour angle from latitude/declination

## Stateless Design

The original Fortran uses module state `tg_prev` to persist ground temperature between calls. The C++ translation is stateless:
- Input: `tg_prev` (previous ground temperature)
- Output: `tg_new` (updated ground temperature)
- Caller is responsible for storing `tg_new` for the next timestep

## Files

- `top_down_newtonian_damping.hpp` - Header-only kernel implementation
- `test_driver.cpp` - Validation driver
- `Makefile` - Build script

## Building and Testing

```bash
# Build
make

# Run test (reads data from Fortran baseline)
make run

# Or specify data directory explicitly
./test_top_down_newtonian_damping /path/to/fortran/baseline/
```

## Validation

Compares C++ output against Fortran baseline with:
- Relative tolerance: 1e-14
- Absolute tolerance: 1e-20

Outputs validated:
- `tdt` — temperature tendency (K/s)
- `teq` — equilibrium temperature (K)
- `h_trop` — tropopause height (km)
- `tg_new` — new ground temperature (K)

## Parameters

The `TopDownParams` struct contains all physical parameters:

| Parameter | Description |
|-----------|-------------|
| `solar_const` | Solar constant (W/m²) |
| `stefan` | Stefan-Boltzmann constant (W/m²/K⁴) |
| `orbital_period` | Orbital period (days) |
| `ecc` | Orbital eccentricity |
| `obliq` | Obliquity (degrees) |
| `albedo` | Surface albedo |
| `lapse` | Lapse rate (K/km) |
| `heat_capacity` | Heat capacity (J/m³/K) |
| `ml_depth` | Mixed layer depth (m) |
| `t_strat` | Stratospheric temperature (K) |
| `sigma_b` | Boundary layer top |
| `tka`, `tks` | Relaxation coefficients (1/s) |
| `strat_option` | Stratosphere option (0-3) |

## Stratosphere Options

- `STRAT_DEFAULT (0)` — Cap teq at 0 K (effectively no cap)
- `STRAT_C_ABOVE_TP (1)` — Constant stratosphere temperature above tropopause
- `STRAT_HS_LIKE (2)` — HS-like max(teq, tstr)
- `STRAT_EXTEND_TP (3)` — Extend tropopause temperature into stratosphere
