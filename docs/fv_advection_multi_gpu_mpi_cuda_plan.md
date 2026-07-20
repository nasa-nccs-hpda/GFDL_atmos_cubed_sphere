# FV Advection Multi-GPU MPI-CUDA Implementation Plan

## Purpose

The single-GPU FV advection CUDA path has reached a clear architectural limit.
The latest broad `a_grid_horiz_advection_3d` resident boundary solved the
original transfer problem, but the model is still slower than CPU C++ at T42L25:

| Architecture | MPP runtime | Relative to CPU C++ | Main bottleneck |
|---|---:|---:|---|
| CPU C++ baseline | 25.546 s | 1.00x | CPU reference |
| Resident-v1 | 108.505 s | 0.24x | H2D transfer |
| Resident-v2 | 108.794 s | 0.23x | H2D transfer |
| Resident-v3 | 51.997 s | 0.49x | single-GPU contention / sync |
| `a_grid` resident | 51.000 s | 0.50x | 16 MPI ranks sharing 1 GPU |

The transfer problem is mostly solved:

```text
resident-v2 mean H2D: 50.471 s
a_grid mean H2D:       1.138 s
```

The next performance hypothesis is that 16 MPI ranks contending for one GPU are
serializing CUDA work and adding context/scheduling overhead. The next
experiment should use a better MPI-to-GPU mapping, ideally one MPI rank per GPU
or a small number of ranks per GPU.

This document is a planning document only. It does not modify production
Fortran source.

## Goals

1. Preserve the current validated `a_grid` resident CUDA path.
2. Add explicit, debuggable rank-to-GPU assignment.
3. Support single-node and multi-node GPU runs.
4. Keep CPU and previous CUDA fallback modes intact.
5. Measure whether multi-GPU mapping closes the gap to CPU C++.

Target experiment:

```text
T42L25, 30 days
16 MPI ranks
1 GPU per rank if hardware allows
```

Secondary experiments:

```text
16 ranks / 8 GPUs   = 2 ranks per GPU
16 ranks / 4 GPUs   = 4 ranks per GPU
16 ranks / 1 GPU    = current baseline comparison
T85L25 with same mapping matrix
```

## Current Single-GPU Architecture

Per MPI rank, per timestep:

```text
Fortran rank-local state on CPU
  |
  | a_grid resident pre-halo phase
  v
CUDA device:
  - upload required local fields / halo slices
  - run resident FV kernels
  - produce q1 / partial advection state
  |
  | halo-only q1 transfer
  v
CPU:
  - mpp_update_domains(q1)
  - polar correction / boundary updates
  |
  | corrected halo injection
  v
CUDA device:
  - finish resident FV kernels
  - produce dq_dt
  |
  | final output transfer
  v
CPU Fortran continues
```

The current bottleneck is no longer bulk H2D traffic. With all 16 ranks sharing
one GPU, the likely bottlenecks are:

- GPU context contention;
- CUDA work serialization across ranks;
- rank imbalance;
- launch/synchronization overhead amplified by rank sharing;
- possible CPU/GPU affinity mismatch.

## Phase 1: GPU Affinity and Basic Multi-GPU Mapping

### Runtime Mapping Modes

Add an explicit runtime switch for mapping policy:

```text
FV_KERNELS_GPU_MAPPING=local_rank
FV_KERNELS_GPU_MAPPING=round_robin
FV_KERNELS_GPU_MAPPING=env
```

Recommended default for CUDA resident runs:

```text
FV_KERNELS_GPU_MAPPING=local_rank
```

Fallback behavior:

- If unset, preserve the current behavior.
- If CUDA is requested and no GPUs are visible, fail clearly.
- If an invalid mapping policy is requested, fail clearly.

### Option 1a: Global Round-Robin

```cpp
gpu_id = mpi_rank % num_visible_gpus;
cudaSetDevice(gpu_id);
```

Pros:

- simple;
- works for single-node runs;
- useful as a fallback.

Cons:

- wrong for multi-node if `mpi_rank` is global and each node sees only local
  GPUs;
- may oversubscribe GPUs unevenly if rank placement is not contiguous per node.

Use this for quick smoke tests only.

### Option 1b: Node-Aware Local Rank Mapping

```cpp
local_rank = rank_within_node;
gpu_id = local_rank % num_visible_gpus;
cudaSetDevice(gpu_id);
```

