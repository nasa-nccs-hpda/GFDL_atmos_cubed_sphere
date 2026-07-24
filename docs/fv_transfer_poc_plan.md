# Testing whether switching methods removes the GPU slowdown — a proof of concept

**Status: plan, not started. Date 2026-07-24. Branch `gpu/transform-stack-feasibility`.**

## The question

Does changing the underlying method actually get rid of the GPU slowdown we
kept hitting?

The old "spectral" method had one slow step where every processor swaps data
with every other processor at once. On GPUs that step is especially costly,
because the data has to keep leaving the GPU, going back to the regular
processor to do the swap, and returning. We measured it: that one step ate
about a quarter of the whole run and put a low ceiling on any GPU speedup (see
`docs/transform_stack_feasibility_COMPLETE.md`).

The "FV" method does not have that step. Its processors only ever talk to their
immediate neighbors, which is a small exchange that can happen GPU-to-GPU
without dropping off the GPU. This proof of concept checks one thing, and
nothing more:

> When the FV method runs across several GPUs, is the data traffic between
> those GPUs small, and does it stay on the GPUs — unlike the old method's big
> swap that had to leave them?

If yes, then swapping the method really is a good way to beat the slowdown, and
the general strategy is proven. This is a test of *speed*, not of whether the
weather comes out right.

## What this proof of concept is NOT

- It does not try to produce a correct climate. No long runs.
- It does not use the Held-Suarez test's forcing. That part has nothing to do
  with the traffic problem.
- It does not build a full working model or check the answer against a known
  reference.
- It does not match the old method's size or settings.

All of that belongs to a later, bigger effort — only worth doing if this proof
of concept comes out well.

## What we already have (and can reuse)

We checked the code. The hard groundwork is already in place:

- A real run that splits the FV work across **16 processors at once**, launched
  through the existing scripts.
- Those processors already do the **neighbor-to-neighbor talking** we care
  about.
- The FV math already **runs on a GPU**, with work done earlier to keep the
  data sitting on the GPU between steps.
- A small standalone version that runs one FV piece on a single GPU, needing
  almost nothing to set up.

Building all of that from scratch would have been the expensive part, and it is
done.

## What is missing (what we would build)

Two limits stop the current setup from answering the question:

1. All 16 processors currently share **one** GPU, so it is not really running
   on several GPUs yet.
2. The neighbor talking happens back on the **regular processor**, not
   GPU-to-GPU — the exact move we are trying to avoid.

Three additions fix this. Only the middle one is real work.

**Addition 1 — give each processor its own GPU (small).** Right now they all
pile onto one. Spreading them out is a well-understood, quick change. A few
hours to a day.

**Addition 2 — make the neighbor swap go GPU-to-GPU (the real work).** Today the
edge data drops off the GPU, gets swapped on the regular processor, and comes
back. We make it go straight from one GPU to the next. This is the single thing
the whole test hinges on, and it is also something any real multi-GPU FV effort
would need anyway, so it is not wasted work. A few days to about two weeks — all
the uncertainty is here.

**Addition 3 — put a stopwatch on the between-GPU traffic (small).** So we can
report exactly what share of the run it takes. A few hours.

## The measurement

Run the modified version for a short stretch — minutes, just long enough to get
a steady timing picture, not long enough for any climate. Record:

- How big a share of the run the between-GPU traffic takes.
- Whether it stays on the GPUs.
- The same at two or three sizes, from small on up.

## How we decide pass or fail

**Pass** if both are true:

1. The between-GPU traffic is a **small share** of the run and stays on the
   GPUs — clearly under the old method's quarter-of-the-run figure.
2. That share **gets smaller as the problem gets bigger.** This is the clinching
   point: neighbor talking grows with the *edge* of each processor's piece,
   while the math grows with the *whole* piece, so the traffic should matter
   less and less as you scale up — the opposite of the old method, whose slow
   step did not shrink.

**Fail or unclear** if the between-GPU traffic is a large share, or does not
shrink as the problem grows. That would mean the FV method just trades one
traffic problem for another, and switching methods is not the clean win we
assumed.

## Effort, risk, and what it needs

- **Building it:** about one to two weeks, almost all of it in Addition 2.
- **Running it:** minutes. Trivial next to the building.
- **Main risk:** the GPU-to-GPU swap turns out harder than hoped — for example,
  the tools in our run environment do not support it directly and we have to add
  another piece. That affects how long the build takes, not whether the result
  is trustworthy.
- **Hardware:** more than one GPU on the machine (the current setup assumes
  one).

## Order of work

1. Additions 1 and 3 (own-GPU-per-processor, and the stopwatch) — cheap, do
   first. Even before the main change, this lets us measure the current
   host-side traffic as a baseline.
2. Addition 2 (the GPU-to-GPU swap) — the core build.
3. Measure across two or three sizes.
4. Write up the result — the traffic share, whether it stayed on the GPUs, and
   whether it shrank with size — against the old method's quarter-of-the-run
   figure. That is the go/no-go on the whole strategy.
