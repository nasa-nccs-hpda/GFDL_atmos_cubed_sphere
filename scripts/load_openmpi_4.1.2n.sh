#!/bin/bash

module purge
module load gcc/11.2.0
module load openmpi/4.1.2n

export MPI_ROOT=/panfs/ccds02/app/modules/openmpi/platform/aarch64/rhel/9.8/4.1.2_gcc-12.1.0nv12.1

unset OPAL_PREFIX
unset OMPI_MCA_prefix
unset PRTE_PREFIX
unset PMIX_INSTALL_PREFIX
unset MPI_HOME
unset MPIHOME
unset OPENMPI
unset M_MPI_ROOT

export OPAL_PREFIX="$MPI_ROOT"
export PATH="$MPI_ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$MPI_ROOT/lib:${LD_LIBRARY_PATH:-}"

hash -r

echo "mpicc:    $(which mpicc)"
echo "mpirun:   $(which mpirun)"
echo "ompi_info: $(which ompi_info)"
