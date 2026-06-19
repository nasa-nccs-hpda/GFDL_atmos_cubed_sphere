# FV Advection CUDA Data Residency Design

## Goal

Replace the current per-call CUDA lifecycle with an architecture that can
amortize allocation, transfer, launch, and synchronization overhead while
leaving production Fortran source untouched.

## Current Boundary

```text
Fortran local routine
-> ISO_C_BINDING wrapper
-> C CUDA entry point
-> allocate/copy/launch/sync/copy/free
-> return host output
```

This boundary is correct but about 5.18x slower than CPU C++ in the measured
30-day model run.

## Option 1: Persistent Reusable Device Buffers In The C API

### Design

Add an opaque CUDA context owned by the C++/CUDA library:

```text
fv_cuda_context_create(...)
fv_cuda_context_resize(...)
fv_cuda_run_<kernel>(context, host arrays...)
fv_cuda_context_destroy(context)
```

Device allocations persist across calls. The initial version can still copy
inputs and outputs on each call; a later version can add dirty/resident-state
tracking.

### Expected Speedup Potential

Low to moderate if only allocation/free are removed. Moderate to high only if
selected arrays can remain resident and copies are also reduced.

### Implementation Difficulty

Medium. Requires context lifecycle, size validation, error handling, and safe
cleanup, but does not require translating more numerical kernels.

### Fortran Interface Changes

Add private overlay-only initialization/finalization calls and an opaque
`C_PTR`. Existing public model APIs can remain unchanged.

### Validation Risk

Low to medium. Main risks are stale device data, incorrect context reuse after
dimension changes, and cleanup ordering.

### Memory Ownership

The CUDA library owns device buffers. Fortran continues to own host arrays.
The context records dimensions, capacities, and validity/dirty flags.

### Rollback Plan

Retain the current stateless CUDA entry points and select them with a build or
runtime flag. Removing the context path restores the validated implementation.

## Option 2: Fused Multi-Kernel CUDA Call

### Design

Create one CUDA entry point that executes the existing local sequence behind a
single host/device boundary:

```text
semi_x_3d
-> vanleer_x_3d
-> vanleer_sphere_3d
```

Inputs are transferred once, intermediate data remains on the GPU, and outputs
return after the sequence.

### Expected Speedup Potential

Moderate. It removes repeated lifecycle overhead among the three existing
kernels. Potential is higher when combined with persistent buffers.

### Implementation Difficulty

Medium to high. The production call sites use different arrays and occur within
Fortran control flow, so a valid fused boundary must preserve ordering and
dependencies rather than merely calling three unrelated benchmark kernels.

### Fortran Interface Changes

Add one overlay-only fused C binding with a larger argument list. Existing
public model interfaces remain unchanged, but the private overlay routine must
collect all required arrays at one call site.

### Validation Risk

Medium to high. Risks include changed operation order, aliasing, boundary
handling, and mismatched intermediate state.

### Memory Ownership

Either per-fused-call temporary device buffers or, preferably, an Option 1
context. Intermediate arrays remain device-owned for the duration of the fused
operation.

### Rollback Plan

Keep the three validated independent wrapper calls behind preprocessor flags.
The fused entry can be disabled without changing production source.

## Option 3: Broader Boundary Around Horizontal Advection Or update_tracers

### Design

Move the host/device boundary outward to encompass most local work in:

```text
a_grid_horiz_advection_3d
```

or the larger measured region:

```text
update_tracers
```

Fortran retains MPI, halo exchange, domain decomposition, and diagnostics.
Local arrays remain resident between multiple computational phases, returning
to the host only where MPI/Fortran logic requires visibility.

### Expected Speedup Potential

Highest. Existing profiling measured approximately 12.04% for tracer grid
horizontal advection and 17.55% for `update_tracers`, compared with roughly 6%
for the current three-kernel CPU bundle.

### Implementation Difficulty

High to very high. Requires explicit ownership boundaries, dependency mapping,
halo synchronization points, and likely additional kernel fusion or
translation of neighboring local loops.

### Fortran Interface Changes

The production API remains untouched through an overlay, but the overlay-to-C
surface becomes broad. It may require context handles, multiple state arrays,
and explicit host/device synchronization calls around halo updates.

### Validation Risk

High. Risks include prognostic state lifetime, halo freshness, tracer ordering,
boundary conditions, and cumulative numerical divergence.

### Memory Ownership

A long-lived CUDA context owns device mirrors of local prognostic and metric
arrays. Fortran owns canonical host arrays at MPI/diagnostic boundaries. The
design must define which side is authoritative between synchronization points.

### Rollback Plan

Keep the existing all-Fortran and fine-grained overlay paths selectable at
compile time. Introduce the broader path incrementally and validate at each
boundary before enabling it by default.

## Comparison

| Option | Speedup Potential | Difficulty | Interface Change | Validation Risk |
|---|---|---|---|---|
| 1. Persistent buffers | low-moderate; higher with residency | medium | private context lifecycle | low-medium |
| 2. Fused three-kernel call | moderate | medium-high | one broader private C call | medium-high |
| 3. Broad advection/update boundary | high | high-very high | broad context/state API | high |

## Recommended Next Step

Run the new microbenchmark before changing model integration.

If persistent mode removes most of the current CUDA cost, implement Option 1 as
the next model-path experiment: an opaque reusable buffer context behind new
overlay-only C bindings, while preserving the current stateless wrappers as a
rollback path.

Option 1 should be treated as infrastructure for Option 2, not the final
architecture. Allocation reuse alone cannot remove H2D/D2H costs. After the
context is validated, fuse the existing kernel sequence where the real Fortran
call graph permits one transfer boundary.

Do not begin Option 3 until Options 1/2 establish a correct ownership model and
the duration-matched model validation ladder remains clean.
