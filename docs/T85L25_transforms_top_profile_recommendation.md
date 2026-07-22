# T85L25 Transforms Top-Level Profile Recommendation

Date: 2026-07-22

## Purpose

Analyze the Phase 2 top-level spectral transform timers and Phase 3
FFT/Legendre stage timers for the T85L25 Held-Suarez 30-day run.

Input log:

```text
logs/T85L25_transforms_top_profile_16node_30day.log
logs/T85L25_transforms_stage_profile_16node_30day.log
```

Reference broad dynamics profile:

```text
logs/T85L25_dynamics_region_profile_16node_30day.log
PROFILE_DYNAMICS_REGION name=transforms time_max=142.453 s
```

## Phase 2 Run Status

The Phase 2 top-level transform run completed successfully through 30 days.

Completion marker:

```text
Integration completed through 2000 Feb  1   0: 0: 0
```

The log contains PMIx warnings, but they did not abort the run. The model
printed both:

```text
PROFILE_DYNAMICS_DEEP
PROFILE_TRANSFORM_TOP
```

markers.

## Phase 2 Model Runtime

Model MPP timing from this Phase 2 run:

```text
tmin = 303.062758 s
tmax = 303.063429 s
tavg = 303.063049 s
tstd =   0.000216 s
pemin = 0
pemax = 15
```

The whole-model MPI imbalance is negligible:

```text
tmax - tmin = 0.000671 s
```

## Phase 3 Run Status

The Phase 3 FFT/Legendre stage run also completed successfully through 30
days.

Completion marker:

```text
Integration completed through 2000 Feb  1   0: 0: 0
```

The log contains the same PMIx warnings seen in previous Slurm/container runs,
but the model completed and printed:

```text
PROFILE_DYNAMICS_DEEP
PROFILE_TRANSFORM_TOP
PROFILE_TRANSFORM_STAGE
```

markers.

Phase 3 model MPP timing:

```text
tmin = 307.548322 s
tmax = 307.549007 s
tavg = 307.548541 s
tstd =   0.000253 s
pemin = 0
pemax = 15
```

Whole-model MPI imbalance remains negligible:

```text
tmax - tmin = 0.000685 s
```

## Top-Level Transform Timer Summary

Percentages use this run's model MPP `tmax = 303.063429 s`.

| Timer | Calls Max | Calls / Timestep | Time Max (s) | Avg (s/call) | MPP Runtime % |
|---|---:|---:|---:|---:|---:|
| `grid_to_spherical_direct` | 25923 | 3.000 | 33.214 | 1.2813e-03 | 10.96% |
| `spherical_to_grid_direct` | 69124 | 8.000 | 89.590 | 1.2961e-03 | 29.56% |
| `vor_div_from_uv_grid_composite` | 8641 | 1.000 | 29.426 | 3.4054e-03 | 9.71% |
| `uv_grid_from_vor_div_composite` | 8642 | 1.000 | 29.144 | 3.3724e-03 | 9.62% |
| `grid_to_spherical_nested_vor_div` | 17282 | 2.000 | 27.809 | 1.6091e-03 | 9.18% |
| `spherical_to_grid_nested_uv` | 17284 | 2.000 | 28.218 | 1.6326e-03 | 9.31% |
| `nonoverlap_total` | 112330 | 13.001 | 180.321 | 1.6053e-03 | 59.50% |

Notes:

- `nonoverlap_total` is direct forward + direct inverse + the two composite
  wind wrappers.
- Nested timers are not added to `nonoverlap_total` because they are already
  included in the composite wrapper timers.
- The one- or two-call excess over exact timestep multiples is likely from
  initialization, completion, diagnostics, or shutdown transform calls.

## Forward Vs Inverse Transform Time

There are two useful ways to view forward vs inverse time.

### Primitive Direction Timing

This view counts primitive `trans_grid_to_spherical` and
`trans_spherical_to_grid` calls, including nested calls inside wind composites.

| Direction | Components | Calls Max | Calls / Timestep | Time Max (s) | Share Of Primitive Time |
|---|---|---:|---:|---:|---:|
| Forward grid-to-spectral | direct + nested in `vor_div` | 43205 | 5.001 | 61.023 | 34.1% |
| Inverse spectral-to-grid | direct + nested in `uv_from_vor_div` | 86408 | 10.001 | 117.808 | 65.9% |
| Total primitive direction time | forward + inverse | 129613 | 15.002 | 178.831 | 100.0% |

