# semi_y_3d Fortran Baseline Harness

This directory contains a standalone Fortran baseline harness for:

```text
src/atmos_spectral/model/fv_advection.F90
fv_advection_mod::semi_y_3d
```

`semi_y_3d` is private inside `fv_advection_mod`, so an external test program
cannot call it directly through `use fv_advection_mod`.  This harness therefore
uses a test-only module containing the original `semi_y_3d` local body plus the
minimal module state it needs (`nx`, `js`, `je`, `nz`, and `dyy`).  Production
source is not modified.

## Build And Run

```bash
cd tests/fortran_baseline/semi_y_3d
make
./test_semi_y_3d
```

or:

```bash
make run
```

If `gfortran` is not available but the Isca container provides `mpifort`, use:

```bash
make FC=mpifort
./test_semi_y_3d
```

## Synthetic Grid

The first fixture uses:

```text
nx = 8
js = 2
je = 6
nz = 3
qx y bounds = js-2:je+2 = 0:8
dyy bounds = js:je+1 = 2:7
dt = 37.5
```

The velocity field includes positive, negative, and exact-zero values so both
branches of the Fortran `where (va >= 0.0)` expression are exercised.

## Binary Files

Files are Fortran unformatted stream binaries written in column-major order.
All floating-point arrays are `real(8)`.

Inputs generated after a successful run:

```text
inputs/params.bin
inputs/input_dyy.bin
inputs/input_va.bin
inputs/input_qx.bin
```

Outputs generated after a successful run:

```text
outputs/output_dq.bin
```

`params.bin` contains six default Fortran integers followed by one `real(8)`:

```text
nx, js, je, nz, qx_jlo, qx_jhi
dt
```

Array layout:

```text
input_dyy.bin: dyy(js:je+1)
input_va.bin:  va(nx,js:je,nz)
input_qx.bin:  qx(nx,js-2:je+2,nz)
output_dq.bin: dq(nx,js:je,nz)
```

These files are intended to become the reference fixture for the future C++
`semi_y_3d` translation and C API validation.
