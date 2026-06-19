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
