# GPU Speed Record Plan

## Goal

Make the Held-Suarez prototype run both CPU and GPU variants from the same
validation ladder, then keep widening the GPU-resident region until the GPU
variant is faster end to end at meaningful resolution.

## Current Fast Path

The current active GPU path is the finite-volume advection kernel bundle:

- `semi_x_3d`
- `semi_y_3d`
- `vanleer_x_3d`
- `vanleer_sphere_3d`

The CUDA wrapper now avoids repeated device discovery, reuses device buffers
across calls, and caches static grid metrics on the device when the same host
storage is reused.

The native CUDA overlay uses a two-stage fused `advection_sphere_3d` path:

1. CUDA predictor stage computes `q1` and `q2`.
2. Fortran performs the required `mpp_update_domains(q1, advection_domain)`.
3. CUDA corrector stage applies `vanleer_x_3d` and `vanleer_sphere_3d`.

The predictor keeps `q2` resident on the device for the corrector stage and
copies back only the interior of `q1` needed for the Fortran halo exchange.

Run the current CPU/GPU comparison workflow with:

```bash
FV_KERNELS_OVERWRITE=1 scripts/compare_fv_kernels_cpu_gpu.sh
```

## Performance Rule

Do not judge GPU success from standalone kernels alone. A GPU change only
counts as a speed win if it improves one of these measured targets:

- 30-day FV kernel-region time
- 30-day full model MPP runtime
- larger T85L25 or T170 full model MPP runtime

## Next Translation Targets

Priority order:

1. Completed first fusion of the local `advection_sphere_3d` compute body while
   keeping Fortran halo updates and polar boundary handling outside the CUDA
   region.
2. Keep tracer/advection arrays resident across the sequence of local FV
   kernels and copy back only when Fortran needs ownership again.
3. Move `horizontal_advection_temperature` through the same fused FV path.
4. Evaluate `compute_corrections` as the next non-FV dynamics region.
5. Treat transform-heavy regions separately with vendor-library or batched FFT
   strategy rather than hand-translating small loops.

## Comparison Contract

Every translated region must keep these runnable variants:

- all-Fortran baseline
- CPU C++ hybrid
- CUDA hybrid

Every translated region must pass:

- standalone Fortran fixture comparison
- CPU C++ comparison
- CUDA comparison
- Fortran C-wrapper comparison
- 1-day native smoke
- 30-day native validation

## Immediate Bottleneck Questions

After the next CUDA profile, inspect:

- Is `cuda_h2d` still larger than useful kernel time?
- Is `cuda_d2h` still required after every local kernel?
- Does `cuda_alloc_resize` disappear after warmup?
- Does `cuda_sync` dominate because every kernel is synchronously copied back?

If copies or synchronization dominate, widen the GPU boundary before translating
another isolated leaf routine.
