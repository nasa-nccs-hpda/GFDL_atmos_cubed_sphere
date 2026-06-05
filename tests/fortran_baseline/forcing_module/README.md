Fortran baseline harness for Held-Suarez forcing (forcing_module)

This directory contains a small Fortran test driver that generates synthetic
inputs and writes Fortran baseline outputs for the combined Held-Suarez
forcing (rayleigh + newtonian). The harness uses the existing standalone
kernels in `tests/fortran_baseline/*_standalone.F90`.

Usage:

  cd tests/fortran_baseline/forcing_module
  make
  ./test_forcing_module

Outputs are written to `inputs/` and `outputs/` as binary stream files.
