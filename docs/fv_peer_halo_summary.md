# Filling the FV halo by a direct NVLink peer copy — summary

**Date 2026-08-04. Branch `gpu/fv-transfer-poc`.**

This is not an algorithm change — the FV advection math is untouched. It changes
only *how the halo is filled*, so it belongs with the transfer-mechanism work
(`fv_transfer_*`), not the spectral→FV algorithm-change summaries
(`fv_*_algorithm_change_summary.md`).

## The idea being tested

The earlier FV-transfer work moved the advection Y-halo — the only cross-GPU
dependency in the whole operator — off the host and directly between GPUs with
NCCL, bit-exact at 2 and 4 GPUs. That path still carried cluster-era machinery:
it **packs** the edge rows into a staging buffer, issues grouped
`ncclSend`/`ncclRecv`, then **unpacks** into the halo. On four NVLinked V100s
that machinery is the cost — the edge strip itself is only ~200–330 KB and moves
in about a microsecond, while the pack and unpack kernels and the NCCL group
calls dominate.

This experiment pushed the algorithm-change thesis to its sharpest point: on a
single NVLinked node the halo *exchange* concept dissolves entirely. A neighbor's
memory is directly addressable over NVLink, so the halo can be filled by **one
strided copy that reads the neighbor's interior edge rows straight into my halo
rows** — no packing, no send/receive, no unpacking, no staging buffer. It reaches
the same numerical result by deleting the communication abstraction rather than
accelerating it.

## What we built

A third halo backend, selected at runtime alongside the existing host and NCCL
paths. It is gated by a build flag (`USE_FV_ADVECTION_PEER` /
`-DFV_ADVECTION_USE_PEER`) and an environment switch (`FV_ADVECTION_PEER_HALO`),
mirroring the NCCL wiring across all seven files. The shared code the two
GPU-to-GPU paths have in common — the pole folds and the begin/finish dispatch —
now sits under one umbrella (`FV_ADVECTION_DEVICE_HALO`, defined when either
path is built). The three backends are mutually exclusive at runtime; every flux
kernel, the pole folds, and the compute-stream gate are untouched. Only the
mechanism that fills the halo changes.

The fill itself is, per field and per side, a single `cudaMemcpy2DAsync`: my
south halo rows are pulled from the south neighbor's interior edge, my north halo
rows from the north neighbor's interior edge. A rank that owns a pole has no
neighbor on that side and reflects through the existing device fold, unchanged.

## Two capabilities had to be proven first

**Cross-process peer addressing (CUDA IPC).** One rank per GPU means one process
per GPU, so a raw device pointer from a neighbor is meaningless in my address
space. Each rank exports a handle to its resident buffer with
`cudaIpcGetMemHandle`; the neighbor imports it with `cudaIpcOpenMemHandle` to get
a locally valid pointer, then offsets to the edge rows. Handles are exchanged
once over host-only `MPI_Sendrecv`, because the resident buffers are fixed for
the run. This was the real feasibility gate — IPC is a distinct capability from
the peer access NCCL already uses, and some container and driver configurations
disable it. **It works in the isca-debian container** (topology NV2, all
ordered pairs report `canAccessPeer=1`).

**Ordering.** NCCL's send/receive gave producer–consumer ordering for free; a
pull must supply it explicitly. The model's halo uploads are synchronous and each
call ends with a device synchronize, so a single barrier before the copy
guarantees the neighbor's edge holds the current step's data, and the
end-of-call synchronize guarantees no neighbor overwrites it early. The
standalone benchmark needed interprocess CUDA events for the same guarantees;
inside the model those are unnecessary, which keeps the model path simple.

## What was proven

**Bit-exactness — the pass/fail line for the numerics — passed.** The peer path
is designed to reproduce the host halo update and the polar fold exactly, so the
two runs must match bit for bit. Host-routed versus peer reported *all 20 fields
identical* at both **2 GPUs and 4 GPUs**. The 4-GPU run is the one that matters:
it is the first to exercise an **interior rank** — one with a real neighbor on
both sides and no pole to fold against — which the 2-GPU layout never produces.
That two-sided pull matched bit for bit, so the peer-copy geometry, the handle
exchange, and the ordering are proven correct for the general case, not just the
edge case.

**Standalone speed — passed, before any model wiring.** The Phase 1 benchmark
byte-verified the pull geometry and timed the peer copy head-to-head against the
NCCL exchange at matching edge sizes. The peer copy was about **26–27% faster**
at 2 ranks (T85, 256×128×25: 0.0185 vs 0.0252 ms; T170, 512×256×25: 0.0236 vs
0.0317 ms). Every time is in the 20–30 µs range, which means both paths are
governed by fixed overhead, not by the bandwidth of the strip — exactly the
regime in which deleting the pack/unpack machinery should help, and it does.

## What was not measured

The in-model three-way transfer-cost comparison — host versus NCCL versus peer
at T85 and T170 — **was not run.** The task was stopped after the bit-exact gate
passed. The one in-model timing observed in passing was a host-routed-versus-peer
contrast during the correctness run (peer begin averaged ~1.71 ms against
~5.79 ms host-routed), which measures peer against the *host* path, not against
NCCL, and so is not the comparison the thesis rests on. The claim that the peer
copy beats NCCL inside the running model therefore stands on the standalone
benchmark alone, not on an end-to-end measurement.

## Bottom line

The peer-copy halo is code-complete, committed, and proven bit-exact against the
host path at both 2 and 4 GPUs, including the two-sided interior rank. It
demonstrates the thesis in its strongest form: on one NVLinked node the halo
*exchange* is a cluster-era artifact — the neighbor's memory is directly
addressable, and a single strided copy fills the halo with no packing, sending,
or staging. The standalone benchmark shows that copy is ~26% faster than the NCCL
exchange at the sizes tested, in an overhead-bound regime where removing the
machinery is what pays. The one gap is the in-model three-way timing sweep, which
was not run before the task was stopped; the end-to-end speed claim is a
standalone-benchmark figure, not a whole-model measurement.
