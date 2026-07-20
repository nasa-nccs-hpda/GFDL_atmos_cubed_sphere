# Multi-GPU Runtime Checkpoint - 2026-07-20

## Objective

Evaluate whether better MPI-to-GPU mapping improves the Held-Suarez FV advection
CUDA resident `a_grid` runtime.

The baseline before this experiment was:

```text
T42L25, 30 days, 16 MPI ranks, 1 GPU shared
held_suarez_fv_kernels_cuda.x
FV_KERNELS_CUDA_MODE=resident
FV_KERNELS_RESIDENT_BOUNDARY=a_grid
FV_KERNELS_RESIDENT_STATIC_METRICS=1
FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only
```

## Code Changes

Implemented node-aware CUDA GPU assignment in:

```text
translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu
```

Added runtime controls:

```text
FV_KERNELS_GPU_MAPPING=local_rank
FV_KERNELS_GPU_MAPPING=round_robin
FV_KERNELS_GPU_MAPPING=env
FV_KERNELS_GPU_ID=<device_id>
FV_KERNELS_REQUIRE_UNIQUE_GPU=1
```

The recommended multi-node mode is:

```text
FV_KERNELS_GPU_MAPPING=local_rank
```

For one rank per node/GPU:

```text
FV_KERNELS_REQUIRE_UNIQUE_GPU=1
```

For multiple ranks sharing one GPU per node:

```text
unset FV_KERNELS_REQUIRE_UNIQUE_GPU
```

Added diagnostic markers:

```text
PROFILE_FV_GPU_MAPPING
PROFILE_FV_GPU_MEMORY
```

No production Fortran source was modified.

## Utility Script

Created:

```text
build_sandbox.sh
```

Purpose:

```text
Check /lscratch/jli30/isca-sandbox on each allocated Slurm node and build it
only where missing using:

singularity build --sandbox /lscratch/jli30/isca-sandbox docker://nasanccs/isca-debian:latest
```

Usage inside a Slurm allocation:

```bash
./build_sandbox.sh
```

## Documentation Added

```text
docs/fv_advection_multi_gpu_mpi_cuda_plan.md
docs/fv_advection_multi_gpu_mapping_implementation_report.md
```

## Completed Runs

### 4 nodes / 4 GPUs / 4 MPI ranks

Configuration:

```text
1 rank per node
1 GPU per node
FV_KERNELS_REQUIRE_UNIQUE_GPU=1
```

Log:

```text
logs/fv_kernels_cuda_a_grid_4node_4gpu_manual_30day.log
```

Result:

```text
Total runtime: 96.413 s
Mapping: PASS
```

Interpretation:

```text
Too few MPI ranks and multi-node communication made this slower than the
single-node/single-GPU reference.
```

### 4 nodes / 4 GPUs / 16 MPI ranks

Configuration:

```text
4 ranks per node
4 ranks sharing each node-local GPU
FV_KERNELS_REQUIRE_UNIQUE_GPU unset
```

Log:

```text
logs/fv_kernels_cuda_a_grid_16rank_4node_4gpu_manual_30day.log
```

Result:

```text
Total runtime: 85.330 s
Mapping: PASS
CUDA region max: about 4.85 s
```

Interpretation:

```text
CUDA region improved versus 16 ranks sharing 1 GPU, but multi-node overhead
still dominated total runtime.
```

### 16 nodes / 16 GPUs / 16 MPI ranks

Configuration:

```text
1 rank per node
1 GPU per node
FV_KERNELS_REQUIRE_UNIQUE_GPU=1
```

Final successful log:

```text
logs/fv_kernels_cuda_a_grid_16node_16gpu_manual_30day_final.log
```

Result:

```text
Total runtime: 63.973 s
Mapping: PASS
CUDA resident total mean: 1.001 s
CUDA resident total max: 1.019 s
```

Mapping:

```text
16 ranks
16 hostnames
local_rank=0 for every rank
device=0 for every rank
visible_gpus=1 for every rank
strict_unique=1
```

Interpretation:

```text
GPU contention hypothesis confirmed inside the CUDA region. CUDA time dropped
from about 20.3 s in the 16-rank/1-GPU run to about 1.0 s in the
16-rank/16-GPU run.

However, total runtime is still slower than the best single-node/single-GPU
run because T42L25 multi-node MPI/domain communication dominates.
```

## Performance Summary

| Configuration | Total MPP Runtime | CUDA Region Max | Notes |
|---|---:|---:|---|
| CPU C++ FV bundle | 25.546 s | n/a | CPU reference |
| 16 ranks / 1 GPU `a_grid` CUDA | 51.000 s | about 20.3 s | best CUDA total runtime so far |
| 4 ranks / 4 nodes / 4 GPUs | 96.413 s | not primary | too few MPI ranks |
| 16 ranks / 4 nodes / 4 GPUs | 85.330 s | about 4.85 s | CUDA faster, total slower |
| 16 ranks / 16 nodes / 16 GPUs | 63.973 s | about 1.02 s | CUDA fastest, total still slower |

## Findings

1. The CUDA-region bottleneck from GPU contention is real.
2. One GPU per rank reduces CUDA resident time from about 20.3 s to about 1.0 s.
3. At T42L25, inter-node communication overhead outweighs the CUDA-region gain.
4. The best end-to-end CUDA runtime remains the 16-rank / 1-GPU `a_grid` run.
5. The 16-node / 16-GPU run is useful as a GPU-mapping validation, not yet a
   wall-clock win.

## Known Issues

The profile helper still prints:

```text
PROFILE_FV_ADVECTION_CUDA rank=unknown
```

because the rank-string helper does not yet read Slurm variables such as:

```text
SLURM_PROCID
SLURM_LOCALID
```

The GPU mapping marker does report ranks correctly.

PMIx/Munge warning messages appear during `srun` launches, for example:

```text
PMIX ERROR ... psec Component: munge
```

These were non-fatal in the successful runs.

## Current Conclusion

For T42L25:

```text
Multi-node multi-GPU mapping improves CUDA time but does not improve total model
runtime.
```

The next search for a better runtime should focus on reducing communication
overhead or increasing local GPU work per rank.

## Recommended Next Tasks

### Highest Priority

Run larger-resolution cases with the validated 16-node / 16-GPU launch:

```text
T85L25
T170L25 if feasible
```

Reason:

```text
Larger local work may amortize inter-node communication and CUDA launch overhead
better than T42L25.
```

### Medium Priority

Try fewer nodes while preserving 16 ranks only if a single node with multiple
GPUs is available:

```text
1 node / 4 GPUs / 16 ranks
1 node / 8 GPUs / 16 ranks
1 node / 16 GPUs / 16 ranks
```

The Grace nodes tested here appear to provide one GPU per node.

### Small Cleanup

Update:

```text
translated/held_suarez/cpp/fv_advection/kernels/include/fv_advection_kernel_profile.hpp
```

to include:

```text
SLURM_PROCID
```

in `rank_string()`, so CUDA performance markers no longer show
`rank=unknown`.

## Resume Instructions

1. Read this checkpoint.
2. Read:

```text
docs/fv_advection_multi_gpu_mpi_cuda_plan.md
docs/fv_advection_multi_gpu_mapping_implementation_report.md
docs/fv_advection_cuda_a_grid_performance_results.md
```

3. Use the successful 16-node launch pattern from:

```text
logs/fv_kernels_cuda_a_grid_16node_16gpu_manual_30day_final.log
```

4. Next experiment should be a larger-resolution run, preferably T85L25, using
   the same 16 ranks / 16 GPUs mapping.

5. Do not repeat container debugging unless a node-local sandbox is missing. Use:

```bash
./build_sandbox.sh
```

inside the allocation to repair missing node-local sandboxes.