This is the recommended first implementation.

Ways to get `local_rank`:

```text
OMPI_COMM_WORLD_LOCAL_RANK   OpenMPI
MV2_COMM_WORLD_LOCAL_RANK    MVAPICH
SLURM_LOCALID                Slurm
PMI_LOCAL_RANK               MPICH/PMI variants
```

Suggested priority:

1. `OMPI_COMM_WORLD_LOCAL_RANK`
2. `SLURM_LOCALID`
3. `MV2_COMM_WORLD_LOCAL_RANK`
4. `PMI_LOCAL_RANK`
5. fallback to global-rank round-robin with a warning

Pseudo-code:

```cpp
int detect_local_rank(int global_rank) {
    const char* names[] = {
        "OMPI_COMM_WORLD_LOCAL_RANK",
        "SLURM_LOCALID",
        "MV2_COMM_WORLD_LOCAL_RANK",
        "PMI_LOCAL_RANK"
    };
    for (const char* name : names) {
        if (const char* value = std::getenv(name)) {
            return parse_nonnegative_int_or_error(name, value);
        }
    }
    return global_rank;
}

int choose_gpu(int global_rank) {
    int num_gpus = 0;
    cudaGetDeviceCount(&num_gpus);
    if (num_gpus <= 0) {
        fail("CUDA backend requested but no visible CUDA devices were found");
    }

    std::string policy = getenv_or_default("FV_KERNELS_GPU_MAPPING", "local_rank");
    if (policy == "local_rank") {
        return detect_local_rank(global_rank) % num_gpus;
    }
    if (policy == "round_robin") {
        return global_rank % num_gpus;
    }
    if (policy == "env") {
        return parse_gpu_id_from_env();
    }
    fail("Unknown FV_KERNELS_GPU_MAPPING value");
}
```

### Option 1c: Topology-Aware Mapping

Topology-aware mapping should be deferred until basic local-rank mapping is
measured.

Possible future tools:

- Slurm GPU binding;
- `CUDA_VISIBLE_DEVICES` set by scheduler;
- OpenMPI mapping/binding options;
- hwloc / `nvidia-smi topo -m`;
- NUMA binding using `numactl` or MPI bind-to options.

Do not add hwloc as a dependency in the first implementation.

## Required Questions and Answers

### How to detect number of GPUs?

Use runtime CUDA detection:

```cpp
int count = 0;
cudaError_t err = cudaGetDeviceCount(&count);
```

Do not detect GPUs at build time. Build-time detection is brittle because the
build container and run allocation may not expose the same devices.

### How to handle `num_gpus != num_ranks`?

Use an explicit oversubscription policy.

Recommended default:

```text
allow oversubscription, but print mapping
```

Examples:

| Ranks | Visible GPUs | Mapping |
|---:|---:|---|
| 16 | 16 | one rank per GPU |
| 16 | 8 | two ranks per GPU |
| 16 | 4 | four ranks per GPU |
| 16 | 1 | current baseline |

Optional strict mode:

```text
FV_KERNELS_REQUIRE_UNIQUE_GPU=1
```

If set, fail when `local_ranks_per_node > visible_gpus`.

### What if multiple nodes are used?

Each process sees the GPUs visible on its local node. Use `local_rank`, not
global MPI rank, for the GPU index.

Run log should print:

```text
PROFILE_FV_GPU_MAPPING rank=<global_rank> local_rank=<local_rank> device=<gpu_id> visible_gpus=<n> hostname=<host>
```

This makes multi-node mapping auditable from the log.

### How to verify each rank got the intended GPU?

At CUDA initialization:

```cpp
cudaSetDevice(gpu_id);
cudaGetDevice(&current_device);
cudaGetDeviceProperties(&props, current_device);
```

Print one line per rank:

```text
PROFILE_FV_GPU_MAPPING rank=7 local_rank=7 device=7 visible_gpus=16 name="NVIDIA H100" pci_bus_id=...
```

For strict tests, parse the run log and confirm:

- all ranks printed a mapping line;
- each local rank maps to expected GPU;
- one-rank-per-GPU runs have no duplicate device assignments per node.

## Phase 2: CUDA Context Management

### Context Creation

No explicit CUDA context creation is required. CUDA creates a primary context
implicitly on first CUDA runtime call after `cudaSetDevice`.

Recommended sequence:

```cpp
void init_cuda_for_rank(int global_rank) {
    int device = choose_gpu(global_rank);
    check(cudaSetDevice(device), "cudaSetDevice");

    int current = -1;
    check(cudaGetDevice(&current), "cudaGetDevice");
    if (current != device) {
        fail("cudaSetDevice did not select requested device");
    }

    cudaDeviceProp props;
    check(cudaGetDeviceProperties(&props, current), "cudaGetDeviceProperties");

    print_mapping_line(global_rank, local_rank, current, props);

    size_t free_bytes = 0;
    size_t total_bytes = 0;
    check(cudaMemGetInfo(&free_bytes, &total_bytes), "cudaMemGetInfo");
    print_memory_line(global_rank, current, free_bytes, total_bytes);
}
```

### Failure Handling

Fail clearly if:

- CUDA backend requested but `cudaGetDeviceCount` returns zero;
- `cudaSetDevice` fails;
- requested `FV_KERNELS_GPU_ID` is outside the visible device range;
- `FV_KERNELS_REQUIRE_UNIQUE_GPU=1` and visible GPUs are fewer than local ranks;
- device memory is below a conservative threshold.

Do not silently fall back to CPU when CUDA was explicitly requested.

## Phase 3: Memory Management Per GPU

Each MPI rank already owns its resident device buffers. Multi-GPU mapping should
not require changing the data structures, only ensuring allocation happens
after the correct `cudaSetDevice`.

Expected memory at T42L25:

```text
one full rank-local array estimate: 128 * 64 * 25 * 8 = 1.6 MB
resident working set estimate:      50-100 MB per rank
16 ranks total:                     0.8-1.6 GB across GPUs
```

With one GPU per rank, this is small for modern GPUs.

Add runtime memory diagnostics:

```text
PROFILE_FV_GPU_MEMORY rank=<rank> device=<gpu_id> free_before=<bytes> total=<bytes>
PROFILE_FV_GPU_MEMORY rank=<rank> device=<gpu_id> free_after_alloc=<bytes> allocated_estimate=<bytes>
```

The buffer manager should:

- allocate on the rank's selected GPU;
- reuse persistent buffers;
- reallocate only when dimensions grow/change;
- free on finalize or process shutdown;
- include selected GPU id in error messages.

## Phase 4: Build and Runtime Detection

### Build

Do not detect GPU count during build.

Continue using the existing CUDA build path:

```bash
USE_CUDA_FV_ADVECTION_KERNELS=1 ./run_compile_fv_kernels.sh
```

The executable should be portable across allocations with different GPU counts,
as long as CUDA runtime libraries are available.

### Runtime

Use runtime environment variables:

```bash
export FV_KERNELS_CUDA_MODE=resident
export FV_KERNELS_RESIDENT_BOUNDARY=a_grid
export FV_KERNELS_RESIDENT_STATIC_METRICS=1
export FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only
export FV_KERNELS_PROFILE=1
export FV_KERNELS_GPU_MAPPING=local_rank
```

Optional strict mode:

```bash
export FV_KERNELS_REQUIRE_UNIQUE_GPU=1
```

Optional single-device override:

```bash
export CUDA_VISIBLE_DEVICES=0
```

Optional multi-device visible set:

```bash
export CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
```

On scheduler-managed GPU nodes, prefer scheduler GPU binding over manual
`CUDA_VISIBLE_DEVICES` when available.

## Proposed Data Flow With Multi-GPU Mapping

One rank per GPU:

```text
MPI rank 0  -> GPU 0
MPI rank 1  -> GPU 1
MPI rank 2  -> GPU 2
...
MPI rank 15 -> GPU 15
```

Per rank:

```text
CPU Fortran rank-local arrays
  |
  | selected GPU only for this rank
  v
GPU N persistent buffers:
  - static metrics
  - q / q1 / q2 local working arrays
  - velocities
  - slopes / fluxes / tendencies
  |
  | halo-only q1 transfer
  v
CPU Fortran MPI halo exchange
  |
  | halo-only injection
  v
same GPU N
  |
  | dq_dt transfer
  v
CPU Fortran update path
```

No inter-rank GPU communication is required in the first implementation. MPI
halo exchange remains on CPU exactly as it does today.

## Profiling and Logging Additions

Add these markers:

```text
PROFILE_FV_GPU_MAPPING rank=<rank> local_rank=<local_rank> device=<device> visible_gpus=<n> hostname=<host>
PROFILE_FV_GPU_MEMORY rank=<rank> device=<device> free_before=<bytes> total=<bytes>
PROFILE_FV_GPU_MEMORY rank=<rank> device=<device> free_after_alloc=<bytes> allocated_estimate=<bytes>
```

Keep existing markers:

```text
PROFILE_FV_ADVECTION_KERNEL backend=cuda_resident ...
PROFILE_FV_ADVECTION_CUDA backend=cuda_resident ...
```

Analysis script should report:

- MPP runtime;
- CUDA region max/mean/min across ranks;
- H2D/D2H/kernel/sync breakdown;
- device assignment histogram;
- ranks per GPU;
- slowest rank and its assigned GPU.

## Experiment Matrix

Run the same 30-day T42L25 model settings:

| Experiment | MPI ranks | Visible GPUs | Expected mapping | Purpose |
|---|---:|---:|---|---|
| single GPU baseline | 16 | 1 | 16 ranks/GPU | current reference |
| 4 GPU mapping | 16 | 4 | 4 ranks/GPU | contention scaling |
| 8 GPU mapping | 16 | 8 | 2 ranks/GPU | contention scaling |
| 16 GPU mapping | 16 | 16 | 1 rank/GPU | target |

Then repeat the best mapping at T85L25.

Suggested output names:

```text
held_suarez_fv_kernels_cuda_a_grid_30day_1gpu
held_suarez_fv_kernels_cuda_a_grid_30day_4gpu
held_suarez_fv_kernels_cuda_a_grid_30day_8gpu
held_suarez_fv_kernels_cuda_a_grid_30day_16gpu
```

Suggested logs:

```text
logs/fv_kernels_cuda_a_grid_30day_1gpu.log
logs/fv_kernels_cuda_a_grid_30day_4gpu.log
logs/fv_kernels_cuda_a_grid_30day_8gpu.log
logs/fv_kernels_cuda_a_grid_30day_16gpu.log
```

## Validation Plan

For each mapping:

1. Run 1-day smoke test.
2. Confirm every MPI rank prints one `PROFILE_FV_GPU_MAPPING` line.
3. Confirm mapping matches the requested GPU count.
4. Run 30-day simulation.
5. Validate NetCDF output against:
   - all-Fortran baseline;
   - CPU C++ FV bundle;
   - single-GPU `a_grid` resident output.

Expected validation command pattern:

```bash
python3 tests/validate_T85L25_forcing_outputs.py \
  --fortran-exp held_suarez_default \
  --cpu-exp held_suarez_fv_kernels_30day \
  --cuda-exp held_suarez_fv_kernels_cuda_a_grid_30day_16gpu \
  --run 1 \
  --filename atmos_monthly.nc \
  --data-root /explore/nobackup/people/jli30/SystemTesting/Isca/isca_data \
  --markdown-out tests/reports/fv_advection_a_grid_16gpu_30day_validation.md \
  --json-out tests/reports/fv_advection_a_grid_16gpu_30day_validation.json
```

Pass condition:

- dimensions match;
- selected fields match previous tolerances;
- no CUDA mapping or allocation failures;
- profile markers present for all ranks.

## Expected Performance Impact

If single-GPU contention is the dominant remaining bottleneck, moving from
16 ranks on 1 GPU to 1 rank per GPU should reduce:

- CUDA queueing;
- context switching;
- rank imbalance;
- synchronization wait time;
- wall-clock time spent in resident CUDA phases.

Idealized upper bound:

```text
single-GPU a_grid MPP: 51.000 s
CPU C++ baseline:      25.546 s
```

The current CUDA path must save about 25.5 s to match CPU C++. The measured CUDA
region max rank is about 20.3 s, and mean is about 15.3 s, so multi-GPU mapping
alone may close a meaningful part of the gap but may not guarantee a full win.

Expected outcomes:

| Outcome | Interpretation |
|---|---|
| 16 GPUs beats CPU C++ | CUDA path is viable for this boundary at T42L25 |
| 16 GPUs near CPU C++ | test T85L25; larger work may win |
| 16 GPUs still 1.5-2x slower | kernel/sync overhead or CPU boundary dominates |
| little improvement vs 1 GPU | rank contention was not the main bottleneck |

## Implementation Plan

