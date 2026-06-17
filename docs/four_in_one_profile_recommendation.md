# four_in_one Profile Recommendation

Date: 2026-06-16

## Purpose

Use the 30-day `four_in_one` profiling run to decide whether
`spectral_dynamics_mod::four_in_one` is worth translating next.

Input log:

```text
logs/four_in_one_profile_30day.log
```

Reference docs:

```text
docs/four_in_one_feasibility_analysis.md
docs/four_in_one_performance_modernization_plan.md
docs/next_module_performance_decision.md
```

## Run Status

The 30-day profile run completed successfully.

Completion markers:

```text
Integration completed through 2000 Feb  1   0: 0: 0
Run 1 complete
```

Output directory:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_profile_four_in_one/run0001/
```

## Extracted Timing Summary

From the profile marker:

```text
PROFILE_FOUR_IN_ONE calls_max=        4320  seconds_max=  0.63200000000000045       avg_seconds_per_call_max=   1.4629629629629641E-004
```

From the model MPP clock summary:

```text
Total runtime  tmin=24.346626  tmax=24.346627  tavg=24.346627
```

From shell `time`:

```text
real  0m27.931s
user  6m23.586s
sys   0m7.664s
```

Summary table:

| Metric | Value |
|---|---:|
| Model MPP wall-clock time, avg | 24.346627 s |
| Shell real time | 27.931 s |
| `four_in_one` time, max PE | 0.632000 s |
| `four_in_one` call count, max PE | 4320 |
| Average `four_in_one` time per call | 0.000146296 s |
| Fraction of model MPP runtime | 2.596% |
| Fraction of shell real time | 2.263% |
| MPI ranks | 16 |

The call count matches the expected 30-day Held-Suarez cadence:

```text
30 days * 86400 s/day / 600 s timestep = 4320 calls
```

## MPI Rank Behavior

The timing instrumentation reports maximum time and maximum call count across
PEs using `mpp_max`.

The model clock summary reports nearly identical runtime across the 16 PEs:

```text
tmin=24.346626
tmax=24.346627
tavg=24.346627
tstd=0.000000
```

This suggests the run was well balanced at the coarse model-runtime level.
The `four_in_one` report is conservative because it uses the maximum PE time.
It does not report min/avg/std for `four_in_one`, so detailed rank imbalance
inside the kernel is unknown.

## Decision Criteria

Project threshold:

| Runtime fraction | Decision |
|---:|---|
| `>10%` | Strong GO |
| `5-10%` | GO if isolation risk is acceptable |
| `2-5%` | PARTIAL GO or translate for workflow learning |
| `<2%` | Not ideal for performance target |

Measured `four_in_one` fraction:

```text
2.596% of model MPP runtime
2.263% of shell real time
```

This falls in the `2-5%` band.

## Recommendation

Decision:

```text
PARTIAL GO
```

`four_in_one` is measurable and technically feasible, but it is not large
enough to be a strong wall-clock performance target by itself.

Proceed with `four_in_one` only if the next objective is:

- Prove the dynamics-kernel translation workflow after the forcing module.
- Exercise a clean Fortran dynamics overlay boundary.
- Build confidence translating a prognostic-tendency kernel before attempting
  a larger, branchier module.

Do not treat `four_in_one` as the primary route to meaningful end-to-end
speedup.  Even a perfect implementation could only affect roughly 2.6% of this
30-day run's model runtime before integration overheads.

## Whether To Proceed With C++ Translation

Recommended action:

```text
Proceed only as a workflow-learning dynamics translation, not as the main
performance target.
```

If the project priority is immediate wall-clock runtime improvement, pause
`four_in_one` translation and profile the next-ranked candidate,
`vert_advection_3d`, with the same overlay timing approach.

If the project priority is low-risk progression from physics forcing to
dynamics kernels, continue with `four_in_one` because it remains highly
isolatable:

- No callees.
- No MPI calls inside the routine.
- No FFT/spectral transforms inside the routine.
- No I/O or diagnostics.
- No derived-type or optional arguments.
- Hidden state can be passed explicitly.

## Confidence Level

Confidence: medium-high.

Reasons:

- The 30-day run completed successfully.
- The timing marker was printed once at shutdown.
- The call count exactly matches the expected timestep count.
- The model-level MPP clock and shell `time` both exist, so the runtime
  fraction is computable two ways.

Limitations:

- Only maximum PE `four_in_one` time is reported.
- The timing uses `system_clock`, which is adequate for coarse timing but not a
  detailed profiler.
- Only `four_in_one` was timed; nearby dynamics regions such as
  `vert_advection`, transforms, pressure/geopotential, damping, and leapfrog
  were not measured in this run.
- The measured fraction is for this Held-Suarez resolution and 30-day
  configuration; it may change with resolution.

## Risks

Performance risks:

- At ~2.6%, `four_in_one` has limited end-to-end speedup potential.
- A C++ hybrid call boundary may add overhead unless implemented carefully.
- CUDA offload would almost certainly be dominated by transfer overhead if only
  this routine is moved to GPU.

Numerical risks:

- The vertical recurrence through `dmean_tot` must preserve operation order.
- Small tendency differences can propagate through transforms, damping, and
  leapfrog updates.
- `intent(inout)` tendency arrays must accumulate exactly, not overwrite.

Workflow risks:

- The overlay replaces a large `spectral_dynamics.F90` source file, so it must
  be kept in sync with production source.
- Build/link machinery must remain separate from the existing
  `held_suarez_hybrid.x` forcing-module executable.

## Next Implementation Step

Recommended next step for performance-driven work:

```text
Add equivalent coarse timing around vert_advection_3d calls in spectral_dynamics.
```

Specifically time:

```text
vert_advection_u
vert_advection_v
vert_advection_t
```

Then compare combined vertical-advection runtime against `four_in_one`.

Recommended next step for workflow-learning work:

```text
Build the standalone Fortran baseline harness for four_in_one.
```

Do not start C++ translation until the project chooses between these two paths.

## Final Recommendation

`four_in_one` is worth translating as a controlled dynamics-kernel workflow
exercise, but it is not the best standalone target for wall-clock improvement.

Final decision:

```text
PARTIAL GO: translate four_in_one only if workflow learning is the priority;
otherwise profile vert_advection_3d next for a stronger performance target.
```

