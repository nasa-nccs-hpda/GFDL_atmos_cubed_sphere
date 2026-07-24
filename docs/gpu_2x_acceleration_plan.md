# GPU 2x Acceleration Plan

## Current Result

The verified widened FV CUDA path runs inside the full Held-Suarez executable,
but it is not enough for end-to-end speedup.

Measured 30-day timings:

```text
CPU hybrid, 16 ranks:  about 26.7 s
CUDA hybrid, 16 ranks: about 47.9 s
CUDA hybrid, 1 rank:   about 231.6 s
```

The 1-rank CUDA run proves MPI rank count is not a simple fix: the rest of the
Fortran model still needs MPI parallelism.

## Profile Interpretation

Latest CUDA FV profile:

```text
a_grid_advection_stage1 max: 10.32 s
a_grid_advection_stage2 max:  9.45 s
cuda_sync max:              16.50 s
cuda_h2d max:                1.15 s
cuda_d2h max:                0.10 s
```

Transfers are no longer the dominant issue. Kernel/synchronization overhead and
small per-rank GPU work are the dominant issue.

The CPU FV region is only about 1.4 s of the 26.7 s CPU run. Even making the FV
region free cannot produce 2x total speedup.

## Consequence

A 2x GPU speedup requires moving much larger regions than FV advection kernels.
The next target should not be another small FV helper. It should be one of:

1. Pressure/geopotential column physics.
2. Horizontal temperature advection plus tracer advection in one GPU-resident
   path.
3. `compute_corrections`.
4. Transform-heavy spectral routines using batched/vendor-library strategy.

## Next Build Target

Port `press_and_geopot_mod` next because it is column-wise, timestep-repeated,
and less MPI-entangled than transforms.

Validation ladder:

```text
Fortran fixture
-> CPU C++
-> CUDA
-> ISO_C_BINDING wrapper
-> native overlay
-> 1-day smoke
-> 30-day validation
```

2x target strategy:

```text
FV advection fused path
+ pressure/geopotential CUDA
+ correction/temperature advection CUDA
+ transform strategy
```
