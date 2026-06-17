# a_grid_horiz_advection_3d Feasibility Analysis

Date: 2026-06-16

## Objective

Assess whether `fv_advection_mod::a_grid_horiz_advection_3d` is a feasible next
C++ modernization target for the Held-Suarez prototype.

Decision constraint:

```text
Do not translate yet.
```

## Performance Motivation

The second-level dynamics profile identified the active grid-tracer horizontal
advection call site as the strongest concrete routine-level candidate:

```text
tracer_grid_horizontal_advection: 2.905 s, 12.04% of model MPP runtime
update_tracers wrapper: 4.236 s, 17.55% of model MPP runtime
```

This is substantially larger than previous isolated candidates:

```text
four_in_one: about 2.6%
vert_advection_3d u+v+t: about 0.34%
```

## Location

Source file:

```text
src/atmos_spectral/model/fv_advection.F90
```

Module:

```text
fv_advection_mod
```

Generic public interface:

```fortran
interface a_grid_horiz_advection
   module procedure a_grid_horiz_advection_3d
   module procedure a_grid_horiz_advection_2d
end interface
```

Target routine:

```fortran
subroutine a_grid_horiz_advection_3d(ua, va, q, dt, dq_dt, flux)
```

Held-Suarez call site:

```text
src/atmos_spectral/model/spectral_dynamics.F90
```

Inside `update_tracers`, grid-tracer branch:

```fortran
call a_grid_horiz_advection(ug(:,:,:,current), vg(:,:,:,current), tr_future, delta_t, dt_tr(:,:,:,ntr))
```

## Interface Analysis

Arguments:

| Argument | Intent | Shape | Meaning |
|---|---|---|---|
| `ua` | `intent(in)` | `dimension(:,js:,:)` | A-grid zonal wind/current-level velocity field. |
| `va` | `intent(in)` | `dimension(:,js:,:)` | A-grid meridional wind/current-level velocity field. |
| `q` | `intent(in)` | `dimension(:,js:,:)` | Advected scalar/tracer field. |
| `dt` | `intent(in)` | scalar `real` | Timestep for semi-Lagrangian/Van Leer update. |
| `dq_dt` | `intent(inout)` | `dimension(:,js:,:)` | Accumulated tracer tendency; updated in place. |
| `flux` | optional `intent(in)` | scalar `logical` | If present and true, skips divergence contribution before advection. |

No derived-type arguments are passed to the routine.

No `intent(out)` arguments are present.

The array lower bound `js` is a module variable from `fv_advection_mod`, not an
argument.  The first dimension is assumed-size by interface syntax but is
treated internally as `nx`.

## Module State And Constants

`a_grid_horiz_advection_3d` depends on initialized module state set by
`fv_advection_init`:

| State | Role |
|---|---|
| `module_is_initialized` | Runtime guard. |
| `nx`, `ny` | Global horizontal dimensions. |
| `js`, `je` | Local compute-domain y bounds. |
| `advection_domain` | FMS `domain2D` used for halo updates. |
| `c`, `cc` | Cosine latitude factors. |
| `dy`, `dyy`, `dy_plus`, `dy_minus` | Metric spacing arrays. |
| `dx` | Zonal grid spacing. |
| `monotone` | Slope limiter mode. |

Initialization also uses:

```text
radius
pi
mpp_define_domains
mpp_get_compute_domain
```

Those are not direct arguments to `a_grid_horiz_advection_3d`, but their
results are required for any standalone or hybrid implementation.

## Side Effects

Primary side effect:

```text
dq_dt is updated in place.
```

Additional effects:

- Calls `mpp_update_domains` on local temporary arrays.
- Applies polar boundary conditions when `js == 1` or `je == ny`.
- May call `error_mesg(..., FATAL)` if `fv_advection_mod` is uninitialized.

The routine does not directly update `grid_tracers`; `update_tracers` later
uses `dq_dt` to update `tr_future` and `grid_tracers`.

