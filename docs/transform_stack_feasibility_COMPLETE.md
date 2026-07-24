# Transform-stack GPU feasibility — COMPLETE (bootstrap summary)

**Status: effort closed 2026-07-24. Branch `gpu/transform-stack-feasibility`.**
This file is the entry point. Read it first, then follow the chain below only if
you need the derivation. No code was changed by this effort — it is an
analysis + measurement study with a go/no-go verdict.

## One-paragraph summary

We asked whether the spectral transform stack (Legendre + FFT + transpose) is a
worthwhile GPU port for the Held-Suarez configuration. Answer: the transform
region is **transpose-bound, not compute-bound**. GPU compute for Legendre/FFT
is bit-exact and fast in isolation (~590 GF/s at full tile), but at the real
per-rank tile the matrices are tiny and the CPU compute they would replace is
already cheap, so accelerating the *compute* moves the region almost not at all.
The only path with a real gain is replacing the hand-rolled `mpp_transmit`
transpose with a device-resident **CUDA-aware-MPI / NCCL all-to-all**. Even that
yields only **~1.1–1.2× whole-model at T42L25 / 16 ranks** (Amdahl-bounded by the
35.6% region share); the case gets materially stronger only at **rank-per-GPU /
higher resolution**. Verdict: **conditional go**, gated on re-checking the payoff
at a coarser decomposition before committing multi-week effort.

## The numbers that matter (all measured, not estimated)

| Quantity | Value | Where |
|---|---|---|
| Transform region share of runtime | **35.6%** (Amdahl cap on any transform win) | deep profile |
| Fourier transpose, directly measured | **~24% of total runtime** (~67% of the region) | T3-followup, clean 16-rank gpu015 run |
| GPU Legendre / FFT, full tile | bit-exact, **~590 GF/s** | T2 |
| GPU Legendre / FFT, real per-rank tile | **46 / 68 GF/s** (9–13× below ceiling) | T2 |
| Realistic whole-model gain (NCCL transpose) | **~1.1–1.2×** (1.14× if transpose halved, 1.19× if cut to 1/3, 1.32× ceiling) | T3 |
| Absolute Amdahl ceiling (whole 35.6% region → 0) | **1.55×** (unreachable) | T3 |

**Correction worth carrying forward:** an earlier 35–38% transpose figure was an
**oversubscription artifact** (16 ranks on 10 cores). On dedicated cores the
honest share is **~24%**. Always measure on 1-rank-per-core.

## Verdict

**Conditional go. The prize is the transpose, not the compute.**
- Naive per-call GPU offload → **NO** (transfer trap; net loss).
- Resident compute + host-staged transpose → **~neutral** (staging cost cancels compute saved).
- Resident compute + CUDA-aware-MPI / NCCL device-to-device transpose → **the only path with a gain**, and even then modest at this config.

## Decision

**Not pursuing this strategy for now (2026-07-24).** The measured payoff at
T42L25 / 16 ranks (~1.1–1.2× whole-model) does not justify the multi-week
CUDA-aware-MPI transpose redesign at this configuration. The analysis is
self-contained and committed; if this is revisited, the strongest case is at
rank-per-GPU / higher resolution, and a cheap CPU-only option (the
reverse-transpose load imbalance) remains available independent of any GPU work.

## Document chain (derivation, in order)

1. `docs/transform_stack_feasibility_plan.md` — the T1/T2/T3 plan.
2. `docs/transform_feasibility_analysis.md` — **T1**: structure, data volumes, transpose crossings.
3. `docs/transform_compute_prototype_results.md` — **T2**: measured GPU compute ceiling (H100), bit-exactness.
4. `docs/transform_feasibility_gono_go.md` — **T3 (final)**: transpose cost model, direct transpose measurement, three scenarios, full verdict.

Key commits: `f6d314d` (finalized go/no-go with measured transpose share),
`490f1ec` (reverted the timing scaffolding; tree clean).
