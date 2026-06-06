# Hybrid Build Report Phase 3

Generated: 2026-06-05

## Goal

Implement the recommended minimal-fix hybrid build approach from
`docs/hybrid_build_diagnosis_phase2.md` and determine whether object
compilation begins.

Stop condition reached: first new compile/build-environment failure.

## Minimal Fix Implemented

Updated `hybrid_experiments/held_suarez_cpp_force/build_hybrid.py` to:

- create a production-like local source layout:
  - `hybrid_experiments/held_suarez_cpp_force/builddir/code -> <repo>`
  - `mkmf -a <builddir>/code/src`
- write the overlay entry in `builddir/path_names` relative to that source root:
  - `extra/local_overrides/hs_forcing/hs_forcing.F90`
- keep the build isolated to `hybrid_experiments/held_suarez_cpp_force/builddir`
- replace `subprocess.run(..., text=True)` with `universal_newlines=True` so the
  helper runs under the system Python 3.6.

## Command Run

```bash
python3 hybrid_experiments/held_suarez_cpp_force/build_hybrid.py
```

Attempting to run with `module load gcc/12.1.0` failed before the helper ran
because the sandbox/session module initialization tried to create
`/home/478312811/.nccstmp` and could not.

## Results

`mkmf` succeeded and generated a populated Makefile:

- `Makefile is ready.`
- `all: held_suarez.x`
- `SRCROOT = .../hybrid_experiments/held_suarez_cpp_force/builddir/code/src/`
- `hs_forcing.o` points at the overlay source:
  - `$(SRCROOT)extra/local_overrides/hs_forcing/hs_forcing.F90`

Object compilation did begin. Two C objects were produced before the build
stopped:

- `hybrid_experiments/held_suarez_cpp_force/builddir/affinity.o`
- `hybrid_experiments/held_suarez_cpp_force/builddir/create_xgrid.o`

No executable was generated.

## First New Failure

The previous blocker, empty `mkmf` output/no object rules, is resolved.

The new failure is a build environment/template failure during compilation:

- `nc-config` is not found in `PATH`
- `F90`/`FC` are unset, so Fortran compile commands begin with `$(CPPDEFS)`;
  because that expands to `-D...`, make treats the leading `-` as an
  ignore-errors prefix and runs malformed commands like `Duse_libMPI ...`
- MPI headers are unavailable to the C compiler:

```text
/.../src/shared/mpp/threadloc.c:27:10: fatal error: mpi.h: No such file or directory
 #include <mpi.h>
          ^~~~~~~
compilation terminated.
make: *** [Makefile:229: threadloc.o] Error 1
```

Environment checks from the same shell:

- no `F90`, `FC`, `GFDL_*`, `NETCDF*`, or `MPI*` variables were set
- `which nc-config` found nothing
- `which mpicc` found nothing

## Conclusion

The recommended minimal-fix hybrid build approach is sufficient to get past
`mkmf` scanning and into object compilation.

Current blocker is no longer source localization. It is the missing canonical
compiler/NetCDF/MPI environment for the hybrid helper shell.
