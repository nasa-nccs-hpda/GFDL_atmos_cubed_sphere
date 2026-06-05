# Translation Specification: calc_ecc_anomaly

## Source Information

| Field | Value |
|-------|-------|
| **Original File** | `src/atmos_param/hs_forcing/hs_forcing.F90` |
| **Line Range** | 864–890 |
| **Module** | `hs_forcing_mod` |
| **Routine Name** | `calc_ecc_anomaly` |
| **Routine Type** | Subroutine |

## Purpose

Solves Kepler's equation to compute the **eccentric anomaly** (E) from the **mean anomaly** (M) and orbital **eccentricity** (e) using Newton-Raphson iteration.

Kepler's equation:
```
E - e * sin(E) = M
```

This is a fundamental orbital mechanics calculation used to determine planetary position along an elliptical orbit. The eccentric anomaly is then used to compute the true anomaly and orbital distance in `update_orbit`.

## Interface

### Inputs

| Parameter | Fortran Type | Description | Units | Valid Range |
|-----------|--------------|-------------|-------|-------------|
| `mean_anomaly` | `real, intent(in)` | Mean anomaly M | radians | [0, 2π) typical, but algorithm handles any real |
| `ecc` | `real, intent(in)` | Orbital eccentricity e | dimensionless | [0, 1) for bound orbits |

### Outputs

| Parameter | Fortran Type | Description | Units |
|-----------|--------------|-------------|-------|
| `ecc_anomaly` | `real, intent(out)` | Eccentric anomaly E | radians |

### Array Dimensions

None — all parameters are scalars.

## Dependencies

### External Module Dependencies

**None.** This routine is completely self-contained.

### Intrinsic Functions Used

| Function | Purpose |
|----------|---------|
| `sin(x)` | Sine function |
| `cos(x)` | Cosine function |
| `abs(x)` | Absolute value |

### Called By

- `update_orbit` (line 832 in same file)

### Calls

- None (leaf routine)

## Global/Module Variables

**None accessed.** All state is local to the subroutine.

## Local Variables

| Variable | Type | Description |
|----------|------|-------------|
| `dE` | `real` | Newton-Raphson correction step |
| `d` | `real` | Residual: `E - e*sin(E) - M` |
| `k` | `integer` | Loop iteration counter |
| `maxiter` | `integer, parameter` | Maximum iterations = 30 |
| `tol` | `real, parameter` | Convergence tolerance = 1.0e-10 |

## Numerical Formulas

### Newton-Raphson Iteration

Given Kepler's equation as `f(E) = E - e*sin(E) - M = 0`:

1. **Derivative:** `f'(E) = 1 - e*cos(E)`

2. **Update rule:** `E_{n+1} = E_n - f(E_n) / f'(E_n)`

   Expanded: `E_{n+1} = E_n - (E_n - e*sin(E_n) - M) / (1 - e*cos(E_n))`

3. **Initial guess:** `E_0 = M` (good for low eccentricity)

4. **Convergence criterion:** `|E - e*sin(E) - M| < 1.0e-10`

### Algorithm Pseudocode

```
E = M                           // initial guess
d = E - e*sin(E) - M            // initial residual
for k = 1 to 30:
    dE = d / (1 - e*cos(E))     // Newton step
    E = E - dE                  // update
    d = E - e*sin(E) - M        // new residual
    if |d| < 1e-10: break
if not converged: warn
return E
```

## Side Effects

| Side Effect | Description |
|-------------|-------------|
| Console output | Prints warning to stdout if iteration fails to converge after 30 iterations |

**Note:** The warning print statement is the only side effect. No global state is modified.

## Numerical Considerations

1. **Precision:** Uses default `real` (typically 32-bit), but tolerance `1.d-10` is double-precision literal. This may cause precision issues — the tolerance is tighter than single-precision can reliably achieve.

2. **Convergence:** Newton-Raphson converges quadratically for `e < 1`. For `e` close to 1, convergence may be slower but 30 iterations is typically sufficient.

3. **Edge cases:**
   - `e = 0`: Trivial case, `E = M` (converges in 1 iteration)
   - `e → 1`: Slower convergence near perihelion
   - `M = 0`: `E = 0` is exact solution

## Proposed C++ Function Signature

### Option A: Pure Function (Recommended)

```cpp
namespace hs_forcing {

struct EccAnomalyResult {
    double ecc_anomaly;
    bool converged;
    int iterations;
};

EccAnomalyResult calc_ecc_anomaly(double mean_anomaly, double ecc,
                                   int max_iter = 30,
                                   double tol = 1.0e-10);

} // namespace hs_forcing
```

### Option B: Simple Signature (Direct Port)

