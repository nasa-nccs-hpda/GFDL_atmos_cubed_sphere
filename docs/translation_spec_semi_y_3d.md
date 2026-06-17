# Translation Spec: semi_y_3d

Date: 2026-06-16

## Objective

Translate the first local finite-volume advection kernel behind a C API while
keeping `fv_advection_mod`, domain decomposition, halo exchange, and pole
boundary handling in Fortran.

Selected kernel:

```text
src/atmos_spectral/model/fv_advection.F90
module: fv_advection_mod
subroutine: semi_y_3d
```

This is a PARTIAL GO / Strategy 3 target.  Do not translate the full
`a_grid_horiz_advection_3d` routine yet.

## Source Location

```fortran
subroutine semi_y_3d(dq, va, qx, dt)

real, intent(out), dimension(:,js  :,:) :: dq
real, intent(in),  dimension(:,js  :,:) :: va
real, intent(in),  dimension(:,js-2:,:) :: qx
real, intent(in)                        :: dt

integer :: j

do j = js, je
  where (va(:,j,:) >= 0.0)
    dq(:,j,:) = va(:,j,:)*dt*(qx(:,j-1,:) - qx(:,j  ,:))/dyy(j)
  elsewhere
    dq(:,j,:) = va(:,j,:)*dt*(qx(:,j  ,:) - qx(:,j+1,:))/dyy(j+1)
  end where
enddo

return
end subroutine semi_y_3d
```

## Role In Runtime

`semi_y_3d` is called from `advection_sphere_3d`:

```text
a_grid_horiz_advection_3d
  -> advection_sphere_3d
       -> semi_x_3d
       -> semi_y_3d
       -> mpp_update_domains(q1, advection_domain)
       -> vanleer_x_3d
       -> vanleer_sphere_3d
```

It computes the meridional semi-Lagrangian predictor increment:

```text
q2(:,js:je,:) = q(:,js:je,:) + dq(:,js:je,:)
```

The measured parent region is the grid-tracer horizontal advection path, which
contributed about 12% of the 30-day Held-Suarez model MPP runtime.  This
individual kernel is only one part of that region, but it is the cleanest first
translation boundary.

## Interface

Fortran arguments:

| Argument | Intent | Shape | Meaning |
|---|---|---|---|
| `dq` | `out` | `(:,js:,:)` | Output predictor increment over `j=js:je`. |
| `va` | `in` | `(:,js:,:)` | Meridional velocity over compute-domain cell centers. |
| `qx` | `in` | `(:,js-2:,:)` | Halo-ready tracer field with at least `j-1` and `j+1` available. |
| `dt` | `in` | scalar | Time increment passed as `0.5*dt` by `advection_sphere_3d`. |

Implicit module state used:

| State | Role | Translation Handling |
|---|---|---|
| `nx` | x dimension | Pass as explicit integer. |
| `js`, `je` | local y compute bounds | Pass as explicit integers or convert to zero-based local extents. |
| `dyy` | meridional metric at half-levels | Pass as explicit array covering `js:je+1`. |

No optional arguments, derived types, MPI objects, spectral transforms, or FMS
callbacks are used directly by this kernel.

## Dependency Classification

| Dependency | Classification | Notes |
|---|---|---|
| `dq` | B. can be passed as output | Direct output array. |
| `va` | B. can be passed as input | Direct input array. |
| `qx` | B. can be passed as input | Must preserve halo/lower-bound semantics. |
| `dt` | B. can be passed as input | Scalar. |
| `nx`, `js`, `je`, `nz` | B. can be passed as input | Metadata. |
| `dyy(js:je+1)` | B. can be passed as input | Metric array. |
| `mpp_update_domains` | A. no action | Occurs outside this kernel. |
| `advection_domain` | A. no action | Not used directly. |
| `monotone`, `dx`, `c`, `dy` | A. no action | Not used by `semi_y_3d`. |

## Numerical Semantics

The translated kernel must preserve:

- branch condition: `va >= 0.0`;
- zero velocity uses the positive branch;
- Fortran column-major array interpretation;
- `j=js` reads `qx(:,js-1,:)`;
- `j=je` reads `qx(:,je+1,:)`;
- positive branch divides by `dyy(j)`;
- negative branch divides by `dyy(j+1)`;
- double precision behavior used by the Isca build (`-fdefault-real-8`).