Result:

```text
Inverse spectral-to-grid transforms dominate primitive transform time.
```

### Non-Overlapping Direction Timing

This view counts the composite wind wrappers as whole forward-side or
inverse-side operations.

| Direction | Components | Calls Max | Calls / Timestep | Time Max (s) | Share Of Non-Overlap Time |
|---|---|---:|---:|---:|---:|
| Forward side | `grid_to_spherical_direct` + `vor_div_from_uv_grid_composite` | 34564 | 4.000 | 62.640 | 34.7% |
| Inverse side | `spherical_to_grid_direct` + `uv_grid_from_vor_div_composite` | 77766 | 9.001 | 118.734 | 65.8% |
| Non-overlap total | reported `nonoverlap_total` | 112330 | 13.001 | 180.321 | 100.0% |

The small difference between `62.640 + 118.734 = 181.374 s` and the reported
`nonoverlap_total = 180.321 s` comes from max reductions being applied to each
reported timer independently. A sum of independently max-reduced components is
not guaranteed to equal the max-reduced aggregate.

## Composite Wind-Transform Cost

Composite wind transforms are a major part of the transform path.

| Composite | Calls Max | Calls / Timestep | Time Max (s) | Avg (s/call) |
|---|---:|---:|---:|---:|
| `vor_div_from_uv_grid_composite` | 8641 | 1.000 | 29.426 | 3.4054e-03 |
| `uv_grid_from_vor_div_composite` | 8642 | 1.000 | 29.144 | 3.3724e-03 |
| Composite total | 17283 | 2.000 | 58.570 | n/a |

Nested primitive calls inside the composites:

| Nested Primitive | Calls Max | Calls / Timestep | Time Max (s) | Avg (s/call) |
|---|---:|---:|---:|---:|
| `grid_to_spherical_nested_vor_div` | 17282 | 2.000 | 27.809 | 1.6091e-03 |
| `spherical_to_grid_nested_uv` | 17284 | 2.000 | 28.218 | 1.6326e-03 |

Interpretation:

```text
Most composite wind-transform time is in the nested primitive transforms, but
the composite wrappers also include divide-by-cos, spectral helper math,
vorticity/divergence reconstruction, and truncation.
```

## Primitive Call Counts Per Timestep

Using `model_steps = 8640`:

| Metric | Calls / Timestep |
|---|---:|
| Direct forward primitive calls | 3.000 |
| Direct inverse primitive calls | 8.000 |
| Nested forward primitive calls inside `vor_div` | 2.000 |
| Nested inverse primitive calls inside `uv_from_vor_div` | 2.000 |
| Total forward primitive calls | 5.001 |
| Total inverse primitive calls | 10.001 |
| Composite wind wrapper calls | 2.000 |
| Non-overlap top-level calls | 13.001 |

The expected main dynamics transform call sites from `PROFILE_DYNAMICS_DEEP`
are:

```text
3 direct forward transforms per timestep
1 forward wind composite per timestep
4 direct inverse transforms per timestep
1 inverse wind composite per timestep
```

The top-level module timers also see additional direct inverse transform calls,
raising direct inverse from the main-dynamics 4 per timestep to about 8 per
timestep. These extra inverse transforms are outside the original broad
`transforms` bucket and likely come from diagnostics, helper paths, or
completion/update code.

## Non-Overlap Total Vs Broad Transforms Timer

Reference broad transforms timer:

```text
T85L25 broad transforms time = 142.453 s
```

This Phase 2 run:

```text
PROFILE_TRANSFORM_TOP nonoverlap_total = 180.321 s
```

Comparison:

| Quantity | Time (s) | Ratio To Broad Timer |
|---|---:|---:|
| Broad dynamics `transforms` timer | 142.453 | 1.000 |
| Dynamics-deep main transform call-site sum | 143.151 | 1.005 |
| Transform-module `nonoverlap_total` | 180.321 | 1.266 |
| Excess module-level transform time over broad timer | 37.868 | 0.266 |

Interpretation:

```text
The existing dynamics-deep call-site timers validate the broad transforms
timer: 143.151 s vs 142.453 s.

The new transform-module top-level timers intentionally measure a wider module
boundary. They reveal about 38 s of additional transform-module work outside
the broad dynamics transforms bucket.
```

