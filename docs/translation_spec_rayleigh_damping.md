# Translation Specification: `rayleigh_damping`

## Source Information

| Attribute | Value |
|-----------|-------|
| **Original File** | `src/atmos_param/hs_forcing/hs_forcing.F90` |
| **Line Range** | 615–679 |
| **Module** | `hs_forcing_mod` |
| **Routine Name** | `rayleigh_damping` |

---

## Purpose

Apply Rayleigh (linear) friction damping to horizontal wind components near the surface. This implements Held-Suarez (1994) Equation 3:

```
∂v/∂t = -kv(σ) * v
```

where `kv(σ)` is the friction coefficient that increases from zero at `σ = σ_b` to `kf` at the surface (`σ = 1`).

---

## Inputs

| Name | Type | Dimensions | Units | Description |
|------|------|------------|-------|-------------|
| `Time` | `time_type` | scalar | — | Current model time (used only for `relax_to_specified_wind` option) |
| `ps` | `real` | (lon, lat) | Pa | Surface pressure |
| `p_full` | `real` | (lon, lat, lev) | Pa | Pressure at full (mid) levels |
| `p_half` | `real` | (lon, lat, lev+1) | Pa | Pressure at half (interface) levels |
| `u` | `real` | (lon, lat, lev) | m/s | Zonal wind component |
| `v` | `real` | (lon, lat, lev) | m/s | Meridional wind component |
| `mask` | `real` | (lon, lat, lev) | — | Optional land/sea mask (0 or 1) |

---

## Outputs

| Name | Type | Dimensions | Units | Description |
|------|------|------------|-------|-------------|
| `udt` | `real` | (lon, lat, lev) | m/s² | Zonal wind tendency |
| `vdt` | `real` | (lon, lat, lev) | m/s² | Meridional wind tendency |

---

## Array Dimensions

| Dimension | Fortran Index | Typical Size | Description |
|-----------|---------------|--------------|-------------|
| `lon` | 1 | 64–256 | Longitude points |
| `lat` | 2 | 32–128 | Latitude points |
| `lev` | 3 | 20–40 | Vertical levels (top to bottom) |

Array ordering is column-major (Fortran). C++ should use row-major with reversed indices or maintain Fortran ordering for validation.

---

## Dependencies

### External Modules (Required)
- `time_manager_mod`: `time_type` — only for `relax_to_specified_wind` option
- `get_zonal_mean_flow()` — only for `relax_to_specified_wind` option

### External Modules (Can Be Eliminated)
For the default Held-Suarez case (`relax_to_specified_wind = .false.`), **no external dependencies** are required.

---

## Global/Module Variables Used

| Variable | Type | Default | Source | Description |
|----------|------|---------|--------|-------------|
| `vkf` | `real` | computed | `hs_forcing_init` | Friction coefficient (1/s), derived from `kf` |
| `sigma_b` | `real` | 0.7 | namelist | Sigma level of boundary layer top |
| `relax_to_specified_wind` | `logical` | `.false.` | namelist | Use file-specified wind relaxation |

**Note:** `vkf` is computed in `hs_forcing_init` as:
```fortran
vkf = 1./(SECONDS_PER_DAY*abs(kf))  ! kf default = -1 day
```

---

## Numerical Formulas

### Standard Held-Suarez Damping (default branch)

1. **Sigma coordinate:**
   ```
   σ(i,j,k) = p_full(i,j,k) / ps(i,j)
   ```

2. **Friction coefficient (vertical profile):**
   ```
   kv(σ) = kf * max(0, (σ - σ_b) / (1 - σ_b))
   ```
   
   In code form:
   ```
   vcoeff = -vkf / (1 - σ_b)
   vfactr = vcoeff * (σ - σ_b)    where σ_b < σ ≤ 1
   vfactr = 0                      elsewhere
   ```

3. **Wind tendencies:**
   ```
   ∂u/∂t = vfactr * u
   ∂v/∂t = vfactr * v
   ```

### Relaxation to Specified Wind (optional branch)

When `relax_to_specified_wind = .true.`:
```
∂u/∂t = kf * (u_specified - u_zonal_mean)
∂v/∂t = kf * (v_specified - v_zonal_mean)
```

---

## Control Flow

