# Result: switching to the FV method beats the GPU transfer slowdown

**Status: complete. Date 2026-07-25. Branch `gpu/fv-transfer-poc`. Node gpu022, 2× Tesla V100 (NVLink).**

Follow-on to the plan in `docs/fv_transfer_poc_plan.md`. Read that first for the
question and what this test is and is not.

## The short answer

Yes. The FV method's neighbor exchange, done GPU-to-GPU, is tiny, never leaves
the GPUs, and takes up a smaller share of the work as the problem grows. That is
the opposite of the old spectral method's big swap, which ate about a quarter of
the run and got worse with size. For this kind of transfer slowdown, changing
the underlying method is a worthwhile strategy.

## How the test was built

The old measurements showed the spectral method's global swap ("transpose") cost
about **24% of runtime** and had to leave the GPU each time (see
`docs/transform_stack_feasibility_COMPLETE.md`). The FV method instead has each
processor talk only to its immediate north and south neighbors — a small, local
exchange.

Three pieces were added on this branch, reusing the existing 16-rank FV advection
run:

1. **One GPU per rank** — each processor binds to its own GPU
   (`cudaSetDevice`, commit de3529c). Verified: clean split across the two cards.
2. **A timer on the old host-routed exchange** (commit 09d66d0) — to have a
   baseline. It measured the neighbor exchange, as the model does it today
   (staged through the host), at about **2.5 milliseconds per call**, roughly
   **4% of the 109-second run**.
3. **The GPU-to-GPU exchange itself.** Two findings settled how to build it:
   - The container's MPI cannot move data GPU-to-GPU. Its OpenMPI reports
     `opal_built_with_cuda_support=false`, and its UCX layer has no working
     `cuda_copy`/`cuda_ipc` transports — handing MPI a GPU pointer crashes in a
     host-memory copy. A negative-control test confirms this
     (`tests/poc/cuda_aware_mpi_smoke.cu`).
   - **NCCL** — NVIDIA's own transfer library — is present in the container and
     moves data GPU-to-GPU directly over NVLink, with no host staging and
     without needing a GPU-aware MPI. A smoke test passed
     (`tests/poc/nccl_smoke.cu`).

The benchmark (`tests/poc/halo_exchange_bench.cu`) then replicates the model's
exact layout: the grid split in Y only, one slab per rank, two halo rows on each
edge (`yhalo=2`), 8-byte reals. It packs the two edge rows, sends them to the
neighbor over NCCL, unpacks them, and times the whole pack-send-unpack while
counting the bytes moved. The buffers stay on the GPU throughout.

Because the meaningful unit is the transfer *between two GPUs*, the benchmark
runs one rank per GPU (the two cards on the node), each holding the real
per-rank slab, exchanging across the link. Resolution is raised by using the
real per-rank tile at T85, T170, and T340.

## The numbers

| Resolution (per-rank tile) | Time per exchange | Bytes moved (both GPUs) | Halo ÷ interior |
|---|---|---|---|
| T85L25  (8 rows / rank)  | 0.025 ms | 0.39 MiB | 0.250 |
| T170L25 (16 rows / rank) | 0.031 ms | 0.78 MiB | 0.125 |
| T340L25 (32 rows / rank) | 0.042 ms | 1.56 MiB | 0.062 |

Reading the three columns against the three things the test had to show:

- **Small.** Each exchange takes tens of microseconds and moves under a couple of
  megabytes. The same exchange done host-side cost about 2.5 ms — the GPU-to-GPU
  version is roughly **100× cheaper per call**.
- **Stays on the GPUs.** NCCL moved everything device-to-device over NVLink; the
  negative-control test proved plain MPI could not. The data never dropped to the
  host.
- **Shrinks as resolution rises.** The last column **halves at every step**. The
  bigger the problem, the smaller the relative cost of talking to neighbors —
  because the shared edge grows slower than the interior volume.

Put in runtime terms: the host-staged exchange was about 4% of the run; at
roughly 1/100 the per-call cost, the GPU-to-GPU version lands well under a tenth
of a percent. The spectral transpose, by contrast, is 24% and grows with size.

## What this does and does not establish

- It **does** establish the general point the work set out to test: when a
  transfer bottleneck comes from a global all-to-all step, moving to a method
  whose communication is local (nearest-neighbor) removes that bottleneck on
  GPUs — the traffic is small, stays on-device, and shrinks in relative terms as
  the problem grows.
- It **does not** claim a whole-model speedup number, and it is not a climate
  validation. The figures come from a standalone benchmark at the real tile
  sizes, not a live model run; the runtime-share comparison is derived from the
  model's separately-measured times, not measured inside one run. Turning this
  into a production FV dynamical core is a much larger, separate effort (no dry
  FV solo Held-Suarez driver exists in this repo today).

## Files

- `tests/poc/cuda_aware_mpi_smoke.cu` — negative control: MPI cannot move GPU
  buffers here.
- `tests/poc/nccl_smoke.cu` — NCCL GPU-to-GPU works.
- `tests/poc/halo_exchange_bench.cu` — the neighbor-exchange benchmark.
- `src/extra/local_overrides/fv_advection_kernels/fv_advection.F90` — the
  host-side exchange timer (baseline).
