# FV Advection Subroutine Residency Design

## Purpose

Resident-v1 and resident-v2 proved that the Fortran -> C -> CUDA integration is
correct, but also showed that moving individual kernels one at a time does not
solve the performance problem. The CUDA kernels are not the limiting factor.
Repeated CPU-to-GPU transfers are.

This document defines the next scoped experiment:

```text
resident-v3 = static metric residency + halo-only q1 post-halo transfer
```

The goal is to reduce host-to-device traffic while preserving the existing
Fortran/MPI halo exchange and without modifying production Fortran source.

## Current Evidence

Current 30-day T42L25 results with 16 MPI ranks:

| Backend | MPP runtime | Result |
|---|---:|---|
| CPU C++ FV bundle | 25.546 s | fastest translated path |
| Stateless CUDA | 132.355 s | slow, allocation/copy dominated |
| Persistent CUDA mean | 127.173 s | allocation improved, copies remain |
| Resident CUDA v1 | 108.505 s | broader boundary helps |
| Resident CUDA v2 | 108.794 s | semi-y on GPU, no speedup |

Resident-v2 CUDA region, mean across ranks:

| Phase | Time |
|---|---:|
| allocation | 1.393 s |
| H2D | 50.471 s |
| kernel | 9.687 s |
| synchronization | 19.259 s |
| D2H | 0.100 s |
| total | 71.825 s |

H2D remains about 70% of the measured CUDA region. Resident-v2 reduced kernel
time but did not reduce end-to-end runtime because the additional uploads for
`va`, `dyy`, and haloed `q` canceled the saved `q2` upload.

## Current Resident-v2 Boundary

The overlay path is:

```text
src/extra/local_overrides/fv_advection_kernels/fv_advection.F90
```

Current flow inside `advection_sphere_3d`:

```text
Resident begin:
  H2D: c(js:je)
  H2D: ua(:,js:je,:)
  H2D: va(:,js:je,:)
  H2D: q(:,js:je,:)
  H2D: q(:,js-2:je+2,:)
  H2D: dyy(js:je+1)
  GPU: semi_x_3d
  GPU: q1 = q + semi_x_dq
  GPU: semi_y_3d
  GPU: q2 = q + semi_y_dq
  D2H: q1(:,js:je,:)

CPU/Fortran:
  mpp_update_domains(q1)
  polar boundary corrections

Resident finish:
  H2D: c(js:je)
  H2D: cc(js:je+1)
  H2D: dy(js-1:je+1)
  H2D: dy_plus(js-1:je+1)
  H2D: dy_minus(js-1:je+1)
  H2D: uc(:,js:je,:)
  H2D: vc(:,js:je+1,:)
  H2D: q1(:,js-2:je+2,:)
  H2D: dq_dt(:,js:je,:)
  GPU: vanleer_x_3d using resident q2
  GPU: vanleer_sphere_3d using corrected q1
  D2H: dq_dt(:,js:je,:)
```

The CPU/MPI boundary is non-negotiable for this phase:

```text
mpp_update_domains(q1, advection_domain)
```

## Resident-v3 Scope

Resident-v3 should implement two conservative transfer reductions:

1. Keep static metrics resident on device.
2. Upload only corrected `q1` halo rows after the CPU halo/polar phase.

Do not change physics. Do not modify production Fortran source. Do not remove
existing stateless, persistent, resident-v1, or resident-v2 fallback paths.

## Static Metric Residency

### Candidate Static Metrics

These arrays are initialized by `fv_advection_init` and are invariant for a
fixed decomposition/resolution:

```text
c(js:je)
cc(js:je+1)
dy(js-1:je+1)
dy_plus(js-1:je+1)
dy_minus(js-1:je+1)
dyy(js:je+1)
```

`dx` is scalar and does not need device storage.

### Current Problem

These metric arrays are copied every resident begin/finish call even though
they are unchanged across timesteps. The arrays are small compared with 3D
state arrays, but the repeated calls occur thousands of times:

```text
4320 begin calls/rank + 4320 finish calls/rank for 30 days
```

Eliminating repeated metric copies is low risk and simplifies later residency.

### Proposed Device State

Extend the persistent CUDA context:

```cpp
struct ResidentMetricState {
    int nx = 0;
    int ny = 0;
    int nz = 0;
    bool valid = false;

    double* d_c = nullptr;        // ny
    double* d_cc = nullptr;       // ny + 1
    double* d_dy = nullptr;       // ny + 2
    double* d_dy_plus = nullptr;  // ny + 2
    double* d_dy_minus = nullptr; // ny + 2
    double* d_dyy = nullptr;      // ny + 1
};
```

In the current slot-based context this can be implemented without a new struct
by reserving existing slots and adding validity metadata:

```text
slot 0  d_c
slot 8  d_cc
slot 9  d_dy
slot 10 d_dy_plus
slot 11 d_dy_minus
slot 15 d_dyy
```

### Validity Rules

Metrics are valid if:

```text
mode == resident-v3
resident_metric_valid == true
resident_metric_nx == nx
resident_metric_ny == ny
resident_metric_nz == nz
```

If dimensions change:

```text
invalidate metrics
resize/reallocate as needed
upload metrics again
```

Optional debug mode:

```text
FV_KERNELS_RESIDENT_VERIFY_METRICS=1
```

could periodically copy metrics or checksum host/device values, but this should
not be enabled in performance runs.

### API Strategy

Preferred minimal-change approach:

Keep the existing Fortran and C signatures. The C/CUDA layer still receives
metric pointers every call, but only performs H2D copies on first use or after
dimension change.

No Fortran overlay signature changes are required.

Suggested runtime switch:

```text
FV_KERNELS_RESIDENT_STATIC_METRICS=0   # default/current behavior
FV_KERNELS_RESIDENT_STATIC_METRICS=1   # resident-v3 static metric cache
```

This allows rollback without rebuilding.

### Implementation Sketch

```cpp
bool static_metrics_enabled() {
    return getenv("FV_KERNELS_RESIDENT_STATIC_METRICS") == "1";
}

int ensure_resident_metrics(
    int nx,
    int ny,
    int nz,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* dyy,
    CudaPhaseCounter& phases) {

    if (!static_metrics_enabled()) {
        copy metrics every call; // current behavior
        return success;
    }

    if (metrics_valid_for(nx, ny, nz)) {
        return success;
    }

    ensure metric buffers;
    copy c, cc, dy, dy_plus, dy_minus, dyy once;
    mark metrics valid;
    return success;
}
```

Resident begin should call:

```text
ensure_resident_c_and_dyy(...)
```

Resident finish should call:

```text
ensure_resident_c_cc_dy_dy_plus_dy_minus(...)
```

The implementation can be one combined helper or two helpers. A combined helper
is cleaner once both begin and finish use the same resident metric state.

## Halo-Only q1 Post-Halo Transfer

### Current q1 Transfers

Current resident-v2 transfers:

```text
begin D2H:
  q1(:,js:je,:) only

finish H2D:
  q1(:,js-2:je+2,:) full local haloed field
```

The pre-halo D2H transfer is already interior-only. The safer first
optimization is the finish H2D transfer.

### Key Observation

Before CPU halo exchange:

```text
GPU d_q1 contains interior q1 values at device rows 2 : ny+1
CPU q1 receives the same interior values
```

After:

```text
call mpp_update_domains(q1, advection_domain)
polar boundary corrections
```

Only halo rows should have changed:

```text
q1(:,js-2:js-1,:)
q1(:,je+1:je+2,:)
```

For local device indexing where `d_q1` has `ny + 4` rows:

```text
device rows 0:1      lower halo
device rows 2:ny+1   interior, already resident
device rows ny+2:ny+3 upper halo
```

Therefore resident finish should upload only:

```text
host q1 lower halo -> device rows 0:1
host q1 upper halo -> device rows ny+2:ny+3
```

and should not reupload the interior.

### Expected Transfer Reduction

Current post-halo q1 H2D copies:

```text
full q1 = nx * (ny_local + 4) * nz
```

Halo-only q1 H2D copies:

```text
halo q1 = nx * 4 * nz
```

At current T42L25 with 16 MPI ranks:

```text
global ny = 64
local ny = 4
full q1 rows = 8
halo rows = 4
q1 upload reduction = 50%
```

At larger local domains the reduction improves:

```text
local ny = 8   -> 4 / 12 = 33% of full q1
local ny = 16  -> 4 / 20 = 20% of full q1
local ny = 32  -> 4 / 36 = 11% of full q1
```

The current T42 16-rank layout is a worst-ish case because each rank owns only
four latitude rows.

### API Strategy

Preferred minimal-change approach:

Keep the existing resident finish Fortran/C signature:

```text
q1(nx,js-2:je+2,nz)
```

Inside CUDA finish, use a runtime switch:

```text
FV_KERNELS_RESIDENT_Q1_TRANSFER=full       # default/current behavior
FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only  # resident-v3 behavior
```

When `full`, keep current behavior:

```cpp
copy_to_existing_device(d_q1, q1, q1_count, "resident q1", phases)
```

When `halo_only`, call a helper using two `cudaMemcpy2D` calls.

### q1 Memory Layout

Fortran and C/CUDA use contiguous column-major-compatible storage with `i` as
the fastest dimension. The resident CUDA indexing treats q1 as:

```text
q1(i, local_j, k)
idx = i + nx * (local_j + (ny + 4) * k)
```

The host pointer passed to C starts at `q1(:,js-2,:)`, corresponding to local
row `0`.

Therefore:

```text
lower halo host offset = 0
upper halo host offset = nx * (ny + 2)

lower halo device offset = 0
upper halo device offset = nx * (ny + 2)

row width = nx * sizeof(double)
rows per k = 2
planes = nz
host pitch = nx * (ny + 4) * sizeof(double)
device pitch = nx * (ny + 4) * sizeof(double)
```

Since each halo band has two contiguous rows per vertical level, copy each band
as a 2D block over `nz` planes:

```cpp
cudaMemcpy2D(
    d_q1 + lower_offset,
    nx * (ny + 4) * sizeof(double),
    h_q1 + lower_offset,
    nx * (ny + 4) * sizeof(double),
    nx * 2 * sizeof(double),
    nz,
    cudaMemcpyHostToDevice);

cudaMemcpy2D(
    d_q1 + upper_offset,
    nx * (ny + 4) * sizeof(double),
    h_q1 + upper_offset,
    nx * (ny + 4) * sizeof(double),
    nx * 2 * sizeof(double),
    nz,
    cudaMemcpyHostToDevice);
```

### Safety Checks

The first implementation should support a validation/debug mode:

```text
FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only
FV_KERNELS_RESIDENT_VERIFY_Q1=1
```

With verification enabled:

1. Copy halo-only into `d_q1`.
2. Optionally copy full `q1` into a temporary debug buffer.
3. Compare device `d_q1` against full-copy buffer or compare final NetCDF
   output against baseline.

For the first implementation, NetCDF validation is sufficient if the standalone
resident fixture also tests halo-only finish behavior.

### Pre-Halo q1 Download

Do not change this in resident-v3 by default.

Current begin downloads:

```text
q1(:,js:je,:)
```

This is conservative because CPU `mpp_update_domains(q1)` receives the whole
local array. It may only need boundary interior rows, but that is an assumption
about FMS internals. A later experiment can investigate:

```text
FV_KERNELS_RESIDENT_Q1_BEGIN_TRANSFER=interior_full
FV_KERNELS_RESIDENT_Q1_BEGIN_TRANSFER=boundary_only
```

Boundary-only begin would require proving that `mpp_update_domains` and polar
corrections never read uninitialized interior rows beyond the send bands.

## Resident-v3 Proposed Data Flow

```text
First resident call or dimension change:
  H2D once: c, cc, dy, dy_plus, dy_minus, dyy

Each timestep / advection call:

Resident begin:
  H2D: ua
  H2D: va
  H2D: q interior
  H2D: q haloed
  GPU: semi_x_3d
  GPU: q1 = q + semi_x_dq
  GPU: semi_y_3d
  GPU: q2 = q + semi_y_dq
  D2H: q1 interior

CPU/Fortran:
  mpp_update_domains(q1)
  polar boundary corrections

Resident finish:
  H2D: uc
  H2D: vc
  H2D: corrected q1 halo rows only
  H2D: dq_dt initial value
  GPU: vanleer_x_3d using resident q2
  GPU: vanleer_sphere_3d using corrected q1
  D2H: dq_dt
```

## Runtime Switches

