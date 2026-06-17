# four_in_one Feasibility Analysis

Date: 2026-06-16

## Purpose

Before translating `spectral_dynamics_mod::four_in_one`, this document defines
the routine boundary, dependency surface, validation requirements, and go/no-go
recommendation.

The goal is to decide whether `four_in_one` can be isolated using the same
general workflow that worked for the Held-Suarez forcing module:

```text
Fortran model -> ISO_C_BINDING wrapper -> C ABI -> C++ implementation
```

No source translation is performed here.

## Location

Source file:

```text
src/atmos_spectral/model/spectral_dynamics.F90
```

Module:

```text
spectral_dynamics_mod
```

Routine:

```text
four_in_one
```

Approximate source location:

```text
src/atmos_spectral/model/spectral_dynamics.F90:1038
```

Calling site:

```text
spectral_dynamics
```

`spectral_dynamics` calls `four_in_one` inside the every-timestep dynamics loop,
after `pressure_variables` and `compute_pressure_gradient`, and before
`compute_geopotential`, vertical advection, transforms, damping, and leapfrog
updates.

## Full Interface

Fortran signature:

```fortran
subroutine four_in_one(divg, u_grid, v_grid, t_grid, p_surf, ln_p_half, ln_p_full, p_full, &
                       dx_psg, dy_psg, dt_psg, wg, wg_full, dt_tg, dt_ug, dt_vg)
```

Arguments:

| Argument | Intent | Rank | Declared shape | Runtime shape | Role |
|---|---|---:|---|---|---|
| `divg` | `in` | 3 | `(:,:,:)` | `(is:ie, js:je, num_levels)` | Grid divergence input |
| `u_grid` | `in` | 3 | `(:,:,:)` | `(is:ie, js:je, num_levels)` | Zonal wind grid input |
| `v_grid` | `in` | 3 | `(:,:,:)` | `(is:ie, js:je, num_levels)` | Meridional wind grid input |
| `t_grid` | `in` | 3 | `(:,:,:)` | `(is:ie, js:je, num_levels)` | Temperature or virtual-temperature input |
| `p_surf` | `in` | 2 | `(:,:)` | `(is:ie, js:je)` | Surface pressure |
| `ln_p_half` | `in` | 3 | `(:,:,:)` | `(is:ie, js:je, num_levels+1)` | Log half-level pressure |
| `ln_p_full` | `in` | 3 | `(:,:,:)` | `(is:ie, js:je, num_levels)` | Log full-level pressure |
| `p_full` | `in` | 3 | `(:,:,:)` | `(is:ie, js:je, num_levels)` | Full-level pressure |
| `dx_psg` | `in` | 2 | `(:,:)` | `(is:ie, js:je)` | X pressure-gradient term |
| `dy_psg` | `in` | 2 | `(:,:)` | `(is:ie, js:je)` | Y pressure-gradient term |
| `dt_psg` | `inout` | 2 | `(:,:)` | `(is:ie, js:je)` | Surface-pressure tendency accumulator |
| `wg` | `out` | 3 | `(:,:,:)` | `(is:ie, js:je, num_levels+1)` | Hybrid-coordinate interface mass flux |
| `wg_full` | `out` | 3 | `(:,:,:)` | `(is:ie, js:je, num_levels)` | Full-level vertical velocity/mass-flux diagnostic |
| `dt_tg` | `inout` | 3 | `(:,:,:)` | `(is:ie, js:je, num_levels)` | Temperature tendency accumulator |
| `dt_ug` | `inout` | 3 | `(:,:,:)` | `(is:ie, js:je, num_levels)` | Zonal-wind tendency accumulator |
| `dt_vg` | `inout` | 3 | `(:,:,:)` | `(is:ie, js:je, num_levels)` | Meridional-wind tendency accumulator |

There are no derived-type arguments.

There are no optional arguments.

There are no pointer arguments.

There are no allocatable dummy arguments.

All dummy arrays are real-valued.  In this Isca build, the compiler flags use
`-fdefault-real-8`, so these are effectively double precision at the ABI
boundary.

## Local Temporaries

`four_in_one` allocates automatic local arrays over the local horizontal grid:

