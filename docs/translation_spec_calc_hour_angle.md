# Translation Specification: calc_hour_angle

## Overview

| Attribute | Value |
|-----------|-------|
| **Source File** | `src/atmos_param/hs_forcing/hs_forcing.F90` |
| **Lines** | 842–860 |
| **LOC** | 19 |
| **Purpose** | Compute solar hour angle from latitude and solar declination |
| **Dependencies** | None (pure intrinsics: `tan`, `acos`) |
| **GPU Suitability** | ★★★★★ (5/5) |

## Algorithm Description

The hour angle determines the length of daylight at each grid point. It is computed from the latitude and solar declination using the relationship:

```
cos(H) = -tan(φ) * tan(δ)
```

Where:
- H = hour angle (radians, 0 to π)
- φ = latitude (radians)
- δ = solar declination (radians)

The hour angle represents the half-length of the day: `day_length = 2 * H / ω` where ω is Earth's angular velocity.

### Boundary Cases

The argument to `acos` must be clamped to [-1, 1]:
- If `-tan(φ)*tan(δ) > 1`: Polar night (H = 0)
- If `-tan(φ)*tan(δ) < -1`: Polar day (H = π)

## Fortran Source Code

```fortran
subroutine calc_hour_angle(lat, dec, hour_angle)

real, intent(in)                  :: dec
real, intent(in), dimension(:,:)  :: lat
real, intent(out), dimension(:,:) :: hour_angle

real, dimension(size(lat,1), size(lat,2)) :: inv_hour_angle

inv_hour_angle = -tan(lat(:,:))*tan(dec)
where (inv_hour_angle > 1)
    inv_hour_angle = 1
endwhere
where (inv_hour_angle < -1)
    inv_hour_angle = -1
endwhere

hour_angle = acos(inv_hour_angle)

end subroutine calc_hour_angle
```

## C++ Translation

### Signature

```cpp
namespace hs_forcing {

void calc_hour_angle(
    int nlon,
    int nlat,
    const double* lat,       // [nlon, nlat] - latitude (radians)
    double dec,              // solar declination (radians)
    double* hour_angle       // [nlon, nlat] - output hour angle (radians)
);

}
```

### Algorithm Mapping

| Fortran | C++ |
|---------|-----|
| `real, dimension(:,:) :: lat` | `const double* lat` with explicit dimensions |
| `tan(lat(:,:))` | `std::tan(lat[idx])` in loop |
| `where (x > 1) x = 1` | `std::min(x, 1.0)` or if-clamp |
| `where (x < -1) x = -1` | `std::max(x, -1.0)` or if-clamp |
| `acos(inv_hour_angle)` | `std::acos(clamped)` |

### Array Layout

Fortran column-major order preserved for validation:
```cpp
int idx = i + nlon * j;  // (i,j) indexing
```

## Test Strategy

### Test Grid

- `nlon = 8`: longitude points
- `nlat = 6`: latitude points spanning -90° to +90°

### Test Cases

1. **Standard case**: `dec = 23.5° * π/180` (summer solstice)
   - Varying hour angles across latitudes
   - Mid-latitudes should have intermediate values

2. **Polar night boundary**: High latitude + winter declination
   - Should produce `hour_angle = 0` (clamped from `cos > 1`)

3. **Polar day boundary**: High latitude + summer declination
   - Should produce `hour_angle = π` (clamped from `cos < -1`)

4. **Equator**: `lat = 0`
   - `hour_angle = π/2` regardless of declination

5. **Zero declination**: `dec = 0` (equinox)
   - `hour_angle = π/2` everywhere

### Validation Criteria

- **Relative tolerance**: 1e-14
- **Absolute tolerance**: 1e-20
- **Goal**: Bit-reproducible (zero difference)

## File Locations

### Fortran Baseline
```
tests/fortran_baseline/calc_hour_angle/
├── calc_hour_angle_standalone.F90  # Extracted kernel
├── test_harness.F90                # Test driver with synthetic data
├── Makefile
├── input_lat.bin                   # Generated inputs
├── input_dec.bin
└── output_hour_angle.bin           # Reference output
```

### C++ Translation
```
translated/held_suarez/cpp/calc_hour_angle/
├── calc_hour_angle.hpp             # Header-only kernel
├── test_driver.cpp                 # Validation driver
├── Makefile
└── README.md
```

## Notes

- First 2D array kernel in the translation sequence
- Demonstrates `where` construct → conditional/clamp pattern
- No FMS dependencies — fully self-contained
- Direct precursor to `update_orbit` which depends on orbital mechanics
