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
The native CUDA overlay also uses a two-stage fused `advection_sphere_3d` path:
predictor kernels run before the required Fortran halo update, and the x plus
spherical Van Leer corrector kernels run in one CUDA entry point after it. The
`q2` predictor field stays on the device across the halo update.

## CPU/GPU Model Comparison

From the repository root, build both native overlays and run the smoke/profile
comparison workflow:

```sh
FV_KERNELS_OVERWRITE=1 scripts/compare_fv_kernels_cpu_gpu.sh
```

Default runtime paths are:

- `CONTAINER=/lscratch/jacaraba/isca-sandbox`
- `GFDL_WORK=/explore/nobackup/people/jacaraba/projects/AgenticAI/isca_work`
- `GFDL_DATA=/explore/nobackup/people/jacaraba/projects/AgenticAI/isca_data`
- `APPTAINER_BIND_ROOT=/explore/nobackup/people/jacaraba`

Override any of these as environment variables if your container image or
project directory has a different name.

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
