# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the GFDL FV3 (Finite-Volume Cubed-Sphere) dynamical core for atmospheric modeling, integrated with the Isca climate modeling framework. It combines:
- **FV3 dynamical core**: NOAA/GFDL's finite-volume atmospheric dynamics solver
- **GFDL Microphysics**: Cloud microphysics parameterizations  
- **Isca framework**: Python-based experiment management for idealized climate simulations

## Build System

### CMake Build (GEOS/MAPL Integration)
The top-level `CMakeLists.txt` builds FV3 as part of the GEOS ecosystem using ESMA/ecBuild:
```bash
# Requires MAPL, FMS, ESMF, and GFTL dependencies
# FV_PRECISION controls floating-point precision: R4, R4R8, or R8
# Key preprocessor defines: MAPL_MODE, SPMD, TIMING, MOIST_CAPPA, USE_COND
```

### Isca Build (Standalone Experiments)
For standalone idealized experiments using Isca:

**Required Environment Variables:**
```bash
export GFDL_BASE=/path/to/this/repo   # Source code location
export GFDL_WORK=/path/to/workdir     # Compilation and run working directory  
export GFDL_DATA=/path/to/output      # Experiment output directory
export GFDL_ENV=docker                # Environment config (see src/extra/env/)
```

**Install Python package:**
```bash
pip install -e src/extra/python
```

**Compile and run via Python:**
```python
from isca import DryCodeBase, Experiment, GFDL_BASE
cb = DryCodeBase.from_directory(GFDL_BASE)
cb.compile()  # Builds to $GFDL_WORK/codebase
```

### Docker Build
```bash
docker build -f requirements/Dockerfile -t isca .
```

## Architecture

### FV3 Dynamical Core (`model/`)
- `fv_dynamics.F90`: Top-level dynamics driver, executes on dt_atmos loop
- `dyn_core.F90`: Core dynamics solver
- `sw_core.F90`, `tp_core.F90`: Shallow-water and transport core algorithms
- `nh_core.F90`, `nh_utils.F90`: Non-hydrostatic extensions
- `fv_mapz.F90`: Vertical remapping (Lagrangian-to-Eulerian)
- `lin_cloud_microphys.F90`: GFDL cloud microphysics

### Grid and Parallelization (`tools/`)
- `fv_mp_mod.F90`: MPI parallelization and domain decomposition
- `fv_grid_tools.F90`: Cubed-sphere grid construction
- `fv_eta.F90`: Vertical coordinate definitions

### GEOS Utilities (`geos_utils/`)
- `cub2latlon.F90`, `cub2cub.F90`: Grid interpolation routines
- `ghost_cubsph.F90`: Halo exchange for cubed-sphere

### Isca Python Framework (`src/extra/python/isca/`)
- `codebase.py`: `IscaCodeBase`, `DryCodeBase`, etc. - compilation management
- `experiment.py`: `Experiment` class - namelist, diagnostics, run orchestration
- `diagtable.py`: Diagnostic output table configuration

### Environment Configs (`src/extra/env/`)
Platform-specific compiler settings. Set `GFDL_ENV` to match your system (e.g., `docker`, `ubuntu_conda`, `gfortran`).

## Running Experiments

**Held-Suarez test case:**
```bash
./run_held_suarez.sh  # Runs via Apptainer container
# Or directly:
cd exp/test_cases/held_suarez
python3 held_suarez_test_case.py
```

The Python script defines namelists, diagnostic tables, and resolution, then calls `cb.compile()` and `exp.run()`.

## Postprocessing

**Combine distributed output files:**
```bash
cd postprocessing
./compile_mppn.sh      # Compile mppnccombine tool
./mppnccombine_run.sh  # Combine output
```

## Key Conventions

- Fortran source uses `.F90` extension with preprocessor directives
- `path_names` file lists source files for mkmf-based builds
- Build templates in `bin/mkmf.template.*` and `src/extra/python/isca/templates/`
- Experiments write to `$GFDL_DATA/<exp_name>/`
- Uses 8-byte reals by default (`-fdefault-real-8`)

## Branches

- `geos/main`: Main integration branch for GEOS
- `geos/develop`: Development branch
- `geos/release/MAPL-v3`: MAPL v3 release branch

---

## Held-Suarez Test Case: Fortran Architecture

The Held-Suarez (1994) benchmark is an idealized atmospheric dynamics test using spectral transforms with simplified physics (Newtonian relaxation + Rayleigh friction). This section documents the Fortran module hierarchy for porting to C/C++/CUDA.

### Call Flow Overview

