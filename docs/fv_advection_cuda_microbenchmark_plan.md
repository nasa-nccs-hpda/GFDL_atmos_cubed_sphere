# FV Advection CUDA Microbenchmark Plan

## Objective

Measure the cost structure of the existing FV advection CUDA boundary without
changing the production model or native overlay.

Benchmark location:

```text
benchmarks/fv_advection_kernels/
```

## Kernels

The standalone harness mirrors the model-facing kernels:

- `semi_x_3d`
- `vanleer_x_3d`
- `vanleer_sphere_3d`

Existing standalone correctness reports remain authoritative. The benchmark is
for timing architecture, not replacement numerical validation.

## Modes

### A. CPU C++

Call the validated CPU C++ implementation repeatedly using host-resident
arrays.

### B. CUDA Current

For every iteration:

```text
allocate
-> H2D
-> launch
-> synchronize
-> D2H
-> free
```

This reproduces the current model-facing lifecycle.

### C. CUDA Persistent

For a batch of N iterations:

```text
allocate once
-> H2D once
-> launch N kernels
-> synchronize once
-> D2H once
-> free once
```

This mode estimates the upper value of device residency. It does not claim
that model inputs are unchanged across timesteps; it isolates the cost removed
when ownership and transfer boundaries are redesigned.

## Metrics

The harness reports:

- allocation time;
- H2D time;
- host launch time;
- CUDA-event kernel execution time;
- host synchronization time;
- D2H time;
- free time;
- total time;
- total time per call.

`kernel_ms` is measured with CUDA events. `sync_ms` is host wait time and
overlaps kernel execution, so the two must not be added together when
reconstructing total time.

## Representative Problem Sizes

Assume the production 16-rank latitude decomposition:

| Label | Global Horizontal Grid | Local Grid / Rank | Vertical Levels | Representative dt |
|---|---:|---:|---:|---:|
| T42L25 | 128 x 64 | 128 x 4 | 25 | 600 s |
| T85L25 | 256 x 128 | 256 x 8 | 25 | 300 s |
| T170L25 | 512 x 256 | 512 x 16 | 25 | 150 s |

T170L25 is optional for the first run but useful for identifying when kernel
arithmetic begins to amortize fixed overhead.

## Build

Inside the CUDA-capable Isca container:

```bash
cd /explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/benchmarks/fv_advection_kernels
make clean all NVCC=/usr/local/cuda/bin/nvcc
```

## Run

Single resolution:

```bash
./bin/fv_advection_cuda_benchmark \
  --resolution T42 \
  --iterations 100 \
  --mode all
```

All planned resolutions:

```bash
ITERATIONS=100 benchmarks/fv_advection_kernels/run_all.sh
```

Expected log:

```text
logs/fv_advection_cuda_microbenchmark.log
```

The executable emits CSV rows suitable for direct parsing.

## Experimental Protocol

1. Run on an otherwise idle GPU node.
2. Record GPU model, driver, CUDA runtime, and clock/power state.
3. Use one process and one GPU for the unit benchmark.
4. Run at least three repetitions per resolution.
5. Use a larger iteration count if total measured time is below one second.
6. Compare medians, not a single launch.
7. Run current and persistent modes in the same process invocation.
8. Do not compare the one-process microbenchmark directly to the 16-rank model
   without accounting for rank contention.

## Analysis

For each kernel and resolution, compute:

```text
current_cuda / cpu
persistent_cuda / cpu
current_cuda / persistent_cuda
phase_time / current_cuda_total
phase_time / persistent_cuda_total
```

Questions to answer:

- How much time is removed by allocation reuse?
- How much time is removed by copy-once residency?
- Is raw kernel execution faster than CPU C++?
- At which resolution does CUDA kernel time become competitive?
- Is `vanleer_sphere_3d` slow because of arithmetic or lifecycle overhead?

## Pass/Decision Criteria

The benchmark is successful if it produces complete phase timings for all
three modes at T42L25 and T85L25.

Architecture decision guidance:

- Persistent CUDA faster than CPU: proceed toward resident/fused integration.
- Persistent CUDA near CPU: proceed only if broader fusion increases work per
  transfer.
- Persistent CUDA still much slower: inspect kernel implementation, rank/GPU
  mapping, occupancy, and memory behavior before model integration.
- Allocation reuse helps but copies dominate: Option 1 alone is insufficient;
  use a fused or broader boundary.

## Current Status

The benchmark harness and build/run scripts are implemented. It has not been
built or run in this shell because `nvcc` and a GPU are only available inside
the CUDA-capable container.
