# Held-Suarez CUDA Forcing POC Report

Date: 2026-06-15

## Purpose

This CUDA work is a proof of the Fortran -> C -> CUDA architecture, not a
speedup target.  Prior profiling/source inspection indicated that Held-Suarez
forcing is too small to produce meaningful full-model speedup by itself.

The existing public interfaces are preserved:

- No change to the Fortran wrapper public interface.
- No change to the C ABI seen by Fortran.
- The CPU C++ forcing path remains the default.
- CUDA is selected only at runtime with `HS_FORCE_BACKEND=cuda` and only when
  the library is built with `USE_CUDA_HS_FORCE=1`.

## Files Added Or Changed

Added CUDA backend:

- `translated/held_suarez/cuda/forcing_module/hs_forcing_cuda.h`
- `translated/held_suarez/cuda/forcing_module/hs_forcing_cuda.cu`
- `translated/held_suarez/cuda/forcing_module/hs_forcing_cuda_kernels.cuh`
- `translated/held_suarez/cuda/forcing_module/validate_hs_forcing_cuda.cpp`

Changed existing forcing module:

- `translated/held_suarez/cpp/forcing_module/src/held_suarez_c_api.cpp`
  - Added `HS_FORCE_BACKEND=cpu|cuda` runtime selection.
  - CPU remains default.
  - `HS_FORCE_BACKEND=cuda` fails clearly if the library was not built with
    CUDA support.
- `translated/held_suarez/cpp/forcing_module/Makefile`
  - Added optional `USE_CUDA_HS_FORCE=1` build path using `nvcc`.
  - CPU-only build remains the default.
- `hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py`
  - Builds `libhs_forcing.a` with CUDA support when
    `USE_CUDA_HS_FORCE=1`.
  - Selects the CUDA hybrid mkmf template for the final model link.
- `src/extra/python/isca/templates/mkmf.template.hybrid_cuda`
  - Adds `-lcudart` for CUDA-enabled hybrid executable linking.
- `run_compile_hybrid.sh`
  - Propagates `USE_CUDA_HS_FORCE` and `NVCC` into the container build.

Added hybrid CUDA run wrappers:

- `hybrid_experiments/held_suarez_cpp_force/run_hybrid_1day_cuda.sh`
- `hybrid_experiments/held_suarez_cpp_force/run_hybrid_30day_cuda.sh`

## Backend Selection

Default:

```bash
unset HS_FORCE_BACKEND
# or
export HS_FORCE_BACKEND=cpu
```

CUDA:

```bash
export HS_FORCE_BACKEND=cuda
```

If CUDA is requested from a CPU-only build, the C API returns
`HS_ERROR_INVALID_CONFIG` and prints:

```text
HS forcing backend error: HS_FORCE_BACKEND=cuda requested, but libhs_forcing was built without USE_CUDA_HS_FORCE=1.
```

There is no silent CPU fallback when CUDA is explicitly requested.

## CUDA Scope

Implemented in the CUDA POC:

- Standard Held-Suarez equilibrium mode.
- Rayleigh wind damping.
- Newtonian temperature damping.
- Accumulation into `udt`, `vdt`, `tdt`.
- Optional `mask` handling.
- Explicit `cudaMalloc`, `cudaMemcpy`, `cudaFree`.
- `cudaGetLastError` and `cudaDeviceSynchronize` checks after kernel launches.

Not implemented in the CUDA POC:

- Top-down equilibrium mode.
- Energy-conserving forcing path.
- Persistent device allocations.
- Managed memory.
- Device-resident model state.
- Performance-oriented kernel fusion beyond basic in-kernel accumulation.

Unsupported CUDA modes return `HS_ERROR_INVALID_CONFIG` with a clear error.

## Build Commands

CPU-only build:

```bash
cd translated/held_suarez/cpp/forcing_module
make clean
make all
```

CUDA-enabled build:

```bash
cd translated/held_suarez/cpp/forcing_module
make clean
make USE_CUDA_HS_FORCE=1 all cuda_test
```

CUDA-enabled native hybrid executable build through the existing container
wrapper:

```bash
USE_CUDA_HS_FORCE=1 ./run_compile_hybrid.sh
```

If `nvcc` is not named `nvcc` in the container, pass it explicitly:

```bash
USE_CUDA_HS_FORCE=1 NVCC=/path/to/nvcc ./run_compile_hybrid.sh
```

The CUDA hybrid build uses:

```text
src/extra/python/isca/templates/mkmf.template.hybrid_cuda
```

which adds `-lcudart` to the final model link.

CUDA-enabled standalone validation:

```bash
cd translated/held_suarez/cpp/forcing_module
./bin/validate_hs_forcing_cuda ../../../../tests/fortran_baseline 1e-12
```

Expected validation output includes:

```text
udt: max_abs=... rms=... mismatches=... tolerance=1e-12
vdt: max_abs=... rms=... mismatches=... tolerance=1e-12
tdt: max_abs=... rms=... mismatches=... tolerance=1e-12
teq: max_abs=... rms=... mismatches=... tolerance=1e-12
CUDA forcing validation status: PASS
```