```
Python Driver (held_suarez_test_case.py)
    │
    └── Fortran Executable (fms_moist.x or similar)
            │
            ├── atmosphere_mod (src/atmos_spectral/driver/solo/atmosphere.F90)
            │       │
            │       ├── spectral_dynamics_mod  ──► Time integration & spectral dynamics
            │       │       │
            │       │       ├── transforms_mod          ──► Grid ↔ Spectral transforms
            │       │       ├── leapfrog_mod            ──► Time stepping (Robert filter)
            │       │       ├── implicit_mod            ──► Semi-implicit corrections
            │       │       ├── spectral_damping_mod    ──► Hyperdiffusion
            │       │       └── press_and_geopot_mod    ──► Pressure/height calculations
            │       │
            │       └── hs_forcing_mod  ──► Held-Suarez physics (the main forcing)
            │               │
            │               ├── newtonian_damping()     ──► Temperature relaxation
            │               └── rayleigh_damping()      ──► Boundary layer friction
            │
            └── FMS library (time_manager, diag_manager, mpp, etc.)
```

### Module Dependency Graph for Isolation

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    PHYSICS LAYER (Easiest to isolate)                   │
├─────────────────────────────────────────────────────────────────────────┤
│  hs_forcing_mod (src/atmos_param/hs_forcing/hs_forcing.F90)             │
│    - newtonian_damping(): T relaxation to equilibrium profile           │
│    - rayleigh_damping(): u,v friction in boundary layer                 │
│    - No spectral transforms, pure grid-point calculations               │
│    - Dependencies: constants_mod, time_manager_mod                      │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    DYNAMICS LAYER (Core numerical algorithms)           │
├─────────────────────────────────────────────────────────────────────────┤
│  spectral_dynamics_mod (src/atmos_spectral/model/spectral_dynamics.F90) │
│    - Main dynamics driver, couples spectral ↔ grid                      │
│    - Manages vorticity/divergence, temperature, tracers                 │
│                                                                         │
│  leapfrog_mod (src/atmos_spectral/model/leapfrog.F90)                   │
│    - Robert-Asselin-Williams (RAW) filtered leapfrog time stepping      │
│    - Works on complex spectral coefficients                             │
│    - Key function: leapfrog_3d_complex()                                │
│                                                                         │
│  implicit_mod (src/atmos_spectral/model/implicit.F90)                   │
│    - Semi-implicit treatment of gravity waves                           │
│    - Matrix inversions for vertical structure                           │
│                                                                         │
│  spectral_damping_mod (src/atmos_spectral/model/spectral_damping.F90)   │
│    - Hyperdiffusion (∇⁴ or ∇⁸) for numerical stability                  │
│    - Applied in spectral space                                          │
│                                                                         │
│  press_and_geopot_mod (src/atmos_spectral/model/press_and_geopot.F90)   │
│    - Compute pressure levels from surface pressure                      │
│    - Compute geopotential heights (hydrostatic integration)             │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    TRANSFORM LAYER (Heavy computation)                  │
├─────────────────────────────────────────────────────────────────────────┤
│  transforms_mod (src/atmos_spectral/tools/transforms.F90)               │
│    - Master interface for all transform operations                      │
│    - trans_grid_to_spherical(), trans_spherical_to_grid()               │
│                                                                         │
│  spherical_fourier_mod (src/atmos_spectral/tools/spherical_fourier.F90) │
│    - Spherical harmonics ↔ Fourier coefficients                         │
│    - Legendre transforms (latitude direction)                           │
│    - Uses precomputed Legendre polynomials                              │
│                                                                         │
│  grid_fourier_mod (src/atmos_spectral/tools/grid_fourier.F90)           │
│    - Grid ↔ Fourier transforms (longitude direction)                    │
│    - FFT operations                                                     │
│                                                                         │
│  spherical_mod (src/atmos_spectral/tools/spherical.F90)                 │
│    - Spectral-space operators (no transforms)                           │
│    - compute_laplacian(), compute_gradient_cos()                        │
│    - compute_vor_div() - vorticity/divergence from u,v                  │
│    - Eigenvalues of Laplacian on sphere                                 │
│                                                                         │
│  gauss_and_legendre_mod (src/atmos_spectral/tools/gauss_and_legendre.F90)│
│    - Gaussian quadrature points and weights                             │
│    - Legendre polynomial recurrence                                     │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    FMS INFRASTRUCTURE (External dependency)             │
├─────────────────────────────────────────────────────────────────────────┤
│  constants_mod    - Physical constants (grav, rdgas, cp_air, etc.)      │
│  mpp_mod          - MPI parallelization                                 │
│  time_manager_mod - Time stepping and calendar                          │
│  diag_manager_mod - Diagnostic output                                   │
│  fms_mod          - File I/O, namelist parsing                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Computational Kernels (Targets for C++/CUDA)

