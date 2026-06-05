# Translation Specification: `newtonian_damping`

## Source Information

| Attribute | Value |
|-----------|-------|
| **Original File** | `src/atmos_param/hs_forcing/hs_forcing.F90` |
| **Line Range** | 508–611 |
| **Module** | `hs_forcing_mod` |
| **Routine Name** | `newtonian_damping` |

---

## Purpose

Compute Newtonian (linear) temperature relaxation toward an equilibrium temperature profile. This implements Held-Suarez (1994) Equations 1–2:

```
∂T/∂t = -kT(φ,σ) * (T - Teq(φ,p))
```

where:
- `Teq` is the radiative-convective equilibrium temperature
- `kT` is the relaxation coefficient (varies with latitude and sigma)

This is the **primary thermal forcing** for the Held-Suarez benchmark.

---

## Inputs

| Name | Type | Dimensions | Units | Description |
|------|------|------------|-------|-------------|
| `Time` | `time_type` | scalar | — | Current model time |
| `lat` | `real` | (lon, lat) | radians | Latitude |
| `lon` | `real` | (lon, lat) | radians | Longitude |
| `ps` | `real` | (lon, lat) | Pa | Surface pressure |
| `p_full` | `real` | (lon, lat, lev) | Pa | Pressure at full (mid) levels |
| `p_half` | `real` | (lon, lat, lev+1) | Pa | Pressure at half (interface) levels |
| `t` | `real` | (lon, lat, lev) | K | Temperature |
| `mask` | `real` | (lon, lat, lev) | — | Optional land/sea mask (0 or 1) |

---

## Outputs

| Name | Type | Dimensions | Units | Description |
|------|------|------------|-------|-------------|
| `tdt` | `real` | (lon, lat, lev) | K/s | Temperature tendency |
| `teq` | `real` | (lon, lat, lev) | K | Equilibrium temperature (diagnostic) |

---

## Array Dimensions

| Dimension | Fortran Index | Typical Size | Description |
|-----------|---------------|--------------|-------------|
| `lon` | 1 | 64–256 | Longitude points |
| `lat` | 2 | 32–128 | Latitude points |
| `lev` | 3 | 20–40 | Vertical levels (top to bottom) |

---

## Dependencies

### External Modules

| Module | Usage | Required for Default HS? |
|--------|-------|--------------------------|
| `constants_mod` | `KAPPA` (R/cp ≈ 2/7) | **Yes** |
| `time_manager_mod` | `time_type` | No (only for `from_file`, `exoplanet`) |
| `interpolator_mod` | `interpolator()` | No (only for `from_file`) |
| `astronomy_mod` | `diurnal_exoplanet()` | No (only for `exoplanet`) |

**For standard Held-Suarez (`equilibrium_t_option = 'Held_Suarez'`):** Only `KAPPA` constant is required.

---

## Global/Module Variables Used

| Variable | Type | Default | Source | Description |
|----------|------|---------|--------|-------------|
| `t_zero` | `real` | 315 K | namelist | Equatorial equilibrium temperature |
| `t_strat` | `real` | 200 K | namelist | Stratospheric temperature minimum |
| `delh` | `real` | 60 K | namelist | Equator-pole temperature difference |
| `delv` | `real` | 10 K | namelist | Static stability parameter |
| `eps` | `real` | 0 K | namelist | Hemispheric asymmetry |
| `sigma_b` | `real` | 0.7 | namelist | Boundary layer top |
| `P00` | `real` | 1e5 Pa | namelist | Reference pressure |
| `tka` | `real` | computed | init | Atmospheric damping rate (1/s) |
| `tks` | `real` | computed | init | Surface damping rate (1/s) |
| `KAPPA` | `real` | 2/7 | constants | R/cp for ideal gas |
| `equilibrium_t_option` | `string` | `'Held_Suarez'` | namelist | Teq calculation method |

**Note:** `tka` and `tks` are computed in `hs_forcing_init`:
```fortran
tka = 1./(SECONDS_PER_DAY*abs(ka))  ! ka default = -40 days
tks = 1./(SECONDS_PER_DAY*abs(ks))  ! ks default = -4 days
```

---

## Numerical Formulas

### Held-Suarez Equilibrium Temperature (default)

1. **Latitude-dependent terms:**
   ```
   sin²φ = sin(lat)²
   cos²φ = 1 - sin²φ
   cos⁴φ = cos²φ × cos²φ
   ```

2. **Surface equilibrium temperature:**
   ```
   T* = T₀ - Δθh·sin²φ - ε·sin(φ)
   ```
   where:
   - `T₀ = 315 K` (equatorial temperature)
   - `Δθh = 60 K` (equator-pole difference)
   - `ε = 0` (hemispheric asymmetry, usually zero)

3. **Stratospheric temperature:**
   ```
   Tstr = Tstrat - ε·sin(φ)
   ```
   where `Tstrat = 200 K`

