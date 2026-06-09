# yppm GPU port — design notes and path to a full GPU `fv_tp_2d`

## What is implemented

| File | Role |
|------|------|
| `yppm.hpp` | Header-only `yppm_col` (single column, `__host__ __device__`). Scratch is accessed through `ScratchYPPMView` (raw pointers); backing storage is caller-supplied, so the per-column work arrays are **runtime-sized** (`nj = je - js + 1`) — no compile-time `NMAX` cap. |
| `yppm_gpu.cuh` | Reusable CUDA launch API. One thread per column. Two entry points (below). |
| `test_yppm_gpu.cu` | Multi-column unit test: replicates a column `NCOL` times, runs the launch API, checks bit-exact agreement with the CPU `yppm_col` and that every column is identical. |
| `driver_yppm_gpu.cu` | `tp-core-driver-gpu <resolution> <iterations> [levels]` — allocate-once / copy-once / timed launch loop, mirroring the CPU `tp-core-driver`. |

## Data layout: column-contiguous

For `ncol` independent columns, each column's `j`-values are stored
contiguously, so thread `t` owns the slice `[t*len, (t+1)*len)` and needs no
gather/scatter:

- `q`, `dya`  → `nj_q  = jed - jsd + 1` per column
- `cry`,`flux`→ `nj_flux = je - js + 2` per column
- scratch     → `yppm_scratch_{real,bool}_words(nj)` per column, in one device buffer.

`ncol = (x-columns in the tile) × (batched levels)`. `js/je/jsd/jed/npx/npy`
are identical for every column — the j-direction (south/north) boundary
treatment applies to all x-columns alike, exactly as the CPU multi-column
wrapper calls `yppm_col` per column.

## Two entry points (the important part for the full port)

- **`yppm_gpu_launch_device(...)`** — device pointers only. No allocation, no
  copy, no synchronize. **This is what a future device-resident GPU `fv_tp_2d`
  should call.** Data stays on the GPU across the whole transport step; only the
  kernel launch happens here. It also takes a `cudaStream_t`.
- **`yppm_gpu(...)`** — host convenience that owns memory (alloc, H2D, launch,
  sync, D2H, free). Used by the unit test; convenient but the per-call copies
  make it unsuitable for the production inner loop.

## Path to a full GPU `fv_tp_2d`

`fv_tp_2d` (`model/tp_core.F90:109`) interleaves `xppm` and `yppm` over a tile.
To port it:

1. **Port `xppm` the same way** — a new `xppm.hpp` (`__host__ __device__`
   `xppm_col`) plus an `xppm_gpu.cuh` launch mirroring this one. `yppm` here is
   the prototype to copy.
2. **Make data device-resident.** Allocate `q`, `crx`, `cry`, `fx`, `fy`, the
   intermediate `q_i`/`q_j`, and the scratch **once**, on the GPU. The per-call
   H2D/D2H in `yppm_gpu(...)` and in the benchmark's setup is a harness
   artifact, not the model.
3. **Orchestrate on a stream.** A GPU `fv_tp_2d` issues the `xppm`/`yppm`
   kernels via the device-pointer launches on one `cudaStream_t`, with the same
   ordering as the Fortran. Only copy results back at the end of the step.
4. **Batch over levels.** `fv_tp_2d` is called per vertical level per tile;
   folding the level (and tile) index into `ncol` keeps the GPU saturated. The
   launch API already treats `ncol` as a flat column count, so this is just a
   larger `ncol`.

## Known limits / future optimization

- **Thread-per-column, scratch in global memory.** Faithful and correct, and it
  scales to any resolution. The next optimization is **one block per column with
  the j-loops parallelized across threads and scratch in shared memory** — higher
  occupancy and on-chip scratch — at the cost of rewriting `yppm_col`'s j-loops
  with `__syncthreads`. Deferred deliberately; this version sets the baseline.
- `ncol` is an `int` in the launch API. Production tile×level counts fit, but a
  very large batch would need a 64-bit column count.
