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

We confirmed this at both 2 GPUs and 4 GPUs. The 4-GPU run matters because it is
the first to exercise an **interior rank** — one with a real neighbor on both
sides and no pole to fold against, which the 2-GPU layout never produces. That
two-sided exchange also matched bit for bit, so the neighbor-swap code is proven
correct for the general case, not just the edge case.

## The host transfer was fully removed

On the new path, the count of host-side neighbor swaps dropped to zero — every
exchange now happens directly between GPUs. The host-to-device and device-to-host
copy times both fell, confirming the round trip through the CPU is gone.

## Runtime savings (averaged over 3 repeats each)

On **2 GPUs**, at low resolution (T85) the result was a wash, within noise: the
on-GPU exchange costs about what the removed transfer saved. At the next
resolution up (T170) it became a real win of about **2%**, because the transfer
removed was more than twice the cost of doing the exchange on the GPU.

On **4 GPUs**, the same two resolutions moved the other way: T85 was about **4.6%
slower** and T170 was a smaller win of about **1.2%**. Splitting the same grid
across twice as many GPUs makes each GPU's slice half as tall, and a shorter slice
has proportionally more edge to swap — so the exchange takes a bigger bite.

## The win is set by slice height, not resolution alone

The pattern across every run is governed by one number: how many rows of the grid
each GPU holds (the grid's latitude count divided by the number of GPUs). The swap
always moves a fixed two-row strip; the interior work grows with the number of
rows. So a taller slice makes the swap a smaller fraction and the win larger:

| rows per GPU | outcome |
| --- | --- |
| 32  | ~4.6% slower (T85 on 4 GPUs) |
| 64  | wash to ~1% win (T85 on 2 GPUs; T170 on 4 GPUs) |
| 128 | ~2% win (T170 on 2 GPUs) |

Finer resolution helps because it makes slices taller; adding GPUs at a fixed
resolution hurts because it makes them shorter. This is the opposite of the
spectral transpose, whose cost grows with resolution no matter how the work is
split — and it matches what the earlier standalone proof-of-concept predicted.

## The highest-resolution point could not be measured

T340 defeated both configurations, each in a different way. On **2 GPUs** each
GPU's memory filled to 96% of its 32 GB; the run thrashed and could not finish one
simulated day inside the time limit. Splitting across **4 GPUs** halved the
per-GPU memory and the model did step for over four hours — but the host-routed
reference run then died with a bus error, before finishing one day and before the
GPU-to-GPU path had its turn. A mid-run bus error points to a host-memory limit
(shared memory or output buffers), not a code fault. With no surviving reference
run there is nothing to compare against, so T340 stays unmeasured at both rank
counts. Based on slice height (T340 on 4 GPUs gives 128 rows per GPU, the same as
T170 on 2 GPUs) the expected result would be a win of roughly 2%, but that is a
projection, not a measurement.

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
moving its neighbor exchange onto the GPUs works, gives identical results (proven
bit for bit at both 2 and 4 GPUs, including the two-sided interior case), and
removes the host transfer entirely. It produces a measurable speedup once each
GPU's slice is tall enough — the benefit is set by slice height, so it grows with
resolution and shrinks as a fixed grid is spread over more GPUs. The
highest-resolution point (T340) could not be measured: memory-bound on 2 GPUs and
a host-memory bus error on 4. The larger prize remains replacing the spectral core
with the FV3 finite-volume core, where every step's global reshuffle becomes the
local, GPU-friendly exchange this work validated.
