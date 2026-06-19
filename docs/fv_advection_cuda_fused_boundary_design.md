# FV Advection CUDA Fused-Boundary Design

## Decision Context

Persistent device allocations validated the buffer-reuse mechanism but did not
make the integrated CUDA path competitive.

| Backend | 30-day MPP runtime | Relative result |
|---|---:|---:|
| CPU C++ FV bundle | 25.546 s | reference |
| Stateless CUDA FV bundle | 132.355 s | 5.18x slower than CPU |
| Persistent CUDA FV bundle | 127.381 s | 4.99x slower than CPU |

Persistent buffers improve CUDA over stateless CUDA by only 1.039x. On the
maximum-total rank, H2D copies consume 64.778 s (67.6%) and kernel execution
consumes 28.941 s (30.2%). Allocation is down to 1.5%, so further allocator
tuning cannot materially change the result.

Even the optimistic subtraction of all measured H2D time leaves about 62.6 s
of model MPP runtime. That remains roughly 2.45x the complete CPU C++ run.
Transfer elimination is necessary, but GPU sharing, synchronization, kernel
granularity, and fusion must improve too.

## Correctness And Repeatability Gate

The four duration-matched outputs are present:

```text
$GFDL_DATA/held_suarez_default/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_fv_kernels_30day/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_fv_kernels_cuda_30day/run0001/atmos_monthly.nc
$GFDL_DATA/held_suarez_fv_kernels_cuda_persistent_30day/run0001/atmos_monthly.nc
```

The all-Fortran and FV runs use matching 30-day T42L25 namelists. Standalone
and Fortran-to-C-to-CUDA persistent tests already pass exactly. The model-level
NetCDF comparison is a local-shell workflow matching the existing
`validate_fv_semi_y_30day.sh` pattern:

```bash
./scripts/validate_fv_kernels_persistent_30day.sh
```

It generates comparisons against all-Fortran, CPU C++, and stateless CUDA in
`tests/reports/` and logs to
`logs/fv_kernels_cuda_persistent_30day_validation.log`.

The local comparison completed with exact agreement for `temp`, `ucomp`,
`vcomp`, and `ps` against all-Fortran, CPU C++, and stateless CUDA outputs.
Dimensions match and every reported maximum error and RMSE is zero.

Repeat the persistent timing under a distinct experiment name:

```bash
FV_KERNELS_EXPERIMENT=held_suarez_fv_kernels_cuda_persistent_30day_repeat \
FV_KERNELS_LOG="$PWD/logs/fv_kernels_cuda_persistent_30day_repeat.log" \
./scripts/run_fv_kernels_persistent_30day.sh
```

Compare the repeat with the original only when node, GPU, MPI rank count,
diagnostics, and executable are identical. Report both values and their mean;
do not treat the 3.9% improvement as stable if run-to-run spread is comparable.

The repeat completed at 126.964 s MPP versus 127.381 s originally, a 0.33%
difference. Their 127.173 s mean confirms that the persistent timing is stable
and that its small improvement over stateless CUDA is not measurement noise.

## Existing Execution Boundary

`a_grid_horiz_advection_3d` performs host-side domain updates and polar boundary
work before entering `advection_sphere_3d`. The latter executes:

1. `semi_x_3d`, producing `q1`.
2. `semi_y_3d`, producing `q2`.
3. `mpp_update_domains(q1, advection_domain)` in Fortran.
4. Polar halo correction of `q1` in Fortran.
5. `vanleer_x_3d`, consuming `q2`.
6. `vanleer_sphere_3d`, consuming halo-complete `q1`.

The required MPI halo exchange is a hard synchronization boundary. A single
opaque CUDA call cannot span it while domain handling remains in Fortran.

## Option A: Fuse Existing FV Kernels

**Boundary.** Replace individual wrappers with one pre-halo CUDA operation for
`semi_x_3d` and `semi_y_3d`, plus one post-halo operation for `vanleer_x_3d`
and `vanleer_sphere_3d`. A literal one-call implementation is rejected because
Fortran must perform the intervening halo update.

**Fortran overlay changes.** Replace four local wrapper calls with two staged
calls and retain `mpp_update_domains` and polar correction between them.

**C API changes.** Add `fv_advection_pre_halo(...)` and
`fv_advection_post_halo(...)`, operating on an opaque per-rank context. Existing
kernel APIs remain available as fallback.

**Memory ownership.** CUDA owns persistent `q1`, `q2`, velocity, and tendency
buffers. The host receives and returns the halo-relevant `q1` region between
stages.

**Expected H2D reduction.** Approximately 25-50%. Intermediate arrays can stay
on device, but each advection update still imports model inputs and crosses the
halo boundary.

**Risk and validation.** Medium. Validate each stage against captured Fortran
intermediates, then run the existing unit, wrapper, 1-day, and 30-day ladder.
The main risk is preserving update order and halo extents.

**Expected speedup.** Moderate for the CUDA region, limited end to end. It
reduces launches and intermediate copies but does not establish residency
across tracer updates.

**Rollback.** Runtime-select the existing per-kernel stateless or persistent
backend.

## Option B: Broader `a_grid_horiz_advection_3d` Inner Boundary

**Boundary.** Keep initialization, `mpp_update_domains`, domain metadata, and
polar ownership in Fortran. Move local interpolation, divergence, predictor,
and flux work into a two-phase CUDA inner region separated by the existing
Fortran halo exchange.

**Fortran overlay changes.** Introduce begin/end calls around the local region:

```text
begin_local_advection -> export q1 halo -> Fortran halo update
-> import q1 halo -> finish_local_advection
```

