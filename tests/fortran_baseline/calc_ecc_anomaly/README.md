# Fortran Baseline Test: calc_ecc_anomaly

Standalone test harness for the `calc_ecc_anomaly` subroutine extracted from `hs_forcing_mod`.

## Purpose

This harness:
1. Runs the original Fortran routine with synthetic test inputs
2. Writes inputs and outputs to data files for comparison with C++ port
3. Verifies basic correctness (analytical solutions, symmetry)

## Files

| File | Description |
|------|-------------|
| `calc_ecc_anomaly.F90` | Standalone module with the routine (extracted from `hs_forcing.F90`) |
| `test_harness.F90` | Test driver program |
| `Makefile` | Build script |
| `inputs.dat` | Generated test inputs (after running) |
| `outputs.dat` | Generated test outputs (after running) |

## Precision Notes

The standalone module uses **double precision** (`real(dp)`) to match typical FMS compilation settings. The original `hs_forcing.F90` uses default `real` but with a `1.d-10` tolerance literal, indicating double precision was intended.

## Known Limitations

The Newton-Raphson iteration with initial guess `E₀ = M` may fail to converge for very high eccentricities (e > 0.98) combined with small mean anomalies. This is a characteristic of the original algorithm. Production use in `hs_forcing_mod` typically involves planetary eccentricities (e < 0.3) where convergence is guaranteed.

## Requirements

- Fortran compiler (gfortran, ifort, or nvfortran)
- GNU Make

## Building

```bash
# Default (gfortran)
make

# With Intel Fortran
make FC=ifort

# With NVIDIA HPC SDK
make FC=nvfortran
```

## Running

```bash
make run
```

Or directly:

```bash
./test_calc_ecc_anomaly
```

## Expected Output

```
 Wrote inputs to: inputs.dat
 Wrote outputs to: outputs.dat

 ===== calc_ecc_anomaly Test Results =====

  ID        M (rad)           e            E (rad)         Residual
 ------------------------------------------------------------
   1      0.7853981634      0.000000      0.78539816339745  0.000000E+00
   2      0.0000000000      0.500000      0.00000000000000  0.000000E+00
   ...

 ===== Verification =====

 PASS: e=0 case (E = M)
 PASS: M=0 case (E = 0)
 PASS: Antisymmetry E(-M) = -E(M)
 PASS: All residuals < 1e-8

 Done.
```

## Output File Format

### inputs.dat

```
# Test inputs for calc_ecc_anomaly
# Columns: test_id, mean_anomaly, ecc
   1   0.7853981633974483E+00   0.0000000000000000E+00
   2   0.0000000000000000E+00   0.5000000000000000E+00
   ...
```

### outputs.dat

```
# Test outputs for calc_ecc_anomaly
# Columns: test_id, ecc_anomaly, residual
   1   0.7853981633974483E+00   0.0000000000000000E+00
   2   0.0000000000000000E+00   0.0000000000000000E+00
   ...
```

## Test Cases

| ID | Description | M | e | Expected E |
|----|-------------|---|---|------------|
| 1 | Zero eccentricity | π/4 | 0.0 | π/4 |
| 2 | Zero mean anomaly | 0.0 | 0.5 | 0.0 |
| 3 | Circular at π | π | 0.0 | π |
| 4 | Earth-like | 1.0 | 0.0167 | ~1.017 |
| 5 | Mars-like | 2.0 | 0.0934 | ~2.085 |
| 6 | Mercury-like | 1.5 | 0.2056 | ~1.668 |
| 7 | High eccentricity | 0.5 | 0.9 | ~1.384 |
| 8-9 | Antisymmetry pair | ±1.5 | 0.3 | ±E |
| 10 | High ecc | 0.1 | 0.95 | ~0.742 |
| 11 | Full orbit | 2π | 0.5 | ~2π |
| 12 | Edge case | 3.0 | 0.999 | converges? |

## Verification Against C++ Port

After implementing the C++ version, compare results:

```bash
# Run Fortran baseline
make run

# Run C++ version (outputs to same format)
../cpp/test_calc_ecc_anomaly

# Compare outputs
diff outputs.dat ../cpp/outputs.dat
```

Or use a tolerance-based comparison:

```python
import numpy as np
fortran = np.loadtxt('outputs.dat', usecols=(1,2))
cpp = np.loadtxt('../cpp/outputs.dat', usecols=(1,2))
assert np.allclose(fortran, cpp, rtol=1e-10, atol=1e-12)
```

## Cleaning Up

```bash
make clean      # Remove executables and .mod files
make distclean  # Also remove output data files
```