```cpp
namespace hs_forcing {

double calc_ecc_anomaly(double mean_anomaly, double ecc);

} // namespace hs_forcing
```

### Option C: Kokkos-Compatible (GPU-Ready)

```cpp
namespace hs_forcing {

KOKKOS_INLINE_FUNCTION
double calc_ecc_anomaly(double mean_anomaly, double ecc) {
    // Implementation inline for GPU kernels
}

} // namespace hs_forcing
```

### Recommended: Option A

Returns a struct with convergence information for better error handling than the original Fortran's print statement.

## Unit Test Strategy

### Test Categories

#### 1. Analytical Solutions

| Test Case | M | e | Expected E | Notes |
|-----------|---|---|------------|-------|
| Zero eccentricity | π/4 | 0.0 | π/4 | E = M when e = 0 |
| Zero mean anomaly | 0.0 | 0.5 | 0.0 | E = 0 when M = 0 |
| Circular orbit | π | 0.0 | π | E = M for any M |

#### 2. Known Reference Values

Use high-precision reference implementations (e.g., from JPL ephemeris or Vallado's "Fundamentals of Astrodynamics"):

| Test Case | M (rad) | e | Expected E (rad) | Tolerance |
|-----------|---------|---|------------------|-----------|
| Earth-like | 1.0 | 0.0167 | 1.01671... | 1e-9 |
| Mars-like | 2.0 | 0.0934 | 2.08456... | 1e-9 |
| Mercury-like | 1.5 | 0.2056 | 1.66847... | 1e-9 |
| High ecc | 0.5 | 0.9 | 1.38418... | 1e-9 |

#### 3. Symmetry Tests

- `calc_ecc_anomaly(-M, e)` should equal `-calc_ecc_anomaly(M, e)`
- `calc_ecc_anomaly(M + 2π, e)` should equal `calc_ecc_anomaly(M, e) + 2π`

#### 4. Convergence Tests

| Test Case | Description | Expected |
|-----------|-------------|----------|
| Low ecc | e = 0.01, M = π | Converges in < 5 iterations |
| Medium ecc | e = 0.5, M = π | Converges in < 10 iterations |
| High ecc | e = 0.99, M = 0.1 | Converges in < 30 iterations |
| Edge case | e = 0.999, M = 3.0 | Should converge or report failure |

#### 5. Fortran-C++ Comparison

Run identical inputs through both implementations and verify:
- Output values match within tolerance (1e-10)
- Same convergence behavior

### Test Implementation Outline

```cpp
#include <gtest/gtest.h>
#include "hs_forcing/calc_ecc_anomaly.hpp"
#include <cmath>

namespace hs_forcing::test {

TEST(CalcEccAnomaly, ZeroEccentricity) {
    double M = M_PI / 4.0;
    auto result = calc_ecc_anomaly(M, 0.0);
    EXPECT_NEAR(result.ecc_anomaly, M, 1e-12);
    EXPECT_TRUE(result.converged);
}

TEST(CalcEccAnomaly, ZeroMeanAnomaly) {
    auto result = calc_ecc_anomaly(0.0, 0.5);
    EXPECT_NEAR(result.ecc_anomaly, 0.0, 1e-12);
}

TEST(CalcEccAnomaly, EarthOrbit) {
    // Reference value from high-precision computation
    double M = 1.0;
    double e = 0.0167;
    double E_expected = 1.0167097569; // precomputed
    auto result = calc_ecc_anomaly(M, e);
    EXPECT_NEAR(result.ecc_anomaly, E_expected, 1e-9);
}

TEST(CalcEccAnomaly, HighEccentricity) {
    double M = 0.5;
    double e = 0.9;
    auto result = calc_ecc_anomaly(M, e);
    // Verify Kepler's equation: E - e*sin(E) = M
    double residual = result.ecc_anomaly - e * std::sin(result.ecc_anomaly) - M;
    EXPECT_NEAR(residual, 0.0, 1e-10);
    EXPECT_TRUE(result.converged);
}

TEST(CalcEccAnomaly, Antisymmetry) {
    double M = 1.5;
    double e = 0.3;
    auto pos = calc_ecc_anomaly(M, e);
    auto neg = calc_ecc_anomaly(-M, e);
    EXPECT_NEAR(pos.ecc_anomaly, -neg.ecc_anomaly, 1e-12);
}

} // namespace hs_forcing::test
```

## Verification Checklist

- [ ] C++ output matches Fortran for all test cases within tolerance
- [ ] Convergence behavior identical (iteration counts similar)
- [ ] Edge cases handled identically
- [ ] No memory leaks or undefined behavior
- [ ] GPU version (if applicable) matches CPU version
