Held-Suarez forcing — standalone C++ module

Purpose: Minimal standalone C++ wrapper for the `hs_forcing` kernels translated from Fortran. Intended for validation against Fortran baseline data and as a later integration point for iso_c_binding.

Quick build & test

- Build (from this directory):

```bash
make all
```

- Run tests (uses Fortran baseline data):

```bash
./bin/driver_forcing_module ../../../../../tests/fortran_baseline/
```

Repository layout

- `include/` — public headers (`held_suarez_forcing.hpp`, `held_suarez_config.hpp`, `held_suarez_c_api.h`)
- `src/` — C API implementation (`held_suarez_c_api.cpp`) and library sources
- `tests/` — `driver_forcing_module.cpp` test harness that compares outputs with Fortran baseline

Verification

- Test outputs are compared and summary JSON reports are written to `tests/reports/` by the test harness (if enabled). See existing reports in `tests/reports/`.

Notes

- Preserves Fortran column-major ordering for arrays.
- Does not implement file I/O, MPI or diagnostics: tests rely on baseline binary blobs.