This means Phase 2 succeeded, but `nonoverlap_total` should not be used as a
direct replacement for the broad dynamics-region timer. It is a wider
transform-module accounting metric.

## Dynamics Call-Site Breakdown

The main dynamics transform call-site sum from this run is:

```text
143.151 s
```

| Call Site | Calls Max | Time Max (s) | Calls / Timestep |
|---|---:|---:|---:|
| `transform_dt_ln_ps` | 8640 | 5.347 | 1 |
| `transform_dt_t` | 8640 | 13.664 | 1 |
| `transform_vor_div_from_uv` | 8640 | 29.423 | 1 |
| `transform_phis_plus_ke` | 8640 | 13.984 | 1 |
| `transform_future_div` | 8640 | 18.721 | 1 |
| `transform_future_vor` | 8640 | 14.093 | 1 |
| `transform_future_uv_from_vor_div` | 8640 | 29.136 | 1 |
| `transform_future_t` | 8640 | 14.125 | 1 |
| `transform_future_ln_ps` | 8640 | 4.658 | 1 |

Largest dynamics transform call sites:

1. `transform_vor_div_from_uv`: 29.423 s
2. `transform_future_uv_from_vor_div`: 29.136 s
3. `transform_future_div`: 18.721 s
4. `transform_future_t`: 14.125 s
5. `transform_future_vor`: 14.093 s
6. `transform_phis_plus_ke`: 13.984 s
7. `transform_dt_t`: 13.664 s

## Phase 3 FFT Vs Legendre Split

Phase 3 added `PROFILE_TRANSFORM_STAGE` timers inside:

```text
grid_fourier_mod
spherical_fourier_mod
```

The run used the same T85L25, 30-day, 16-rank external Slurm launch pattern.

### Stage Timer Table

Percentages use Phase 3 model MPP `tmax = 307.549007 s`.

| Stage Timer | Calls Max | Calls / Timestep | Time Max (s) | Avg (s/call) | MPP Runtime % |
|---|---:|---:|---:|---:|---:|
| `fft_forward_total` | 43205 | 5.001 | 5.426 | 1.2559e-04 | 1.76% |
| `fft_forward_pack` | 43205 | 5.001 | 0.842 | 1.9488e-05 | 0.27% |
| `fft_forward_kernel` | 43205 | 5.001 | 4.710 | 1.0902e-04 | 1.53% |
| `fft_inverse_total` | 86408 | 10.001 | 9.499 | 1.0993e-04 | 3.09% |
| `fft_inverse_kernel` | 86408 | 10.001 | 8.366 | 9.6820e-05 | 2.72% |
| `fft_inverse_unpack` | 86408 | 10.001 | 1.166 | 1.3494e-05 | 0.38% |
| `legendre_spherical_to_fourier_total` | 86408 | 10.001 | 39.699 | 4.5944e-04 | 12.91% |
| `legendre_spherical_to_fourier_loop` | 86408 | 10.001 | 39.689 | 4.5932e-04 | 12.90% |
| `legendre_fourier_to_spherical_total` | 43205 | 5.001 | 20.404 | 4.7226e-04 | 6.63% |
| `legendre_fourier_to_spherical_loop` | 43205 | 5.001 | 20.158 | 4.6657e-04 | 6.55% |

### Aggregate FFT Vs Legendre

| Aggregate | Components | Time (s) | Share Of Measured FFT+Legendre |
|---|---|---:|---:|
| FFT total | `fft_forward_total + fft_inverse_total` | 14.925 | 19.9% |
| Legendre total | `legendre_fourier_to_spherical_total + legendre_spherical_to_fourier_total` | 60.103 | 80.1% |
| FFT kernel only | `fft_forward_kernel + fft_inverse_kernel` | 13.076 | 17.4% |
| Legendre loop only | `legendre_fourier_to_spherical_loop + legendre_spherical_to_fourier_loop` | 59.847 | 79.8% |
| Measured FFT+Legendre total | FFT total + Legendre total | 75.028 | 100.0% |

Result:

```text
Legendre dominates the measured math kernels.
```

The measured Legendre total is about 4.0x the measured FFT total:

```text
60.103 / 14.925 = 4.03
```

### Directional Stage Split

Direction mapping:

