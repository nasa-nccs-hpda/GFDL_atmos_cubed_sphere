#!/bin/bash
set -euo pipefail

CONTAINER=${CONTAINER:-/lscratch/rlgill/isca-debian_latest}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

export GFDL_BASE=${GFDL_BASE_OVERRIDE:-${SCRIPT_DIR}}
export GFDL_WORK=${GFDL_WORK:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_work}
export GFDL_DATA=${GFDL_DATA:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_data}

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

echo '=== Hybrid dry run ==='
python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py --dry-run \
  --executable-name held_suarez_fv_kernels_cuda.x \
  2>&1 | tee logs/hybrid_run_dryrun.log

echo '=== Hybrid 1-day run ==='
python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py --days 1 --overwrite \
  --executable-name held_suarez_fv_kernels_cuda.x \
  2>&1 | tee logs/hybrid_run_1day.log
"