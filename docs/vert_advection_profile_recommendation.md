# vert_advection_3d Profile Recommendation

Date: 2026-06-16

## Purpose

Use the repaired 30-day vertical-advection call-site profile to decide whether
`vert_advection_mod::vert_advection_3d` should be the next performance-targeted
C++ modernization module.

Input log:

```text
logs/vert_advection_profile_30day_callsite.log
```

Reference docs:

```text
docs/vert_advection_profile_plan.md
docs/next_module_performance_decision.md
memory/MIGRATION_STATUS.md
```

## Run Status

The 30-day call-site profile run completed successfully.

Completion markers:

```text
Integration completed through 2000 Feb  1   0: 0: 0
Run 1 complete
```

The repaired call-site markers were present:

```text
PROFILE_VERT_ADVECTION_CALLSITE field=u ...
PROFILE_VERT_ADVECTION_CALLSITE field=v ...
PROFILE_VERT_ADVECTION_CALLSITE field=t ...
PROFILE_VERT_ADVECTION_CALLSITE total ...
```

## Extracted Timing Summary

Model MPP runtime:

```text
tmin = 95.722956 s
tmax = 95.723106 s
tavg = 95.723039 s
tstd = 0.000045 s
pemin = 0
pemax = 15
```

Shell timing:

```text
real = 98.883 s
user = 530.780 s
sys  = 428.547 s
```

Vertical-advection call-site timing:

| Field | Calls Max | Time Max (s) | Avg Max (s/call) | Avg Max (us/call) | Fraction Of MPP tmax |
|---|---:|---:|---:|---:|---:|
| u | 4320 | 0.132 | 3.0556e-05 | 30.56 | 0.138% |
| v | 4320 | 0.117 | 2.7083e-05 | 27.08 | 0.122% |
| temperature | 4320 | 0.099 | 2.2917e-05 | 22.92 | 0.103% |
| u+v+t total | 12960 | 0.327 | 2.5231e-05 | 25.23 | 0.342% |

The total fraction using shell `real` time is:

```text
0.327 / 98.883 = 0.331%
```

For comparison, even if the vertical-advection time is divided by the previous
unreported-marker run's lower model runtime of 24.520750 s, the fraction would
still be only:

```text
0.327 / 24.520750 = 1.33%
```

That remains below the 2% weak-target threshold.

## Caller And Field Breakdown

The timing is separated by the three primary Held-Suarez dry dynamics
call-sites in `spectral_dynamics.F90`:

```text
u wind
v wind
temperature
```

The expected dry-run call count was:

```text
30 days * 86400 s/day / 600 s timestep * 3 fields = 12960 calls
```

The measured total call count was:

```text
12960 calls
```

This confirms the reported total covers the expected u, v, and temperature
calls.  Tracer call-site timing was not included in this first repaired profile,
and the observed count does not indicate additional tracer vertical-advection
calls in the measured total.

## MPI Rank Behavior

The profile reports max-reduced call counts and elapsed times.  The model-level
MPP timing shows very small whole-run imbalance:

```text
tmin = 95.722956 s
tmax = 95.723106 s
tavg = 95.723039 s
tstd = 0.000045 s
```

The call-site instrumentation does not report vertical-advection min/avg/std by
rank, so field-level rank imbalance cannot be quantified.  For target-selection
purposes, the max-reduced vertical-advection time is already far below the
performance threshold.

## Comparison With four_in_one

Known `four_in_one` profile:

| Metric | four_in_one |
|---|---:|
| Max PE time | 0.632 s |
| Runtime fraction | about 2.6% of model MPP time |
| Calls | 4320 |
| Avg time per call | about 146 us |
| Decision | PARTIAL GO |

Measured `vert_advection_3d` call-site profile:

| Metric | vert_advection_3d u+v+t |
|---|---:|
| Max PE time | 0.327 s |
| Runtime fraction | about 0.34% of model MPP tmax |
| Calls | 12960 |
| Avg time per call | about 25 us |
| Decision | NO-GO for performance |

Vertical advection is smaller than `four_in_one` in this 30-day Held-Suarez
configuration, despite being called three times as often.  Its average
call-site cost is much lower.

## Decision Criteria

Project threshold:

| Runtime fraction | Decision |
|---:|---|
| `>10%` | Strong GO |
| `5-10%` | GO |
| `2-5%` | PARTIAL GO |
| `<2%` | Weak performance target |

Measured `vert_advection_3d` u+v+t fraction:

```text
0.34% of model MPP tmax
```

Decision:

```text
NO-GO for performance-targeted C++ modernization.
```

## Recommendation

Do not translate `vert_advection_3d` next for performance purposes.

The call-site profile is now valid, and it shows the u, v, and temperature
vertical-advection calls are too small in this Held-Suarez configuration to
justify the complexity of translating the full `vert_advection_3d` module as
the next wall-clock improvement target.

Recommended next target direction:

```text
Move to press_and_geopot profiling, or broaden the timing scope around larger
spectral/dynamics regions before choosing another translation target.
```

The next candidate should be selected from routines with every-timestep
pressure/geopotential/state-update work or from a broader spectral dynamics
region that has a measured runtime fraction above the 2-5% partial-go band.

## Confidence Level

Confidence in run completion: high.

Confidence in vertical-advection timing extraction: high.

Confidence in no-go decision for this exact Held-Suarez configuration: high.

Reasons:

- The run completed the full 30 simulated days.
- The repaired call-site markers were present.
- The measured u/v/t call count exactly matches the expected 12,960 calls.
- The max-reduced total time is far below the 2% threshold.
- Even a conservative comparison against the earlier lower model runtime keeps
  the fraction below 2%.

## Risks

Known risks and caveats:

- The timing covers u, v, and temperature call sites, not tracer call sites.
  That is appropriate for the current dry Held-Suarez path, but moist/tracer
  configurations could change the call mix.
- The call-site profile run's total model runtime is larger than the earlier
  missing-marker run.  The no-go decision is robust to this because the
  vertical-advection total remains below 2% even when compared against the
  earlier lower runtime.
- `system_clock` timing is coarse, but the measured total is so small that
  timer granularity does not affect the target-selection conclusion.
- Higher resolutions or different advection schemes could make vertical
  advection more important.  This recommendation applies to the current
  Held-Suarez prototype configuration.

## Next Implementation Step

Do not start `vert_advection_3d` translation.

Recommended next profiling step:

```text
Profile press_and_geopot routines:
  pressure_variables
  compute_geopotential
  compute_pressures_and_heights
```

Alternative broader step:

```text
Add coarse region timers inside spectral_dynamics for:
  pressure/geopotential
  transforms
  horizontal advection
  damping
  leapfrog/update
```

That would identify a larger measured target before beginning another
Fortran-to-C++ hybrid integration.

## Whether To Proceed With Translation

Proceed with `vert_advection_3d` translation now?

```text
No.
```

Use `vert_advection_3d` only as a later workflow-learning or scheme-coverage
exercise, not as the next performance-targeted modernization module.
