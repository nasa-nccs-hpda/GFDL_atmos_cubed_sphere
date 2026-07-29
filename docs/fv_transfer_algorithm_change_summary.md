# Reducing GPU data transfer by changing the algorithm

Testing whether a local-stencil method moves less GPU data than the spectral core.

## The idea being tested

The spectral method the model uses must shuffle data across all GPUs through the
host (CPU memory) on every step — a "transpose" that eats about a quarter of the
runtime and grows worse as resolution rises. A local-stencil method like
finite-volume (FV) only swaps a thin strip of edge data with its two neighbors,
which can travel GPU-to-GPU over the fast NVLink connection and never touch the
host. The question was whether a local-stencil method genuinely avoids that
transfer cost.

## We did not replace the spectral algorithm

The spectral core, and its host-staged transpose, still run in the model. We used
a piece already present in the code — an **FV advection kernel**, a local-stencil
computation that advances fields by looking only at nearby cells — as a stand-in
for what a local-stencil method's data movement looks like. A full FV replacement
for the spectral core would be a large separate project and was not attempted.

## What we built

We took that existing multi-GPU FV advection kernel and moved every neighbor
edge-data swap (three of them) off the host and directly between GPUs over NVLink.
A runtime switch turns the new path on or off, so one program can run either way
for a fair comparison.

## The result did not change

Rerouting the data GPU-to-GPU is a plumbing change, not a math change — the
finite-volume computation is identical either way. With the new path on, output
matched the old host-routed version bit for bit across all 20 fields. This checks
that the new plumbing is correct; it is **not** a comparison of spectral versus FV.

## The host transfer was fully removed

On the new path, the count of host-side neighbor swaps dropped to zero — every
exchange now happens directly between GPUs. The host-to-device and device-to-host
copy times both fell, confirming the round trip through the CPU is gone.

## Runtime savings (2-GPU runs, averaged over 3 repeats)

At low resolution (T85) the result was a wash, within noise: the on-GPU exchange
costs about what the removed transfer saved. At the next resolution up (T170) it
became a real win of about **2%**, because the transfer removed was more than twice
the cost of doing the exchange on the GPU.

## The savings grow with resolution

As the grid gets finer, the edge data that must be swapped grows more slowly than
the interior work, so the exchange cost shrinks relative to the whole. The win
appears and widens with resolution — the opposite of the spectral transpose, whose
cost grows. This matches what the earlier standalone proof-of-concept predicted.

## The highest-resolution point is still missing

At T340 on 2 GPUs, each GPU's memory filled to 96% of its 32 GB; the run thrashed
and could not finish one simulated day inside the time limit, so it was cancelled —
memory-bound, not stuck. The fix was to split across 4 GPUs, halving per-GPU
memory, but the scheduler kept granting only 2 GPUs per job despite requesting 4,
and a 4-GPU node did not free up in time. No policy blocks 4 GPUs; it is a
request-syntax and availability issue still open.

## What the real algorithm change would be

Removing the transfer cost for good means retiring the spectral method, not tuning
it — the global reshuffle is intrinsic to computing in spherical-harmonic space.
The target is the **FV3 finite-volume cubed-sphere core** already implied by this
repository: it drops the Fourier and Legendre transforms (and the transpose with
them), computes with local flux operators that read only neighboring cells, and
communicates only by nearest-neighbor halo exchange — the exact GPU-to-GPU pattern
we validated. The trade-offs: it is a much larger solver to wire up, its results
would match the spectral model only in a statistical (climate) sense rather than
bit for bit, and per-GPU memory becomes the leading design constraint — the aborted
T340 run is the early warning of that.

## Bottom line

We did not change the model's algorithm. We gathered evidence *for* the
algorithm-change strategy by measuring a representative local-stencil computation:
moving its neighbor exchange onto the GPUs works, gives identical results, removes
the host transfer entirely, and already produces a measurable speedup at moderate
resolution that grows as resolution rises. The next concrete step for the transfer
win is the highest-resolution measurement (pending a 4-GPU allocation); the larger
prize is replacing the spectral core with the FV3 finite-volume core, where every
step's global reshuffle becomes the local, GPU-friendly exchange this work
validated.