Recommended switches:

```text
FV_KERNELS_CUDA_MODE=resident
FV_KERNELS_RESIDENT_STATIC_METRICS=1
FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only
FV_KERNELS_PROFILE=1
```

Fallback:

```text
FV_KERNELS_RESIDENT_STATIC_METRICS=0
FV_KERNELS_RESIDENT_Q1_TRANSFER=full
```

Invalid values should fail with a clear error rather than silently changing
behavior.

## Implementation Plan

### Step 1: Add Resident Option Parsing

Files:

```text
translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu
translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.h
```

Add helpers:

```cpp
bool resident_static_metrics_enabled();
enum class Q1TransferMode { full, halo_only, invalid };
Q1TransferMode resident_q1_transfer_mode();
```

Pass/fail:

- Valid unset/default values preserve current resident behavior.
- Invalid values produce an explicit CUDA backend error.

### Step 2: Add Metric Validity State

Extend `PersistentContext`:

```cpp
bool resident_metrics_valid = false;
int resident_metrics_nx = 0;
int resident_metrics_ny = 0;
int resident_metrics_nz = 0;
```

On context release or buffer resize:

```text
resident_metrics_valid = false
```

Pass/fail:

- Resident-v2 behavior unchanged when static metrics are disabled.
- With static metrics enabled, metrics are copied once per run/rank unless
  dimensions change.

### Step 3: Implement Static Metric Upload Helper

Add:

```cpp
int ensure_resident_metric_buffers(...);
int upload_resident_metrics_if_needed(...);
```

Implementation rule:

- Use existing phase counter `h2d` for metric copies.
- Do not count skipped copies as H2D.
- Keep allocation accounting unchanged.

Pass/fail:

- Standalone resident fixture passes with static metrics disabled.
- Standalone resident fixture passes with static metrics enabled.
- Profile shows reduced H2D calls/time for metric arrays.

### Step 4: Implement Halo-Only q1 Upload Helper

Add:

```cpp
int copy_q1_halo_to_existing_device(
    double* d_q1,
    const double* h_q1,
    int nx,
    int ny,
    int nz,
    CudaPhaseCounter& phases);
```

Use two `cudaMemcpy2D` calls:

```text
lower two rows
upper two rows
```

Pass/fail:

- `FV_KERNELS_RESIDENT_Q1_TRANSFER=full` preserves current behavior.
- `FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only` passes standalone resident
  comparison.
- 1-day smoke run completes.
- 30-day NetCDF validation matches all-Fortran and CPU C++ outputs.

### Step 5: Update Standalone CUDA Fixture

File:

```text
translated/held_suarez/cuda/fv_advection/kernels/validate_fv_advection_kernels_cuda.cpp
```

The resident fixture should run under:

```bash
FV_KERNELS_CUDA_MODE=resident \
FV_KERNELS_RESIDENT_STATIC_METRICS=1 \
FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only \
./bin/validate_fv_advection_kernels_cuda ...
```

The fixture should perturb halo rows before finish to prove that halo-only
upload changes device `q1` correctly while interior remains resident.

Pass/fail:

- `resident_q1` comparison passes.
- `resident_combined_dq_dt` comparison passes.

### Step 6: Build Native Isca Executable

Use the existing native overlay build:

```bash
USE_CUDA_FV_ADVECTION_KERNELS=1 \
NVCC=/usr/local/cuda/bin/nvcc \
./run_compile_fv_kernels.sh
```

Pass/fail:

- `held_suarez_fv_kernels_cuda.x` builds.
- No production Fortran source is modified.

### Step 7: 1-Day Smoke Test

Use a new experiment/log name if possible:

```bash
FV_KERNELS_CUDA_MODE=resident \
FV_KERNELS_RESIDENT_STATIC_METRICS=1 \
FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only \
FV_KERNELS_PROFILE=1 \
python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name held_suarez_fv_kernels_cuda.x \
  --exp-name held_suarez_fv_kernels_cuda_resident_v3_1day \
  --days 1 \
  --production-diag \
  --num-cores 16 \
  --overwrite
```

Pass/fail:

- Model starts.
- Run completes.
- `PROFILE_FV_ADVECTION_CUDA backend=cuda_resident` markers appear.

