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
- `advection_sphere_predictor`
- `advection_sphere_corrector`

The CUDA backend also reports aggregate phase counters:

- `cuda_alloc_resize`
- `cuda_h2d`
- `cuda_sync`
- `cuda_d2h`

CPU timings include the C ABI wrapper and C++ implementation time. CUDA timings include
the C ABI wrapper, persistent-buffer allocation growth, copies, kernel launch,
synchronization, and copy-back time. Allocation is only expected when a buffer
first appears or grows for a larger domain. Static grid metrics are copied once
per stable host pointer and then reused from device memory.

In the native CUDA overlay, `advection_sphere_3d` uses a two-stage fused CUDA
path. The predictor stage computes `q1` and `q2`, then Fortran performs the
required `mpp_update_domains(q1, advection_domain)` halo exchange. The
corrector stage applies the x and spherical Van Leer updates in one CUDA entry
point. `q2` stays resident on the device between those stages, and only the
interior of `q1` is copied back before the Fortran halo update.

## Required rebuild

Rebuild the executables after this profiling change:

```bash
USE_CUDA_FV_ADVECTION_KERNELS=0 ./run_compile_fv_kernels.sh
USE_CUDA_FV_ADVECTION_KERNELS=1 ./run_compile_fv_kernels.sh
```

Or run the full CPU/GPU comparison workflow:

```bash
FV_KERNELS_OVERWRITE=1 scripts/compare_fv_kernels_cpu_gpu.sh
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
