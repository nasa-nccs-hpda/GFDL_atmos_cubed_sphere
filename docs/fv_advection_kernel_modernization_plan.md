# FV Advection Kernel Modernization Plan

Date: 2026-06-16

## Objective

Plan the first C++ modernization step for local finite-volume advection kernels
inside:

```text
src/atmos_spectral/model/fv_advection.F90
```

Decision context:

```text
PARTIAL GO / Strategy 3
Keep fv_advection_mod and domain/halo handling in Fortran.
Move local finite-volume loop kernels behind a C API.
Do not translate yet.
```

## Measured Motivation

The deep dynamics profile identified the active grid-tracer horizontal
advection path as a strong measured region:

```text
tracer_grid_horizontal_advection: about 12.04% of model MPP runtime
update_tracers wrapper: about 17.55% of model MPP runtime
```

The selected boundary is intentionally narrower than the whole measured
routine because `a_grid_horiz_advection_3d` owns FMS halo updates and polar
boundary handling.

## Local Call Graph

Primary measured call site:

```text
spectral_dynamics_mod::update_tracers
  -> fv_advection_mod::a_grid_horiz_advection_3d
```

Local finite-volume call graph:

```text
a_grid_horiz_advection_3d
  -> mpp_update_domains(vx, advection_domain)        [keep in Fortran]
  -> mpp_update_domains(qx, advection_domain)        [keep in Fortran]
  -> polar boundary fill for vx/qx                   [keep in Fortran first]
  -> local setup of uc, vc, div                      [Fortran first, later candidate]
  -> advection_sphere_3d
       -> semi_x_3d
            -> find_cell_x
       -> semi_y_3d
       -> mpp_update_domains(q1, advection_domain)   [keep in Fortran]
       -> polar boundary fill for q1                 [keep in Fortran first]
       -> vanleer_x_3d
            -> integer_flux_x, conditionally
            -> slope_x
            -> find_cell_x
       -> vanleer_sphere_3d
            -> slope_sphere
```

## Kernel Ranking

All kernels are called once per active `a_grid_horiz_advection_3d` call unless
noted.  In the measured 30-day run, that means 4320 calls for the active grid
tracer path.

| Rank | Kernel | Call Frequency | Array Size | Arithmetic Intensity | GPU Suitability | Ease Of Isolation | Dependency Complexity | Validation Difficulty | Notes |
|---:|---|---|---|---|---|---|---|---|---|
| 1 | `semi_y_3d` | High | `nx * local_ny * nz` | Low-medium | High | Very high | Low | Low-medium | No callees; uses halo-ready `qx`, `va`, `dyy`; best first kernel. |
| 2 | `semi_x_3d` | High | `nx * local_ny * nz` | Medium | High | Medium | Medium | Medium | Calls `find_cell_x`; periodic gather/index behavior. |
| 3 | `slope_sphere` | High | `nx * (local_ny+3) * nz` | Medium | High | High | Low-medium | Medium | Limiter helper for y-direction Van Leer; uses halo input and metrics. |
| 4 | `vanleer_sphere_3d` | High | `nx * local_ny * nz` plus flux/slope | Medium | High | Medium | Medium | Medium-high | Calls `slope_sphere`; updates `dq_dt`; pole flux zeroing. |
| 5 | `slope_x` | High | `nx * local_ny * nz` | Medium | High | High | Low | Medium | Periodic x limiter; numerically sensitive. |
| 6 | `find_cell_x` | High, called by `semi_x_3d` and `vanleer_x_3d` | `nx * local_ny * nz` integer output | Low | Medium | Very high | Low | Low | Simple helper, useful but too small alone. |
| 7 | `vanleer_x_3d` | High | `nx * local_ny * nz` plus flux/slope/index temporaries | Medium-high | Medium-high | Medium-low | High | High | Calls `integer_flux_x`, `slope_x`, `find_cell_x`; branchy periodic update. |
| 8 | `integer_flux_x` | Conditional per row when `maxval(abs(b)) > 1` | Variable-length sums | Variable | Low-medium | Medium | Medium | High | Branchy variable-length periodic sums; translate after `vanleer_x_3d` analysis. |
| 9 | `advection_sphere_3d` | High | Orchestrator over all local arrays | Mixed | Medium | Low first | High | High | Contains halo update; should remain Fortran until local kernels are validated. |

## Selected First Kernel

Selected first kernel:

```text
semi_y_3d
```

Why this is the right starting point:

- It is part of the measured `a_grid_horiz_advection_3d` path.
- It has no callees.
- It has no MPI, no `mpp_update_domains`, and no spectral transforms.
- It operates over regular 3D arrays.
- It uses a simple directional upwind branch:

```fortran
where (va(:,j,:) >= 0.0)
  dq(:,j,:) = va(:,j,:)*dt*(qx(:,j-1,:) - qx(:,j  ,:))/dyy(j)
elsewhere
  dq(:,j,:) = va(:,j,:)*dt*(qx(:,j  ,:) - qx(:,j+1,:))/dyy(j+1)
end where
```

- It validates the Fortran-to-C++ local-kernel C API without requiring the
  harder x-periodic indexing and limiter helpers first.

This is not expected to capture the full 12% measured region alone.  It is the
lowest-risk first step toward the local finite-volume kernel group.

