# Native Overlay Build

Generated: 2026-06-05

## Goal

Produce two Held-Suarez executables through the native Isca
`CodeBase.compile()` workflow:

- `held_suarez_fortran.x`
- `held_suarez_hybrid.x`

The implementation does not manually invoke `mkmf` and does not alter the
original `src/atmos_param/hs_forcing/hs_forcing.F90` source.

## Implementation

Created:

```text
hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py
```

The script defines two `DryCodeBase` subclasses:

```python
class HeldSuarezFortranCodeBase(DryCodeBase):
    executable_name = "held_suarez_fortran.x"

class HeldSuarezHybridCodeBase(DryCodeBase):
    executable_name = "held_suarez_hybrid.x"
```

Both variants delegate to `CodeBase.compile()`.

## Source Replacement Mechanism

The baseline build uses the default dry model `path_names`.

The hybrid build reads the same dry `path_names` list and replaces exactly this
entry:

```text
atmos_param/hs_forcing/hs_forcing.F90
```

with:

```text
extra/local_overrides/hs_forcing/hs_forcing.F90
```

The hybrid path list also adds the required Fortran/C interface module:

```text
../translated/held_suarez/cpp/forcing_module/fortran/hs_forcing_c_interface.F90
```

That extra source is required because the overlay uses:

```fortran
use hs_forcing_c_interface, only: hs_forcing_driver_c_wrapper
```

No other original source entry is replaced.

## Compile Flags

The hybrid build appends:

```text
-DUSE_CPP_HS_FORCE
```

through `cb.compile_flags`, which the normal Isca `compile.sh` template inserts
into the `cppDefs` passed to `mkmf`.

## Template Changes

Updated:

```text
src/extra/python/isca/templates/mkmf.template.hybrid
```

The hybrid template now provides the C++ forcing library link flags through the
normal `mkmf.template.*` mechanism:

```make
LDFLAGS = -lnetcdff -lnetcdf -lmpi -L$(PWD)/lib -lhs_forcing -lstdc++ -lm
```

Created:

```text
src/extra/env/hybrid
```

It sources the production-like `ubuntu_conda` environment, then selects the
hybrid template:

```bash
source ${GFDL_BASE}/src/extra/env/ubuntu_conda
export GFDL_MKMF_TEMPLATE=hybrid
```

This matters because the generated Isca `compile.sh` sources the env file before
choosing:

```bash
template=${template_dir}/mkmf.template.${GFDL_MKMF_TEMPLATE}
```

## Hybrid Library Placement

Before delegating to `CodeBase.compile()`, the hybrid subclass copies:

```text
<srcdir>/../translated/held_suarez/cpp/forcing_module/libhs_forcing.a
```

to:

```text
<hybrid-builddir>/lib/libhs_forcing.a
```

This matches the template link flag:

```make
-L$(PWD)/lib -lhs_forcing
```

because the normal generated `compile.sh` runs from the build directory.

## Executable Locations

With the production container variables used by `run_held_suarez.sh`, and with
`GFDL_BASE` pointing at the source tree to compile, expected outputs are:

```text
$GFDL_WORK/codebase/<source-token>/build/held_suarez_fortran/held_suarez_fortran.x
$GFDL_WORK/codebase/<source-token>/build/held_suarez_hybrid/held_suarez_hybrid.x
```

The exact `<source-token>` is produced by Isca's `url_to_folder(GFDL_BASE)`.

## Native Build Commands

Inside the same Isca Apptainer container that has `/usr/bin/mpifort` and can
already build the original Held-Suarez case:

```bash
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data

cd ${GFDL_BASE}

GFDL_ENV=ubuntu_conda python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py fortran
GFDL_ENV=hybrid python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py hybrid
```

Or:

```bash
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py both
```

The `both` target launches two subprocesses, one with `GFDL_ENV=ubuntu_conda`
and one with `GFDL_ENV=hybrid`.

## Build Attempt Status

No native Isca build was run from the current Codex shell because the successful
container workflow is not reachable here:

```text
apptainer: command not found
```

The escalated runtime check also returned:

```text
apptainer: command not found
```

So the stop point for this session is before compilation: the requested
container runtime is unavailable from the current environment. The implementation
is ready to run inside the working Isca Apptainer container.

## Verification Performed

Syntax check:

```bash
python3 -m py_compile hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py
```

Result: passed.