| Direction | FFT Component | Legendre Component | Stage Subtotal |
|---|---:|---:|---:|
| Forward grid-to-spectral | `fft_forward_total = 5.426 s` | `legendre_fourier_to_spherical_total = 20.404 s` | 25.830 s |
| Inverse spectral-to-grid | `legendre_spherical_to_fourier_total = 39.699 s` | `fft_inverse_total = 9.499 s` | 49.198 s |

The inverse direction still dominates the measured stage subtotal:

```text
inverse stage subtotal = 49.198 s
forward stage subtotal = 25.830 s
```

This is consistent with Phase 2, where inverse primitive transform time was
about two thirds of primitive transform time.

### What The Stage Timers Do Not Yet Explain

Phase 3 measured FFT and Legendre stages:

```text
FFT + Legendre total = 75.028 s
```

Phase 3 top-level transform-module non-overlap total:

```text
PROFILE_TRANSFORM_TOP nonoverlap_total = 181.807 s
```

So FFT and Legendre explain only:

```text
75.028 / 181.807 = 41.3%
```

of the transform-module non-overlap time.

The remaining approximate gap is:

```text
181.807 - 75.028 = 106.779 s
```

This gap is likely dominated by transform wrapper stages that Phase 3 has not
split yet:

- `transpose_fourier`
- `reverse_transpose_fourier`
- `mpp_transmit`
- `mpp_sync`
- `mpp_update_domains(..., XUPDATE)`
- `mpp_sum`
- local array packing/extraction in `transforms.F90`
- spectral truncation and helper math in wind composites

Therefore, while Legendre dominates the measured math part, the full transform
bottleneck cannot be treated as a pure Legendre problem yet.

### Dynamics Transform Call-Site Validation In Phase 3

The Phase 3 dynamics-deep main transform call-site sum is:

```text
144.593 s
```

Compared with the original broad transforms timer:

```text
142.453 s
```

Ratio:

```text
144.593 / 142.453 = 1.015
```

So the stage-instrumented run still validates the original broad transform
region within about 1.5%.

## Recommendation

Proceed to Phase 4 communication/transpose/wrapper stage timers inside
`transforms.F90`.

Priority order:

1. Instrument transform communication and transpose stages.
   - Reason: FFT + Legendre explain only about 41% of top-level transform
     module time.
   - Target routines:
     - `trans_spherical_to_grid_3d`
     - `trans_grid_to_spherical_3d`
     - `reverse_transpose_fourier`
     - `transpose_fourier`
     - `mpp_transmit`
     - `mpp_sync`
     - `mpp_update_domains`
     - `mpp_sum`

2. Instrument the two composite wind wrappers.
   - Reason: the two composites account for about 58.6 s and are the largest
     individual dynamics transform call sites.
   - Target routines:
     - `vor_div_from_uv_grid_3d`
     - `uv_grid_from_vor_div_3d`
     - nested primitive transforms
     - `compute_vor_div`
     - `compute_ucos_vcos`
     - truncation and `divide_by_cos`

3. Treat Legendre as the leading math-kernel modernization candidate.
   - Reason: Legendre is about 80% of measured FFT+Legendre time and about 4x
     FFT time.
   - Target routines:
     - `trans_spherical_to_fourier_3d`
     - `trans_fourier_to_spherical_3d`
     - Legendre table access and accumulation loops

4. Deprioritize cuFFT as the immediate next prototype.
   - Reason: measured FFT total is only 14.925 s in this run, much smaller
     than Legendre and much smaller than the unexplained wrapper/communication
     gap.

## Phase 4 Questions

The next run should split the remaining transform wrapper and communication
time into:

```text
transpose / mpp_transmit time
mpp_update_domains / mpp_sum time
truncation time
divide_by_cos and spectral helper math
array copy / extraction overhead
```

The key decision is whether the next modernization path should be:

1. communication/decomposition redesign;
2. GPU Legendre-transform prototype;
3. wind-transform composite kernel/helper modernization;
4. broader transform-library strategy;
5. or cuFFT/vendor FFT prototype as a lower-priority component.

## Final Decision

Do not translate yet.

Phase 2 and Phase 3 confirmed:

- the original broad `transforms` timer is real and reproducible;
- inverse spectral-to-grid work dominates primitive transform time;
- wind composites are the largest individual dynamics transform call sites;
- module-level transform accounting exposes additional transform work outside
  the broad dynamics transform bucket;
- Legendre dominates measured FFT+Legendre math time;
- FFT is not the dominant measured transform math cost;
- roughly 59% of top-level transform-module time remains outside the current
  FFT/Legendre stage timers.

