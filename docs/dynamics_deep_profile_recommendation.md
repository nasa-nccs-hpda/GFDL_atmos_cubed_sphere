# Dynamics Deep Profile Recommendation

Date: 2026-06-16

## Purpose

Use the second-level Held-Suarez dynamics profile to choose the next
performance-targeted modernization target.

Input log:

```text
logs/dynamics_deep_profile_30day.log
```

Previous profile context:

```text
four_in_one: about 2.6% runtime
vert_advection_3d u+v+t: about 0.34% runtime
transforms broad region: about 38.9%
tracer_correction_diagnostics broad region: about 32.6%
advection broad region: about 7.9%
press_geopot broad region: about 4.8%
```

## Run Status

The 30-day deep profile run completed successfully.

Completion markers:

```text
Integration completed through 2000 Feb  1   0: 0: 0
Run 1 complete
```

The expected deep profile markers were present:

```text
PROFILE_DYNAMICS_DEEP name=...
```

## Runtime Reference

Model MPP timing:

```text
tmin = 24.136458 s
tmax = 24.136459 s
tavg = 24.136458 s
tstd = 0.000000 s
pemin = 0
pemax = 15
```

Shell timing:

```text
real = 27.296 s
user = 381.447 s
sys  = 7.159 s
```

Region timers report max-reduced call counts and times.  They do not report
per-region min/avg/std across MPI ranks.

## Timing Table

Percentages use model MPP `tmax = 24.136459 s` and shell `real = 27.296 s`.

| Rank | Deep Region | Calls Max | Time Max (s) | Avg Max (s/call) | MPP Runtime % | Shell Real % | Band |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | `update_tracers` | 4320 | 4.236 | 9.8056e-04 | 17.55% | 15.52% | Strong |
| 2 | `tracer_grid_horizontal_advection` | 4320 | 2.905 | 6.7245e-04 | 12.04% | 10.64% | Strong |
| 3 | `compute_corrections` | 4320 | 2.275 | 5.2662e-04 | 9.43% | 8.33% | Reasonable |
| 4 | `transform_vor_div_from_uv` | 4320 | 1.790 | 4.1435e-04 | 7.42% | 6.56% | Reasonable |
| 5 | `horizontal_advection_temperature` | 4320 | 1.750 | 4.0509e-04 | 7.25% | 6.41% | Reasonable |
| 6 | `transform_future_uv_from_vor_div` | 4320 | 1.696 | 3.9259e-04 | 7.03% | 6.21% | Reasonable |
| 7 | `transform_future_div` | 4320 | 1.620 | 3.7500e-04 | 6.71% | 5.93% | Reasonable |
| 8 | `tracer_vertical_advection` | 4320 | 1.214 | 2.8102e-04 | 5.03% | 4.45% | Reasonable by MPP |
| 9 | `transform_dt_t` | 4320 | 0.807 | 1.8681e-04 | 3.34% | 2.96% | Weak but possible |
| 10 | `transform_phis_plus_ke` | 4320 | 0.802 | 1.8565e-04 | 3.32% | 2.94% | Weak but possible |
| 11 | `transform_future_t` | 4320 | 0.770 | 1.7824e-04 | 3.19% | 2.82% | Weak but possible |
| 12 | `transform_future_vor` | 4320 | 0.752 | 1.7407e-04 | 3.12% | 2.75% | Weak but possible |
| 13 | `transform_dt_ln_ps` | 4320 | 0.236 | 5.4630e-05 | 0.98% | 0.86% | Do not target |
| 14 | `transform_future_ln_ps` | 4320 | 0.127 | 2.9398e-05 | 0.53% | 0.47% | Do not target |
| 15 | `vertical_advection_u` | 4320 | 0.127 | 2.9398e-05 | 0.53% | 0.47% | Do not target |
| 16 | `vertical_advection_v` | 4320 | 0.114 | 2.6389e-05 | 0.47% | 0.42% | Do not target |
| 17 | `vertical_advection_t` | 4320 | 0.114 | 2.6389e-05 | 0.47% | 0.42% | Do not target |
| 18 | `every_step_diagnostics` | 4320 | 0.006 | 1.3889e-06 | 0.02% | 0.02% | Do not target |
| 19 | `tracer_horizontal_advection` | 0 | 0.000 | 0.0000e+00 | 0.00% | 0.00% | Inactive |
| 20 | `tracer_grid_to_spectral` | 0 | 0.000 | 0.0000e+00 | 0.00% | 0.00% | Inactive |
| 21 | `tracer_spectral_to_grid` | 0 | 0.000 | 0.0000e+00 | 0.00% | 0.00% | Inactive |

## Ranking Summary

The strongest individual measured call site is:

```text
tracer_grid_horizontal_advection: 12.04% of model MPP runtime
```

This call is inside `update_tracers`, whose total wrapper time is:

```text
update_tracers: 17.55% of model MPP runtime
```

The transform stack is still important in aggregate, but the deep split shows
the cost is distributed across several call sites rather than concentrated in a
single easy routine:

```text
instrumented transform total = about 8.60 s, or 35.6% of model MPP runtime
```

Largest transform-related pieces:

```text
transform_vor_div_from_uv: 7.42%
transform_future_uv_from_vor_div: 7.03%
transform_future_div: 6.71%
```

## Comparison With Previous Results

