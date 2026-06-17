# Dynamics Region Profile Recommendation

Date: 2026-06-16

## Purpose

Use the 30-day broad dynamics-region profile to choose the next
performance-targeted Held-Suarez modernization module or region.

Input log:

```text
logs/dynamics_region_profile_30day.log
```

Context from previous profiles:

```text
four_in_one: about 2.6% of model MPP runtime
vert_advection_3d u+v+t: about 0.34% of model MPP runtime
```

## Run Status

The 30-day dynamics-region profile run completed successfully.

Completion markers:

```text
Integration completed through 2000 Feb  1   0: 0: 0
Run 1 complete
```

The expected region markers were present:

```text
PROFILE_DYNAMICS_REGION name=...
```

## Model Runtime

Model MPP timing:

```text
tmin = 84.143081 s
tmax = 84.143257 s
tavg = 84.143189 s
tstd = 0.000060 s
pemin = 0
pemax = 15
```

Shell timing:

```text
real = 86.932 s
user = 505.085 s
sys  = 338.437 s
```

MPI imbalance at the whole-model level is negligible:

```text
tmax - tmin = 0.000176 s
```

The region profile reports max-reduced call counts and times.  It does not
report region-level min/avg/std across MPI ranks.

## Extracted Timing Table

Percentages use model MPP `tmax = 84.143257 s` and shell `real = 86.932 s`.

| Rank | Region | Calls Max | Time Max (s) | Avg Max (s/call) | MPP Runtime % | Shell Real % | Classification |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | `spectral_dynamics_step` | 4320 | 80.321 | 1.8593e-02 | 95.46% | 92.40% | Envelope, not a direct module target |
| 2 | `transforms` | 21600 | 32.748 | 1.5161e-03 | 38.92% | 37.67% | Excellent target region |
| 3 | `tracer_correction_diagnostics` | 4320 | 27.401 | 6.3428e-03 | 32.56% | 31.52% | Excellent region, needs subdivision |
| 4 | `advection` | 4320 | 6.659 | 1.5414e-03 | 7.91% | 7.66% | Reasonable target region |
| 5 | `press_geopot` | 4320 | 4.051 | 9.3773e-04 | 4.81% | 4.66% | Weak but possible |
| 6 | `damping` | 4320 | 1.074 | 2.4861e-04 | 1.28% | 1.24% | Do not target for performance |
| 7 | `leapfrog_update` | 4320 | 0.192 | 4.4444e-05 | 0.23% | 0.22% | Do not target for performance |

Important interpretation:

- `spectral_dynamics_step` is the full envelope and should not be summed with
  the subregions.
- The subregions are intentionally coarse.  They are suitable for target
  selection, not final performance attribution.
- `transforms` is accumulated across five transform-heavy groups per timestep,
  which explains its 21,600 calls.

## Runtime Thresholds

Decision bands:

| Runtime Fraction | Meaning |
|---:|---|
| `>20%` | Excellent target |
| `10-20%` | Strong target |
| `5-10%` | Reasonable target |
| `2-5%` | Weak but possible |
| `<2%` | Do not target for performance |

Measured regions:

| Region | Band |
|---|---|
| `transforms` | Excellent |
| `tracer_correction_diagnostics` | Excellent, but mixed with diagnostics/corrections |
| `advection` | Reasonable |
| `press_geopot` | Weak but possible |
| `damping` | Do not target |
| `leapfrog_update` | Do not target |

## Comparison With Previous Candidates

| Candidate Or Region | Time (s) | Runtime Fraction | Calls | Decision |
|---|---:|---:|---:|---|
| `transforms` region | 32.748 | 38.92% | 21600 | Excellent measured region |
| `tracer_correction_diagnostics` region | 27.401 | 32.56% | 4320 | Excellent, needs subdivision |
| `advection` region | 6.659 | 7.91% | 4320 | Reasonable, needs subdivision |
| `press_geopot` region | 4.051 | 4.81% | 4320 | Weak but possible |
| `four_in_one` routine | 0.632 | about 2.6% | 4320 | Partial go only |
| `vert_advection_3d` u+v+t | 0.327 | about 0.34% | 12960 | No-go for performance |

The broad profile changes the target-selection picture.  Isolated kernels were
small, but region-level timing shows substantial time in transform-heavy code
and in the tracer/correction/diagnostics tail.

## Interpretation

### Transform Region

`transforms` is the largest measured subregion at about 39% of model MPP time.
This is the clearest performance signal.

