# FV-Advection CUDA Residency Optimization — 5-Task Summary

Branch `perf/resident-semi-y-integration`. The five tasks moved the FV-advection hot
path onto the GPU and stripped redundant host↔device (H2D) traffic, holding numerics
bit-exact against the Fortran/CPU baselines. **Context for scale:** FV-advection is only
~6% of model wall time at T85 and ~2.6% at T170, so large in-path speedups translate to
modest whole-model gains.

## Tasks (each builds on the last)
- **1 — `semi_y_3d` resident:** Added a `PersistentContext` of reusable device buffers so
  the meridional-advection computation stays on the GPU across calls; established the
  residency infrastructure.
- **2 — q1 halo-only + `d_q2` fix:** Finish phase transfers only q1 halo rows (not full
  fields); fixed an incorrect resident `q2` computation.
- **3 — divergence fold (`ce4ddc2`):** New on-device kernels compute `uc/vc/div` and
  `dq = q·div` in the begin phase; dropped the host divergence loop and `uc/vc/dq_dt`
  uploads (per-call H2D ~6·count → ~3·count).
- **4 — resolution scaling (`91eebe0`):** Parameterized runner by resolution/levels/
  timestep; found kernel savings grow with grid while transfer cost amortizes, and
  identified the remaining win — 6 constant grid metrics still re-uploaded every call.
- **5 — resident grid-metrics (`8d516b6`):** Upload the 6 run-constant metrics once
  instead of per-call; per-timestep fields still transfer each call.

## Performance and evaluation
Isolated same-node A/B, per-rank average over 16 ranks. Signs: negative = faster/less.
The "advection share of wall" column is a *fraction* (how big advection is), not a change.
Whole-model speedup = advection time reduction × advection's share of the wall.

| Resolution | Advection H2D | Advection time | Advection share of wall | Whole-model speedup |
|---|---|---|---|---|
| T85  | −82% | −27% | 6.0% | **−1.6% (faster)** |
| T170 | −52% | −17% | 2.6% | **−0.4% (faster)** |

- Kernel time is unchanged across the A/B, confirming the gains come from eliminated
  transfers, not altered compute.
- Numerics are **bit-exact** at both T85 and T170 (Fortran = CPU = CUDA, zero error).
- The whole-model figures are estimates (advection time reduction × wall share); direct
  wall measurement cannot resolve a sub-1% delta through run-to-run noise.

## Net result
Advection-path H2D traffic cut by roughly half to four-fifths with identical model
results — a large win within the path, and a real but small whole-model improvement
(~1.6% at T85, ~0.4% at T170) given advection's ~2–6% share of runtime. The share
shrinks at higher resolution, where the spectral transforms dominate.
