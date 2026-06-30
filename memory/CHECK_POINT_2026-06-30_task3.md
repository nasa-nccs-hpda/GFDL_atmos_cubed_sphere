# Checkpoint - 2026-06-30 (Task 3: divergence fold)

## Start here
Read in order:
- `memory/FINAL_PROJECT_CHECKPOINT_2026-06-19.md`
- `memory/CHECK_POINT_2026-06-25.md`
- `memory/CHECK_POINT_2026-06-30.md` (task 2 + d_q2 bug)
- then this file (task 3 delta)
- plan: `~/.claude/plans/tranquil-herding-orbit.md`

## Repo / branch
- Branch `perf/resident-semi-y-integration`.
- This session ran on the **arm64 Mac clone** (no nvcc) — code edited here, git-synced.
  Build + all validation gates run on **gpu011** (x86_64+V100, apptainer).
- Cluster repo root: `/explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere`.

## Task sequence
1. semi_y resident — DONE (06-25)
2. q1 halo-only transfers + d_q2 bug fix — DONE (06-30)
3. **broader update_tracers residency — scope B implemented this session, UNTESTED**
4. larger-resolution scaling (next)
5. transforms/vendor-library study (later)

## Task 3 = scope B (fold divergence into resident begin)
Goal: per grid-tracer call, stop sending uc/vc/dq_dt H2D and stop doing the host
divergence loop. Now `resident_advection_begin` computes uc, vc, div and
`dq = q*div` on the device and keeps them resident; `resident_advection_finish`
uploads **only the q1 halo rows**. Expected: lower H2D, runtime <= ~176.5 s.

## Files changed (uncommitted, not yet compiled)
- `translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu`
  - new kernels `compute_uc_kernel`, `compute_vc_kernel`, `div_qdiv_kernel`
  - `PersistentContext.buffers` 16 -> `kNumBuffers=20`; documented non-aliasing
    slot map (0 c,1 ua,2 q_int,3 q1,4 q2,5 va_halo,6 dyy,7 dq,8 cc,9 dy,
    10 dy_plus,11 dy_minus,12 uc,13 vc,14 q_halo,15 va_int,16 semi scratch)
  - `resident_advection_begin`: + `fold_div`, uploads haloed va + all 6 metrics,
    strips q & va interiors (D2D), produces uc/vc/q2/q1 and dq=q*div
  - `resident_advection_finish`: drops metric/uc/vc/dq uploads; q1 halo H2D only
  - extern-C `..._begin/finish_cuda_c` signatures updated
- `translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.h`
  - matching internal + extern-C decls
- `translated/held_suarez/cpp/fv_advection/kernels/fortran/fv_advection_kernels_c_interface.F90`
  - bind(C) interfaces + `..._begin/finish_wrapper`
- `src/extra/local_overrides/fv_advection_kernels/fv_advection.F90`
  - `advection_sphere_3d(... , vx, fold_div)`; host skips uc/vc/div when resident;
    semi_y/q2 moved into the non-resident branch; passes `.not.flux_local`
- `translated/held_suarez/cuda/fv_advection/kernels/validate_fv_advection_kernels_cuda.cpp`
  - reads new `input_va_sphere.bin`; recomputes uc/vc/div reference and seeds
    expected dq = q*div (keep reference independent — the d_q2 lesson)
- `tests/fortran_baseline/fv_advection_kernels/test_fv_advection_kernels.F90`
  - generates haloed synthetic `va_sphere`, writes `input_va_sphere.bin`;
    `input_va.bin` now = va_sphere interior

## Precondition (documented in code)
Device overwrites `dq` with `q*div` — valid only because the grid-tracer caller
enters with `dt_tr = 0` (update_tracers, spectral_dynamics.F90:1519). flux mode
(`fold_div=false`) zeroes dq instead; that combo never occurs with resident on.

## Validation gates (gpu011, in order) — NONE run yet
1. `make USE_CUDA_FV_ADVECTION_KERNELS=1 cuda_resident_check`
   (regenerate fixtures so `input_va_sphere.bin` exists; check
   `resident_combined_dq_dt` passes)
2. `USE_CUDA_FV_ADVECTION_KERNELS=1 ./run_compile_fv_kernels.sh`
3. 1-day smoke; 30-day run
4. 30-day NetCDF validation (host: `module load anaconda/24.9.0 nco/5.0.3`):
   exact vs CPU C++, rounding-level vs Fortran
5. profile: confirm resident finish H2D ~ q1 halo only; record 30-day runtime
6. repeat 30-day for +/-0.1% stability
Commit only after gates pass.

## First-compile watch item
`uc`/`vc` locals in `a_grid_horiz_advection_3d` are passed to
`advection_sphere_3d` uninitialized on the resident path (ignored there). If the
build uses `-Werror=maybe-uninitialized`, suppress or pre-zero them.
