# FV Advection Multi-GPU Mapping Implementation Report

## Summary

Implemented node-aware CUDA device selection for the FV advection CUDA backend.

The change is contained in:

```text
translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu
```

No production Fortran source was modified. The public Fortran/C/CUDA API was not
changed.

## Runtime Controls

New optional environment variables:

```text
FV_KERNELS_GPU_MAPPING=local_rank
FV_KERNELS_GPU_MAPPING=round_robin
FV_KERNELS_GPU_MAPPING=env
FV_KERNELS_GPU_ID=<device_id>
FV_KERNELS_REQUIRE_UNIQUE_GPU=1
```

Recommended multi-GPU setting:

```bash
export FV_KERNELS_GPU_MAPPING=local_rank
```

Optional strict one-rank-per-GPU check:

```bash
export FV_KERNELS_REQUIRE_UNIQUE_GPU=1
```

If `FV_KERNELS_GPU_MAPPING` is unset, the backend preserves the previous default
behavior by using the current CUDA device when available, otherwise device `0`.

## Local Rank Detection

The implementation derives local rank from launch environment variables, in
this order:

```text
OMPI_COMM_WORLD_LOCAL_RANK
SLURM_LOCALID
MV2_COMM_WORLD_LOCAL_RANK
PMI_LOCAL_RANK
```

If none are present, it falls back to the global rank, or `0` if no rank
environment is available. This avoids linking the CUDA helper library directly
against MPI and keeps the existing ABI unchanged.

Global rank is detected from:

```text
OMPI_COMM_WORLD_RANK
PMI_RANK
SLURM_PROCID
MPI_RANKID
```

## Mapping Policies

### `local_rank`

```text
device = local_rank % visible_gpus
```

This is the recommended policy for single-node and multi-node GPU runs.

### `round_robin`

```text
device = global_rank % visible_gpus
```

Useful for quick single-node testing, but not recommended for multi-node runs.

### `env`

```text
device = FV_KERNELS_GPU_ID
```

Useful for manual debugging.

## Initialization Path

CUDA device initialization now happens before any CUDA allocation:

```text
ensure_cuda_device_initialized()
  -> cudaGetDeviceCount
  -> detect global rank
  -> detect local rank
  -> choose device
  -> cudaSetDevice
  -> cudaGetDevice
  -> cudaGetDeviceProperties
  -> cudaMemGetInfo
  -> print mapping and memory markers
```

This gate is used by:

- persistent/resident buffer initialization;
- stateless CUDA allocation path.

## Log Markers

Each process prints one mapping marker:

```text
PROFILE_FV_GPU_MAPPING rank=<rank> local_rank=<local_rank> device=<device> visible_gpus=<n> hostname=<host> name="<gpu_name>" pci_bus_id=<id> policy=<policy> strict_unique=<0|1> cuda_visible_devices=<value>
```

Each process also prints one memory marker:

```text
PROFILE_FV_GPU_MEMORY rank=<rank> device=<device> free_before=<bytes> total=<bytes>
```

These markers are printed even if `FV_KERNELS_PROFILE` is not set, because they
are configuration diagnostics rather than performance counters.

## Recommended Build Command

Inside the Isca/CUDA container:

```bash
USE_CUDA_FV_ADVECTION_KERNELS=1 ./run_compile_fv_kernels.sh \
  2>&1 | tee logs/fv_kernels_multigpu_mapping_compile.log
```

## Recommended Smoke Test

Use the existing validated resident `a_grid` configuration plus local-rank GPU
mapping:

```bash
export FV_KERNELS_CUDA_MODE=resident
export FV_KERNELS_RESIDENT_BOUNDARY=a_grid
export FV_KERNELS_RESIDENT_STATIC_METRICS=1
export FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only
export FV_KERNELS_PROFILE=1
export FV_KERNELS_GPU_MAPPING=local_rank
export FV_KERNELS_REQUIRE_UNIQUE_GPU=1
```

Then run a 1-day smoke test with a dedicated experiment name, for example:

```bash
python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name held_suarez_fv_kernels_cuda.x \
  --exp-name held_suarez_fv_kernels_cuda_a_grid_multigpu_1day \
  --days 1 \
  --production-diag \
  --num-cores 16 \
  --overwrite \
  2>&1 | tee logs/fv_kernels_cuda_a_grid_multigpu_1day.log
```

## What To Check

In the run log:

```bash
rg "PROFILE_FV_GPU_MAPPING|PROFILE_FV_GPU_MEMORY|Run 1 complete" \
  logs/fv_kernels_cuda_a_grid_multigpu_1day.log
```

Expected for one rank per GPU:

- 16 `PROFILE_FV_GPU_MAPPING` lines;
- local ranks `0..15`;
- visible GPUs at least `16`, unless the scheduler maps each process to a
  single logical GPU through `CUDA_VISIBLE_DEVICES`;
- no duplicate physical GPU assignments when strict mode is used;
- `Run 1 complete`.

If the scheduler exposes one logical GPU per rank, the marker may show:

```text
device=0 visible_gpus=1 cuda_visible_devices=<rank-specific GPU id>
```

That can still be correct if `CUDA_VISIBLE_DEVICES` differs by rank.

## Next Performance Run

After the 1-day smoke test passes, run the 30-day multi-GPU comparison:

```bash
python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name held_suarez_fv_kernels_cuda.x \
  --exp-name held_suarez_fv_kernels_cuda_a_grid_multigpu_30day \
  --days 30 \
  --production-diag \
  --num-cores 16 \
  --overwrite \
  2>&1 | tee logs/fv_kernels_cuda_a_grid_multigpu_30day.log
```

Compare against:

```text
CPU C++ FV bundle:        25.546 s MPP
single-GPU a_grid CUDA:   51.000 s MPP
```

Target:

```text
MPP runtime < 35 s
```

## Validation

After the 30-day run, validate NetCDF output against the existing all-Fortran
and CPU C++ FV bundle references:

```bash
python3 tests/validate_T85L25_forcing_outputs.py \
  --fortran-exp held_suarez_default \
  --cpu-exp held_suarez_fv_kernels_30day \
  --cuda-exp held_suarez_fv_kernels_cuda_a_grid_multigpu_30day \
  --run 1 \
  --filename atmos_monthly.nc \
  --data-root /explore/nobackup/people/jli30/SystemTesting/Isca/isca_data \
  --markdown-out tests/reports/fv_advection_a_grid_multigpu_30day_validation.md \
  --json-out tests/reports/fv_advection_a_grid_multigpu_30day_validation.json
```

## Notes

The implementation does not use `MPI_Comm_split_type` directly, because the CUDA
helper library currently does not link against MPI and the Fortran/C API does
not pass communicator handles. Environment-based local-rank detection is the
smallest non-invasive implementation and matches the current overlay strategy.

If environment-based detection is insufficient on a target system, the next
step would be to add a tiny optional initialization C API that accepts global
rank and local rank from Fortran/MPI code, while keeping the existing kernel
entry points unchanged.