#### 1. Held-Suarez Forcing (`hs_forcing_mod`)
**File:** `src/atmos_param/hs_forcing/hs_forcing.F90`
**Lines:** 508-611 (newtonian_damping), 615-679 (rayleigh_damping)

**Newtonian Damping** - Temperature relaxation:
```fortran
! Equilibrium temperature profile (Held-Suarez 1994 Eq. 1-2)
teq = max(T_strat, T_eq * (p/p0)^kappa)
! Temperature tendency
tdt = -k_T * (T - teq)
```

**Rayleigh Damping** - Boundary layer friction:
```fortran
! Only active where sigma > sigma_b (near surface)
udt = -k_v * u * max(0, (sigma - sigma_b)/(1 - sigma_b))
vdt = -k_v * v * max(0, (sigma - sigma_b)/(1 - sigma_b))
```

**Data structures:** 2D/3D arrays indexed (i,j,k) for lon, lat, level.

#### 2. Leapfrog Time Stepping (`leapfrog_mod`)
**File:** `src/atmos_spectral/model/leapfrog.F90`
**Lines:** 217-247 (leapfrog_3d_complex)

```fortran
! RAW-filtered leapfrog (Williams 2011)
a_future = a_previous + 2*dt * da/dt
a_current += robert_coeff * (a_prev - 2*a_curr + a_future)
```

**Data structures:** Complex 3D arrays for spectral coefficients.

#### 3. Spectral Transforms (`transforms_mod`, `spherical_fourier_mod`)
**Files:** 
- `src/atmos_spectral/tools/transforms.F90`
- `src/atmos_spectral/tools/spherical_fourier.F90`

Two-step transform:
1. **Longitude (FFT):** Grid → Fourier coefficients
2. **Latitude (Legendre):** Fourier → Spherical harmonics

**GPU-friendly:** FFTs are well-suited for CUDA (cuFFT). Legendre transforms involve matrix-vector products.

#### 4. Spectral Operators (`spherical_mod`)
**File:** `src/atmos_spectral/tools/spherical.F90`

```fortran
! Laplacian eigenvalue: -n(n+1)/a^2
! Gradient, divergence, vorticity via spectral derivatives
```

### Isolation Strategy for Unit Testing

**Tier 1 - Pure Grid-Point Physics (No transforms):**
- `hs_forcing_mod`: newtonian_damping, rayleigh_damping
- Input: lat, p_full, T, u, v arrays
- Output: tdt, udt, vdt tendencies
- **Test:** Compare against reference Fortran output for fixed inputs

**Tier 2 - Spectral Operators (No transforms):**
- `spherical_mod`: compute_laplacian, compute_gradient_cos
- Input: Complex spectral arrays
- Output: Spectral derivatives
- **Test:** Verify eigenvalues, compare with analytic solutions

**Tier 3 - Time Integration:**
- `leapfrog_mod`: Time stepping with Robert filter
- Input: Previous/current spectral states, tendencies
- Output: Future state
- **Test:** Energy conservation, filter stability

**Tier 4 - Transforms (Most complex):**
- `transforms_mod`, `spherical_fourier_mod`, `grid_fourier_mod`
- Input: Grid fields or spectral coefficients
- Output: Transformed fields
- **Test:** Round-trip identity (grid→spectral→grid ≈ grid)

### Data Structures Summary

| Variable | Dimensions | Type | Description |
|----------|------------|------|-------------|
| `ug, vg, tg` | (lon, lat, lev, time) | real | Grid-point winds, temperature |
| `vors, divs, ts` | (m, n, lev, time) | complex | Spectral vorticity, divergence, temp |
| `p_full, p_half` | (lon, lat, lev) | real | Pressure at full/half levels |
| `teq` | (lon, lat, lev) | real | Equilibrium temperature |

### Namelist Parameters (hs_forcing_nml)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `t_zero` | 315 K | Equatorial equilibrium temperature |
| `t_strat` | 200 K | Stratospheric temperature |
| `delh` | 60 K | Equator-pole temperature difference |
| `delv` | 10 K | Static stability parameter |
| `sigma_b` | 0.7 | Boundary layer top (p/ps) |
| `ka` | -40 days | Atmospheric relaxation timescale |
| `ks` | -4 days | Surface relaxation timescale |
| `kf` | -1 day | Rayleigh friction timescale |

### Build Dependencies for Standalone Testing

To extract and test modules independently:
1. **Minimal FMS stub:** Provide constants_mod, mpp stubs
2. **Remove I/O:** Strip diag_manager, fms_io dependencies
3. **Single-processor:** Remove MPI domain decomposition