| Candidate Or Region | Runtime Fraction | Interpretation |
|---|---:|---|
| `tracer_grid_horizontal_advection` | 12.04% | Strong, concrete call site |
| `update_tracers` wrapper | 17.55% | Strong region, contains tracer advection |
| Transform call-site aggregate | about 35.6% | Excellent broad region, distributed and coupled |
| Broad transforms region | about 38.9% | Confirmed by deep aggregate |
| Broad tracer/correction/diagnostics region | about 32.6% | Partly explained by `update_tracers` and `compute_corrections` |
| Broad advection region | about 7.9% | Temperature horizontal advection is 7.25%; vertical u/v/t remains small |
| `press_geopot` broad region | about 4.8% | Still weak but possible |
| `four_in_one` | about 2.6% | Workflow-learning target only |
| `vert_advection_3d` u+v+t | about 0.34% | No-go for performance |

## Interpretation

### Best Practical Performance Target

The best next practical target is:

```text
fv_advection_mod::a_grid_horiz_advection_3d
```

Evidence:

- It corresponds to the active `tracer_grid_horizontal_advection` call site.
- It accounts for about 12% of model MPP runtime in this 30-day run.
- It is called every timestep.
- It is a concrete routine-level target, unlike the mixed transform stack.
- It is more performance-relevant than `four_in_one` and `vert_advection_3d`.
- It is a regular grid/tracer advection kernel, likely more GPU-relevant than
  the completed forcing module.

Source file:

```text
src/atmos_spectral/model/fv_advection.F90
```

Routine:

```text
fv_advection_mod::a_grid_horiz_advection_3d
```

### Transform Stack

The transform family remains the largest aggregate performance region, but no
single transform call site dominates enough to make it the next low-risk
translation target.  A transform modernization path is likely a broader design
project, not a one-routine overlay replacement.

### Temperature Horizontal Advection

`horizontal_advection_temperature` is about 7.25% of model MPP runtime.  It is
also a reasonable target, but it is reached through `transforms_mod` rather
than the finite-volume advection module.  It may be more coupled than
`a_grid_horiz_advection_3d`.

### Compute Corrections

`compute_corrections` is about 9.43%, but it likely contains global integral
work and correction bookkeeping.  It should be inspected, but it is less
obviously GPU-friendly than tracer grid horizontal advection.

## Recommendation

Recommendation:

```text
A. Select a specific clean routine for feasibility analysis:
   fv_advection_mod::a_grid_horiz_advection_3d
```

Do not start translation immediately.  The next step should be a feasibility
and boundary analysis for `a_grid_horiz_advection_3d`, similar to the earlier
`four_in_one` feasibility pass.

This recommendation updates the previous target-search path:

- Do not translate `four_in_one` for performance.
- Do not translate `vert_advection_3d` for performance.
- Do not start with the transform stack because it is distributed and coupled.
- Prefer `a_grid_horiz_advection_3d` because it is both measured and more
  concretely isolatable.

## Suggested Next Implementation Plan

1. Locate `fv_advection_mod::a_grid_horiz_advection_3d`.
2. Analyze its full interface:
   - arguments,
   - array dimensions,
   - optional arguments,
   - module state,
   - helper routines,
   - side effects.
3. Identify call sites in Held-Suarez, especially the grid tracer branch in
   `update_tracers`.
4. Determine whether a standalone Fortran baseline harness can capture inputs
   and outputs.
5. Classify dependencies:
   - directly translatable helpers,
   - module constants/state,
   - callbacks or coupled infrastructure,
   - MPI/domain dependencies, if any.
6. Decide whether to translate:
   - only `a_grid_horiz_advection_3d`,
   - the supporting finite-volume advection helpers it requires,
   - or a broader `update_tracers` region.
7. Only after that analysis, decide whether to begin C++ translation.

## Whether To Start Translation Now

Start translation now?

```text
No.
```

The project now has a strong measured routine-level candidate, but it still
needs boundary analysis before code translation.

## Confidence Level

Confidence in run completion: high.

Confidence in timing extraction: high.

Confidence in selecting `a_grid_horiz_advection_3d` for the next feasibility
analysis: medium-high.

Confidence in starting translation immediately: low.

Reasons:

- The deep profile completed and emitted all expected markers.
- The active grid tracer branch is clearly measurable.
- The candidate has much larger runtime share than previous isolated targets.
- The routine boundary and helper dependencies have not yet been analyzed.

## Risks

Technical risks:

- `a_grid_horiz_advection_3d` may call helper routines or use module state that
  makes isolation broader than expected.
- Grid tracer advection may be sensitive to numerical limiter behavior and
  boundary handling.
- A hybrid C++ replacement may need to preserve exact array layout and update
  semantics for `dt_tr`.
- GPU offload may still be limited if the rest of the model remains CPU-bound,
  but the measured 12% share is large enough to justify feasibility work.

Strategy risks:

- The transform stack remains the largest aggregate runtime region.  Choosing
  finite-volume tracer advection is a pragmatic next step, not the final
  end-state for maximum speedup.
- If the goal shifts to a larger redesign rather than incremental hybrid
  replacement, the transform stack may become the more important target.

## Final Decision

Final decision:

```text
Proceed to feasibility and boundary analysis for
fv_advection_mod::a_grid_horiz_advection_3d.

Do not translate yet.
```
