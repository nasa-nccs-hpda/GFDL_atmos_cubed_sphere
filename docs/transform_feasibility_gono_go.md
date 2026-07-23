# Transform-stack GPU feasibility — T3: transpose cost model + go/no-go

Phase T3 (final) of `docs/transform_stack_feasibility_plan.md`. Analysis only,
built on:
- T1 structure/volumes — `docs/transform_feasibility_analysis.md`
- T2 measured compute ceiling (H100) — `docs/transform_compute_prototype_results.md`
- Deep wall-time profile (30-day, MPP `tmax=24.136 s`, 4320 steps) —
  `docs/dynamics_deep_profile_recommendation.md`

## Measured inputs (not estimated)

| Quantity | Value | Source |
|---|---|---|
| Transform region share | **35.6%** of MPP runtime (8.60 s) | deep profile |
| Per-rank transform region | **1.99 ms / timestep** (8.60 s / 4320) | deep profile |
| Transposes per timestep | **13 crossings** (11 full + 2 single-level) | T1 |
| Off-rank volume per full transpose | **≈0.98 MiB**, 15 msgs/rank, +1 barrier | T1 |
| GPU Legendre, per-rank tile, resident | **0.020 ms** kernel-only | T2 |
| GPU FFT, per-rank tile, resident | **0.0033 ms** kernel-only | T2 |
| Per-rank GFLOP/s vs full tile | **46 vs 587** (Legendre), 68 vs 589 (FFT) | T2 |
| **Fourier transpose, directly measured** | **≈24% of total runtime** (avg over ranks) | T3-followup |

The 1.99 ms/step **already includes** the CPU compute *and* the MPI transpose —
it is the baseline we must beat.

### T3-followup: the transpose is now directly measured

`transpose_fourier` and `reverse_transpose_fourier` in `transforms.F90` were
instrumented with `system_clock` and the standard 30-day H-S was run **clean**
(T42L25, 16 ranks, 1 rank/core on a 40-core node, no oversubscription):

| Quantity | Value |
|---|---|
| Total runtime (`mpp_clock`) | **58.71 s** (4320 steps ⇒ 13.6 ms/step) |
| Forward transpose (5 calls/step) | avg **6.91 s/rank**, 0.320 ms/call |
| Reverse transpose (10 calls/step) | avg **7.04 s/rank**, 0.163 ms/call |
| Transpose total per rank | avg **13.95 s** (range 11.9–17.3 s) |
| **Transpose share of total** | **avg 23.8%, range 20.3–29.4%** |

Two things this settles:

1. **The earlier 35–38% figure was an oversubscription artifact.** That run put
   16 ranks on 10 cores; the 15 `mpp_sync()` barriers/step absorbed core-
   contention idle, inflating both the region and the total. On dedicated cores
   the total drops 3.1× (183.8 s → 58.7 s) and per-call transpose drops 4–5×
   (fwd 1.28→0.32 ms, rev 0.88→0.16 ms). The honest share is **~24% of total**,
   not ~36%.
2. **The region is transpose-bound, at the low end of the prediction.** With the
   transform region at 35.6% of runtime, the transpose is ≈ 24/35.6 ≈ **67% of
   the region** — inside the 65–85% predicted below, but at the bottom of it. So
   the transpose still dominates the region, but less overwhelmingly than the
   oversubscribed number suggested.

There is also a clear **load imbalance in the reverse transpose**: ranks 11–15
spend ~9.5 s (≈29% share) vs ~5.5–6.4 s (≈21%) on ranks 0–10. This is a property
of the hand-rolled `mpp_transmit` decomposition, not the arithmetic, and is
recoverable independent of any GPU work.

## The cost model

Decompose the transform region per timestep into compute and transpose:

```
region_cpu  =  C_cpu  +  T        =  1.99 ms/step   (measured total)
```

- **C_gpu (resident compute)** — 13 transforms × (Legendre 0.020 + FFT 0.0033) ms
  ≈ **0.30 ms/step** kernel-only. With ~4 kernel launches per transform at
  ~5-10 µs launch overhead each (the kernels are so small that launch latency is
  comparable to the kernel), realistic resident compute ≈ **0.4-0.6 ms/step**.
- **C_cpu (CPU compute)** — the per-rank problem is tiny: ~0.4 MFLOP per
  transform over 3 wavenumbers / 4 latitudes (T1). A competent core does that in
  tens of µs; 13 transforms ⇒ C_cpu is at most a few tenths of a ms.
- **T (transpose)** — **now measured directly, not inferred.** On dedicated
  cores the transpose is **≈24% of total runtime ≈ 67% of the transform
  region**, i.e. still **the dominant term**, at the low end of the 65-85% band
  the subtraction argument had bracketed. The subtraction estimate
  (T ≈ 1.99 − C_cpu) pointed the right way; the direct measurement pins it.

### Independent check on T (α-β model)

Per full transpose: 15 messages/rank of ~65 KiB, 0.98 MiB off-rank, + a barrier.

| Interconnect assumption | latency term | bandwidth term | per call | ×13 |
|---|---|---|---|---|
| Fast IB (1.5 µs, 20 GB/s) | 22 µs | 51 µs | ~0.10-0.15 ms | **1.3-1.9 ms** |
| Contended (3 µs, 8 GB/s) | 45 µs | 128 µs | ~0.18-0.22 ms | **2.3-2.9 ms** |

