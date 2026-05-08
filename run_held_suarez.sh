#!/bin/bash

set -e

CONTAINER=/lscratch/jli30/isca-sandbox

export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data

SCRIPT_DIR=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/exp/test_cases/held_suarez

echo "SLURM_NTASKS=${SLURM_NTASKS:-not_set}"
echo "Container=${CONTAINER}"

apptainer exec \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  ${CONTAINER} \
  bash -lc "
export GFDL_BASE=/isca
export GFDL_ENV=ubuntu_conda
export GFDL_WORK=${GFDL_WORK}
export GFDL_DATA=${GFDL_DATA}

export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none

echo Inside container:
echo SLURM_NTASKS=\$SLURM_NTASKS
echo nproc=\$(nproc)

which mpirun
mpirun --oversubscribe -np ${SLURM_NTASKS:-1} hostname

cd ${SCRIPT_DIR}

python3 held_suarez_test_case.py
"