### Step 8: 30-Day Validation and Performance Run

Run:

```bash
FV_KERNELS_CUDA_MODE=resident \
FV_KERNELS_RESIDENT_STATIC_METRICS=1 \
FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only \
FV_KERNELS_PROFILE=1 \
python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name held_suarez_fv_kernels_cuda.x \
  --exp-name held_suarez_fv_kernels_cuda_resident_v3_30day \
  --days 30 \
  --production-diag \
  --num-cores 16 \
  --overwrite
```

Validate:

```bash
python3 tests/validate_T85L25_forcing_outputs.py \
  --fortran-exp held_suarez_default \
  --cpu-exp held_suarez_fv_kernels_30day \
  --cuda-exp held_suarez_fv_kernels_cuda_resident_v3_30day \
  --run 1 \
  --filename atmos_monthly.nc \
  --data-root /explore/nobackup/people/jli30/SystemTesting/Isca/isca_data \
  --markdown-out tests/reports/fv_advection_kernels_resident_v3_30day_model_validation.md \
  --json-out tests/reports/fv_advection_kernels_resident_v3_30day_model_validation.json
```

Pass/fail:

- NetCDF dimensions match.
- `temp`, `ucomp`, `vcomp`, and `ps` match existing baselines.
- No NaNs/FATAL/Traceback in log.

## Expected Performance Impact

Static metrics alone should provide a small improvement because metrics are
small. Its main value is establishing the resident-state mechanism.

Halo-only q1 post-halo upload should reduce one large upload:

```text
q1 full upload: nx * (ny_local + 4) * nz
q1 halo upload: nx * 4 * nz
```

At T42L25 with 16 ranks:

```text
local ny = 4
q1 upload reduction = 50%
```

However, the full H2D phase also includes `ua`, `va`, `q`, `q_halo`, `uc`, `vc`,
and `dq_dt`. Therefore total H2D reduction is expected to be modest:

```text
expected H2D reduction: 5-15%
expected MPP runtime reduction: 2-8%
```

This is unlikely to close the 4.25x gap to CPU C++ by itself. It is still worth
doing because it directly tests whether shrinking CPU/MPI boundary transfers
measurably improves runtime.

## Risks

### q1 Interior Assumption

Halo-only finish assumes the device interior `q1` remains correct after begin
and that CPU halo/polar correction modifies only halo rows. This matches the
intended flow but must be validated with the standalone fixture and 30-day
NetCDF comparison.

### Boundary Rank Behavior

South/north boundary ranks apply polar corrections:

```fortran
q1(i, 0,:)    = q1(ii(i),1,:)
q1(i,-1,:)    = q1(ii(i),2,:)
q1(i,ny+1,:)  = q1(ii(i),ny,:)
q1(i,ny+2,:)  = q1(ii(i),ny-1,:)
```

The halo-only upload must include these corrected rows.

### Local ny Dependence

At 16 MPI ranks and T42, local `ny` is only 4. The q1 halo is half of the local
haloed q1 field. Benefits should improve at larger local ny or different MPI
decompositions.

### Metrics Validity

Metrics are expected to be static after initialization. If future experiments
change resolution/decomposition inside a process, the context must invalidate
and re-upload metrics.

## Rollback Plan

No source rollback should be needed if runtime switches are implemented.

Use:

```text
FV_KERNELS_RESIDENT_STATIC_METRICS=0
FV_KERNELS_RESIDENT_Q1_TRANSFER=full
```

or use existing modes:

```text
FV_KERNELS_CUDA_MODE=stateless
FV_KERNELS_CUDA_MODE=persistent
FV_KERNELS_CUDA_MODE=resident
```

The production Fortran source remains untouched.

## Decision Criteria

Resident-v3 is successful if:

1. standalone CUDA fixture passes;
2. 1-day smoke test completes;
3. 30-day NetCDF validation passes;
4. 30-day MPP runtime improves beyond run-to-run noise relative to resident-v2;
5. H2D time decreases measurably.

Resident-v3 is not expected to beat CPU C++. A good outcome is a clear measured
H2D reduction and a small MPP improvement. If resident-v3 is flat, the next
step should skip further boundary micro-optimizations and move to a broader
`a_grid_horiz_advection_3d` or `update_tracers` residency design.