```fortran
real, dimension(is:ie, js:je) :: dp
real, dimension(is:ie, js:je) :: dp_inv
real, dimension(is:ie, js:je) :: dlog_1
real, dimension(is:ie, js:je) :: dlog_2
real, dimension(is:ie, js:je) :: dlog_3
real, dimension(is:ie, js:je) :: dmean
real, dimension(is:ie, js:je) :: dmean_tot
real, dimension(is:ie, js:je) :: x1
real, dimension(is:ie, js:je) :: x2
real, dimension(is:ie, js:je) :: x3
real, dimension(is:ie, js:je) :: x4
real, dimension(is:ie, js:je) :: x5
real, dimension(is:ie, js:je) :: p_surf_inv
```

It also uses:

```fortran
real :: kappa
integer :: k
```

The local temporaries can be private arrays or scalar-per-cell temporaries in
C++.  A C++ implementation does not need to materialize every temporary as a
full 2D array if operation ordering is preserved.

## Module Variables Used

`four_in_one` reads these module variables from `spectral_dynamics_mod`:

| Variable | Source | Role | Classification |
|---|---|---|---|
| `is`, `ie`, `js`, `je` | Set by `get_grid_domain` during `spectral_dynamics_init` | Local grid bounds and automatic-array lower/upper bounds | B. Can be passed as dimensions |
| `num_levels` | Namelist/module state | Vertical dimension and loop bound | B. Can be passed as input |
| `vert_difference_option` | Namelist/module state | Selects `simmons_and_burridge` or `mcm` branch | B. Can be passed as enum/int |
| `dpk(:)` | Derived from `pk` in `spectral_dynamics_init` | Half-level pressure-coordinate delta | B. Can be passed as input |
| `dbk(:)` | Derived from `bk` in `spectral_dynamics_init` | Sigma-coordinate delta | B. Can be passed as input |
| `bk(:)` | Vertical-coordinate array | Needed in both branches and final `wg` adjustment | B. Can be passed as input |
| `rdgas` | `constants_mod` | Gas constant | A/B. Already available in Fortran, pass scalar for C++ |
| `cp_air` | `constants_mod` | Specific heat; used for `kappa=rdgas/cp_air` | A/B. Already available in Fortran, pass scalar or `kappa` |

`four_in_one` does not write module variables.

It does not read or write `ug`, `vg`, `tg`, `psg`, `vors`, `divs`, `ts`, or
other prognostic module arrays directly.  It receives the current fields and
tendency arrays through arguments.

## Common And Global State

There are no Fortran `common` blocks in `four_in_one`.

There is no file I/O.

There is no namelist access inside the routine.

There are no diagnostics calls.

There are no restart calls.

There are no MPI, MPP, or domain-decomposition calls inside the routine.

The only global coupling is read-only module state listed above.

## Constants

Direct constants:

```text
0.0
0.5
1.0
```

Physical constants:

```text
rdgas
cp_air
kappa = rdgas / cp_air
```

Vertical-coordinate constants:

```text
bk(k)
bk(k+1)
dpk(k)
dbk(k)
```

## Side Effects

The routine modifies only its `intent(out)` and `intent(inout)` arguments:

```text
dt_psg
wg
wg_full
dt_tg
dt_ug
dt_vg
```

It does not update global module state.

It does not update prognostic state arrays directly.  It updates tendency and
flux arrays that are later consumed by the rest of `spectral_dynamics`.

Numerical side effects are significant because these tendencies feed later
spectral transforms, damping, leapfrog updates, and future-state fields.

## Internal Algorithm

The routine has two branches.

### `simmons_and_burridge`

For each vertical level:

- Compute layer pressure thickness `dp`.
- Compute log-pressure differences.
- Compute pressure-gradient weights `x1`, `x2`, `x3`.
- Accumulate wind tendencies `dt_ug`, `dt_vg`.
- Compute column mass divergence `dmean`.
- Compute thermal tendency contribution `x5`.
- Accumulate temperature tendency `dt_tg`.
- Compute `wg_full`.
- Accumulate `dmean_tot` down the column.
- Write interface flux `wg(:,:,k+1)`.

After the level loop:

- Subtract `dmean_tot` from `dt_psg`.
- Adjust interior `wg` levels with `dmean_tot*bk(k)`.
- Set top and bottom `wg` to zero.

### `mcm`

The `mcm` branch has the same output/update structure but uses
`p_surf_inv`, simplified pressure-gradient scaling, and
`(dmean_tot + 0.5*dmean)/p_full(:,:,k)` for the thermal/vertical term.

## Dependencies

### Routines called by `four_in_one`

None.

This is the strongest isolation signal.  The routine is computationally
self-contained once its scalar constants, vertical-coordinate arrays, option
flag, dimensions, and input/output arrays are supplied.

