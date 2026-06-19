# FV Advection CUDA Persistent Buffer Plan

## Objective

Remove steady-state `cudaMalloc` and `cudaFree` calls from the existing FV
advection CUDA kernel bundle without changing production Fortran, numerical
ordering, or the public Fortran/C ABI.

## Runtime Selection

```bash
export FV_KERNELS_CUDA_MODE=stateless   # default
export FV_KERNELS_CUDA_MODE=persistent
```

An unset variable selects `stateless`. An unsupported value returns an explicit
CUDA error and does not silently select another backend.

## First Persistent Design

Each MPI rank is a separate process and therefore owns one process-local CUDA
buffer pool in `fv_advection_kernels_cuda.cu`.

The pool:

- contains eight reusable double-precision device buffers;
- grows individual buffers when a call requires greater capacity;
- reuses existing capacity when dimensions stay constant or shrink;
- is shared sequentially by the six validated fixture entry points;
- is released with an `atexit` cleanup handler;
- does not alter or cache Fortran host-array state.

The first implementation deliberately retains this lifecycle per call:

```text
H2D copies
-> CUDA kernel launch
-> synchronization
-> D2H result copy
```

Only allocation/free moves out of the steady-state call path.

## Preserved Paths

- Existing C and Fortran signatures are unchanged.
- The stateless implementation remains compiled and is the default.
- CPU C++ behavior is unchanged.
- Production Fortran source is unchanged.
- No new numerical kernels are introduced.

## Profiling

Enable phase profiling with:

```bash
export FV_KERNELS_PROFILE=1
```

Existing per-kernel markers now identify:

```text
backend=cuda_stateless
backend=cuda_persistent
```

The aggregate phase marker is:

```text
PROFILE_FV_ADVECTION_CUDA backend=<cuda_stateless|cuda_persistent> \
  rank=<rank> calls=<n> allocation=<seconds> h2d=<seconds> \
  kernel=<seconds> sync=<seconds> d2h=<seconds> free=<seconds> \
  total=<seconds>
```

`kernel` uses reusable CUDA events. `sync` is host wait time and overlaps
kernel execution; the fields must not be summed to reconstruct total time.
Finalize-time buffer release is included in `free` when profiling is enabled.

## Validation Ladder

### Direct CUDA Fixture

Inside the CUDA-capable container:

```bash
cd translated/held_suarez/cpp/fv_advection/kernels
make NVCC=/usr/local/cuda/bin/nvcc cuda_persistent_check
```

Expected report:

```text
tests/reports/fv_advection_kernels_cuda_persistent_compare_report.json
```

### Fortran To C To CUDA Fixture

```bash
cd translated/held_suarez/cpp/fv_advection/kernels/fortran
make FC=mpifort BACKEND=cuda CUDA_MODE=persistent check
```

Expected report:

```text
tests/reports/fv_advection_kernels_fortran_cuda_persistent_c_compare_report.json
```

### Native Overlay And Model

Only after both standalone tests pass:

1. rebuild the existing CUDA native overlay executable;
2. run a one-day smoke test with `FV_KERNELS_CUDA_MODE=persistent`;
3. compare output against the all-Fortran and CPU C++ references;
4. run a profiled 30-day persistent experiment;
5. compare CPU C++, stateless CUDA, and persistent CUDA model runtime.

## Pass Criteria

- All standalone fixture fields remain within the existing `1e-12` tolerance.
- Fortran-to-C results match the same baseline.
- Stateless validation remains passing.
- One-day model output passes the existing comparison ladder.
- Performance claims are deferred until a duration-matched 30-day run.

## Rollback

Set:

```bash
export FV_KERNELS_CUDA_MODE=stateless
```

No source rebuild or Fortran change is required to return to the validated
stateless backend.