## Hybrid CUDA Commands

After building the hybrid executable against the CUDA-enabled
`libhs_forcing.a`, run a 1-day smoke test:

```bash
hybrid_experiments/held_suarez_cpp_force/run_hybrid_1day_cuda.sh \
  2>&1 | tee logs/hybrid_cuda_1day.log
```

Then run a 30-day CUDA hybrid test:

```bash
hybrid_experiments/held_suarez_cpp_force/run_hybrid_30day_cuda.sh \
  2>&1 | tee logs/hybrid_cuda_30day.log
```

Equivalent explicit command:

```bash
HS_FORCE_BACKEND=cuda python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --days 1 \
  --production-diag \
  --overwrite
```

## Local Verification Status

This shell does not have `nvcc`, so the CUDA-enabled build and CUDA validation
were not run here.

Verified locally:

```bash
cd translated/held_suarez/cpp/forcing_module
make -B all
```

Result:

- CPU-only build succeeded.
- Existing CPU forcing path still builds.

Verified CPU-only CUDA-request behavior:

```bash
cd translated/held_suarez/cpp/forcing_module
make -B cuda_test
./bin/validate_hs_forcing_cuda ../../../../tests/fortran_baseline 1e-12
```

Result:

```text
CUDA forcing validation grid: 8 x 4 x 5
HS forcing backend error: HS_FORCE_BACKEND=cuda requested, but libhs_forcing was built without USE_CUDA_HS_FORCE=1.
CUDA backend failed with status -3
```

This is the expected behavior for a CPU-only build.

Standalone CUDA validation status:

```text
Not run in this shell: nvcc unavailable.
```

Container CUDA build attempt:

```bash
USE_CUDA_HS_FORCE=1 ./run_compile_hybrid.sh
```

Result:

```text
USE_CUDA_HS_FORCE= 1
NVCC=
nvcc -O2 -std=c++17 -Iinclude -I../../cuda/forcing_module -c ../../cuda/forcing_module/hs_forcing_cuda.cu -o build/hs_forcing_cuda.o
make: nvcc: No such file or directory
```

Status:

```text
Blocked: the current Isca Apptainer container does not provide nvcc on PATH.
```

The build helper now preflights `NVCC` when `USE_CUDA_HS_FORCE=1` is requested
and will fail early with a direct message if the CUDA compiler is missing.

1-day hybrid CUDA run status:

```text
Not run: CUDA-enabled hybrid executable has not been built because nvcc is
missing in the current container.
```

30-day hybrid CUDA run status:

```text
Not attempted. Run only after the 1-day CUDA smoke test passes.
```

## CUDA Kernel Candidates

Implemented kernels:

- `rayleigh_accumulate_kernel`
  - Flat 1D kernel over `nlon * nlat * nlev`.
  - Computes Rayleigh tendencies and accumulates into `udt`, `vdt`.
- `newtonian_accumulate_kernel`
  - Flat 1D kernel over `nlon * nlat * nlev`.
  - Computes latitude-dependent terms locally, computes `teq`, and accumulates
    `tdt`.

The implementation intentionally keeps all device allocations local to each
forcing call.  This validates architecture but is not optimized.

## Correctness Tolerance

Suggested standalone tolerance:

```text
1e-12
```

The CUDA path recomputes latitude-dependent terms inside the 3D Newtonian
kernel rather than using the CPU implementation's separate 2D precompute arrays.
Small floating-point differences are therefore possible even with double
precision.

## Known Limitations

- This CUDA backend is not expected to speed up the full model.
- CPU/GPU transfers are done each forcing call.
- The rest of the model remains on CPU.
- Device allocation/free is done each forcing call.
- Only standard Held-Suarez forcing is implemented.
- Top-down and energy-conserving modes are unsupported in CUDA.
- The CPU path remains the reference implementation.
- This is a proof of the Fortran -> C -> CUDA architecture.
- Future performance work should target larger dynamics/state-update modules.

## Expected Performance Impact

Expected end-to-end performance impact: negligible.

Reasons:

- Held-Suarez forcing is a small fraction of the model workload.
- The CUDA POC copies all inputs and outputs every forcing call.
- Kernel launch and transfer overhead can dominate the small forcing kernels.
- Rayleigh damping and accumulation are memory-bound.
- The Newtonian vertical loop has `log`/`pow` work, but the total problem size
  is still modest.

The value of this POC is architectural:

```text
Fortran model -> ISO_C_BINDING wrapper -> C ABI -> C++ backend selection -> CUDA kernels
```

## Recommended Next Performance Target

For actual GPU speedup work, profile and port a larger timestep/dynamics module:

1. `four_in_one` in `src/atmos_spectral/model/spectral_dynamics.F90`
2. `press_and_geopot_mod` in `src/atmos_spectral/model/press_and_geopot.F90`
3. `vert_advection_mod` in `src/atmos_shared/vert_advection/vert_advection.F90`

These have larger grid/vertical loops and are more representative of future
GEOS GPU-portability work.