## Dependency Analysis

Direct calls from `a_grid_horiz_advection_3d`:

```text
mpp_update_domains(vx, advection_domain)
mpp_update_domains(qx, advection_domain)
advection_sphere_3d(dq_dt, dt, qx, uc, vc, ua, va)
```

Indirect calls through `advection_sphere_3d`:

```text
semi_x_3d
semi_y_3d
mpp_update_domains(q1, advection_domain)
vanleer_x_3d
vanleer_sphere_3d
```

Further helper calls:

```text
find_cell_x
slope_x
integer_flux_x
slope_sphere
```

Module dependencies:

```text
fms_mod: mpp_pe, mpp_npes, mpp_root_pe, error_mesg, FATAL, write_version_number
constants_mod: radius, pi
mpp_domains_mod: mpp_define_domains, mpp_update_domains, mpp_get_compute_domain, domain2D
```

Spectral transforms:

```text
None.
```

MPI/domain decomposition:

```text
Yes.
```

The target routine and `advection_sphere_3d` both call `mpp_update_domains`.
The module owns a `domain2D` object and uses Y-direction decomposition with
halo width 2.

Halo and boundary conditions:

```text
Yes.
```

The routine fills halos via `mpp_update_domains`, then applies pole-specific
boundary mappings for `js == 1` and `je == ny`.

## Dependency Classification

| Dependency | Classification | Notes |
|---|---|---|
| `dt`, `ua`, `va`, `q`, `dq_dt`, optional `flux` | B. can be passed as input | Direct API values. |
| `nx`, `ny`, `js`, `je`, `dx`, `c`, `cc`, `dy`, `dyy`, `dy_plus`, `dy_minus`, `monotone` | B. can be passed as input | Needed for C++ standalone/hybrid kernels. |
| `advection_domain`, `mpp_update_domains` | D. needs Fortran callback or Fortran-owned wrapper | Too FMS-specific for first C++ port. |
| Polar boundary fill logic | C. needs C++ translation or remains in Fortran wrapper | Local logic, but tied to halo arrays and domain edge ownership. |
| `advection_sphere_3d` | C. needs C++ translation | Main local advection orchestrator. |
| `semi_x_3d`, `semi_y_3d` | C. needs C++ translation | Local semi-Lagrangian predictors. |
| `vanleer_x_3d`, `vanleer_sphere_3d` | C. needs C++ translation | Main limiter/flux update kernels. |
| `find_cell_x`, `slope_x`, `integer_flux_x`, `slope_sphere` | C. needs C++ translation | Helper kernels; numerically sensitive. |
| `error_mesg` guard | A or D | Can remain in Fortran wrapper; no need in C++ local kernels. |
| `fv_advection_init` metric setup | A initially, B later | Keep Fortran init first; pass initialized metrics to C++. |
| `fv_advection_end` | A | No C++ action initially. |

## Can It Be Isolated Like `hs_forcing`?

Not directly.

`hs_forcing` was a relatively clean physics module boundary.  It could be
replaced through an overlay wrapper with the model passing arrays into a C API.

`a_grid_horiz_advection_3d` is different:

- it is tied to `fv_advection_mod` module state,
- it owns halo updates through FMS `mpp_domains`,
- it uses polar boundary conditions based on local domain ownership,
- it updates an accumulated tendency array in place,
- and the top-level routine is part communication/boundary wrapper, part local
  numerical kernel.

The local finite-volume advection math can be isolated, but the full top-level
routine should not be translated first unless we are ready to reproduce or
callback into FMS domain behavior.

## Strategy Options

### Strategy 1: Translate `a_grid_horiz_advection_3d` Directly

Pros:

- Matches the measured call site exactly.
- Could eventually replace the full Fortran routine.

Cons:

- Must handle `mpp_update_domains` and `domain2D`.
- Must preserve pole boundary behavior.
- Harder to validate because communication and local math are mixed.

Recommendation:

```text
Not first.
```

### Strategy 2: Translate A Smaller Inner Kernel First

Candidate kernels:

```text
vanleer_x_3d
vanleer_sphere_3d
semi_x_3d
semi_y_3d
slope_x
slope_sphere
find_cell_x
integer_flux_x
```

Pros:

- Avoids FMS halo APIs.
- Good for validating numerical loop translations.

Cons:

- May miss the measured call-site integration benefit.
- Requires multiple helper translations before useful hybrid integration.

Recommendation:

```text
Useful for staged validation, but not the best top-level integration boundary.
```

### Strategy 3: Keep Fortran Wrapper And Call C++ For Local Loop Kernels

Boundary:

```text
Fortran a_grid_horiz_advection_3d wrapper:
  - keeps mpp_update_domains
  - keeps polar boundary setup
  - prepares vx/qx/uc/vc/div
  - calls C++ for local advection kernels
```

The first C++ target can cover:

```text
advection_sphere_3d local math
semi_x_3d
semi_y_3d
vanleer_x_3d
vanleer_sphere_3d
slope_x
slope_sphere
find_cell_x
integer_flux_x
```

Pros:

- Avoids reimplementing FMS domain communication.
- Keeps module initialization and halos in Fortran.
- Gives a realistic hybrid dynamics/advection path.
- Preserves the measured routine context.

Cons:

- The first boundary is more complex than `hs_forcing`.
- Requires careful array layout and lower-bound handling.
- May require translating several helper kernels together.

Recommendation:

```text
Best strategy.
```

### Strategy 4: Reject This Target

Not recommended.  The 12% measured runtime share is large enough to justify a
feasibility prototype, and the local loop kernels are GPU-relevant.

## Recommended Module Boundary

Recommended first boundary:

```text
Keep fv_advection_mod and a_grid_horiz_advection_3d in Fortran.
Move local finite-volume advection loop kernels behind a C API.
```

Practical first C++ function:

```text
fv_advection_local_update(...)
```

The Fortran wrapper would pass:

- `dq_dt`,
- `dt`,
- local `q`, `qx`, `uc`, `vc`, `ua`, `va`,
- dimensions and bounds,
- metric arrays `c`, `cc`, `dy`, `dyy`, `dy_plus`, `dy_minus`,
- `dx`,
- `monotone`.

The wrapper would keep:

- `mpp_update_domains`,
- `advection_domain`,
- pole boundary fill,
- module initialization and finalization,
- fatal error handling.

## Baseline Harness Design

Recommended standalone Fortran harness:

1. Initialize `fv_advection_mod` with the same `lon_max`, `lat_max`,
   `glat_bnd`, and `degrees_lon` values used by Held-Suarez.
2. Generate or capture representative arrays:
   - `ua`,
   - `va`,
   - `q`,
   - initial `dq_dt`,
   - `dt`,
   - optional `flux`.
3. Run the original Fortran `a_grid_horiz_advection_3d`.
4. Write binary outputs:
   - final `dq_dt`,
   - optionally intermediate local arrays for staged validation.
5. Include at least:
   - one grid tracer case matching the 30-day profile path,
   - `flux=.false.` default path,
   - if needed later, `flux=.true.` path.

For the first local-kernel validation, add a harness mode that captures the
post-halo local arrays passed to `advection_sphere_3d`.  That avoids needing
MPI/domain behavior in the C++ standalone test.

## C API Surface

First-stage local-kernel C API should avoid FMS objects:

```c
void fv_advection_local_update(
    int nx,
    int js,
    int je,
    int ny,
    int nz,
    double dt,
    double dx,
    int monotone,
    const double *c,
    const double *cc,
    const double *dy,
    const double *dyy,
    const double *dy_plus,
    const double *dy_minus,
    const double *q,
    const double *qx,
    const double *uc,
    const double *vc,
    const double *ua,
    const double *va,
    double *dq_dt);
```