4. **Equilibrium temperature profile:**
   ```
   p_norm = p / P00
   θe = T* - Δθv·cos²φ·ln(p_norm)
   Teq = max(θe · p_norm^κ, Tstr)
   ```
   where:
   - `Δθv = 10 K` (static stability)
   - `κ = R/cp ≈ 2/7`

### Damping Coefficient

5. **Sigma coordinate:**
   ```
   σ = p_full / ps
   ```

6. **Damping rate (latitude and sigma dependent):**
   ```
   kT(φ,σ) = ka + (ks - ka)·cos⁴φ·max(0, (σ - σ_b)/(1 - σ_b))
   ```
   
   In boundary layer (σ > σ_b):
   ```
   tfactr = (ks - ka)/(1 - σ_b) · (σ - σ_b)
   tdamp = ka + cos⁴φ · tfactr
   ```
   
   Above boundary layer (σ ≤ σ_b):
   ```
   tdamp = ka
   ```

### Temperature Tendency

7. **Newtonian relaxation:**
   ```
   ∂T/∂t = -kT · (T - Teq)
   ```

---

## Control Flow

```
# Precompute latitude terms (2D)
sin_lat = sin(lat)
cos_lat = cos(lat)
sin_lat_2 = sin_lat²
cos_lat_2 = 1 - sin_lat_2
cos_lat_4 = cos_lat_2²

t_star = t_zero - delh*sin_lat_2 - eps*sin_lat
tstr = t_strat - eps*sin_lat

tcoeff = (tks - tka) / (1 - sigma_b)
rps = 1 / ps

for each level k:
    # Compute equilibrium temperature
    if equilibrium_t_option == 'Held_Suarez':
        p_norm = p_full(:,:,k) / P00
        the = t_star - delv*cos_lat_2*ln(p_norm)
        teq(:,:,k) = max(the * p_norm^KAPPA, tstr)
    elif equilibrium_t_option == 'from_file':
        teq(:,:,k) = tz(j,k)  # from interpolator
    elif equilibrium_t_option == 'exoplanet':
        # diurnal cycle variant
        ...
    
    # Compute damping coefficient
    sigma = p_full(:,:,k) * rps
    where sigma_b < sigma <= 1:
        tfactr = tcoeff * (sigma - sigma_b)
        tdamp(:,:,k) = tka + cos_lat_4 * tfactr
    elsewhere:
        tdamp(:,:,k) = tka

# Apply tendency
for each level k:
    tdt(:,:,k) = -tdamp(:,:,k) * (t(:,:,k) - teq(:,:,k))

if mask present:
    tdt *= mask
    teq *= mask
```

---

## Side Effects

- **None** for the default Held-Suarez branch
- `from_file` branch calls `get_zonal_mean_temp()` which reads interpolator state
- `exoplanet` branch calls `diurnal_exoplanet()` from astronomy module

---

## Proposed C++ Function Signature

### Parameters Structure

```cpp
namespace hs_forcing {

struct NewtonianParams {
    // Equilibrium temperature parameters
    double t_zero;   // equatorial temperature (K), default 315
    double t_strat;  // stratospheric temperature (K), default 200
    double delh;     // equator-pole difference (K), default 60
    double delv;     // static stability (K), default 10
    double eps;      // hemispheric asymmetry (K), default 0
    double P00;      // reference pressure (Pa), default 1e5
    double kappa;    // R/cp, default 2/7
    
    // Damping parameters
    double ka;       // atmospheric damping rate (1/s), ~1/(40 days)
    double ks;       // surface damping rate (1/s), ~1/(4 days)
    double sigma_b;  // boundary layer top, default 0.7
};

}
```

### Core Kernel (GPU-portable)

```cpp
namespace hs_forcing {

// Standard Held-Suarez Newtonian damping
void newtonian_damping(
    // Grid dimensions
    int nlon, int nlat, int nlev,
    
    // Inputs
    const double* lat,     // [nlon][nlat] latitude (radians)
    const double* ps,      // [nlon][nlat] surface pressure (Pa)
    const double* p_full,  // [nlon][nlat][nlev] pressure at full levels (Pa)
    const double* t,       // [nlon][nlat][nlev] temperature (K)
    
    // Parameters
    const NewtonianParams& params,
    
    // Outputs
    double* tdt,           // [nlon][nlat][nlev] temperature tendency (K/s)
    double* teq,           // [nlon][nlat][nlev] equilibrium temperature (K)
    
    // Optional mask (nullptr if not used)
    const double* mask = nullptr  // [nlon][nlat][nlev]
);

}  // namespace hs_forcing
```

### CUDA Kernel Signature

```cpp
__global__ void newtonian_damping_kernel(
    int nlon, int nlat, int nlev,
    const double* __restrict__ lat,
    const double* __restrict__ ps,
    const double* __restrict__ p_full,
    const double* __restrict__ t,
    // Params passed as individual values for register efficiency
    double t_zero, double t_strat, double delh, double delv,
    double eps, double P00, double kappa,
    double ka, double ks, double sigma_b,
    double* __restrict__ tdt,
    double* __restrict__ teq,
    const double* __restrict__ mask  // may be nullptr
);
```

