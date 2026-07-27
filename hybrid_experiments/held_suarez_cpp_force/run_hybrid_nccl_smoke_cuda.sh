#!/usr/bin/env bash
# Level 1, Phase A, Step 1 verification: one MPI rank per GPU (np=2) so the
# startup fv_advection_nccl_init runs and the NCCL communicator is built.
#
# Success = a line on stderr like:
#   PROFILE_FV_ADVECTION_CUDA nccl_init world_rank=0 world_size=2 north=1 south=-1 device_count=2
# from each rank. A clear "one MPI rank per GPU" message instead means the
# rank/GPU count was mismatched; a FATAL from fv_advection_init means setup
# failed. This is a startup smoke test, not a numerics or timing run.
set -euo pipefail

CONTAINER=${CONTAINER:-/lscratch/rlgill/isca-debian_latest}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

export GFDL_BASE=${GFDL_BASE_OVERRIDE:-${SCRIPT_DIR}}
export GFDL_WORK=${GFDL_WORK:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_work}
export GFDL_DATA=${GFDL_DATA:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_data}

apptainer exec --nv \
  --bind /explore/nobackup/people/rlgill:/explore/nobackup/people/rlgill \
  "${CONTAINER}" \
  bash -lc "
set -e

export GFDL_BASE=${GFDL_BASE}
export GFDL_WORK=${GFDL_WORK}
export GFDL_DATA=${GFDL_DATA}
export GFDL_ENV=hybrid
export HS_FORCE_BACKEND=cuda

# Resident CUDA path on, so fv_advection_init calls fv_advection_nccl_init.
export FV_KERNELS_CUDA_MODE=resident
# Print the nccl_init profile line (and the per-call profile report at exit).
export FV_KERNELS_PROFILE=1

# One rank per GPU: do NOT oversubscribe. Keep the single-copy setting only.
export OMPI_MCA_btl_vader_single_copy_mechanism=none

cd ${GFDL_BASE}
mkdir -p logs

python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name held_suarez_fv_kernels_cuda.x \
  --num-cores 2 \
  --days 1 \
  --overwrite
"
