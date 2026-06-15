#!/usr/bin/env bash
set -euo pipefail

CONTAINER=/lscratch/jli30/isca-sandbox

export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data

apptainer exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  ${CONTAINER} \
  bash -lc "
set -e

export GFDL_BASE=${GFDL_BASE}
export GFDL_WORK=${GFDL_WORK}
export GFDL_DATA=${GFDL_DATA}
export GFDL_ENV=hybrid
export HS_FORCE_BACKEND=cuda

export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none

cd ${GFDL_BASE}
mkdir -p logs

python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --days 1 \
  --production-diag \
  --overwrite
"