### Alternative: Split Kernels

For better GPU occupancy, split into two kernels:

```cpp
// Kernel 1: Compute equilibrium temperature (expensive trig + log)
__global__ void compute_teq_kernel(
    int nlon, int nlat, int nlev,
    const double* lat, const double* p_full,
    double t_zero, double t_strat, double delh, double delv,
    double eps, double P00, double kappa,
    double* teq
);

// Kernel 2: Compute damping and tendency (cheaper arithmetic)
__global__ void compute_tdt_kernel(
    int nlon, int nlat, int nlev,
    const double* lat, const double* ps, const double* p_full,
    const double* t, const double* teq,
    double ka, double ks, double sigma_b,
    double* tdt,
    const double* mask
);
```

---

## Unit Test Strategy

### Test 1: Uniform Atmosphere at Equilibrium
- **Setup:** `T = Teq` everywhere
- **Expected:** `tdt = 0` everywhere
- **Validates:** Equilibrium state produces no forcing

### Test 2: Equatorial Surface Equilibrium
- **Setup:** lat = 0, σ = 1, p = P00
- **Expected:** `Teq = t_zero = 315 K`
- **Validates:** Equatorial reference temperature

### Test 3: Polar Stratospheric Temperature
- **Setup:** lat = ±90°, σ < σ_b
- **Expected:** `Teq = t_strat = 200 K`
- **Validates:** Polar stratospheric minimum

### Test 4: Vertical Temperature Structure
- **Setup:** Multiple pressure levels at equator
- **Expected:** `Teq` follows adiabatic lapse in troposphere, capped at `t_strat`
- **Validates:** Correct κ exponent and max function

### Test 5: Damping Rate Profile
- **Setup:** σ = {0.5, 0.8, 1.0}, equator vs pole
- **Expected:** 
  - Above σ_b: `kT = ka` everywhere
  - At surface: `kT = ks` at equator, `kT = ka` at pole
- **Validates:** Latitude-sigma damping structure

### Test 6: Sign of Tendency
- **Setup:** `T > Teq` (warm anomaly)
- **Expected:** `tdt < 0` (cooling tendency)
- **Validates:** Correct sign convention

### Test 7: Mask Application
- **Setup:** Checkerboard mask pattern
- **Expected:** Zero tendency and Teq where mask = 0
- **Validates:** Mask multiplication

### Test 8: Reference Comparison
- **Setup:** Extract T, lat, ps, p_full from Fortran run
- **Expected:** Bit-reproducible `tdt`, `teq` (within floating-point tolerance)
- **Validates:** Numerical equivalence to Fortran

### Test 9: Energy Budget
- **Setup:** Domain-integrated heating rate
- **Expected:** `∫ρcp·tdt dV` matches expected radiative imbalance
- **Validates:** Physical consistency

---

## Implementation Notes

1. **Trigonometric Functions:** `sin²φ`, `cos²φ`, `cos⁴φ` are latitude-only. Precompute once per column, not per level.

2. **Logarithm:** `log(p_norm)` is level-dependent. Avoid recomputing `sin²φ` terms inside level loop.

3. **Memory Layout:** Fortran stores `p_full(:,:,k)` contiguously per level. Consider transposing to `p_full[k][j][i]` for GPU coalescing across `i`.

4. **Branching:** The `where` construct for damping creates divergence. On GPU, compute both damping rates and blend:
   ```cpp
   double in_bl = (sigma > sigma_b && sigma <= 1.0) ? 1.0 : 0.0;
   double tdamp = ka + in_bl * cos_lat_4 * tcoeff * (sigma - sigma_b);
   ```

5. **`max` for Teq:** The `max(Teq, Tstr)` enforces stratospheric minimum. This is a simple comparison, not a reduction.

6. **Precision:** The `p_norm^KAPPA` term requires accurate exponentiation. Use `pow()` or `exp(KAPPA * log(p_norm))`.

7. **Constants:** `KAPPA = 2/7 ≈ 0.2857142857`. Use full double precision to avoid accumulating error.

---

## Fortran-to-C++ Mapping Summary

| Fortran | C++ | Notes |
|---------|-----|-------|
| `real, dimension(:,:)` | `double*` + dims | Pass dimensions explicitly |
| `where (cond) ... elsewhere` | `if/else` or ternary | Per-element conditional |
| `sin_lat(:,:)` | Precomputed 2D array | Avoid recomputing |
| `teq(:,:,k) = max(...)` | `teq[idx] = std::max(...)` | Element-wise max |
| `intent(in/out)` | `const` / non-const | Enforce immutability |
| Optional `mask` | `nullptr` check | C++ idiom for optional args |