The exact pointer order and dimension conventions should follow the existing
forcing-module C API style and preserve Fortran column-major layout.

Avoid passing:

```text
domain2D
advection_domain
```

in the first implementation.

## Validation Data Required

Required comparisons:

- final `dq_dt` after the full Fortran routine,
- local-kernel `dq_dt` after `advection_sphere_3d`,
- intermediate `q1` / `q2` if needed to isolate differences,
- x-direction and sphere/y-direction flux results,
- boundary cases for `js == 1` and `je == ny`,
- multi-level `nz > 1`,
- representative grid tracer path from Held-Suarez.

Metrics:

```text
max abs error
RMSE
max relative error where denominator is safe
mismatch count above tolerance
```

Suggested tolerance:

```text
Start with exact or near-exact for CPU C++.
Relax only if operation order intentionally differs.
```

## Overlay Integration Strategy

Use the native Isca overlay strategy:

1. Add an overlay for `src/atmos_spectral/model/fv_advection.F90`.
2. Keep original `fv_advection_init` / `fv_advection_end` behavior.
3. Add `iso_c_binding` interface only around local kernels.
4. Guard hybrid path with a compile flag, for example:

```text
-DUSE_CPP_FV_ADVECTION
```

5. Use a separate executable target, for example:

```text
held_suarez_hybrid_fv_advection.x
```

6. Link a new C++ static library through the existing native overlay build
   pattern.

Do not replace the production `fv_advection.F90`.

## Expected Compile/Link Risks

- Fortran lower-bound conventions such as `dimension(:,js-2:)` must be mapped
  carefully to C++ indexing.
- Build system must include any new Fortran wrapper module before dependent
  sources.
- If C++ functions are split into several translation units, link order and
  `extern "C"` names must be managed carefully.
- The existing hybrid mkmf template may need another library entry if this is
  built alongside `libhs_forcing.a`.

## Expected Runtime Risks

- C++ local kernels must preserve Fortran column-major order.
- Limiter behavior in `slope_x` and `slope_sphere` is numerically sensitive.
- `integer_flux_x` has branchy periodic summation and may be slow or tricky to
  reproduce exactly.
- Halo and pole logic must remain in Fortran until the local-kernel path is
  validated.
- MPI decomposition means a standalone single-rank harness is not enough; at
  least one multi-rank validation should follow.

## Expected Performance Benefit

Measured upper bound for the active call site:

```text
tracer_grid_horizontal_advection: about 12.04% of model MPP runtime
```

A local-kernel C++ replacement will not capture all of this if the Fortran
wrapper keeps halo updates and boundary setup.  A realistic first-stage benefit
is therefore lower than 12%, but still much more meaningful than the completed
forcing module or the `four_in_one`/`vert_advection_3d` isolated targets.

GPU relevance:

- local x/y advection kernels are array-loop dominated,
- work scales with `nx * local_ny * nz`,
- memory access and limiter branches will likely make this memory- and
  control-flow-sensitive,
- a CUDA version should come after CPU C++ parity.

## Final Recommendation

Recommendation:

```text
PARTIAL GO
```

Recommended strategy:

```text
Strategy 3: keep the Fortran wrapper and call C++ only for local loop kernels.
```

Rationale:

- The target is important enough: about 12% of model runtime at the measured
  call site.
- The full top-level routine is not cleanly isolated because of FMS
  `mpp_update_domains`, `domain2D`, and polar boundary handling.
- The local finite-volume kernels are a good next C++ modernization boundary.
- This is a stronger performance target than `four_in_one` or
  `vert_advection_3d`, but it needs staged validation before translation.

Next action:

```text
Create a detailed modernization plan and baseline harness design for the local
finite-volume advection kernels.  Do not start translation until that plan is
approved.
```
