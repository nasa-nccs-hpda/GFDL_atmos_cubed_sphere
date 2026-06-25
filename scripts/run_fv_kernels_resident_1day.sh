#!/usr/bin/env bash
set -euo pipefail

CONTAINER=${CONTAINER:-/lscratch/rlgill/isca-debian_latest}
export GFDL_BASE="${GFDL_BASE:-/explore/nobackup/people/rlgill/SystemTesting/AAI/GFDL_atmos_cubed_sphere}"
export GFDL_WORK="${GFDL_WORK:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_work}"
export GFDL_DATA="${GFDL_DATA:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_data}"
export FV_KERNELS_OVERWRITE="${FV_KERNELS_OVERWRITE:-0}"
export FV_KERNELS_PROFILE="${FV_KERNELS_PROFILE:-1}"

EXECUTABLE=held_suarez_fv_kernels_cuda.x
EXPERIMENT=held_suarez_fv_kernels_cuda_resident_1day
LOG="${GFDL_BASE}/logs/fv_kernels_cuda_resident_1day.log"

mkdir -p "${GFDL_BASE}/logs"
exec > >(tee "${LOG}") 2>&1

echo "=== Held-Suarez resident CUDA FV boundary: 1-day smoke ==="
echo "start_timestamp=$(date -Is)"
echo "CONTAINER=${CONTAINER}"
echo "GFDL_BASE=${GFDL_BASE}"
echo "GFDL_WORK=${GFDL_WORK}"
echo "GFDL_DATA=${GFDL_DATA}"
echo "executable=${EXECUTABLE}"
echo "experiment=${EXPERIMENT}"
echo "FV_KERNELS_CUDA_MODE=resident"
echo "FV_KERNELS_PROFILE=${FV_KERNELS_PROFILE}"
echo "FV_KERNELS_OVERWRITE=${FV_KERNELS_OVERWRITE}"

overwrite_arg=()
if [[ "${FV_KERNELS_OVERWRITE}" == "1" ]]; then
  overwrite_arg=(--overwrite)
fi

apptainer exec --nv \
  --bind /explore/nobackup/people/rlgill:/explore/nobackup/people/rlgill \
  "${CONTAINER}" \
  bash -lc "
set -e
export GFDL_BASE='${GFDL_BASE}'
export GFDL_WORK='${GFDL_WORK}'
export GFDL_DATA='${GFDL_DATA}'
export GFDL_ENV=hybrid
export FV_KERNELS_CUDA_MODE=resident
export FV_KERNELS_PROFILE='${FV_KERNELS_PROFILE}'
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd '${GFDL_BASE}'

echo container_arch=\$(uname -m)
echo 'gpu_status:'
nvidia-smi -L || true

time python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name '${EXECUTABLE}' \
  --exp-name '${EXPERIMENT}' \
  --days 1 \
  --production-diag \
  --num-cores 16 \
  ${overwrite_arg[*]}
"

echo "end_timestamp=$(date -Is)"
echo "output=${GFDL_DATA}/${EXPERIMENT}/run0001"
echo "log=${LOG}"