## Fortran Baseline Harness Design

Create a focused Fortran harness for `semi_y_3d` before C++ translation.

Harness responsibilities:

1. Initialize dimensions:
   - `nx`,
   - `js`,
   - `je`,
   - `nz`.
2. Initialize metric array:
   - `dyy(js:je+1)`.
3. Generate or load input arrays:
   - `va(:,js:je,:)`,
   - `qx(:,js-2:je+2,:)`,
   - scalar `dt`.
4. Call the original Fortran `semi_y_3d`.
5. Write binary fixtures:
   - inputs,
   - output `dq(:,js:je,:)`,
   - metadata with dimensions and index bounds.

Because `semi_y_3d` is private inside `fv_advection_mod`, the harness will need
one of these approaches:

- compile an overlay/test-only copy that exposes a harness wrapper,
- or add a test-only driver inside an overlay module,
- or capture inputs/outputs from `a_grid_horiz_advection_3d` around the call.

Production source should remain untouched.

## Required Synthetic Input Fields

Synthetic fixtures should include:

- mixed positive/negative `va` values to exercise both branches,
- zero `va` values to test the `>= 0.0` branch,
- smooth `qx` field,
- sharp-gradient `qx` field,
- multi-level `nz > 1`,
- at least one nontrivial `dyy(j)` profile,
- small dimensions for exact debugging,
- production-like dimensions for performance sanity.

Suggested small case:

```text
nx = 8
js = 1
je = 6
nz = 3
```

Suggested production-like case:

```text
Use dimensions from the Held-Suarez run after fv_advection_init.
```

## Realistic Model-Run Input Option

Add a capture-only overlay around the `semi_y_3d` call inside
`advection_sphere_3d` for one timestep or a small sample of calls.

Capture:

```text
va(:,js:je,:)
qx(:,js-2:je+2,:)
dt
dyy(js:je+1)
dq(:,js:je,:) output
nx, js, je, nz
```

This gives a realistic fixture from the active grid tracer path without
needing to translate or expose the whole `a_grid_horiz_advection_3d` routine.

## Output Variables To Compare

Primary output:

```text
dq(:,js:je,:)
```

Metadata to validate:

```text
nx
js
je
nz
dt
dyy(js:je+1)
```

## C++ Function Signature Proposal

Use Fortran column-major layout and pass explicit bounds.

```cpp
void semi_y_3d_cpp(
    int nx,
    int js,
    int je,
    int nz,
    double dt,
    const double* va,
    const double* qx,
    const double* dyy,
    double* dq);
```

Indexing convention:

- `va` and `dq` cover `(:, js:je, :)`.
- `qx` covers `(:, js-2:je+2, :)`.
- `dyy` covers at least `js:je+1`.
- C++ indexing helper must preserve Fortran column-major order.

## C API Proposal

```c
void fv_semi_y_3d_c(
    int nx,
    int js,
    int je,
    int nz,
    double dt,
    const double* va,
    const double* qx,
    const double* dyy,
    double* dq);
```

For first CPU validation, keep the ABI minimal and avoid derived types,
callbacks, or FMS domain objects.

## Fortran Wrapper Proposal

Add a test/hybrid wrapper guarded by a future compile flag:

```fortran
#ifdef USE_CPP_FV_ADVECTION
interface
  subroutine fv_semi_y_3d_c(nx, js, je, nz, dt, va, qx, dyy, dq) bind(C)
    use iso_c_binding
    integer(c_int), value :: nx, js, je, nz
    real(c_double), value :: dt
    real(c_double), intent(in) :: va(*), qx(*), dyy(*)
    real(c_double), intent(inout) :: dq(*)
  end subroutine
end interface
#endif
```

The first integrated overlay would replace only the body of `semi_y_3d` with a
C call while leaving the rest of `fv_advection_mod` in Fortran.

## Validation Tolerances

Initial CPU C++ target:

```text
Exact or near-exact agreement expected.
```

Suggested report metrics:

```text
max abs error
RMSE
max relative error where denominator is safe
mismatch count above 1e-13
```

Start tolerance:

```text
1e-13 for double precision
```

If the C++ implementation preserves the same operation order, exact agreement
or roundoff-level differences should be achievable.

## Expected Risks

Primary risks:

- Fortran lower bounds `js`, `js-2`, and `je+2` must be mapped correctly.
- `dyy(j+1)` access requires `dyy` to include `je+1`.
- The `va >= 0.0` branch must match Fortran's behavior at exactly zero.
- C++ must preserve column-major memory order.
- This first kernel alone will not deliver a meaningful model speedup.

Follow-on risks:

- Later kernels such as `vanleer_x_3d` and `vanleer_sphere_3d` are more
  numerically sensitive.
- The full `a_grid_horiz_advection_3d` path still contains halo updates and
  polar boundary behavior that remain Fortran-owned.

## Next Steps

1. Create `docs/translation_spec_semi_y_3d.md`.
2. Build a Fortran baseline harness or capture overlay for `semi_y_3d`.
3. Generate synthetic fixtures.
4. Generate one realistic fixture from the Held-Suarez grid tracer path.
5. Only after fixtures are available, implement the CPU C++ version.

Do not start C++ translation until the harness and fixture plan are accepted.
