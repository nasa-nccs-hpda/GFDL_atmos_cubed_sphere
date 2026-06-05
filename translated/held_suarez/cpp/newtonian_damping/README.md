# Newtonian Damping C++ Translation

Direct C++ translation of the `newtonian_damping` subroutine from `hs_forcing_mod`.

## Files

| File | Description |
|------|-------------|
| `newtonian_damping.hpp` | Header-only kernel implementation |
| `test_driver.cpp` | Test driver that validates against Fortran baseline |
| `Makefile` | Build system |

## Prerequisites

1. Generate Fortran baseline data first:
   ```bash
   cd ../../../../tests/fortran_baseline/newtonian_damping
   module load gcc/12.1.0
   make run
   ```

2. Return to this directory and build/run:
   ```bash
   cd ../../../../translated/held_suarez/cpp/newtonian_damping
   make run
   ```

## Translation Notes

### Array Layout

The C++ code uses **Fortran column-major order** for direct comparison:
```cpp
// Index a 2D array as: arr[i + nlon * j]
// Index a 3D array as: arr[i + nlon * (j + nlat * k)]
int idx_2d = i + nlon * j;
int idx_3d = i + nlon * (j + nlat * k);
```

### Algorithm Mapping

| Fortran | C++ |
|---------|-----|
| `sin_lat(:,:) = sin(lat(:,:))` | `sin_lat[idx_2d] = std::sin(lat[idx_2d])` |
| `sin_lat_2(:,:) = sin_lat(:,:)*sin_lat(:,:)` | `sin_lat_2[idx_2d] = sin_lat[idx_2d] * sin_lat[idx_2d]` |
| `cos_lat_2(:,:) = 1.0-sin_lat_2(:,:)` | `cos_lat_2[idx_2d] = 1.0 - sin_lat_2[idx_2d]` |
| `cos_lat_4(:,:) = cos_lat_2(:,:)*cos_lat_2(:,:)` | `cos_lat_4[idx_2d] = cos_lat_2[idx_2d] * cos_lat_2[idx_2d]` |
| `t_star(:,:) = t_zero - delh*sin_lat_2(:,:) - eps*sin_lat(:,:)` | `t_star[idx_2d] = t_zero - delh * sin_lat_2[idx_2d] - eps * sin_lat[idx_2d]` |
| `p_norm(:,:) = p_full(:,:,k)/pref` | `double p_norm = p_full[idx_3d] / P00` |
| `the(:,:) = t_star(:,:) - delv*cos_lat_2(:,:)*log(p_norm(:,:))` | `double the = t_star[idx_2d] - delv * cos_lat_2[idx_2d] * std::log(p_norm)` |
| `teq(:,:,k) = the(:,:)*(p_norm(:,:))**KAPPA` | `double teq_val = the * std::pow(p_norm, KAPPA)` |
| `teq(:,:,k) = max(teq(:,:,k), tstr(:,:))` | `teq[idx_3d] = std::max(teq_val, tstr[idx_2d])` |
| `where (sigma <= 1.0 .and. sigma > sigma_b)` | `if (sigma <= 1.0 && sigma > sigma_b)` |
| `tdt(:,:,k) = -tdamp(:,:,k)*(t(:,:,k)-teq(:,:,k))` | `tdt[idx_3d] = -tdamp[idx_3d] * (t[idx_3d] - teq[idx_3d])` |

### Loop Structure

Fortran uses array operations within a level loop:
```fortran
do k = 1, nlev
  p_norm(:,:) = p_full(:,:,k)/pref
  the(:,:) = t_star(:,:) - delv*cos_lat_2(:,:)*log(p_norm(:,:))
  teq(:,:,k) = the(:,:)*(p_norm(:,:))**KAPPA
  teq(:,:,k) = max( teq(:,:,k), tstr(:,:) )
  ...
enddo
```

C++ uses explicit nested loops:
```cpp
for (int k = 0; k < nlev; ++k) {
    for (int j = 0; j < nlat; ++j) {
        for (int i = 0; i < nlon; ++i) {
            // ...
        }
    }
}
```

### Temporary Arrays

The Fortran code uses 2D temporary arrays for latitude-dependent terms. The C++ translation allocates these as `std::vector<double>`:
- `sin_lat`, `sin_lat_2`, `cos_lat_2`, `cos_lat_4` — trigonometric terms
- `t_star`, `tstr` — equilibrium temperature components
- `rps` — reciprocal of surface pressure
- `tdamp` — damping coefficient (3D)

## Expected Output

```
======================================
Newtonian Damping C++ Test Driver
======================================

...

tdt comparison:
  Max absolute difference: 0.000000e+00 at index -1
  Max relative difference: 0.000000e+00 at index -1
  Status: PASS

teq comparison:
  Max absolute difference: 0.000000e+00 at index -1
  Max relative difference: 0.000000e+00 at index -1
  Status: PASS

======================================
OVERALL RESULT: PASS
======================================
```

## Validation Criteria

- Relative tolerance: `1e-14`
- Absolute tolerance: `1e-20`

These tight tolerances verify bit-reproducibility between Fortran and C++.
