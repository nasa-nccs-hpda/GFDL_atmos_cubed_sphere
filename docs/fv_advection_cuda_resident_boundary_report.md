# FV Advection CUDA Resident Boundary Report

## Status

The two-phase CUDA boundary is implemented in overlay/hybrid files only.
Production Fortran remains unchanged.

The prerequisite persistent 30-day NetCDF validations pass exactly against:

- all-Fortran;
- CPU C++ FV kernels;
- stateless CUDA FV kernels.

The repeated persistent run reports 126.964 s MPP versus 127.381 s for the
first run, confirming stable timing within 0.33%.

## Runtime Selection

```bash
export FV_KERNELS_CUDA_MODE=resident
```

Existing `stateless` and `persistent` modes remain available and unchanged as
fallbacks.

## Boundary

The pre-halo CUDA stage:

1. uploads `c`, `ua`, and `q`;
2. runs the existing `semi_x_3d` CUDA kernel;
3. forms `q1 = q + semi_x_dq` on device using the original operation order;
4. exports the `q1` interior for the host halo operation.

Fortran then retains responsibility for:

- `semi_y_3d` and `q2` formation;
- `mpp_update_domains(q1, advection_domain)`;
- polar halo correction.

The post-halo CUDA stage:

1. imports corrected `q1`, host `q2`, velocities, metrics, and the initial
   tendency;
2. runs `vanleer_x_3d` and `vanleer_sphere_3d` sequentially against one device
   tendency buffer;
3. downloads `dq_dt` once.

The device context is per process, shape-aware, and reused across calls. A
stage-state check rejects unmatched begin/finish calls or dimension changes
within an active update.

## Files Changed

```text
translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.h
translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu
translated/held_suarez/cuda/fv_advection/kernels/validate_fv_advection_kernels_cuda.cpp
translated/held_suarez/cpp/fv_advection/kernels/fortran/fv_advection_kernels_c_interface.F90
translated/held_suarez/cpp/fv_advection/kernels/Makefile
src/extra/local_overrides/fv_advection_kernels/fv_advection.F90
```

## Standalone Validation

Run inside the CUDA-enabled Isca container:

```bash
cd "$GFDL_BASE/translated/held_suarez/cpp/fv_advection/kernels"
make USE_CUDA_FV_ADVECTION_KERNELS=1 cuda_resident_check \
  2>&1 | tee "$GFDL_BASE/logs/fv_advection_cuda_resident_validation.log"
```

Expected additional comparisons:

```text
resident_q1: pass=true
resident_combined_dq_dt: pass=true
overall status: PASS
```

Expected report:

```text
tests/reports/fv_advection_kernels_cuda_resident_compare_report.json
```

## Verification Status

- Persistent 30-day model validation: PASS, exact.
- Persistent repeat timing: PASS, stable within 0.33%.
- C++ validator syntax check: PASS.
- Fortran preprocessing and overlay dispatch check: PASS.
- NVCC build and resident standalone execution: PASS, exact at `1e-12`.
- Native Isca resident-mode smoke test: PASS; resident markers present.

The native one-day smoke subsequently completed with the resident marker on
all ranks. Its MPP runtime was 6.026 s versus 6.219 s for the persistent run.
The generated one-day monthly diagnostics contain fill values because the
production cadence is 30 days, so that NetCDF comparison is inconclusive and
must not be recorded as a numerical PASS. The duration-matched 30-day run is
the next correctness and performance gate.

The 30-day gate subsequently passed with exact NetCDF agreement. Resident MPP
runtime was 108.505 s, a 1.172x speedup over the two-run persistent mean of
127.173 s. Full analysis is in
`docs/fv_advection_cuda_resident_performance_results.md`.

Run and validate it with:

```bash
./scripts/run_fv_kernels_resident_30day.sh
./scripts/validate_fv_kernels_resident_30day.sh
```

## Native Integration Commands

Rebuild the CUDA overlay executable inside the container:

```bash
apptainer exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  /lscratch/jli30/isca-sandbox \
  bash -lc '
set -e
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export GFDL_ENV=hybrid
cd "$GFDL_BASE"
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py fv_kernels_cuda \
  2>&1 | tee logs/fv_kernels_cuda_resident_compile.log
'
```

Then run and validate the one-day resident experiment:

```bash
./scripts/run_fv_kernels_resident_1day.sh
./scripts/validate_fv_kernels_resident_1day.sh
```

Stop at the first NVCC or standalone validation failure. After standalone PASS,
rebuild `held_suarez_fv_kernels_cuda.x`, run a one-day resident smoke test with
profiling, and compare its NetCDF output before attempting 30 days.