No production source changes are required; the overlay remains selectable.

**C API changes.** Add an opaque context and shape-aware calls such as:

```text
fv_advection_begin(context, ua, va, q, dt, ...)
fv_advection_export_q1_halo(context, host_q1)
fv_advection_import_q1_halo(context, host_q1)
fv_advection_finish(context, dq_dt, ...)
```

The exact API should transfer only MPI-required halo slabs rather than full
arrays where the domain library permits it.

**Memory ownership.** CUDA owns all local intermediates and persistent working
storage. Fortran owns prognostic arrays, MPI/domain metadata, and host halo
buffers. Ownership changes are explicit at the two phase boundaries.

**Expected H2D reduction.** Approximately 50-80% within the FV region. Primary
inputs are copied once per broader update; `q1` and `q2` intermediates stay on
device; only the required halo data makes the mid-region round trip.

**Risk and validation.** Medium-high. New local loops must be validated at
intermediate checkpoints, especially divergence, polar indexing, and
`dq_dt` accumulation. Captured realistic MPI-rank fixtures are preferable to
synthetic data for halo-sensitive tests.

**Expected speedup.** Highest credible near-term potential without taking over
MPI. Fusion should reduce H2D, wrapper crossings, launches, and synchronization.
At T42, it may still remain slower than CPU because the measured CUDA kernel
and rank-contention costs alone are large. T85/T170 scaling is essential.

**Rollback.** Compile both overlay paths and select the current per-kernel API
at runtime. The original Fortran implementation remains untouched.

## Option C: `update_tracers` Device Residency

**Boundary.** Keep tracer policy, diagnostics, spectral transforms, and MPI in
Fortran, but retain grid-tracer arrays and tendencies on device across
horizontal advection, local correction, and vertical/local operations.

**Fortran overlay changes.** Substantial. `update_tracers` must explicitly
identify host consumers and synchronize only at transforms, diagnostics, MPI,
or unsupported kernels.

**C API changes.** Add tracer-state registration, device-view lookup, dirty
state tracking, synchronization, and per-step begin/end operations.

**Memory ownership.** Shared logical ownership with explicit host-valid and
device-valid states. CUDA owns allocations; Fortran remains authoritative for
model semantics and unsupported operations.

**Expected H2D reduction.** Approximately 70-95% for translated portions when
several operations consume the same resident tracer fields.

**Risk and validation.** High. Aliasing, multiple time levels, diagnostics,
spectral/grid representations, and error recovery complicate correctness.
Validation requires per-stage state snapshots plus 1-day, 30-day, restart, and
multi-tracer cases.

**Expected speedup.** Highest long-term potential because profiling attributes
about 12% to tracer horizontal advection and a larger mixed fraction to tracer
update/correction work. It only pays off after enough neighboring operations
are CUDA-capable.

**Rollback.** Preserve the current host-authoritative update path and allow
device residency to be disabled per experiment.

## Option D: Fortran-Controlled Device Lifetime

**Boundary.** Fortran explicitly brackets a reusable CUDA context:

```text
initialize_device_buffers
copy_inputs_once
run_many_kernels
copy_outputs_once
finalize_device_buffers
```

This is a lifecycle mechanism, not by itself a sufficient computational
boundary.

**Fortran overlay changes.** Add initialization/finalization and explicit copy
and execution calls at stable model lifecycle points. No domain logic moves.

**C API changes.** Add opaque context creation/destruction, reserve/resize,
named upload/download, execution, synchronization, and error-query functions.

**Memory ownership.** CUDA owns device allocations; Fortran controls lifetime
and remains the host-data owner. The API must define which copy marks each view
valid.

**Expected H2D reduction.** From negligible to 50-90%, depending on how many
kernels execute between `copy_inputs_once` and `copy_outputs_once`. Applied to
the current isolated calls alone, it provides little beyond existing persistent
allocation.

**Risk and validation.** Medium. Lifetime and stale-data errors replace hidden
allocation overhead as the main risk. Add context-state assertions and compare
after every explicit download during bring-up.

**Expected speedup.** Medium as infrastructure; high only when paired with
Option B or C.

**Rollback.** Destroy the context and route calls through the existing
stateless/persistent wrappers.

## Comparison

| Option | H2D reduction | Difficulty | Validation risk | Near-term potential |
|---|---:|---:|---:|---:|
| A. Fuse existing kernels | 25-50% | medium | medium | moderate |
| B. Broader FV inner region | 50-80% | medium-high | medium-high | high |
| C. `update_tracers` residency | 70-95% | very high | high | highest long term |
| D. Explicit lifetime API | scope-dependent, 50-90% with B/C | medium | medium | enabling mechanism |

## Recommendation

Proceed with **Option B implemented on Option D lifecycle infrastructure**.

The first increment should be a two-phase resident API around the existing
`advection_sphere_3d` sequence, with Fortran retaining the `q1` halo exchange.
Fuse the existing kernels within each side of that boundary and transfer only
the halo-required data between phases. This attacks the measured H2D bottleneck
without prematurely taking ownership of tracer policy, MPI, or diagnostics.

Option A is a useful implementation detail inside this boundary, not the final
architecture. Option C should follow only after Option B proves correctness and
T85/T170 measurements show that broader residency can overcome GPU contention.

Implementation is gated on:

1. Persistent 30-day NetCDF comparisons passing.
2. The repeated 30-day timing confirming the persistent/stateless difference.
3. A captured intermediate fixture for `q1`, `q2`, halo slabs, and `dq_dt`.
4. An API design review that fixes ownership and valid-state rules before code.

No production Fortran source, new kernel translation, or hybrid integration is
changed by this design.