However, it is not yet a clean single-routine translation target.  The region
combines:

```text
trans_grid_to_spherical(dt_ln_psg, dt_ln_ps)
trans_grid_to_spherical(dt_tg_tmp, dt_ts)
vor_div_from_uv_grid(dt_ug_tmp, dt_vg_tmp, ...)
trans_grid_to_spherical(phig_full_plus_ke, phis_plus_ke)
trans_spherical_to_grid / uv_grid_from_vor_div future-state updates
```

The transform stack was already identified as high-payoff but high-risk in
`docs/next_module_performance_decision.md` because it is coupled to spectral
algorithms, decomposition, and transform-library behavior.

### Tracer/Correction/Diagnostics Region

`tracer_correction_diagnostics` is also large at about 33% of model MPP time,
but it is a mixed bucket:

```text
update_tracers
compute_corrections
time bookkeeping
every_step_diagnostics
```

This region may include diagnostics overhead, correction reductions, tracer
logic, or hidden transform/advection work.  It should not be translated as a
single region without a deeper split.

### Advection Region

The broad `advection` bucket is about 7.9%, but the repaired
`vert_advection_3d` profile showed only about 0.34% for u+v+t.  Therefore most
of the broad advection cost is likely from:

```text
horizontal_advection(ts, ug, vg, dt_tg_tmp)
```

This makes horizontal advection a plausible next measured candidate after
deeper timing confirms it.

### Pressure/Geopotential

`press_geopot` is about 4.8%, which is larger than `four_in_one` alone but
still below a strong target threshold.  It remains a clean and feasible
fallback if the project wants a lower-risk dynamics translation.

## Recommendation

Recommendation:

```text
B. Instrument deeper sub-regions before translation.
```

Do not start translating a module yet.

The next performance target should be chosen from deeper timers inside the
measured high-cost regions:

1. `transforms`
2. `tracer_correction_diagnostics`
3. `advection`, specifically horizontal advection

The strongest eventual target is likely a broader transform-heavy spectral
dynamics region, but the transform stack is too coupled to select blindly as
the next direct Fortran-to-C++ translation.

## Next Implementation Step

Add a second-level timing overlay that splits the large regions into actionable
subregions.

Recommended transform split:

```text
transform_dt_ln_ps
transform_dt_t
transform_vor_div_from_uv
transform_phis_plus_ke
transform_future_div
transform_future_vor
transform_future_uv_from_vor_div
transform_future_t
transform_future_ln_ps
```

Recommended tracer/correction/diagnostics split:

```text
update_tracers
compute_corrections
every_step_diagnostics
```

Recommended advection split:

```text
horizontal_advection_temperature
vertical_advection_u
vertical_advection_v
vertical_advection_t
```

The vertical-advection split already exists and showed that u+v+t is small, so
the main new advection question is horizontal advection.

## Whether To Start Translation

Start translation now?

```text
No.
```

The measured data now identifies large regions, but not yet a clean module or
routine boundary.  Starting translation before the second-level split would
risk targeting a mixed region that includes diagnostics, transforms, and
coupled spectral infrastructure.

## Confidence Level

Confidence in run completion: high.

Confidence in broad-region ranking: high.

Confidence in selecting a specific next module from this profile alone:
medium-low.

Reasons:

- The 30-day run completed successfully.
- All expected `PROFILE_DYNAMICS_REGION` markers were present.
- The model-level MPI timing is balanced.
- The largest regions are coarse and contain mixed work, so they need one more
  subdivision before implementation.

## Risks

Technical risks:

- `transforms` is likely the biggest target, but it is algorithmically and
  infrastructurally coupled.
- `tracer_correction_diagnostics` may include diagnostics overhead that is not
  a useful modernization target.
- Region-level timers use `system_clock`; they are appropriate for coarse
  selection but not a replacement for detailed profiling.
- Instrumentation overhead may inflate absolute runtime, but the relative
  ranking is strong enough to guide the next profiling pass.

Project risks:

- Continuing to translate isolated routines may not produce meaningful
  end-to-end speedup.
- The next useful target may be a broader model-region redesign rather than a
  one-routine replacement like the forcing-module prototype.

## Final Decision

Final decision:

```text
Do not translate four_in_one, vert_advection_3d, damping, or leapfrog next for
performance.  Add deeper timers inside transforms, tracer/correction/
diagnostics, and horizontal advection.  Use that second-level profile to choose
between a transform-region modernization path and a smaller horizontal
advection or pressure/geopotential target.
```
