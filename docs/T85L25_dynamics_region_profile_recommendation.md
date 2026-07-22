# T85L25 Dynamics Region Profile Recommendation

Date: 2026-07-21

## Purpose

Use the T85L25 30-day broad dynamics-region profile to identify the next
performance-targeted modernization region after the FV advection CUDA resident
experiments.

Input log:

```text
logs/T85L25_dynamics_region_profile_16node_30day.log
```

Related context:

```text
docs/T42_T85_multi_gpu_runtime_summary.md
docs/T85L25_dynamics_region_profile_plan.md
docs/dynamics_region_profile_recommendation.md
```

## Run Status

The T85L25 dynamics-region profile completed the 30-day simulation.

Completion marker:

```text
Integration completed through 2000 Feb  1   0: 0: 0
```

The log contains PMIx component warnings on all ranks:

```text
PMIX ERROR: ERROR in file .../gds_ds12_lock_pthread.c at line 169
```

These warnings did not abort the run. The model reached completion and printed
the expected `PROFILE_DYNAMICS_REGION` markers, so the timing data is usable.

## Model Runtime

Model MPP timing:

```text
tmin = 306.113343 s
tmax = 306.113961 s
tavg = 306.113609 s
tstd =   0.000187 s
pemin = 0
pemax = 15
```

No shell `real/user/sys` timing was found in this log.

Whole-model MPI imbalance is negligible:

```text
tmax - tmin = 0.000618 s
```

## Extracted Timing Table

Percentages use model MPP `tmax = 306.113961 s`.

| Rank | Region | Calls Max | Time Max (s) | Avg Max (s/call) | MPP Runtime % | Classification |
|---:|---|---:|---:|---:|---:|---|
| 1 | `spectral_dynamics_step` | 8640 | 280.133 | 3.2423e-02 | 91.51% | Envelope, not a direct module target |
| 2 | `transforms` | 43200 | 142.453 | 3.2975e-03 | 46.54% | Excellent target region |
| 3 | `tracer_correction_diagnostics` | 8640 | 65.415 | 7.5712e-03 | 21.37% | Excellent mixed region |
| 4 | `advection` | 8640 | 33.061 | 3.8265e-03 | 10.80% | Strong target region |
| 5 | `press_geopot` | 8640 | 18.411 | 2.1309e-03 | 6.01% | Reasonable target region |
| 6 | `damping` | 8640 | 7.891 | 9.1331e-04 | 2.58% | Weak but possible |
| 7 | `leapfrog_update` | 8640 | 1.347 | 1.5590e-04 | 0.44% | Do not target for performance |

Important interpretation:

- `spectral_dynamics_step` is the full dynamics envelope and should not be
  summed with the subregions.
- Region timers are max-reduced across MPI ranks, but this instrumentation does
  not report per-region min/avg/std imbalance.
- The transform timer fires five times per dynamics step, so its call count is
  five times larger than the one-call-per-step regions.

## Comparison With Previous Results

| Region Or Candidate | Resolution / Run | Time (s) | Runtime Fraction | Calls | Interpretation |
|---|---|---:|---:|---:|---|
| `transforms` | T42L25 broad profile | 32.748 | 38.92% | 21600 | Excellent target |
| `tracer_correction_diagnostics` | T42L25 broad profile | 27.401 | 32.56% | 4320 | Excellent but mixed |
| `advection` | T42L25 broad profile | 6.659 | 7.91% | 4320 | Reasonable target |
| `press_geopot` | T42L25 broad profile | 4.051 | 4.81% | 4320 | Weak but possible |
| `four_in_one` | T42L25 routine profile | 0.632 | about 2.6% | 4320 | Partial go only |
| `vert_advection_3d` u+v+t | T42L25 callsite profile | about 0.327 | about 0.34% | 12960 | Weak target |
| FV CUDA resident `a_grid` | T85L25 16-GPU run | 1.862 | 0.58% | 17280/rank | Not the bottleneck |
| `transforms` | T85L25 broad profile | 142.453 | 46.54% | 43200 | Dominant target |
| `tracer_correction_diagnostics` | T85L25 broad profile | 65.415 | 21.37% | 8640 | Excellent mixed target |
| `advection` | T85L25 broad profile | 33.061 | 10.80% | 8640 | Strong target |
| `press_geopot` | T85L25 broad profile | 18.411 | 6.01% | 8640 | Reasonable target |