Next action:

```text
Add Phase 4 stage timers for transpose, MPP communication, grid-domain update,
spectral reduction, truncation, and wind-composite helper math in the
transforms.F90 overlay.
```

## Phase 4 Instrumentation Status

Status: completed.

Log:

```text
logs/T85L25_transforms_wrapper_profile_16node_30day.log
```

New build target:

```text
profile_transforms_wrapper
```

Expected executable:

```text
held_suarez_profile_transforms_wrapper.x
```

New documentation:

```text
docs/transforms_phase4_wrapper_gap_timers.md
```

The Phase 4 overlay keeps the Phase 2 and Phase 3 timers enabled and adds:

```text
PROFILE_TRANSFORM_WRAPPER name=<stage> calls_max=... time_max=... avg_max=...
```

The new timers split the wrapper gap into:

- `mpp_sum` and `mpp_update_domains`;
- Fourier transpose and reverse-transpose parents;
- `mpp_transmit`, `mpp_sync`, packing, and unpacking children;
- Fourier and spectral truncation;
- wind-composite helper math;
- local array copy and extraction.

The 30-day T85L25 wrapper run was completed on 16 nodes / 16 MPI ranks.

## Phase 4 Wrapper-Gap Results

Total model MPP runtime:

```text
306.728 s
```

Top-level transform-module non-overlap total:

```text
180.720 s
```

Measured math kernels:

| Component | Time (s) | Percent Of Transform Non-Overlap | Percent Of Runtime |
|---|---:|---:|---:|
| FFT total | 15.133 | 8.37% | 4.93% |
| Legendre total | 60.617 | 33.54% | 19.76% |
| FFT + Legendre | 75.750 | 41.92% | 24.70% |
| Remaining wrapper gap | 104.970 | 58.08% | 34.22% |

The Phase 4 timers explain the wrapper gap almost entirely as transpose and
MPI communication/synchronization work.

Important wrapper buckets:

| Bucket | Time (s) | Percent Of Transform Non-Overlap | Percent Of Runtime | Interpretation |
|---|---:|---:|---:|---|
| Parent transpose/reverse-transpose | 112.018 | 61.98% | 36.52% | Dominant wrapper cost |
| MPI/sync child timers | 112.704 | 62.36% | 36.74% | Communication dominates transpose parents |
| `mpp_transmit` only | 96.213 | 53.24% | 31.37% | Largest single cost |
| Sync timers | 16.110 | 8.91% | 5.25% | Secondary communication cost |
| Pack/unpack loops | 2.300 | 1.27% | 0.75% | Not the bottleneck |
| Grid copy/extract | 2.033 | 1.12% | 0.66% | Small |
| Wind helper operations | 2.919 | 1.62% | 0.95% | Small |
| Truncation/filter-like operations | 1.009 | 0.56% | 0.33% | Small |

The slight excess of child communication timers over the original wrapper gap
comes from nested accounting and run-to-run/timer overhead. It does not change
the conclusion: the unexplained transform time is communication-dominated.

## Phase 4 Decision Questions

### MPI Communication Dominance

Answer: yes, MPI communication dominates.

Communication-related child timers are about:

```text
112.704 s
```

The pure `mpp_transmit` contribution alone is:

```text
96.213 s
```

This is far above the `>40 s` threshold. A GPU transform prototype that only
ports FFT or Legendre kernels will not solve the transform bottleneck. The next
strategy must address communication/decomposition, GPU-aware MPI, or keep this
transform path on CPU for now.

Decision:

```text
Need GPU-aware MPI/decomposition strategy, or keep transforms on CPU.
```

### Transpose Cost

Answer: transpose cost is extremely high.

Parent transpose timers:

```text
g2s_transpose          36.775 s
s2g_reverse_transpose  75.243 s
total                 112.018 s
```

This is far above the `>30 s` threshold. The child breakdown shows this is not
mostly local packing:

```text
transpose_pack + reverse_transpose_unpack = 2.300 s
transpose_transmit + reverse_transpose_transmit = 96.213 s
transpose/final sync timers = 16.110 s
```

Decision:

```text
Must optimize/defer transpose communication. Local transpose loop fusion alone
is insufficient.
```

### Spectral Operations

The measured non-communication spectral/helper operations are small:

| Operation Group | Time (s) | Notes |
|---|---:|---|
| Fourier truncation | 0.563 | `s2g_fourier_truncation` + `g2s_fourier_truncation` |
| Spectral/wind truncation | 0.446 | `g2s_spectral_truncation` + `vor_div_truncation` |
| Wind helper compute | 1.491 | `compute_vor_div` + `compute_ucos_vcos` |
| Wind `divide_by_cos` | 0.750 | four divide stages |
| Wind array copies | 0.466 | u/v temporary copies |

These operations could be fused with a future GPU Legendre path, especially
truncation and wind helper operations, but they are not large enough to drive
the modernization decision by themselves. Fusion would mostly reduce small CPU
bookkeeping around a larger GPU transform, not unlock the current 100 s gap.

### Memory Allocation

No explicit repeated `allocate/deallocate` hotspot appears in the Phase 4
markers. The transform routines do create large local automatic temporary
arrays such as `grid_xglobal`, `fourier_g`, `fourier_s`, `put_data`, and
`get_data`, and `trans_spherical_to_grid_3d` allocates a `pelist` when spectral
Y is not global. However, measured local copy, pack, unpack, and helper costs
are much smaller than communication.

Persistent buffers may still be useful for a future GPU transform design, but
they are not the first-order fix for this profile. The first-order issue is
distributed transpose communication.

### Call Pattern

The model ran 8640 timesteps. Top-level transform call pattern:

| Transform Category | Calls | Calls Per Timestep | Time (s) |
|---|---:|---:|---:|
| Direct grid-to-spherical | 25923 | 3.00 | 33.361 |
| Direct spherical-to-grid | 69124 | 8.00 | 89.955 |
| Composite `vor_div_from_uv_grid` | 8641 | 1.00 | 29.156 |
| Composite `uv_grid_from_vor_div` | 8642 | 1.00 | 29.353 |
| Nested grid-to-spherical inside wind composite | 17282 | 2.00 | 27.510 |
| Nested spherical-to-grid inside wind composite | 17284 | 2.00 | 28.431 |
| Non-overlap total | 112330 | 13.00 | 180.720 |

Earlier coarse dynamics call sites saw about 5 major transform regions per
timestep, but the transform module sees about 13 primitive/composite
non-overlap transform calls per timestep. The high call count makes batching
attractive, especially for the repeated inverse spherical-to-grid calls.

Batching alone only helps if it reduces distributed transpose calls or combines
multiple fields before communication. Batching only the FFT or Legendre kernels
would leave most of the communication cost intact.

### Data Layout

The current layout is not GPU-friendly for isolated kernel offload because the
transform path repeatedly changes decomposition:

```text
grid space <-> Fourier space <-> spherical/spectral space
```

The expensive stages are the distributed Fourier transposes:

```text
transpose_fourier
reverse_transpose_fourier
```

Local packing/unpacking is cheap; the expensive part is moving distributed
spectral/Fourier slabs across MPI ranks. A GPU implementation must therefore
either:

1. keep transform data resident across multiple operations and use GPU-aware
   MPI/NCCL-like communication for the distributed transpose;
2. change decomposition/batching so fewer transposes are required;
3. call a distributed transform library that owns communication and layout;
4. or leave transforms on CPU and target another region.

## Updated Recommendation After Phase 4

Do not start by porting only FFT or Legendre kernels.

Legendre is still the largest math kernel and remains the best compute-kernel
candidate, but Phase 4 shows that math kernels are not the dominant transform
cost. The dominant transform cost is distributed transpose communication.

Recommended next step:

```text
Design a transform communication/decomposition modernization plan before
implementing GPU Legendre.
```

The plan should compare:

1. CPU transforms retained as-is, with GPU modernization focused elsewhere;
2. GPU Legendre prototype for architecture learning only;
3. batched transform API that groups multiple fields per timestep;
4. GPU-aware MPI distributed transpose;
5. vendor/library strategy for distributed spherical harmonic transforms.

Start translation only after choosing which communication/layout strategy will
own `transpose_fourier` and `reverse_transpose_fourier`.

The previous analysis formula was:

```text
wrapper_explained = sum(non-overlapping wrapper parent/helper timers)
remaining_gap = top_level_nonoverlap - fft_total - legendre_total - wrapper_explained
```

Do not sum parent and child timers together. For transpose accounting, use the
parent timers first, then use child timers only to classify the parent cost.