Recommended operation order for the C++ body:

```text
dq = va * dt * (neighbor_difference) / dyy_value
```

Do not algebraically rearrange this expression during the first translation.

## C++ Function Proposal

Use explicit metadata and Fortran-contiguous buffers:

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

Indexing contract:

- `va` and `dq` represent Fortran arrays with y lower bound `js`;
- `qx` represents a Fortran array with y lower bound `js-2`;
- `dyy` represents metric values covering `js:je+1`;
- the implementation should centralize index mapping in small helper functions
  to avoid lower-bound mistakes.

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

The C symbol should remain stable for the eventual Fortran overlay wrapper.
No public Isca or production Fortran API should change.

## Fortran Wrapper Proposal

The eventual overlay wrapper should use `iso_c_binding` and keep the original
Fortran routine signature for local callers:

```fortran
#ifdef USE_CPP_FV_ADVECTION
  call fv_semi_y_3d_c(nx, js, je, size(qx,3), dt, va, qx, dyy, dq)
#else
  ! Original Fortran body.
#endif
```

The wrapper must not move halo exchange, pole handling, or `advection_domain`
ownership into C++.

## Baseline Harness Design

Create a standalone Fortran baseline before translation.  Because `semi_y_3d`
is private inside `fv_advection_mod`, use one of these non-production options:

1. overlay/test-only copy that exposes a harness wrapper;
2. capture inputs and output around the existing call in `advection_sphere_3d`;
3. test-only driver compiled from an overlay source.

The harness should write:

```text
metadata: nx, js, je, nz, dt
input:    va(:,js:je,:)
input:    qx(:,js-2:je+2,:)
input:    dyy(js:je+1)
output:   dq(:,js:je,:)
```

## Synthetic Test Cases

Minimum synthetic cases:

- mixed positive and negative `va`;
- exact zero `va` to verify the `>= 0.0` branch;
- constant `qx`;
- smooth gradient `qx`;
- sharp-gradient `qx`;
- variable `dyy`;
- small debugging dimensions, for example `nx=8`, `js=1`, `je=6`, `nz=3`;
- production-like dimensions from a Held-Suarez run.

## Realistic Fixture Option

Add capture-only instrumentation around the `semi_y_3d` call in
`advection_sphere_3d` for a small number of calls in a short Held-Suarez run.

This realistic fixture is preferred before hybrid integration because it
captures the actual halo-populated `qx`, local `va`, metric `dyy`, and runtime
dimensions used by the model.

## Comparison Metrics

Compare `dq(:,js:je,:)`:

```text
max absolute error
RMSE
number of mismatches above tolerance
relative error for nonzero reference values
```

Suggested tolerance:

```text
1e-13 for double precision standalone comparison
```

Exact agreement may be possible if the C++ expression order matches Fortran and
compiler optimizations do not reassociate floating-point operations.

## Arithmetic Intensity Estimate

Per grid cell:

Approximate floating-point work:

```text
1 comparison
1 subtraction
1 multiply by dt
1 multiply by va
1 division by dyy
```

Approximate memory traffic:

```text
load va
load two qx values
load one dyy value
store dq
```

The loop is likely memory-bound.  It is GPU-friendly as a regular flat kernel,
but `semi_y_3d` alone is not expected to deliver a large end-to-end speedup.
Its value is as the first validated local-kernel modernization step in the
larger finite-volume advection path.

## Expected Risks

- Lower-bound mismatch for `qx(:,js-2:,:)`.
- Incorrect metric indexing for `dyy(j)` versus `dyy(j+1)`.
- Accidentally sending zero velocity to the negative branch.
- Shape mismatch when passing Fortran array sections through `iso_c_binding`.
- Small standalone performance impact if translated alone.
- Harness complexity because the original routine is private.

## Exit Criteria

Before any model integration:

1. Fortran baseline fixture exists.
2. C++ implementation matches synthetic fixtures within tolerance.
3. C++ implementation matches at least one realistic model-captured fixture.
4. C API and Fortran wrapper preserve the original `semi_y_3d` caller contract.

Only after those pass should the overlay replace the local `semi_y_3d` body in
the native Isca build path.