Scaling from T42L25 to T85L25 strengthens the same broad conclusion:
performance is dominated by spectral dynamics regions, not by the already
modernized FV CUDA resident boundary.

## Ranking

### 1. `transforms`

Runtime fraction:

```text
46.54% of T85L25 MPP runtime
```

This is the strongest measured performance target. It grew from about 39% at
T42L25 to about 47% at T85L25.

Modernization strategy:

```text
External/library strategy or broader transform-region redesign.
```

Do not translate this as isolated scalar loops. This region is likely tied to
spectral transform algorithms, decomposition, and communication. A realistic
GPU path probably needs a cuFFT/vendor-library or algorithm-level approach.

### 2. `tracer_correction_diagnostics`

Runtime fraction:

```text
21.37% of T85L25 MPP runtime
```

This remains an excellent measured region, but it is a mixed bucket. It likely
combines tracer updates, correction terms, time bookkeeping, and diagnostics.

Modernization strategy:

```text
Add deeper timers before translation.
```

The region is large enough to justify more instrumentation immediately.

### 3. `advection`

Runtime fraction:

```text
10.80% of T85L25 MPP runtime
```

This is a strong target at T85L25, but previous work showed that the current FV
CUDA resident boundary is not the dominant cost at this resolution. That means
the remaining advection time is likely outside the already modernized local FV
kernel bundle, or includes call-boundary and communication effects.

Modernization strategy:

```text
Instrument deeper advection subregions and distinguish translated FV CUDA work
from remaining Fortran advection work.
```

### 4. `press_geopot`

Runtime fraction:

```text
6.01% of T85L25 MPP runtime
```

This crossed into the reasonable-target band at T85L25. It is lower payoff than
transforms or tracer/correction, but it may be cleaner to isolate.

Modernization strategy:

```text
Fallback C++/CUDA candidate if transform and tracer/update regions are too
coupled for the next implementation cycle.
```

## Recommendation

Recommendation:

```text
B. Add one more deeper timer before translation.
```

The next modernization target should not be selected from the broad region
names alone. The T85L25 profile says where the time is, but not yet which
module boundary is clean enough to translate safely.

Recommended next instrumentation:

1. Split `transforms` by individual transform call:
   - grid-to-spectral pressure tendency
   - grid-to-spectral temperature tendency
   - vorticity/divergence from wind grid
   - geopotential/kinetic-energy transform
   - spectral-to-grid future-state updates

2. Split `tracer_correction_diagnostics`:
   - `update_tracers`
   - `compute_corrections`
   - every-step diagnostics
   - time/bookkeeping outside diagnostics

3. Split `advection`:
   - horizontal temperature advection
   - horizontal momentum advection
   - vertical advection calls, if present
   - any remaining FV advection work outside the translated CUDA boundary

## Final Decision

Do not start translation yet.

Proceed with deeper T85L25 profiling, with priority order:

1. `transforms`
2. `tracer_correction_diagnostics`
3. `advection`
4. `press_geopot`

Confidence level:

```text
High for identifying transforms as the dominant measured region.
Medium for selecting an implementation boundary, because transform internals
and tracer/correction/diagnostic subcomponents still need separation.
```

## Next Implementation Step

Create or reuse a `PROFILE_DYNAMICS_DEEP` T85L25 run that reports individual
timers under the top three regions. The immediate goal is to answer:

```text
Is the next target a transform-library strategy, a tracer/update boundary, or a
specific clean pressure/advection kernel?
```

