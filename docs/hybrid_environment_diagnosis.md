# Hybrid Environment Diagnosis

Generated: 2026-06-05

## Summary

The phase 3 hybrid build fix succeeded: `mkmf` now emits a populated Makefile
and object compilation starts.

The remaining blocker is the build environment. The successful production
Held-Suarez executable was built in the Isca container environment, while the
current hybrid shell lacks the compiler wrappers, NetCDF tools, MPI headers, and
matching architecture.

`make` was not rerun after adding `setup_env.sh`, because the environment check
still fails and therefore does not match production.

## Evidence Sources

- Production compile script:
  `/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_isca/build/held_suarez/compile.sh`
- Production Makefile:
  `/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_isca/build/held_suarez/Makefile`
- Production executable:
  `/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_isca/build/held_suarez/held_suarez.x`
- Container runner:
  `run_held_suarez.sh`
- Container recipe:
  `requirements/Dockerfile`
- Environment file:
  `src/extra/env/ubuntu_conda`
- Template:
  `src/extra/python/isca/templates/mkmf.template.ubuntu_conda`

## Production Build Environment

The production `compile.sh` sources:

```bash
source /isca/src/extra/env/ubuntu_conda
```

That file sets:

```bash
export GFDL_MKMF_TEMPLATE=ubuntu_conda
export F90=mpifort
export CC=mpicc
```

The rendered production Makefile confirms:

```make
include /isca/src/extra/python/isca/templates/mkmf.template.ubuntu_conda
FC = $(F90)
LD = $(F90)
CPPFLAGS = `nc-config --cflags`
NC_INC = `nc-config --fflags`
NC_LIB = `nc-config --flibs`
LDFLAGS = -lnetcdff -lnetcdf -lmpi
```

`run_held_suarez.sh` runs the case with:

```bash
apptainer exec \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  /lscratch/jli30/isca-sandbox \
  bash -lc "..."
```

Inside that container it sets:

```bash
export GFDL_BASE=/isca
export GFDL_ENV=ubuntu_conda
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
```

The Dockerfile lineage is Ubuntu 22.04 and installs:

- `gfortran`
- `libnetcdf-dev`
- `libpnetcdf-dev`
- `libnetcdff-dev`
- `libhdf5-openmpi-dev`

## Requested Variable Comparison

| Item | Production build | Current hybrid shell before setup | After `setup_env.sh` in current shell |
|---|---|---|---|
| `F90` | `mpifort` | unset | `mpifort`, but command missing |
| `FC` | `$(F90)` in Makefile, effectively `mpifort` | unset | `mpifort`, but command missing |
| `CC` | `mpicc` | unset | `mpicc`, but command missing |
| `CPP` | not explicitly set by production env; system `cpp` implied | unset | `cpp` |
| `PATH` | container path with `/usr/bin` tools available; exact old value was not recorded | current host/Codex path, lacks `mpifort`, `mpicc`, `nc-config`, `nf-config` | unchanged host/Codex path, still lacks required tools |
| `LD_LIBRARY_PATH` | not set in artifacts; executable relies on standard container library paths | unset | unchanged |
| MPI variables | `OMPI_MCA_rmaps_base_oversubscribe=1`, `OMPI_MCA_btl_vader_single_copy_mechanism=none` at run time | unset | both exported by setup script |
| NetCDF variables | no persistent env vars found; build uses `nc-config` and `nf-config` | none; `nc-config`/`nf-config` missing | no persistent vars; tools still missing |
| loaded modules | none indicated; container package environment | `module list`: no modules loaded | no modules loaded |
| architecture | `aarch64` executable and interpreter `/lib/ld-linux-aarch64.so.1` | `x86_64` | `x86_64`, mismatch warning |

## Executable Toolchain Metadata

`file held_suarez.x` reports:

```text
ELF 64-bit LSB shared object, ARM aarch64, dynamically linked,
interpreter /lib/ld-linux-aarch64.so.1
```

`readelf -p .comment held_suarez.x` reports:

```text
GCC: (Ubuntu 11.4.0-1ubuntu1~22.04.3) 11.4.0
```

`readelf -d held_suarez.x` reports dynamic dependencies:

```text
libnetcdff.so.7
libnetcdf.so.19
libmpi.so.40
libmpi_mpifh.so.40
libgfortran.so.5
libm.so.6
libgcc_s.so.1
libc.so.6
ld-linux-aarch64.so.1
```

This matches an Ubuntu 22.04/OpenMPI/NetCDF/gfortran container build, not the
current host shell.

## Hybrid Environment Check

Created:

```bash
hybrid_experiments/held_suarez_cpp_force/setup_env.sh
```

The script:

- sources `/isca/src/extra/env/ubuntu_conda` when running inside the container
- otherwise sources the same env file from this checkout
- exports `F90=mpifort`, `FC=mpifort`, `CC=mpicc`, `CPP=cpp`
- exports the OpenMPI runtime variables used by `run_held_suarez.sh`
- checks for `mpifort`, `mpicc`, `nc-config`, and `nf-config`
- warns if the current architecture is not `aarch64`

Validation in the current shell failed:

```text
ERROR: required production build tool not found in PATH: mpifort
ERROR: required production build tool not found in PATH: mpicc
ERROR: required production build tool not found in PATH: nc-config
ERROR: required production build tool not found in PATH: nf-config
WARNING: production held_suarez.x is aarch64, current shell is x86_64.
Hybrid environment does not match production; do not run make yet.
```

## Container Availability From Current Shell

The local wrapper expects:

```bash
CONTAINER=/lscratch/jli30/isca-sandbox
```

From this shell:

- `/lscratch/jli30/isca-sandbox` is not visible
- `apptainer` is not in `PATH`
- `singularity` is not in `PATH`
- `docker` is not in `PATH`

So the production-like environment cannot be entered from this session.

## Conclusion

The production Held-Suarez executable was built with:

- Ubuntu 22.04 aarch64 userspace
- GCC/gfortran 11.4.0
- OpenMPI wrapper compilers: `mpifort`, `mpicc`
- NetCDF tools/libraries available through `nc-config` and `nf-config`
- Isca env/template pair: `ubuntu_conda`

The hybrid Makefile is now structurally correct, but the current shell cannot
compile it because it lacks the production container/toolchain. Re-run should be
performed only inside the same Isca container or an equivalent Ubuntu 22.04
aarch64 environment with OpenMPI and NetCDF development packages installed.
