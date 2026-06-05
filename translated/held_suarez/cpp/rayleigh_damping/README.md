# Rayleigh Damping C++ Translation

Direct C++ translation of the `rayleigh_damping` subroutine from `hs_forcing_mod`.

## Files

| File | Description |
|------|-------------|
| `rayleigh_damping.hpp` | Header-only kernel implementation |
| `test_driver.cpp` | Test driver that validates against Fortran baseline |
| `Makefile` | Build system |

## Prerequisites

1. Generate Fortran baseline data first:
   ```bash
   cd ../../../../tests/fortran_baseline/rayleigh_damping
   module load gcc/12.1.0
   make run
   ```

2. Return to this directory and build/run:
   ```bash
   cd ../../../../translated/held_suarez/cpp/rayleigh_damping
   make run
   ```

## Translation Notes

### Array Layout

The C++ code uses **Fortran column-major order** for direct comparison:
```cpp
// Index a 3D array as: arr[i + nlon * (j + nlat * k)]
int idx_3d = i + nlon * (j + nlat * k);
```

### Algorithm Mapping

| Fortran | C++ |
|---------|-----|
| `vcoeff = -vkf/(1.0-sigma_b)` | `double vcoeff = -vkf / (1.0 - sigma_b)` |
| `rps = 1./ps` | `double rps = 1.0 / ps[idx_2d]` |
| `sigma(:,:) = p_full(:,:,k)*rps(:,:)` | `double sigma = p_full[idx_3d] * rps` |
| `where (sigma <= 1.0 .and. sigma > sigma_b)` | `if (sigma <= 1.0 && sigma > sigma_b)` |
| `vfactr(:,:) = vcoeff*(sigma(:,:)-sigma_b)` | `double vfactr = vcoeff * (sigma - sigma_b)` |

### Loop Structure

Fortran uses array operations within a level loop:
```fortran
do k = 1, nlev
  sigma(:,:) = p_full(:,:,k)*rps(:,:)
  where (...)
    ...
  endwhere
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

## Expected Output

```
======================================
Rayleigh Damping C++ Test Driver
======================================

Data directory: ../../../../tests/fortran_baseline/rayleigh_damping/

Reading parameters...
Grid dimensions:
  nlon  = 8
  nlat  = 4
  nlev  = 5

Parameters:
  vkf     = 1.1574074074e-05
  sigma_b = 7.0000000000e-01

...

udt comparison:
  Max absolute difference: 0.000000e+00 at index 0
  Max relative difference: 0.000000e+00 at index 0
  Status: PASS

vdt comparison:
  Max absolute difference: 0.000000e+00 at index 0
  Max relative difference: 0.000000e+00 at index 0
  Status: PASS

======================================
OVERALL RESULT: PASS
======================================
```

## Validation Criteria

- Relative tolerance: `1e-14`
- Absolute tolerance: `1e-20`

These tight tolerances verify bit-reproducibility between Fortran and C++.
