# calc_hour_angle C++ Translation

C++ translation of the `calc_hour_angle` routine from `hs_forcing_mod`.

## Source

- **Original**: `src/atmos_param/hs_forcing/hs_forcing.F90` lines 842-860
- **LOC**: 19

## Purpose

Compute solar hour angle from latitude and solar declination. The hour angle determines the length of daylight at each grid point.

## Algorithm

```
cos(H) = -tan(φ) * tan(δ)
```

Where:
- H = hour angle (radians, 0 to π)
- φ = latitude (radians)
- δ = solar declination (radians)

The argument to acos is clamped to [-1, 1]:
- If -tan(φ)*tan(δ) > 1: Polar night (H = 0)
- If -tan(φ)*tan(δ) < -1: Polar day (H = π)

## Files

- `calc_hour_angle.hpp` - Header-only kernel implementation
- `test_driver.cpp` - Validation driver
- `Makefile` - Build script

## Building and Testing

```bash
# Build
make

# Run test (reads data from Fortran baseline)
make run

# Or specify data directory explicitly
./test_calc_hour_angle /path/to/fortran/baseline/
```

## Validation

Compares C++ output against Fortran baseline with:
- Relative tolerance: 1e-14
- Absolute tolerance: 1e-20

Expected result: Exact match (zero difference).
