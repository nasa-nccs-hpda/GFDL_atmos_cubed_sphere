# C++ Translation: calc_ecc_anomaly

C++ translation of the `calc_ecc_anomaly` subroutine from `hs_forcing_mod`.

## Source Mapping

| C++ | Fortran |
|-----|---------|
| `calc_ecc_anomaly.hpp` | `src/atmos_param/hs_forcing/hs_forcing.F90:864-890` |
| `hs_forcing::calc_ecc_anomaly()` | `subroutine calc_ecc_anomaly()` |

## Translation Notes

### Algorithm Preservation

The C++ implementation preserves the original Fortran algorithm exactly:

1. **Initial guess:** `E = M`
2. **Newton-Raphson iteration:** `E = E - (E - e*sin(E) - M) / (1 - e*cos(E))`
3. **Convergence criterion:** `|E - e*sin(E) - M| < 1e-10`
4. **Maximum iterations:** 30

### Interface Enhancement

The C++ version returns a struct with additional information:

```cpp
struct EccAnomalyResult {
    double ecc_anomaly;  // The computed value
    bool converged;      // Whether iteration converged
    int iterations;      // Number of iterations used
};
```

A Fortran-compatible interface is also provided:

```cpp
void calc_ecc_anomaly_fortran_interface(
    double mean_anomaly, double ecc, double& ecc_anomaly);
```

### Precision

Uses `double` (64-bit) throughout, matching the intended precision of the Fortran version (which uses `1.d-10` tolerance).

## Files

| File | Description |
|------|-------------|
| `calc_ecc_anomaly.hpp` | Header-only implementation |
| `test_driver.cpp` | Test driver with Fortran comparison |
| `Makefile` | Build script |
| `outputs.dat` | Generated outputs (after running) |

## Building

```bash
make
```

## Running

### Standalone test (generates synthetic inputs)

```bash
make run
```

### Compare against Fortran baseline

```bash
make compare
```

This will:
1. Build and run the Fortran baseline (if not already done)
2. Run the C++ driver with Fortran input/output files
3. Compare results and report differences

## Expected Output

```
Read 12 test cases from ../../../../tests/fortran_baseline/calc_ecc_anomaly/inputs.dat
Wrote C++ outputs to: outputs.dat

===== calc_ecc_anomaly C++ Test Results =====

  ID         M (rad)           e             E (rad)        Residual
------------------------------------------------------------
   1    0.7853981634      0.000000    0.78539816339745    0.000000e+00
   ...

===== Verification =====

PASS: e=0 case (E = M)
PASS: M=0 case (E = 0)
PASS: Antisymmetry E(-M) = -E(M)
PASS: All residuals < 1e-8

===== Fortran Comparison =====

Max |E_cpp - E_fortran| = 1.234567e-15
PASS: C++ matches Fortran within 1e-10

===== Summary =====
Passed: 5
Failed: 0
```

## Verification Checklist

- [x] Algorithm matches Fortran exactly
- [x] Variable names preserved where possible
- [x] Double precision used throughout
- [x] No optimizations applied
- [x] Comments map to original Fortran logic
- [x] Driver uses same input format as Fortran harness