### Modules used directly by the containing module

`spectral_dynamics_mod` uses many modules, including:

```text
fms_mod
constants_mod
time_manager_mod
field_manager_mod
tracer_manager_mod
diag_manager_mod
transforms_mod
vert_advection_mod
implicit_mod
press_and_geopot_mod
spectral_damping_mod
leapfrog_mod
fv_advection_mod
mpp_mod
mpp_domains_mod
```

However, `four_in_one` itself only depends on:

```text
constants_mod: rdgas, cp_air
spectral_dynamics_mod module state: is, ie, js, je, num_levels, vert_difference_option, dpk, dbk, bk
```

### Indirect dependencies

Indirect dependencies enter through the caller:

- `pressure_variables` prepares `ln_p_half`, `ln_p_full`, and `p_full`.
- `compute_pressure_gradient` prepares `dx_psg` and `dy_psg`.
- Current dynamics state supplies `divg`, `u_grid`, `v_grid`, and `t_grid`.
- Later transforms and dynamics consume the output tendencies and fluxes.

These indirect dependencies do not need to be translated for a `four_in_one`
hybrid POC.

### FFT/spectral transforms

`four_in_one` does not call FFTs, spherical harmonic transforms, or any routine
from `transforms_mod`.

### MPI/MPP/domain decomposition

`four_in_one` does not call `mpp_mod`, `mpp_domains_mod`, or `spec_mpp`.

It does depend on local grid bounds `is:ie` and `js:je`, which were determined
by domain decomposition during initialization.  For C++ these should be passed
as local extents or inferred from array sizes.  No halo exchange is required
inside this routine.

### Prognostic state update

`four_in_one` does not directly advance the prognostic arrays.  It updates
tendencies and fluxes:

```text
dt_psg
dt_ug
dt_vg
dt_tg
wg
wg_full
```

Those outputs feed later timestep integration, so the routine is still a
dynamics-state update kernel in practical terms.

## Dependency Classification

| Dependency | Category | Notes |
|---|---|---|
| `rdgas`, `cp_air` | A/B | Already available in Fortran through `constants_mod`; pass scalar values or pass `kappa` and `rdgas` to C++ |
| `is`, `ie`, `js`, `je` | B | Convert to explicit local extents `nlon`, `nlat`; C++ does not need Fortran lower bounds except for indexing validation |
| `num_levels` | B | Pass as `nlev` |
| `vert_difference_option` | B | Pass as integer enum, for example `1=simmons_and_burridge`, `2=mcm` |
| `bk(:)` | B | Pass pointer and length `nlev+1` |
| `dpk(:)` | B | Pass pointer and length `nlev` |
| `dbk(:)` | B | Pass pointer and length `nlev` |
| `divg`, `u_grid`, `v_grid`, `t_grid` | B | Pass array pointers and dimensions |
| `p_surf`, `ln_p_half`, `ln_p_full`, `p_full` | B | Pass array pointers and dimensions |
| `dx_psg`, `dy_psg` | B | Pass array pointers and dimensions |
| `dt_psg`, `dt_tg`, `dt_ug`, `dt_vg` | B | Pass mutable array pointers and dimensions |
| `wg`, `wg_full` | B | Pass mutable output array pointers and dimensions |
| `pressure_variables` | A for hybrid boundary | Already executed by Fortran caller; not part of `four_in_one` |
| `compute_pressure_gradient` | A for hybrid boundary | Already executed by Fortran caller; not part of `four_in_one` |
| `transforms_mod` routines | A/E | Not used by `four_in_one`; defer transform modernization |
| MPI/MPP/domain decomposition | A/E | No calls inside routine; local extents are enough for this boundary |
| Derived types | A | None in `four_in_one` |
| Optional arguments | A | None |
| Fortran callbacks | A | None required |
| New C++ translations | C, only the kernel itself | No smaller callee exists to translate first |

Legend:

- A. Already available / no action
- B. Can be passed as input
- C. Needs C++ translation
- D. Needs Fortran callback
- E. Too coupled / defer

## Can It Be Isolated Like `hs_forcing`?

Yes, with a different boundary shape.

`hs_forcing` was a larger physics module with a Fortran wrapper and a C++
module-level replacement.  `four_in_one` is an internal dynamics kernel inside
`spectral_dynamics_mod`, so it is not directly replaceable by adding a new
source directory alone.  It needs a source overlay for `spectral_dynamics.F90`
that changes only the `four_in_one` body or call path.

