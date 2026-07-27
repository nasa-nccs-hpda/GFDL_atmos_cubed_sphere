# Changing the algorithm to beat the GPU transfer bottleneck — summary

**Date 2026-07-25. Branch `gpu/fv-transfer-poc`.**

- **The problem:** the spectral method needs a global "transpose" — every
  processor swaps data with every other one — and on GPUs that swap must drop to
  the host each time, eating about 24% of the run and worsening as the problem
  grows.

- **The idea:** instead of optimizing the transfer, change the underlying
  algorithm to one that never needs a global swap at all.

- **The algorithm change:** switch from the spectral method to the FV
  (local-stencil) method, where each processor talks only to its immediate north
  and south neighbors — a small edge exchange rather than an all-to-all.

- **Why that helps on GPUs:** a nearest-neighbor exchange can go straight from
  one GPU to the next, with no reason to touch the host.

- **NCCL:** the container's MPI cannot move data GPU-to-GPU (proven by a crashing
  negative-control test), but NVIDIA's NCCL library can, over the NVLink between
  cards, without a GPU-aware MPI. A smoke test confirmed it works here.

- **Proof of concept:** a standalone benchmark reproduced the real per-processor
  tile and ran the FV neighbor exchange over NCCL at three resolutions, timing it
  and counting the bytes moved.

- **PoC result — passed on all three counts:** the exchange is small, stays on
  the GPUs, and its relative cost *halves* at each resolution doubling — the
  opposite of the transpose.

- **The timings (same FV advection test):**
  1. **Fortran only, no GPU — about 25 s.**
  2. **GPU as built in the earlier effort — about 108 s**, roughly 4× *slower*,
     because moving the field host↔device is about 72% of the GPU time; the
     transfer swamps the compute.
  3. **GPU with the new GPU-to-GPU exchange — not yet measured; that end-to-end
     number is exactly what Level 1 produces.**

  The proof of concept measured only the piece that causes #2's slowdown: the
  neighbor exchange drops from ~2.5 ms to ~0.03 ms per call (~100×) when it stays
  on the GPUs. (For reference, the spectral transpose that started all this was
  ~24% of its run and grew with size.)

- **What that establishes:** the transfer, not the math, is what makes the GPU
  slower today; a local exchange that never leaves the GPU removes that transfer.
  (Caveat: the ~100× is a standalone-benchmark figure for the exchange, not a
  whole-model speedup, and no climate validation.)

- **The plan (Level 1):** wire the NCCL exchange into the running FV advection
  solver, replacing the host round-trip already isolated in the code, with the
  pole reflection moved to a small GPU kernel; run one processor per GPU and check
  the tracer matches to rounding over a few steps — which turns timing #3 above
  from "not measured" into a real end-to-end number. About 1 week of work (2–3
  weeks elapsed with cluster turnaround), plus an optional Phase B that moves the
  last two swaps on-GPU so the host never touches a halo. Full scope in
  `docs/fv_nccl_advection_scope.md`.
