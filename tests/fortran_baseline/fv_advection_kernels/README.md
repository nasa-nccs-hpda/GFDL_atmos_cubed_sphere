# FV Advection Kernel Baseline Fixture

This fixture captures deterministic Fortran reference data for the bundled local finite-volume advection kernels:

- `semi_x_3d`
- `slope_x`
- `slope_sphere`
- `vanleer_x_3d`
- `vanleer_sphere_3d`
- helper `find_cell_x`
- helper `integer_flux_x`

It uses a test-only copy of the routine bodies and minimal module state. The production source tree is not modified.

## Build And Run

Inside the Isca container:

```sh
cd tests/fortran_baseline/fv_advection_kernels
make FC=mpifort
./test_fv_advection_kernels
```

## Fixture Dimensions

- `nx = 8`
- `ny = 8`
- `js = 2`
- `je = 6`
- `nz = 3`
- `monotone = true`

The active local latitude range is `js:je`, with one extra row for `vc` and two halo rows for sphere-y inputs.

## Inputs

Files in `inputs/` are raw little-endian binary files written by Fortran stream I/O:

- `params.txt`: human-readable dimensions and scalar settings
- `input_c.bin`: `c(js:je)`
- `input_cc.bin`: `cc(js:je+1)`
- `input_dy.bin`: `dy(js-1:je+1)`
- `input_dy_plus.bin`: `dy_plus(js-1:je+1)`
- `input_dy_minus.bin`: `dy_minus(js-1:je+1)`
- `input_ua.bin`: `ua(nx,js:je,nz)`
- `input_uc.bin`: `uc(nx,js:je,nz)`
- `input_q_x.bin`: `q_x(nx,js:je,nz)`
- `input_q_sphere.bin`: `q_sphere(nx,js-2:je+2,nz)`
- `input_vc.bin`: `vc(nx,js:je+1,nz)`

## Outputs

Files in `outputs/`:

- `output_find_cell_x_ii.bin`: integer cell indices for the `semi_x_3d` Courant field
- `output_semi_x_dq.bin`
- `output_slope_x.bin`
- `output_integer_flux_x.bin`
- `output_vanleer_x_dq_dt.bin`
- `output_slope_sphere.bin`
- `output_vanleer_sphere_dq_dt.bin`

Array order follows Fortran column-major layout. The C++ fixture reads and writes the same memory order.