The isolation is still feasible because:

- The routine calls no other routines.
- It has no I/O.
- It has no MPI or MPP calls.
- It has no derived-type arguments.
- It has no optional arguments.
- Its hidden state is small and can be made explicit.
- It only mutates arrays supplied as dummy arguments.

The key difference from `hs_forcing` is that `four_in_one` is not currently a
public module routine and relies on module variables for local bounds and
vertical-coordinate metadata.  The overlay must either:

1. Replace the `four_in_one` implementation with a Fortran wrapper that passes
   explicit state to C++, or
2. Replace the call site in `spectral_dynamics` with a wrapper call.

Replacing the body is cleaner because it preserves the call site and limits the
overlay diff.

## Recommended Module Boundary

Recommended boundary:

```text
Fortran spectral_dynamics_mod::four_in_one wrapper
  -> four_in_one_c_interface.F90
  -> C ABI
  -> C++ four_in_one kernel
```

The Fortran wrapper should live in the overlay version of
`spectral_dynamics.F90` or in a small companion module included by the overlay.

The public production source should remain untouched.

The wrapper should convert hidden module state into explicit C ABI arguments:

```text
nlon_local
nlat_local
nlev
option_id
rdgas
cp_air
bk
dpk
dbk
all input arrays
all inout/output arrays
```

Use CPU C++ first.  CUDA should be deferred until:

- Standalone Fortran vs C++ parity passes.
- Hybrid 1-day and 30-day CPU parity are established.
- Profiling shows the kernel is worth offloading.

## Expected C API Surface

Suggested C function:

```c
int four_in_one_c(
    int nlon,
    int nlat,
    int nlev,
    int option_id,
    double rdgas,
    double cp_air,
    const double* bk,
    const double* dpk,
    const double* dbk,
    const double* divg,
    const double* u_grid,
    const double* v_grid,
    const double* t_grid,
    const double* p_surf,
    const double* ln_p_half,
    const double* ln_p_full,
    const double* p_full,
    const double* dx_psg,
    const double* dy_psg,
    double* dt_psg,
    double* wg,
    double* wg_full,
    double* dt_tg,
    double* dt_ug,
    double* dt_vg);
```

Important ABI notes:

- Preserve Fortran column-major indexing.
- Pass contiguous local array sections only.
- Avoid passing character strings across the ABI.  Convert
  `vert_difference_option` to an integer in Fortran before the C call.
- Return an integer status code for invalid options or dimension errors.
- Keep all arrays as `double*` under the current `-fdefault-real-8` build.

## Baseline Harness Design

Suggested location:

```text
tests/fortran_baseline/four_in_one/
```

Harness inputs:

- Small deterministic `nlon`, `nlat`, `nlev`.
- `bk`, `dpk`, `dbk`.
- `rdgas`, `cp_air`.
- `vert_difference_option`.
- `divg`, `u_grid`, `v_grid`, `t_grid`.
- `p_surf`, `ln_p_half`, `ln_p_full`, `p_full`.
- `dx_psg`, `dy_psg`.
- Initial `dt_psg`, `dt_tg`, `dt_ug`, `dt_vg`.

Harness outputs:

- Final `dt_psg`.
- Final `dt_tg`.
- Final `dt_ug`.
- Final `dt_vg`.
- `wg`.
- `wg_full`.

Test cases:

1. Runtime Held-Suarez default: `simmons_and_burridge`.
2. Alternate branch: `mcm`.
3. Nonzero initial tendencies to validate `intent(inout)` accumulation.
4. Multiple vertical levels with nontrivial `bk`, `dpk`, `dbk`.
5. Edge case with horizontally varying pressure gradients.

Comparison metrics:

- Max absolute error per output.
- RMSE per output.
- Mismatch count above tolerance.
- Optional exact binary comparison for the first CPU implementation.

## Validation Data Needed

Minimum standalone data:

```text
metadata.json or metadata.txt
inputs/bk.bin
inputs/dpk.bin
inputs/dbk.bin
inputs/divg.bin
inputs/u_grid.bin
inputs/v_grid.bin
inputs/t_grid.bin
inputs/p_surf.bin
inputs/ln_p_half.bin
inputs/ln_p_full.bin
inputs/p_full.bin
inputs/dx_psg.bin
inputs/dy_psg.bin
inputs/dt_psg_initial.bin
inputs/dt_tg_initial.bin
inputs/dt_ug_initial.bin
inputs/dt_vg_initial.bin
outputs/dt_psg.bin
outputs/dt_tg.bin
outputs/dt_ug.bin
outputs/dt_vg.bin
outputs/wg.bin
outputs/wg_full.bin
```

