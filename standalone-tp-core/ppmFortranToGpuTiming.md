Results are in, and they tell a clear story. First — the checksums match CPU vs GPU to ~6 significant figures in every single case (e.g. 9.6402243855e+03 vs 9.6402243977e+03), which independently confirms both drivers compute the same thing; the tiny差 is the FMA rounding we discussed.

Speedup (CPU single core ÷ GPU, ms/iter)

┌─────┬────────┬─────────────┬──────────┬──────────┬───────┬──────────┬──────────┬───────┐
│ Res │ levels │ ncol (yppm) │ yppm CPU │ yppm GPU │ yppm  │ xppm CPU │ xppm GPU │ xppm  │
├─────┼────────┼─────────────┼──────────┼──────────┼───────┼──────────┼──────────┼───────┤
│  96 │      1 │         102 │   0.0202 │   0.1768 │ 0.11× │   0.0198 │   0.1357 │ 0.15× │
├─────┼────────┼─────────────┼──────────┼──────────┼───────┼──────────┼──────────┼───────┤
│  96 │     64 │        6528 │   1.2992 │   0.1746 │ 7.4×  │   1.2229 │   0.1723 │ 7.1×  │
├─────┼────────┼─────────────┼──────────┼──────────┼───────┼──────────┼──────────┼───────┤
│ 192 │      1 │         198 │   0.0657 │   0.3433 │ 0.19× │   0.0633 │   0.3411 │ 0.19× │
├─────┼────────┼─────────────┼──────────┼──────────┼───────┼──────────┼──────────┼───────┤
│ 192 │     64 │       12672 │   4.3651 │   0.6799 │ 6.4×  │   4.2107 │   0.6699 │ 6.3×  │
├─────┼────────┼─────────────┼──────────┼──────────┼───────┼──────────┼──────────┼───────┤
│ 384 │      1 │         390 │   0.2321 │   0.6501 │ 0.36× │   0.2306 │   0.6506 │ 0.35× │
├─────┼────────┼─────────────┼──────────┼──────────┼───────┼──────────┼──────────┼───────┤
│ 384 │     64 │       24960 │   16.599 │   2.6589 │ 6.2×  │   16.306 │   2.6451 │ 6.2×  │
└─────┴────────┴─────────────┴──────────┴──────────┴───────┴──────────┴──────────┴───────┘

(<1× means the GPU is slower.)

What it means

- The GPU needs to be fed. At levels=1 (a few hundred columns) the GPU is 3–9× slower than one CPU core — it's pure launch/latency overhead. Notice the GPU time barely moves from levels=1→64 at Res=96 (0.177 → 0.175 ms): 64× the work for free, because at levels=1 the A100 was almost idle. Occupancy is everything.
- At realistic load it's ~6–7× and stable. Once there are thousands of columns (levels=64), the GPU holds a steady ~6–7× across all resolutions for both routines.
- It's memory-bandwidth-bound. PPM is low arithmetic intensity, so the plateau at ~6–7× (not 50×) reflects HBM-vs-DRAM bandwidth, not FLOPs.

The honest caveat

This is GPU vs one CPU core. The baseline is single-threaded; production FV3 uses the whole node (many cores via MPI/OpenMP). So "6–7×" is per core, not "6–7× a CPU node." On a ~48-core node a fully-parallel CPU run of this bandwidth-bound kernel could rival or beat the single A100 here. To make a node-level claim we'd need a threaded CPU baseline — say the word and I'll add OpenMP to the CPU drivers.

Ties directly to #1

The levels result is the headline for the device-resident GPU fv_tp_2d (saved, not forgotten): batching all vertical levels into one kernel launch is what moves you from the slow levels=1 regime into the fast plateau. An orchestrator that keeps data on the device and launches xppm/yppm once across all levels is exactly how you'd capture that — and it also amortizes the launch overhead that dominates the small cases.

-----------------------------------------------------
Here's the original Fortran vs GPU comparison. And the three-way checksums confirm correctness: Fortran and C++ CPU match exactly (e.g. yppm 96/1 both 9.6402243855E+03), and the GPU matches to ~7 sig figs (...3977, FMA). Same scheme in all three.

Original Fortran vs GPU (ms/iter, and speedup)

yppm

┌─────┬─────┬─────────┬────────┬─────────┐
│ Res │ lev │ Fortran │  GPU   │ speedup │
├─────┼─────┼─────────┼────────┼─────────┤
│  96 │   1 │  0.0193 │ 0.1773 │  0.11×  │
├─────┼─────┼─────────┼────────┼─────────┤
│  96 │  64 │  3.2874 │ 0.1921 │  17.1×  │
├─────┼─────┼─────────┼────────┼─────────┤
│ 192 │   1 │  0.1779 │ 0.3429 │  0.52×  │
├─────┼─────┼─────────┼────────┼─────────┤
│ 192 │  64 │  9.3913 │ 0.7867 │  11.9×  │
├─────┼─────┼─────────┼────────┼─────────┤
│ 384 │   1 │  0.7282 │ 0.7200 │  1.0×   │
├─────┼─────┼─────────┼────────┼─────────┤
│ 384 │  64 │  38.976 │ 2.6998 │  14.4×  │
└─────┴─────┴─────────┴────────┴─────────┘

