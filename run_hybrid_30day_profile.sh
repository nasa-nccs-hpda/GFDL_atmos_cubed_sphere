#!/bin/bash
set -euo pipefail

CONTAINER=${CONTAINER:-/lscratch/rlgill/isca-debian_latest}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

export GFDL_BASE=${GFDL_BASE_OVERRIDE:-${SCRIPT_DIR}}
export GFDL_WORK=${GFDL_WORK:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_work}
export GFDL_DATA=${GFDL_DATA:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data}

apptainer exec --nv \
  --bind /explore/nobackup/people:/explore/nobackup/people \
  ${CONTAINER} \
  bash -lc "
set -e

export GFDL_BASE=${GFDL_BASE}
export GFDL_WORK=${GFDL_WORK}
export GFDL_DATA=${GFDL_DATA}
export GFDL_ENV=hybrid

export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none

cd ${GFDL_BASE}
mkdir -p logs

{
  time env HS_PROFILE=1 \
    python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
      --days 30 \
      --production-diag \
      --overwrite
} 2>&1 | tee logs/hybrid_hs_profile_30day.log
"
