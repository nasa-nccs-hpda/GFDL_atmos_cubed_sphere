#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
DEFAULT_PROJECT_ROOT=/explore/nobackup/people/jacaraba/projects/AgenticAI

CONTAINER="${CONTAINER:-/lscratch/jacaraba/isca-sandbox}"
export GFDL_BASE="${GFDL_BASE:-${REPO_ROOT}}"
export GFDL_WORK="${GFDL_WORK:-${DEFAULT_PROJECT_ROOT}/isca_work}"
export GFDL_DATA="${GFDL_DATA:-${DEFAULT_PROJECT_ROOT}/isca_data}"
export FV_KERNELS_OVERWRITE="${FV_KERNELS_OVERWRITE:-0}"
export FV_KERNELS_PROFILE="${FV_KERNELS_PROFILE:-0}"
export FV_KERNELS_CPU_NUM_CORES="${FV_KERNELS_CPU_NUM_CORES:-16}"
export FV_KERNELS_CUDA_NUM_CORES="${FV_KERNELS_CUDA_NUM_CORES:-16}"
export APPTAINER_BIND_ROOT="${APPTAINER_BIND_ROOT:-/explore/nobackup/people/jacaraba}"

LOG="${GFDL_BASE}/logs/fv_kernels_1day_smoke.log"
mkdir -p "${GFDL_BASE}/logs"
exec > >(tee "${LOG}") 2>&1

echo "=== Held-Suarez fv_advection kernel-bundle 1-day smoke runs ==="
echo "start_timestamp=$(date -Is)"
echo "CONTAINER=${CONTAINER}"
echo "GFDL_BASE=${GFDL_BASE}"
echo "GFDL_WORK=${GFDL_WORK}"
echo "GFDL_DATA=${GFDL_DATA}"
echo "FV_KERNELS_OVERWRITE=${FV_KERNELS_OVERWRITE}"
echo "FV_KERNELS_PROFILE=${FV_KERNELS_PROFILE}"
echo "FV_KERNELS_CPU_NUM_CORES=${FV_KERNELS_CPU_NUM_CORES}"
echo "FV_KERNELS_CUDA_NUM_CORES=${FV_KERNELS_CUDA_NUM_CORES}"
echo "cpu_executable=held_suarez_fv_kernels.x"
echo "cuda_executable=held_suarez_fv_kernels_cuda.x"
echo "cpu_experiment=held_suarez_fv_kernels_1day"
echo "cuda_experiment=held_suarez_fv_kernels_cuda_1day"

overwrite_arg=()
if [[ "${FV_KERNELS_OVERWRITE}" == "1" ]]; then
  overwrite_arg=(--overwrite)
fi

apptainer exec --nv \
  --bind "${APPTAINER_BIND_ROOT}:${APPTAINER_BIND_ROOT}" \
  "${CONTAINER}" \
  bash -lc "
set -e
export GFDL_BASE='${GFDL_BASE}'
export GFDL_WORK='${GFDL_WORK}'
export GFDL_DATA='${GFDL_DATA}'
export GFDL_ENV=hybrid
export FV_KERNELS_PROFILE='${FV_KERNELS_PROFILE}'
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd '${GFDL_BASE}'

echo '=== CPU C++ kernel-bundle smoke ==='
time python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name held_suarez_fv_kernels.x \
  --exp-name held_suarez_fv_kernels_1day \
  --days 1 \
  --production-diag \
  --num-cores '${FV_KERNELS_CPU_NUM_CORES}' \
  ${overwrite_arg[*]}

echo '=== CUDA kernel-bundle smoke ==='
time python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name held_suarez_fv_kernels_cuda.x \
  --exp-name held_suarez_fv_kernels_cuda_1day \
  --days 1 \
  --production-diag \
  --num-cores '${FV_KERNELS_CUDA_NUM_CORES}' \
  ${overwrite_arg[*]}
"

echo "end_timestamp=$(date -Is)"
echo "Log written to ${LOG}"
