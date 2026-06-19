#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-/lscratch/jli30/isca-sandbox}"
export GFDL_BASE="${GFDL_BASE:-/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere}"
export GFDL_WORK="${GFDL_WORK:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work}"
export GFDL_DATA="${GFDL_DATA:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data}"
export FV_KERNELS_OVERWRITE="${FV_KERNELS_OVERWRITE:-0}"
export FV_KERNELS_PROFILE="${FV_KERNELS_PROFILE:-1}"

EXECUTABLE="${FV_KERNELS_EXECUTABLE:-held_suarez_fv_kernels_cuda.x}"
EXPERIMENT="${FV_KERNELS_EXPERIMENT:-held_suarez_fv_kernels_cuda_persistent_30day}"
LOG="${FV_KERNELS_LOG:-${GFDL_BASE}/logs/fv_kernels_cuda_persistent_30day.log}"

mkdir -p "${GFDL_BASE}/logs"
exec > >(tee "${LOG}") 2>&1

echo "=== Held-Suarez persistent CUDA FV kernels: 30-day profile ==="
echo "start_timestamp=$(date -Is)"
echo "CONTAINER=${CONTAINER}"
echo "GFDL_BASE=${GFDL_BASE}"
echo "GFDL_WORK=${GFDL_WORK}"
echo "GFDL_DATA=${GFDL_DATA}"
echo "executable=${EXECUTABLE}"
echo "experiment=${EXPERIMENT}"
echo "days=30"
echo "num_cores=16"
echo "FV_KERNELS_CUDA_MODE=persistent"
echo "FV_KERNELS_PROFILE=${FV_KERNELS_PROFILE}"
echo "FV_KERNELS_OVERWRITE=${FV_KERNELS_OVERWRITE}"

overwrite_arg=()
if [[ "${FV_KERNELS_OVERWRITE}" == "1" ]]; then
  overwrite_arg=(--overwrite)
fi

apptainer exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "${CONTAINER}" \
  bash -lc "
set -e
export GFDL_BASE='${GFDL_BASE}'
export GFDL_WORK='${GFDL_WORK}'
export GFDL_DATA='${GFDL_DATA}'
export GFDL_ENV=hybrid
export FV_KERNELS_CUDA_MODE=persistent
export FV_KERNELS_PROFILE='${FV_KERNELS_PROFILE}'
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd '${GFDL_BASE}'

echo 'gpu_status:'
nvidia-smi -L || true

time python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name '${EXECUTABLE}' \
  --exp-name '${EXPERIMENT}' \
  --days 30 \
  --production-diag \
  --num-cores 16 \
  ${overwrite_arg[*]}
"

echo "end_timestamp=$(date -Is)"
echo "output=${GFDL_DATA}/${EXPERIMENT}/run0001/atmos_monthly.nc"
echo "log=${LOG}"