```
if relax_to_specified_wind:
    call get_zonal_mean_flow()
    for each level k:
        compute zonal mean of u, v
        udt = kf * (u_file - u_mean)
        vdt = kf * (v_file - v_mean)
else:  # Standard Held-Suarez
    for each level k:
        σ = p_full(:,:,k) / ps
        where σ_b < σ ≤ 1:
            vfactr = -kf/(1-σ_b) * (σ - σ_b)
            udt = vfactr * u
            vdt = vfactr * v
        elsewhere:
            udt = 0
            vdt = 0

if mask present:
    udt *= mask
    vdt *= mask
```

---

## Side Effects

- **None** for the default Held-Suarez branch
- `relax_to_specified_wind` branch calls `get_zonal_mean_flow()` which reads interpolator state

---

## Proposed C++ Function Signature

### Core Kernel (GPU-portable)

```cpp
namespace hs_forcing {

struct RayleighParams {
    double kf;       // friction coefficient (1/s), typically 1/(1 day)
    double sigma_b;  // boundary layer top sigma level, typically 0.7
};

// Standard Held-Suarez Rayleigh damping
// All arrays are 3D with dimensions [nlon][nlat][nlev]
void rayleigh_damping(
    // Grid dimensions
    int nlon, int nlat, int nlev,
    
    // Inputs
    const double* ps,      // [nlon][nlat] surface pressure (Pa)
    const double* p_full,  // [nlon][nlat][nlev] pressure at full levels (Pa)
    const double* u,       // [nlon][nlat][nlev] zonal wind (m/s)
    const double* v,       // [nlon][nlat][nlev] meridional wind (m/s)
    
    // Parameters
    const RayleighParams& params,
    
    // Outputs
    double* udt,           // [nlon][nlat][nlev] zonal wind tendency (m/s²)
    double* vdt,           // [nlon][nlat][nlev] meridional wind tendency (m/s²)
    
    // Optional mask (nullptr if not used)
    const double* mask = nullptr  // [nlon][nlat][nlev]
);

}  // namespace hs_forcing
```

### CUDA Kernel Signature

```cpp
__global__ void rayleigh_damping_kernel(
    int nlon, int nlat, int nlev,
    const double* __restrict__ ps,
    const double* __restrict__ p_full,
    const double* __restrict__ u,
    const double* __restrict__ v,
    double kf, double sigma_b,
    double* __restrict__ udt,
    double* __restrict__ vdt,
    const double* __restrict__ mask  // may be nullptr
);
```

---

## Unit Test Strategy

### Test 1: Zero Tendency Above Boundary Layer
- **Setup:** σ < σ_b for all levels
- **Expected:** `udt = 0`, `vdt = 0` everywhere
- **Validates:** Correct boundary layer detection

### Test 2: Maximum Damping at Surface
- **Setup:** σ = 1.0 (surface level), uniform u, v
- **Expected:** `udt = -kf * u`, `vdt = -kf * v`
- **Validates:** Correct friction coefficient at surface

### Test 3: Linear Profile in Boundary Layer
- **Setup:** Levels with σ = {0.75, 0.85, 0.95} (σ_b = 0.7)
- **Expected:** Linear increase in damping magnitude
- **Validates:** Correct vertical interpolation formula

### Test 4: Mask Application
- **Setup:** Checkerboard mask pattern
- **Expected:** Zero tendency where mask = 0
- **Validates:** Mask multiplication

### Test 5: Reference Comparison
- **Setup:** Extract u, v, ps, p_full from Fortran run
- **Expected:** Bit-reproducible `udt`, `vdt` (within floating-point tolerance)
- **Validates:** Numerical equivalence to Fortran

### Test 6: Conservation Check
- **Setup:** Domain-integrated momentum before/after
- **Expected:** Momentum removed equals `∫ρ * (udt, vdt) dV`
- **Validates:** Physical consistency

---

## Implementation Notes

1. **Loop Structure:** The Fortran code loops over `k` (levels) in the outer loop. For GPU, parallelize over all `(i, j, k)` simultaneously.

2. **Memory Access:** `p_full(:,:,k)` access pattern in Fortran is contiguous for each level. Consider data layout for GPU coalescing.

3. **Branching:** The `where` construct creates divergent control flow. On GPU, compute both branches and blend with conditional.

4. **Precision:** Fortran uses default `real` (single precision with `-fdefault-real-8` makes it double). C++ kernel should use `double` for validation, with `float` option for performance.

5. **Sign Convention:** `vcoeff` is negative, so `udt` and `vdt` are opposite sign to `u` and `v` (damping reduces wind speed).