xppm

┌─────┬─────┬─────────┬────────┬─────────┐
│ Res │ lev │ Fortran │  GPU   │ speedup │
├─────┼─────┼─────────┼────────┼─────────┤
│  96 │  64 │  1.2131 │ 0.1708 │  7.1×   │
├─────┼─────┼─────────┼────────┼─────────┤
│ 192 │  64 │  4.3197 │ 0.7276 │  5.9×   │
├─────┼─────┼─────────┼────────┼─────────┤
│ 384 │  64 │  17.831 │ 2.8252 │  6.3×   │
└─────┴─────┴─────────┴────────┴─────────┘

(levels=1 is GPU launch-overhead-bound — ignore for the real story.)

The interesting finding: yppm's bigger speedup is partly memory layout, not just parallelism

Look at the Fortran yppm vs Fortran xppm at levels=64: yppm is ~2× slower (384: 38.98 vs 17.83 ms). But the C++ CPU and GPU versions show no such gap. Why?

- Fortran yppm sweeps the j (second) index of q(i,j) → strided memory access (stride = number of columns), cache-unfriendly. This is the native FV3 layout.
- Fortran xppm sweeps i (first index) → contiguous, cache-friendly.
- My C++/GPU drivers store each sweep line contiguously regardless of direction, so the C++ CPU yppm (1.29 ms at 96/64) is already ~2.5× faster than Fortran yppm (3.29 ms) — before any GPU.

So the speedups decompose cleanly:
- xppm: ~6–7× = pure parallelism (Fortran already had the good layout).
- yppm: ~12–17× = ~6–7× parallelism × ~2× from the contiguous layout the port introduced.

That layout win is real and free — it'd benefit a CPU rewrite too — but it means the honest "GPU parallelism" factor for both routines is ~6–7× vs one CPU core (consistent with the earlier C++-CPU comparison), with yppm getting an extra ~2× because the original Fortran's y-sweep is memory-strided.

Caveats (unchanged)

Single-threaded Fortran on one core — a full node (many MPI ranks/threads) would narrow this for these bandwidth-bound kernels; GPU time is kernel-only with data resident; levels=64 is the representative load.

------------------------

Throughput at levels=64 (each iteration processes 64 tiles), ms/iter

┌─────┬──────────────┬─────────┬───────┬────────────────┬────────────┐
│ Res │ Fortran ×64¹ │ C++ CPU │  GPU  │ GPU vs Fortran │ GPU vs C++ │
├─────┼──────────────┼─────────┼───────┼────────────────┼────────────┤
│  96 │         6.56 │   12.42 │  1.50 │      4.4×      │    8.3×    │
├─────┼──────────────┼─────────┼───────┼────────────────┼────────────┤
│ 192 │         33.3 │   56.35 │  4.77 │      7.0×      │   11.8×    │
├─────┼──────────────┼─────────┼───────┼────────────────┼────────────┤
│ 384 │        164.3 │   250.3 │ 17.06 │      9.6×      │   14.7×    │
└─────┴──────────────┴─────────┴───────┴────────────────┴────────────┘

¹ Fortran is single-tile; ×64 is the serial-tile extrapolation (the honest CPU-core baseline, since the C++ reference is gather-based and slower).

The batching effect — why this is the whole story

┌─────┬────────────────────────┬─────────────────────────┬───────────────┐
│ Res │ GPU levels=1 (ms/tile) │ GPU levels=64 (ms/tile) │ per-tile gain │
├─────┼────────────────────────┼─────────────────────────┼───────────────┤
│  96 │                  1.101 │                  0.0234 │      47×      │
├─────┼────────────────────────┼─────────────────────────┼───────────────┤
│ 192 │                  2.023 │                  0.0745 │      27×      │
├─────┼────────────────────────┼─────────────────────────┼───────────────┤
│ 384 │                  3.896 │                   0.267 │      15×      │
└─────┴────────────────────────┴────────────┘
                                                                                                                     Look at C96: 64 tiles cost 1.50 ms vs 1.10 m1.36× the time. At one tile the A100 wasalmost idle (pure launch + occupancy overhead); the batch fills the line-parallel PPM steps ((n+6)·64 lines) and     amortizes the 9 launches across all tiles. T-yppm levels=1→64 lesson, now realized forthe full operator — and it's what flipped fv_tp_2d from losing at one tile (0.11–0.79×) to winning by 4–10× over     Fortran.
                                                                                                                     The trend also improves with resolution (4.4with a bandwidth-bound kernel getting betteramortization and occupancy at scale.                                                                                 
Honest caveats (unchanged)                                                                                           
- One CPU core. "4–10×" is vs a single core; a full node (dozens of MPI ranks across the 64 tiles) would narrow it — quite possibly to parity for these bandwidthclaim needs a threaded/MPI CPU baseline.
- Kernel-only GPU time, data resident — the correct production metric (and the reason the orchestrator keeps
everything on-device across the 9 steps).
- Single precision; uniform synthetic grid.