For hybrid validation:

- 1-day smoke run output.
- 30-day all-Fortran or Fortran-overlay output.
- 30-day `four_in_one` hybrid output.
- NetCDF comparisons for `ps`, `ucomp`, `vcomp`, `temp`, `vor`, and `div`.

## Compile And Link Risks

Expected risks:

- Overlaying `spectral_dynamics.F90` is a larger source replacement than the
  forcing overlay.  The overlay must track the production file closely.
- `four_in_one` is private inside `spectral_dynamics_mod`; adding a wrapper may
  require careful placement before/inside `contains`.
- If a companion Fortran C-interface module is added, `path_names` ordering and
  module dependency discovery must include it.
- The C++ static library must be built inside the same container/architecture
  as the model.
- The mkmf template may need `-lstdc++` as with the forcing module.
- If CUDA is added later, the same `libcudart` and architecture issues from the
  forcing POC will recur unless the existing CUDA hybrid template is reused.

Lower risk than forcing CUDA POC:

- No external C++ runtime is required for CPU C++ except `libstdc++`.
- No CUDA runtime is required for the first CPU translation.
- No NetCDF, MPI, or transform libraries are introduced by the kernel itself.

## Runtime Risks

Numerical risks:

- The vertical recurrence through `dmean_tot` must preserve operation order.
- Fortran array syntax may evaluate temporaries in ways that differ from a
  fused C++ loop.  Exact parity may require conservative loop structure.
- `intent(inout)` arrays must accumulate on top of existing tendency values,
  not overwrite them.
- `wg` top and bottom boundary values must be set exactly after the interior
  update.
- The `simmons_and_burridge` and `mcm` branches must both handle `bk`, `dpk`,
  and `dbk` indexing correctly.

Runtime integration risks:

- Small tendency differences can amplify through spectral transforms, damping,
  and leapfrog updates.
- CPU/GPU transfer overhead would likely dominate if this routine alone is
  offloaded to CUDA while the rest of dynamics remains on CPU.
- The routine may not be the dominant runtime component; transforms or vertical
  advection may still dominate.

## Strategy Evaluation

### Strategy 1: Translate `four_in_one` directly

Recommendation: yes.

Pros:

- No subroutine callees need translation.
- Hidden state is small and passable.
- No MPI, I/O, transforms, diagnostics, or derived types inside the boundary.
- The routine is performance-relevant and called every timestep.
- It is a good stepping stone from physics forcing to dynamics kernels.

Cons:

- It is private inside a large module, requiring a `spectral_dynamics.F90`
  overlay.
- It updates numerically sensitive tendencies.
- It may not dominate wall-clock runtime.

### Strategy 2: Translate a smaller subroutine called by `four_in_one` first

Recommendation: no.

`four_in_one` calls no subroutines.  There is no smaller callee to translate
first.  The smaller units would be artificial expressions or branch fragments,
which would add interface overhead without reducing meaningful risk.

### Strategy 3: Choose another candidate first

Recommendation: only if profiling contradicts the static analysis.

`vert_advection_3d` may be more expensive, but it has many schemes, flags,
optional masks, limiters, and validation branches.  It is likely a better
second dynamics target after the `four_in_one` workflow is proven.

`press_and_geopot` is cleaner and also feasible, but it is less directly a
state-update tendency kernel and may have lower performance impact.

## Final Go/No-Go Recommendation

Go, with one prerequisite.

Proceed with `four_in_one` as the next translation target, but first add or run
coarse profiling around `spectral_dynamics` regions to confirm it is a
measurable part of runtime.  If profiling shows `four_in_one` is effectively
negligible and `vert_advection` or transforms dominate, adjust the performance
target before investing in the hybrid implementation.

Recommended immediate sequence:

1. Add non-invasive profiling overlays for `spectral_dynamics` timing.
2. Run duration-matched 30-day all-Fortran/CPU-hybrid timing.
3. If `four_in_one` has measurable runtime, build the standalone Fortran
   baseline harness.
4. Translate CPU C++ `four_in_one`.
5. Validate standalone outputs.
6. Integrate via native Isca overlay using `CodeBase.compile()`.
7. Run 1-day and 30-day validation.

Decision:

```text
GO for Strategy 1: translate four_in_one directly, after confirming timing.
```

