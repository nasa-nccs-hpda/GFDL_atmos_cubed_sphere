# fv_advection Kernel Bundle Profiling Plan

## Status

The 1-day smoke tests completed for:

- `held_suarez_fv_kernels.x`
- `held_suarez_fv_kernels_cuda.x`

The CPU and CUDA kernel-bundle smoke outputs were bitwise identical in `atmos_monthly.nc`.
The comparison against the all-Fortran 1-day monthly file is not meaningful because the
1-day monthly diagnostics contain NetCDF fill values.

## Profiling switch

Kernel-bundle profiling is controlled at runtime:

```bash
export FV_KERNELS_PROFILE=1
```

Default behavior is unchanged when `FV_KERNELS_PROFILE` is unset or set to `0`.

## Timing markers

Each MPI rank prints markers at process exit:

```text
PROFILE_FV_ADVECTION_KERNEL backend=<cpu|cuda> rank=<rank> name=<kernel> calls=<n> time=<seconds> avg=<seconds>
```

Current kernel names:

- `semi_x_3d`
- `slope_x`
- `integer_flux_x`
- `vanleer_x_3d`
- `slope_sphere`
- `vanleer_sphere_3d`

CPU timings include the C ABI wrapper and C++ implementation time. CUDA timings include
the C ABI wrapper, host/device allocation, copies, kernel launch, synchronization, and
copy-back time.

## Required rebuild

Rebuild the executables after this profiling change:

```bash
USE_CUDA_FV_ADVECTION_KERNELS=0 ./run_compile_fv_kernels.sh
USE_CUDA_FV_ADVECTION_KERNELS=1 ./run_compile_fv_kernels.sh
```

## 30-day profile runs

CPU C++ kernel bundle:

```bash
FV_KERNELS_OVERWRITE=1 scripts/run_fv_kernels_cpu_30day.sh
```

CUDA kernel bundle:

```bash
FV_KERNELS_OVERWRITE=1 scripts/run_fv_kernels_cuda_30day.sh
```

Expected logs:

- `logs/fv_kernels_cpu_30day.log`
- `logs/fv_kernels_cuda_30day.log`

After the runs complete, extract timing markers with:

```bash
grep 'PROFILE_FV_ADVECTION_KERNEL' logs/fv_kernels_cpu_30day.log
grep 'PROFILE_FV_ADVECTION_KERNEL' logs/fv_kernels_cuda_30day.log
```

## Next validation

Use 30-day monthly outputs for numerical comparison, not the 1-day monthly smoke files.
