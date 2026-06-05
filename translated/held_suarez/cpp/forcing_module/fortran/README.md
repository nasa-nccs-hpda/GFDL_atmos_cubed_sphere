Fortran wrapper notes
=====================

- **Wrapper input shape**: The Fortran wrapper `hs_forcing_driver_c_wrapper` accepts 1D `lon` and `lat` inputs.
- **Internal expansion**: The wrapper expands these 1D arrays internally into 2D `lon2d` / `lat2d` arrays before calling the C API.
- **Memory layout**: The expansion produces column-major (Fortran-order) 2D arrays to match the C API's expectations for `[nlon, nlat]` indexing.
- **Correctness**: This expansion is acceptable for the current correctness and integration tests — it ensures the C driver receives data in the layout it expects.
- **Future optimization**: A future improvement could expose a 2D `lon`/`lat` wrapper or change the C API to accept 1D inputs directly to avoid repeated expansion for performance-sensitive code. No implementation changes are made here.

Do not modify production Fortran sources in `src/` as part of this change. This note documents the current test wrapper behavior only.

Runner: `run_on_baseline.F90`
--------------------------------

- **Purpose**: `run_on_baseline.F90` is an integration/regression test that reads the Fortran baseline input blobs from `tests/fortran_baseline/forcing_module/inputs/`, calls the C++ Held‑Suarez forcing module through the C API, and writes resulting binary tendencies to `candidate_outputs/` for comparison against the baseline outputs.
- **Behavior**: It reads `params.bin` (grid dims + optional config doubles), loads the baseline input blobs (`input_*.bin`), calls the C API (`hs_forcing_driver_c`) with correctly-shaped 2D arrays, and writes `output_udt.bin`, `output_vdt.bin`, `output_tdt.bin`, and `output_teq.bin` into `candidate_outputs/`.
- **Use**: Build and run with `make run_baseline` from this directory; compare with the baseline using the repository comparator.
- **Status**: Kept as a permanent integration/regression test to validate Fortran→C++ interoperability; not temporary.
