# CUDA FV Advection Performance Diagnosis

## Scope

This diagnosis covers the existing translated FV advection kernel bundle:

- `semi_x_3d`
- `vanleer_x_3d`
- `vanleer_sphere_3d`

The helper routines `slope_x`, `slope_sphere`, `integer_flux_x`, and
`find_cell_x` are folded into the top-level implementations.

No production Fortran source is changed by this work.

## Current Result

The 30-day default Held-Suarez T42L25-style run used 16 MPI ranks and
`dt_atmos=600 s`.

| Variant | MPP Runtime | Shell Real |
|---|---:|---:|
| CPU C++ FV bundle | 25.546 s | 28.987 s |
| CUDA FV bundle | 132.355 s | 136.048 s |

```text
CUDA vs CPU C++ speedup = 0.193x
CUDA is about 5.18x slower than CPU C++.
```

Max-rank model-facing kernel timings:

| Backend | Kernel | Calls | Time | Average / Call | Model Fraction |
|---|---|---:|---:|---:|---:|
| CPU C++ | `semi_x_3d` | 4320 | 0.214 s | 0.0495 ms | 0.84% |
| CPU C++ | `vanleer_x_3d` | 4320 | 0.768 s | 0.1779 ms | 3.01% |
| CPU C++ | `vanleer_sphere_3d` | 4320 | 0.560 s | 0.1295 ms | 2.19% |
| CUDA | `semi_x_3d` | 4320 | 22.566 s | 5.224 ms | 17.05% |
| CUDA | `vanleer_x_3d` | 4320 | 17.089 s | 3.956 ms | 12.91% |
| CUDA | `vanleer_sphere_3d` | 4320 | 56.754 s | 13.138 ms | 42.88% |

The timed CPU region is 6.04% of CPU model runtime. The same boundary becomes
72.84% of CUDA model runtime.

## Current CUDA Lifecycle

Every model-facing CUDA call currently performs:

```text
validate device
-> cudaMalloc for every input/output
-> cudaMemcpy H2D for every input
-> launch one kernel
-> cudaGetLastError
-> cudaDeviceSynchronize
-> cudaMemcpy D2H for the result
-> cudaFree every allocation
```

This lifecycle is appropriate for initial correctness validation. It is a poor
performance architecture for kernels whose CPU execution time is only about
0.05-0.18 ms per call.

## Likely Overhead Sources

### Allocation

`cudaMalloc` is a device-runtime operation with fixed cost and synchronization
effects. The current wrappers allocate four buffers for `semi_x_3d` and
`vanleer_x_3d`, and eight buffers for `vanleer_sphere_3d`, on every call.

At 4320 calls per rank, this produces tens of thousands of allocations per
rank. With 16 MPI ranks using the visible GPU, allocator and context contention
can become more important than the kernel arithmetic.

Expected contribution: high fixed overhead, especially for
`vanleer_sphere_3d`. The microbenchmark must measure the actual fraction.

### Host-To-Device Copies

All state and metric arrays are recopied for every call. Approximate T42 local
payload per rank, excluding small metric arrays:

| Kernel | Approximate H2D Payload / Call | Approximate D2H Payload / Call |
|---|---:|---:|
| `semi_x_3d` | 205 KB | 102 KB |
| `vanleer_x_3d` | 307 KB | 102 KB |
| `vanleer_sphere_3d` | 435 KB | 102 KB |

The copies are synchronous and cannot overlap useful host or device work in the
current implementation.

Expected contribution: moderate to high and increasing with resolution.

### Launch And Synchronization

Each wrapper launches one relatively small local-rank kernel and immediately
synchronizes. This prevents batching, overlap, and asynchronous execution.

At T42 with 16 ranks, a local x/y/level array has only:

```text
128 * 4 * 25 = 12,800 cells
```

That is enough parallelism to run a kernel, but not enough work to amortize the
full launch, context scheduling, and synchronization lifecycle repeated by all
MPI ranks.

Expected contribution: high fixed overhead for the small T42 local domain.

### Device-To-Host Copies

Each result is copied immediately back to Fortran because the next model code
runs on the CPU. This makes device residency impossible and introduces another
synchronous transfer on every call.

Expected contribution: moderate, scaling with output size.

### Free

Every allocation is freed before returning to Fortran. `cudaFree` may
synchronize and returns the allocation to the runtime instead of allowing reuse
at the next timestep.

Expected contribution: moderate fixed overhead; likely amplified by eight
frees per `vanleer_sphere_3d` call and multi-rank contention.

## Expected Phase Mix

Before microbenchmark measurements, the defensible expectation is qualitative:

| Phase | Expected Behavior |
|---|---|
| allocation | large fixed cost; worst for sphere kernel |
| H2D | scales with arrays and resolution |
| launch | fixed cost per kernel; costly for small local domains |
| kernel execution | likely a minority of current wrapper time |
| synchronization | exposes kernel and scheduling latency; prevents overlap |
| D2H | scales with output size and forces CPU visibility |
| free | repeated fixed cost and possible synchronization |

The new microbenchmark is the source of truth for numeric phase percentages.
No phase percentage should be inferred solely from the model-level wrapper
timers.

## Why More Isolated Wrappers Will Not Help

Adding another isolated CUDA wrapper adds another Fortran/C boundary and another
allocation/copy/launch/sync/copy/free lifecycle. Even if its device arithmetic
is faster than CPU arithmetic, its end-to-end call is likely slower unless it
shares resident data with neighboring kernels.

More wrappers therefore increase:

- the number of transfers;
- the number of synchronizations;
- allocator traffic;
- MPI-rank contention for the GPU;
- host/device ownership transitions.

The measured bundle already demonstrates this failure mode. A roughly 6% CPU
region becomes roughly 73% of CUDA runtime.

## Performance Architecture Requirement

Future CUDA speedup requires changing the ownership boundary, not translating
more individual loops. At least one of the following is needed:

- persistent reusable device buffers;
- data remaining resident across multiple calls;
- a fused multi-kernel entry point;
- a broader GPU boundary around horizontal advection or tracer update;
- fewer MPI ranks issuing independent small operations to one GPU.

## Immediate Recommendation

Run the standalone microbenchmark first. Use its current-vs-persistent delta to
quantify the removable lifecycle overhead. Do not modify the hybrid model path
until the benchmark shows which phase dominates and whether persistent
residency can make device execution competitive with CPU C++.
