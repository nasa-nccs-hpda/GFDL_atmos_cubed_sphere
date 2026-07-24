# FV Advection Kernel Bundle

CPU C++ translation for the next finite-volume advection kernel bundle:

- `semi_x_3d`
- `slope_x`
- `slope_sphere`
- `vanleer_x_3d`
- `vanleer_sphere_3d`
- `find_cell_x`
- `integer_flux_x`

This package is standalone for now. It does not modify the native Isca overlay path until the fixture comparison is validated.

## Build And Validate

First generate the Fortran baseline:

```sh
cd tests/fortran_baseline/fv_advection_kernels
make FC=mpifort clean run
```

Then run the C++ comparison:

```sh
cd translated/held_suarez/cpp/fv_advection/kernels
make check
```

The default report is written to:

`tests/reports/fv_advection_kernels_cpp_compare_report.json`

Note: the fixture includes the production-form `vanleer_sphere_3d` metric behavior from `src/atmos_spectral/model/fv_advection.F90`, including `dy(js-1:je+1)` as an input array.

## CUDA Fixture

After CPU validation passes, run the CUDA fixture inside a CUDA-capable container:

```sh
cd translated/held_suarez/cpp/fv_advection/kernels
make USE_CUDA_FV_ADVECTION_KERNELS=1 cuda_check
```

The CUDA report is written to:

`tests/reports/fv_advection_kernels_cuda_compare_report.json`

The CUDA fixture reuses device buffers across repeated calls. With
`FV_KERNELS_PROFILE=1`, it also reports aggregate CUDA phase timings for
allocation growth, host-to-device copies, synchronization, and device-to-host
copies. Grid metric arrays such as `c`, `cc`, `dy`, `dy_plus`, and `dy_minus`
are cached on the device when the same host storage is reused across calls.
The native CUDA overlay also uses a two-stage fused `a_grid_horiz_advection_3d`
path. Stage 1 computes local setup, optional divergence tendency, and predictor
fields before the required Fortran halo update. Stage 2 runs the x plus
spherical Van Leer corrector kernels after it. `uc`, `vc`, `q2`, and `dq_dt`
stay on the device across the halo update.

## CPU/GPU Model Comparison

From the repository root, build both native overlays and run the smoke/profile
comparison workflow:

```sh
FV_KERNELS_OVERWRITE=1 scripts/compare_fv_kernels_cpu_gpu.sh
```

By default this compares CPU with 16 MPI ranks against CUDA with 1 MPI rank:

```sh
FV_KERNELS_CPU_NUM_CORES=16
FV_KERNELS_CUDA_NUM_CORES=1
```

To search for the best CUDA rank count on a node:

```sh
FV_KERNELS_CUDA_RANK_SWEEP="1 2 4 8 16" scripts/sweep_fv_cuda_ranks.sh
```

Default runtime paths are:

- `CONTAINER=/lscratch/jacaraba/isca-sandbox`
- `GFDL_WORK=/explore/nobackup/people/jacaraba/projects/AgenticAI/isca_work`
- `GFDL_DATA=/explore/nobackup/people/jacaraba/projects/AgenticAI/isca_data`
- `APPTAINER_BIND_ROOT=/explore/nobackup/people/jacaraba`

Override any of these as environment variables if your container image or
project directory has a different name.

The FV native build is clean-rebuilt by default:

```sh
FV_KERNELS_FORCE_CLEAN_NATIVE=1
```

After a CUDA run, confirm the widened path was used:

```sh
scripts/verify_fv_cuda_path.sh
```

Summarize CPU and CUDA FV timing markers:

```sh
scripts/summarize_fv_kernel_profile.py \
  logs/fv_kernels_cpu_30day.log \
  logs/fv_kernels_cuda_30day.log
```

This builds:

- `held_suarez_fv_kernels.x`
- `held_suarez_fv_kernels_cuda.x`

and writes the main profile logs to:

- `logs/fv_kernels_cpu_30day.log`
- `logs/fv_kernels_cuda_30day.log`

## Fortran C-Wrapper Fixture

CPU wrapper validation:

```sh
cd translated/held_suarez/cpp/fv_advection/kernels/fortran
make FC=mpifort check
```

CUDA wrapper validation:

```sh
cd translated/held_suarez/cpp/fv_advection/kernels/fortran
make FC=mpifort BACKEND=cuda check
```

Reports:

- `tests/reports/fv_advection_kernels_fortran_c_compare_report.json`
- `tests/reports/fv_advection_kernels_fortran_cuda_c_compare_report.json`