The α-β estimate (1.3-2.9 ms/step) **brackets and corroborates** the
1.3-1.7 ms inferred by subtraction. Both routes say the same thing: **the
transform region at T42L25/16 ranks is transpose-bound.** The hand-rolled
`mpp_transmit` ring with 13 host barriers/step, not the arithmetic, is the cost.

## Three scenarios

Let region′ be the accelerated transform region. Whole-model speedup =
`1 / (0.644 + 0.356 · region′/region_cpu)` (Amdahl, 35.6% share).

### A. Naive per-call GPU offload — **NO**
Each transform: H2D → Legendre(GPU) → D2H → transpose(MPI/host) → H2D →
FFT(GPU) → D2H. Adds **26 transfers/step**; T2 puts per-stage transfer at
~0.03-0.05 ms ⇒ **+0.8-1.3 ms/step**, on top of an unchanged transpose, to save
a compute term that was only a few tenths of a ms. `region′ > region_cpu`.
**Net loss** — the transfer trap, exactly as advection hit and T1 warned.

### B. Resident compute + host-staged transpose (no CUDA-aware MPI) — **marginal / NO**
Ride the committed resident spine, so Legendre+FFT are transfer-free
(C_gpu ≈ 0.5 ms). But every transpose still crosses the host: D2H before + H2D
after ⇒ **26 transfers/step** for the fourier staging (~0.98 MiB each way).
That staging cost (~0.8-1.3 ms/step) roughly cancels the compute saved.
`region′ ≈ region_cpu`. **≈ neutral at this config; not worth the redesign.**

### C. Resident compute + CUDA-aware MPI / NCCL device-to-device transpose — **the only path with a gain**
No transfers anywhere; the transpose is device→device. Two effects:
1. Compute drops C_cpu → C_gpu (small, since both are small).
2. **The transpose itself can get faster** — an optimized NCCL all-to-all vs the
   hand-rolled pairwise ring + 13 host barriers. *This is the real lever,
   because the region is transpose-bound.*

Whole-model speedup depends almost entirely on how much (2) cuts T. With the
transpose now **measured at 24% of total runtime**, `speedup = 1 / (0.76 +
0.24·T′/T)`:
- If NCCL only matches the current transpose (T′ = T): **~1.0× (no gain)** —
  compute was never the bottleneck.
- If NCCL halves the transpose (T′ = T/2, plausible: no host barriers, coalesced
  device buffers, and it also erases the rank 11–15 imbalance): saves ~12% ⇒
  whole-model **≈ 1.14×**.
- If NCCL cuts the transpose to a third (T′ = T/3): saves ~16% ⇒ whole-model
  **≈ 1.19×**.
- If the transpose vanished entirely: **1.32×** — the ceiling from the transpose
  term alone.

**Amdahl ceiling** (entire 35.6% region → 0, transpose *and* compute): whole-
model **1.55×** — the absolute best case, unreachable because the transpose
cannot vanish.

## Verdict

**Conditional go — but the prize is the transpose, not the compute, and the
payoff at T42L25/16-rank is modest. With the transpose now measured at 24% of
total runtime, the realistic whole-model gain is ~1.1-1.2×.**

1. The GPU-compute question T2 was built to answer is settled and *favorable*:
   the halves are bit-exact and run at ~590 GF/s at full tile. But at the real
   16-rank per-rank tile the matrices are so small (46/68 GF/s, ~9-13× below the
   ceiling) and the CPU compute they'd replace is so cheap that **accelerating
   the compute alone moves the transform region almost not at all.**
2. The transform region is **transpose-bound**. Any real gain must come from
   making the transpose faster (device-resident + NCCL all-to-all), which also
   makes the resident compute free. Naive offload (A) loses; host-staged
   residency (B) is ~neutral; only CUDA-aware MPI (C) can win.
3. Even in the best realistic case the whole-model gain is ~1.1-1.2× (measured
   transpose share 24% ⇒ 1.14× if halved, 1.19× if cut to a third, 1.32×
   ceiling) — bounded by the 35.6% Amdahl share. The strong case is
   **rank-per-GPU / higher resolution**, where per-rank matrices fill the GPU
   (compute win grows toward the 100× / 590 GF/s ceiling) and the compute
   fraction of the region rises.

## Recommendation (post-measurement)

**T3-followup is done** (the transpose is instrumented and measured; see above),
so the uncertainty the earlier draft flagged is resolved. Measured T is a large
fraction of the region (~67%, ≳60% as the model predicted), which lands us on
the first branch:

- The port is a **CUDA-aware-MPI transpose project** on the resident spine (NCCL
  all-to-all), *not* a compute port. Accelerating Legendre+FFT alone moves the
  region almost not at all; the win must come from the transpose.
- **But the T42L25/16-rank payoff is modest (~1.1-1.2× whole-model), so its
  value should be re-checked at a coarser decomposition / higher resolution
  before committing multi-week effort.** At rank-per-GPU / higher res the
  per-rank matrices fill the GPU and the compute fraction of the region rises,
  which is where the case gets materially stronger.
- A cheaper intermediate worth noting: the **reverse-transpose load imbalance**
  (ranks 11–15 at ~29% vs ~21%) is a pure-CPU MPI-decomposition issue that could
  be addressed without any GPU work.

This is consistent with every prior doc: transforms are a **design-scale
commitment gated by the transpose**, now quantified — a transpose-bound region
whose acceleration is a CUDA-aware-MPI redesign with an honest ~1.1-1.3×
whole-model ceiling at the current config, and a materially better case only at
rank-per-GPU / higher resolution.
