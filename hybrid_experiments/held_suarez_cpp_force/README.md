Hybrid Held-Suarez experiment overlay
=====================================

Contents:

- `build_hybrid.py`: helper to build original and hybrid executables and link `libhs_forcing.a`.

Usage:

Set environment variables and run the helper from the repository root:

```bash
export GFDL_BASE=$PWD
export GFDL_WORK=/path/to/workdir
export GFDL_DATA=/path/to/data
python3 hybrid_experiments/held_suarez_cpp_force/build_hybrid.py
```

Notes:
- The overlay Fortran source is at `src/extra/local_overrides/hs_forcing/hs_forcing.F90`.
- The script copies `libhs_forcing.a` from `translated/held_suarez/cpp/forcing_module/libhs_forcing.a` into the builddir/lib.
- A custom `mkmf.template.hybrid` is used to add link flags for `-lhs_forcing`.
