# FV Advection CUDA Microbenchmark Results

## Run

Source log:

```text
logs/fv_advection_cuda_microbenchmark.log
```

The run used 100 calls per kernel and representative 16-rank local domains
for T42L25, T85L25, and T170L25.

## Aggregate Results

Times below are the sum of `semi_x_3d`, `vanleer_x_3d`, and
`vanleer_sphere_3d` for 100 calls of each kernel.

| Resolution | CPU C++ | Current CUDA | Persistent CUDA | Current CUDA vs CPU | Persistent CUDA vs CPU | Current / Persistent |
|---|---:|---:|---:|---:|---:|---:|
| T42L25 | 20.568 ms | 263.784 ms | 1.380 ms | 0.078x | 14.91x | 191.16x |
| T85L25 | 83.446 ms | 41.302 ms | 1.565 ms | 2.02x | 53.30x | 26.38x |
| T170L25 | 362.783 ms | 79.741 ms | 2.647 ms | 4.55x | 137.03x | 30.12x |

The T42 current-CUDA aggregate is not representative: the first
`semi_x_3d` invocation consumed 238.006 ms, including a one-time CUDA module
lazy-loading or first-launch cost. The later T42 kernels and all T85/T170 rows
show the stable lifecycle behavior. A warmed, repeated run is needed before
using the T42 ratio quantitatively.

## Per-Kernel Results

| Resolution | Kernel | CPU / Current CUDA | CPU / Persistent CUDA | Current / Persistent CUDA |
|---|---|---:|---:|---:|
| T42L25 | `semi_x_3d` | 0.011x* | 7.27x | 632.72x* |
| T42L25 | `vanleer_x_3d` | 0.889x | 23.44x | 26.37x |
| T42L25 | `vanleer_sphere_3d` | 0.537x | 13.51x | 25.17x |
| T85L25 | `semi_x_3d` | 0.942x | 28.68x | 30.45x |
| T85L25 | `vanleer_x_3d` | 3.329x | 84.51x | 25.38x |
| T85L25 | `vanleer_sphere_3d` | 1.830x | 44.99x | 24.58x |
| T170L25 | `semi_x_3d` | 1.833x | 73.72x | 40.21x |
| T170L25 | `vanleer_x_3d` | 7.801x | 234.86x | 30.11x |
| T170L25 | `vanleer_sphere_3d` | 3.962x | 98.87x | 24.95x |

`*` Contaminated by the first CUDA launch.

## Current CUDA Cost Structure

For the uncontaminated T85L25 rows:

| Kernel | Allocation + Free | H2D + D2H | Interpretation |
|---|---:|---:|---|
| `semi_x_3d` | 58.5% | 25.4% | lifecycle dominates |
| `vanleer_x_3d` | 56.7% | 31.2% | lifecycle dominates |
| `vanleer_sphere_3d` | 50.8% | 39.5% | lifecycle and copies dominate |

Allocation/free and copies account for approximately 81-90% of current CUDA
wall time at T85L25. Kernel execution is not the reason the integrated CUDA
path is slow.

At T170L25, current CUDA is already 1.83-7.80x faster than CPU C++ at unit
level despite retaining the inefficient lifecycle. This confirms that the
arithmetic maps well to the GPU and that higher resolution improves
amortization.

## Interpretation

The persistent experiment is an upper-bound architecture test, not a directly
deployable model speedup. It copies model inputs once, repeats 100 kernels, and
copies the result once. Real model inputs change between calls, so a reusable
allocation that still transfers every call will fall between current and
persistent measurements.

Nevertheless, the result establishes three important facts:

1. The CUDA kernels themselves are fast enough to justify continued work.
2. Per-call allocation/free is the largest removable T85 cost.
3. Long-term speedup requires device residency or a broader/fused boundary to
   reduce H2D and D2H traffic as well.

The much larger slowdown in the 16-rank model than in this single-process
microbenchmark also points to allocator, context, synchronization, and GPU
contention across MPI ranks. Model-level validation remains essential.

## Recommended Next Step

Implement **Option 1: persistent reusable device buffers** for the three
existing kernels only.

The first model experiment should deliberately remain conservative:

- create one lazily initialized CUDA context per process;
- cache and resize device buffers by shape;
- remove `cudaMalloc` and `cudaFree` from steady-state calls;
- retain per-call H2D, kernel synchronization, and D2H initially;
- preserve the current stateless implementation behind a build/runtime switch;
- add phase counters for allocation, H2D, kernel, synchronization, and D2H;
- rerun standalone correctness, 1-day model validation, and a 30-day timed run.

This step tests the largest removable cost without changing numerical
ordering or translating new kernels. If it does not materially improve the
16-rank model, do not optimize the individual wrappers further; proceed to a
fused or broader advection boundary with fewer host/device ownership changes.

If it succeeds, the following step should combine the persistent context with
device residency or a valid fused call sequence. Allocation reuse alone is
infrastructure, not the final performance design.

## Decision

**GO for persistent-buffer integration of the existing kernel bundle.**

Do not add more isolated CUDA wrappers. Do not yet move the full
`a_grid_horiz_advection_3d` boundary. First quantify how much of the measured
model slowdown disappears when steady-state allocation/free is removed.
