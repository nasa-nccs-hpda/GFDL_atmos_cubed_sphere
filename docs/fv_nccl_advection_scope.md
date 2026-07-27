# Level 1 scope: NCCL halos in the running FV advection

**Status: scope, not started. Date 2026-07-25. Branch `gpu/fv-transfer-poc`.**

Follow-on to the completed benchmark (`docs/fv_transfer_poc_results.md`). That
showed the neighbor exchange is small and stays on the GPUs in isolation. This
step puts it inside the running solver: the existing FV advection time-stepper,
run across GPUs, with the neighbor exchange going GPU-to-GPU through NCCL and
nothing staged through the host. It is a demonstration of the strategy, not a
production core and not a climate validation.

## Where the work goes (the exact spot)

The advection already keeps the tracer field on the GPU across a timestep. The
only reason it touches the host at all, mid-step, is to swap the field's edge
rows with its neighbors. That swap is already isolated to three short stretches
of code:

- `resident_advection_begin` copies the tracer's 2 edge rows per side down to the
  host — `fv_advection_kernels_cuda.cu:1575-1594`.
- The Fortran does the neighbor swap and the pole reflection on the host —
  `fv_advection.F90:323-346` (`mpp_update_domains(q1)` plus the polar fold).
- `resident_advection_finish` uploads the 2 filled halo rows per side back to the
  GPU — `fv_advection_kernels_cuda.cu:1648+`.

The field's deep interior never leaves the GPU; only these edge rows make the
round trip. Replacing that round trip with a GPU-to-GPU exchange is the whole job.

## Run shape (a constraint, not a choice)

NCCL wants **one rank per GPU** (piling many ranks on one GPU gave the "invalid
usage" error during the benchmark). The old advection run put 16 ranks on 2
GPUs. So the demonstrator runs one rank per GPU — on this 2-GPU node that means
`-np 2`, each rank owning half the grid in the north-south direction. The code
already derives its decomposition from the rank count (`layout = (/1, npes/)`,
`fv_advection.F90:136`), so this needs no code change, only a different launch.

With 2 ranks, each rank sits against a pole on one side and its single neighbor on
the other — a clean pole-to-pole pair. Showing an interior rank (a neighbor on
*both* sides) and multi-GPU scaling needs a node with 3+ GPUs or more than one
node; that is a later extension, noted below.

## The pieces

**Phase A — move the tracer swap onto the GPU (the milestone).**

1. **Set up NCCL once.** Add a lazy initializer on the CUDA side that builds an
   NCCL communicator using the MPI world already running (rank 0 makes the id,
   broadcasts it over MPI, everyone joins). Mirrors `tests/poc/nccl_smoke.cu`.
   Check that the rank count matches the GPU count and stop with a clear message
   if not.
2. **Pack, exchange, unpack — on the GPU.** Replace the edge-download / host-swap
   / halo-upload with: pack the tracer's edge rows into a contiguous buffer, send
   to the north and south neighbor and receive theirs via NCCL, unpack into the
   halo rows. This is the benchmark's pack/exchange/unpack applied to the resident
   tracer buffer (slot 3, pitch `nx*(ny+4)`).
3. **Do the pole reflection on the GPU.** The pole rows are filled by reflecting
   the field across the pole (`fv_advection.F90:334-346`) — a within-rank
   operation, no communication. Move it into a small kernel, driven by the
   north/south boundary flags the finish step already receives
   (`fv_advection_kernels_cuda.cu:1611-1612`).
4. **Rewire the Fortran.** In the resident path, drop `mpp_update_domains(q1)`
   and the host polar fold; call the new GPU halo step between begin and finish.
   Drop the now-unneeded edge-download in begin and halo-upload in finish, since
   the resident tracer buffer is exchanged in place.
5. **Build.** Add NCCL (`-lnccl`) to the kernel-bundle build
   (`compile_native_overlay.py` / the mkmf template).

**Phase B — move the two wind/field swaps onto the GPU (completes the picture).**

The velocity and tracer fields `vx` and `qx` are still swapped on the host before
the device work starts (`fv_advection.F90:194-195`). Phase A leaves those two on
the host; Phase B moves them onto NCCL the same way, so the host never touches a
halo. Needed for a clean "everything stays on the GPU" statement; not needed to
demonstrate the mechanism.

## Checking it is right (cheap, no climate run)

Because the math is unchanged and only the swap moves, the tracer field from the
GPU-to-GPU run should match the current host-swap run to rounding, for a handful
of steps. Compare with the existing A/B harness (`scripts/ab_compare.sh`) over a
short run. No long climate integration is required.

## What gets measured

Add a timer on the GPU-to-GPU exchange (alongside the existing phase timers) and
report, across resolutions:
- time per exchange and bytes moved, confirmed on-device (no host copies);
- the exchange as a share of the step, against the host-swap baseline already
  measured (~2.5 ms per call, ~4% of the run) and the spectral transpose's 24%.

## Effort

- Phase A: about **1 week of active development**, roughly **2-3 weeks elapsed**
  once the build-run-check loop on the cluster is counted (each check goes
  through a cluster run).
- Phase B: about **1 more week** active.

Most of the code is small and localized; the elapsed time is dominated by the
cluster turnaround and by getting the pole-reflection kernel and the build
integration right, not by volume of code.

## Risks and knobs

- **Build integration.** Threading `-lnccl` through the overlay build is the most
  likely source of friction (it is a bespoke build).
- **Pole reflection on the GPU.** The reflection indexing must match the host
  version exactly, or the correctness check drifts at the poles.
- **Only 2 GPUs here.** The demonstrator shows a pole-to-pole pair. Interior-rank
  behavior and scaling need more GPUs; the NCCL setup would extend to that, but
  multi-node NCCL uses the network path, not the on-node NVLink measured so far.

## Files touched

- `fv_advection_kernels_cuda.cu` — NCCL setup, pack/exchange/unpack, pole kernel,
  begin/finish edits.
- `fv_advection.F90` — rewire the resident halo path.
- `compile_native_overlay.py` / mkmf template — link NCCL.
- `tests/poc/` — reuse the smoke test and benchmark as references.