### Step 1: Add Mapping Utilities

Likely file:

```text
translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu
```

Add:

- `detect_visible_gpu_count()`;
- `detect_local_rank()`;
- `choose_gpu_for_rank()`;
- `initialize_cuda_device_for_rank()`;
- mapping and memory log helpers.

Keep these internal to the CUDA layer. Do not change public Fortran APIs.

### Step 2: Initialize Before Buffer Allocation

Ensure the selected device is set before any persistent buffer allocation.

Pseudo-code:

```cpp
static bool cuda_device_initialized = false;

void ensure_cuda_device_initialized() {
    if (cuda_device_initialized) return;

    int rank = detect_rank_for_logging();
    int device = choose_gpu_for_rank(rank);
    check(cudaSetDevice(device), "cudaSetDevice");
    print_gpu_mapping(rank, device);

    cuda_device_initialized = true;
}

void ensure_context_for_dims(...) {
    ensure_cuda_device_initialized();
    allocate_or_resize_buffers(...);
}
```

Rank detection can use existing rank information if already passed through the C
API. If not available, use environment variables for logging only:

```text
OMPI_COMM_WORLD_RANK
PMI_RANK
SLURM_PROCID
```

### Step 3: Add Strict Mode

Add:

```text
FV_KERNELS_REQUIRE_UNIQUE_GPU=1
```

If set and `local_rank >= visible_gpus`, fail with:

```text
FV CUDA requested unique GPU mapping, but local_rank=<n> and visible_gpus=<m>.
Use fewer ranks per node or expose more GPUs.
```

### Step 4: Add Runtime Scripts

Create scripts after the code path exists:

```text
scripts/run_fv_a_grid_30day_1gpu.sh
scripts/run_fv_a_grid_30day_4gpu.sh
scripts/run_fv_a_grid_30day_8gpu.sh
scripts/run_fv_a_grid_30day_16gpu.sh
```

Each script should:

- echo GPU mapping variables;
- echo `CUDA_VISIBLE_DEVICES`;
- run `nvidia-smi` if available;
- write a dedicated log;
- use a distinct experiment name.

### Step 5: Add Mapping Report

After runs complete, create:

```text
docs/fv_advection_multi_gpu_performance_results.md
```

Include:

- mapping table;
- MPP runtime;
- CUDA region breakdown;
- speedup vs single-GPU `a_grid`;
- speedup vs CPU C++;
- validation status.

## Risks

| Risk | Mitigation |
|---|---|
| Scheduler hides GPUs differently per rank | rely on local-rank mapping and print visible device count |
| Multiple ranks still see only one GPU | inspect `CUDA_VISIBLE_DEVICES` and mapping markers |
| CUDA device assignment happens after allocation | call device init before any buffer allocation |
| Rank/GPU affinity poor | test scheduler binding and topology-aware mapping later |
| Numeric differences | keep CPU MPI halo exchange unchanged and validate NetCDF |
| Memory leak per rank | keep existing finalize/free path and add memory logging |
| Multi-node mapping ambiguity | use local rank, not global rank, for GPU id |

## Rollback Plan

The multi-GPU feature should be runtime-gated.

Rollback to current validated behavior:

```bash
unset FV_KERNELS_GPU_MAPPING
unset FV_KERNELS_REQUIRE_UNIQUE_GPU
export FV_KERNELS_CUDA_MODE=resident
export FV_KERNELS_RESIDENT_BOUNDARY=a_grid
export FV_KERNELS_RESIDENT_STATIC_METRICS=1
export FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only
```

If needed, restrict to one GPU:

```bash
export CUDA_VISIBLE_DEVICES=0
```

No production Fortran source should need to change.

## Recommendation

Proceed with **Phase 1: node-aware local-rank GPU mapping**.

Do not implement topology-aware binding first. The smallest useful experiment is
to set one CUDA device per local MPI rank, print the mapping, and re-run the
same 30-day `a_grid` resident test over 1, 4, 8, and 16 visible GPUs.

The pass/fail question is direct:

```text
Does better MPI-to-GPU mapping reduce the a_grid resident runtime enough to
approach or beat the 25.546 s CPU C++ baseline?
```

If yes, continue optimizing the CUDA resident path. If no, the remaining issue
is likely launch/synchronization overhead, CPU boundary cost, or the need for a
broader model-level GPU-resident design.
