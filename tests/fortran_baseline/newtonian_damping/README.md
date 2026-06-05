# Newtonian Damping Fortran Baseline Test

This directory contains a standalone Fortran test harness for the `newtonian_damping` kernel, extracted from `hs_forcing_mod`. It generates reference data for validating C++/CUDA ports.

## Files

| File | Description |
|------|-------------|
| `newtonian_damping_standalone.F90` | Isolated kernel (Held-Suarez branch only, no FMS dependencies) |
| `test_harness.F90` | Test driver with synthetic data generation |
| `Makefile` | Build system |

## Quick Start

```bash
# On NCCS Discover, load compiler first
module load gcc/12.1.0

# Build
make

# Run (generates binary output files)
make run

# Clean
make clean      # Remove executables and object files
make cleanall   # Also remove output data files
```

## Requirements

- `gfortran` (tested with GCC 12.1.0)
- No external libraries required

On NCCS Discover, the compiler module must be loaded before building AND running (see `memory/KNOWN_ISSUES.md`).

## Test Configuration

The test uses a small grid for fast validation:

| Parameter | Value |
|-----------|-------|
| `nlon` | 8 |
| `nlat` | 4 |
| `nlev` | 5 |

### Held-Suarez Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `t_zero` | 315 K | Equatorial equilibrium temperature |
| `t_strat` | 200 K | Stratospheric temperature |
| `delh` | 60 K | Equator-pole temperature difference |
| `delv` | 10 K | Static stability parameter |
| `eps` | 0 K | Hemispheric asymmetry |
| `P00` | 1e5 Pa | Reference pressure |
| `KAPPA` | 2/7 | R/cp |
| `sigma_b` | 0.7 | Boundary layer top |
| `ka` | 40 days | Atmospheric damping timescale |
| `ks` | 4 days | Surface damping timescale |

### Test Grid

**Sigma levels:** `[0.2, 0.5, 0.75, 0.9, 1.0]`
- Levels 1-2: above boundary layer (σ < 0.7) → damping = ka
- Levels 3-5: in boundary layer (σ > 0.7) → damping varies with latitude

**Latitudes:** `[-45°, -15°, 15°, 45°]`
- Covers mid-latitudes in both hemispheres
- Tests latitude-dependent Teq and damping

## Output Files

All files are raw binary, double precision (8 bytes per value), Fortran column-major order.

### Inputs
| File | Shape | Description |
|------|-------|-------------|
| `input_lat.bin` | (8, 4) | Latitude (radians) |
| `input_ps.bin` | (8, 4) | Surface pressure (Pa) |
| `input_p_full.bin` | (8, 4, 5) | Pressure at full levels (Pa) |
| `input_t.bin` | (8, 4, 5) | Temperature (K) |

### Parameters
| File | Contents |
|------|----------|
| `params.bin` | `nlon, nlat, nlev` (3 × int32), then 10 × float64: `t_zero, t_strat, delh, delv, eps, P00, KAPPA, tka, tks, sigma_b` |

### Outputs
| File | Shape | Description |
|------|-------|-------------|
| `output_tdt.bin` | (8, 4, 5) | Temperature tendency (K/s) |
| `output_teq.bin` | (8, 4, 5) | Equilibrium temperature (K) |

## Reading Output in Python

```python
import numpy as np

# Read 2D array (Fortran order)
lat = np.fromfile('input_lat.bin', dtype=np.float64).reshape((8, 4), order='F')

# Read 3D array (Fortran order)
tdt = np.fromfile('output_tdt.bin', dtype=np.float64).reshape((8, 4, 5), order='F')
teq = np.fromfile('output_teq.bin', dtype=np.float64).reshape((8, 4, 5), order='F')

# Read parameters
with open('params.bin', 'rb') as f:
    dims = np.fromfile(f, dtype=np.int32, count=3)
    nlon, nlat, nlev = dims
    params = np.fromfile(f, dtype=np.float64, count=10)
    t_zero, t_strat, delh, delv, eps, P00, KAPPA, tka, tks, sigma_b = params
```

## Expected Behavior

### Equilibrium Temperature (Teq)

1. **At equator (lat=0), surface (σ=1, p=P00):** `Teq ≈ t_zero = 315 K`
2. **At poles (lat=±90°):** `Teq` capped at `t_strat = 200 K` in stratosphere
3. **Vertical structure:** Teq decreases with height following `p^κ` profile

### Damping Coefficient (kT)

1. **Above boundary layer (σ ≤ 0.7):** `kT = tka` everywhere
2. **In boundary layer (σ > 0.7):**
   - At equator: `kT` increases from `tka` to `tks` (fast damping)
   - At poles: `kT ≈ tka` (cos⁴(lat) → 0)

### Temperature Tendency (tdt)

1. **Sign:** If `T > Teq`, then `tdt < 0` (cooling)
2. **Magnitude:** Proportional to `|T - Teq|` and damping rate `kT`

## Validation Criteria

When comparing C++ output to Fortran reference:
- Relative tolerance: `1e-14` (double precision)
- Absolute tolerance: `1e-20` (for values near zero)

```python
np.allclose(cpp_tdt, fortran_tdt, rtol=1e-14, atol=1e-20)
np.allclose(cpp_teq, fortran_teq, rtol=1e-14, atol=1e-20)
```
