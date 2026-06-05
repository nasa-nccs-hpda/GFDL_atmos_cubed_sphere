# Rayleigh Damping Fortran Baseline Test

This directory contains a standalone Fortran test harness for the `rayleigh_damping` kernel, extracted from `hs_forcing_mod`. It generates reference data for validating C++/CUDA ports.

## Files

| File | Description |
|------|-------------|
| `rayleigh_damping_standalone.F90` | Isolated kernel (no FMS dependencies) |
| `test_harness.F90` | Test driver with synthetic data generation |
| `Makefile` | Build system |

## Quick Start

```bash
# Build
make

# Run (generates binary output files)
make run

# Clean
make clean      # Remove executables and object files
make cleanall   # Also remove output data files
```

## Requirements

- `gfortran` (tested with GCC 9+)
- No external libraries required

On NCCS Discover, load the compiler module first:
```bash
module load gcc/12.1.0
```

## Test Configuration

The test uses a small grid for fast validation:

| Parameter | Value |
|-----------|-------|
| `nlon` | 8 |
| `nlat` | 4 |
| `nlev` | 5 |
| `kf` | 1 day |
| `sigma_b` | 0.7 |

Sigma levels: `[0.2, 0.5, 0.75, 0.9, 1.0]`
- Levels 1-2: above boundary layer (σ < 0.7) → zero tendency
- Levels 3-5: in boundary layer (σ > 0.7) → damping applied

## Output Files

All files are raw binary, double precision (8 bytes per value), Fortran column-major order.

### Inputs
| File | Shape | Description |
|------|-------|-------------|
| `input_ps.bin` | (8, 4) | Surface pressure (Pa) |
| `input_p_full.bin` | (8, 4, 5) | Pressure at full levels (Pa) |
| `input_u.bin` | (8, 4, 5) | Zonal wind (m/s) |
| `input_v.bin` | (8, 4, 5) | Meridional wind (m/s) |

### Parameters
| File | Contents |
|------|----------|
| `params.bin` | `nlon, nlat, nlev` (3 × int32), `vkf, sigma_b` (2 × float64) |

### Outputs
| File | Shape | Description |
|------|-------|-------------|
| `output_udt.bin` | (8, 4, 5) | Zonal wind tendency (m/s²) |
| `output_vdt.bin` | (8, 4, 5) | Meridional wind tendency (m/s²) |

## Reading Output in Python

```python
import numpy as np

# Read 2D array (Fortran order)
ps = np.fromfile('input_ps.bin', dtype=np.float64).reshape((8, 4), order='F')

# Read 3D array (Fortran order)
udt = np.fromfile('output_udt.bin', dtype=np.float64).reshape((8, 4, 5), order='F')

# Read parameters
with open('params.bin', 'rb') as f:
    dims = np.fromfile(f, dtype=np.int32, count=3)
    params = np.fromfile(f, dtype=np.float64, count=2)
    nlon, nlat, nlev = dims
    vkf, sigma_b = params
```

## Reading Output in C++

```cpp
#include <fstream>
#include <vector>

// Read 3D array (Fortran column-major order)
std::vector<double> read_array_3d(const char* filename, int nlon, int nlat, int nlev) {
    std::vector<double> data(nlon * nlat * nlev);
    std::ifstream file(filename, std::ios::binary);
    file.read(reinterpret_cast<char*>(data.data()), data.size() * sizeof(double));
    return data;  // Index as: data[i + nlon * (j + nlat * k)]
}
```

## Expected Behavior

1. **Above boundary layer** (σ ≤ 0.7): `udt = 0`, `vdt = 0`
2. **In boundary layer** (0.7 < σ ≤ 1.0): 
   - `udt = -kv(σ) * u`
   - `vdt = -kv(σ) * v`
   - where `kv(σ) = vkf * (σ - σ_b) / (1 - σ_b)`
3. **At surface** (σ = 1.0): `kv = vkf` (maximum damping)

## Validation Criteria

When comparing C++ output to Fortran reference:
- Relative tolerance: `1e-14` (double precision)
- Absolute tolerance: `1e-20` (for values near zero)

```python
np.allclose(cpp_udt, fortran_udt, rtol=1e-14, atol=1e-20)
```
