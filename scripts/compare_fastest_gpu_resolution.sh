#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
DEFAULT_PROJECT_ROOT=/explore/nobackup/people/jacaraba/projects/AgenticAI

export CONTAINER="${CONTAINER:-/lscratch/jacaraba/isca-sandbox}"
export GFDL_BASE="${GFDL_BASE:-${REPO_ROOT}}"
export GFDL_WORK="${GFDL_WORK:-${DEFAULT_PROJECT_ROOT}/isca_work}"
export GFDL_DATA="${GFDL_DATA:-${DEFAULT_PROJECT_ROOT}/isca_data}"
export APPTAINER_BIND_ROOT="${APPTAINER_BIND_ROOT:-/explore/nobackup/people/jacaraba}"

FAST_GPU_RESOLUTION="${FAST_GPU_RESOLUTION:-T85}"
FAST_GPU_LEVELS="${FAST_GPU_LEVELS:-25}"
FAST_GPU_DAYS="${FAST_GPU_DAYS:-30}"
FAST_GPU_NUM_CORES="${FAST_GPU_NUM_CORES:-16}"
FAST_GPU_OVERWRITE="${FAST_GPU_OVERWRITE:-1}"
FAST_GPU_REBUILD="${FAST_GPU_REBUILD:-1}"
HS_PROFILE="${HS_PROFILE:-1}"

if [[ -z "${FAST_GPU_DT_ATMOS:-}" ]]; then
  case "${FAST_GPU_RESOLUTION}" in
    T42) FAST_GPU_DT_ATMOS=600 ;;
    T85) FAST_GPU_DT_ATMOS=300 ;;
    T170) FAST_GPU_DT_ATMOS=150 ;;
    T341) FAST_GPU_DT_ATMOS=75 ;;
    *)
      echo "FAST_GPU_DT_ATMOS is required for resolution ${FAST_GPU_RESOLUTION}."
      exit 2
      ;;
  esac
fi

CASE_TAG="${FAST_GPU_RESOLUTION}L${FAST_GPU_LEVELS}_dt${FAST_GPU_DT_ATMOS}_${FAST_GPU_DAYS}day"
CPU_LOG="${GFDL_BASE}/logs/fastest_gpu_${CASE_TAG}_cpu.log"
CUDA_LOG="${GFDL_BASE}/logs/fastest_gpu_${CASE_TAG}_cuda.log"

mkdir -p "${GFDL_BASE}/logs"

echo "=== Fastest useful GPU resolution comparison ==="
echo "CONTAINER=${CONTAINER}"
echo "GFDL_BASE=${GFDL_BASE}"
echo "GFDL_WORK=${GFDL_WORK}"
echo "GFDL_DATA=${GFDL_DATA}"
echo "FAST_GPU_RESOLUTION=${FAST_GPU_RESOLUTION}"
echo "FAST_GPU_LEVELS=${FAST_GPU_LEVELS}"
echo "FAST_GPU_DT_ATMOS=${FAST_GPU_DT_ATMOS}"
echo "FAST_GPU_DAYS=${FAST_GPU_DAYS}"
echo "FAST_GPU_NUM_CORES=${FAST_GPU_NUM_CORES}"
echo "FAST_GPU_OVERWRITE=${FAST_GPU_OVERWRITE}"
echo "FAST_GPU_REBUILD=${FAST_GPU_REBUILD}"
echo "HS_PROFILE=${HS_PROFILE}"

if [[ "${FAST_GPU_REBUILD}" == "1" ]]; then
  echo "=== Build CUDA-capable Held-Suarez forcing executable ==="
  USE_CUDA_HS_FORCE=1 "${REPO_ROOT}/run_compile_hybrid.sh"
fi

overwrite_arg=()
if [[ "${FAST_GPU_OVERWRITE}" == "1" ]]; then
  overwrite_arg=(--overwrite)
fi

run_backend() {
  local backend=$1
  local label=$2
  local log=$3
  local exp_name="fastest_gpu_${CASE_TAG}_${backend}"

  echo "=== Run ${label} backend: ${CASE_TAG} ==="
  apptainer exec --nv \
    --bind "${APPTAINER_BIND_ROOT}:${APPTAINER_BIND_ROOT}" \
    "${CONTAINER}" \
    bash -lc "
set -e
export GFDL_BASE='${GFDL_BASE}'
export GFDL_WORK='${GFDL_WORK}'
export GFDL_DATA='${GFDL_DATA}'
export GFDL_ENV=hybrid
export HS_FORCE_BACKEND='${backend}'
export HS_PROFILE='${HS_PROFILE}'
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd '${GFDL_BASE}'
time python3 scripts/run_T85L25_case.py \
  --executable-name held_suarez_hybrid.x \
  --exp-name '${exp_name}' \
  --backend-label '${label}' \
  --resolution '${FAST_GPU_RESOLUTION}' \
  --levels '${FAST_GPU_LEVELS}' \
  --dt-atmos '${FAST_GPU_DT_ATMOS}' \
  --days '${FAST_GPU_DAYS}' \
  --num-cores '${FAST_GPU_NUM_CORES}' \
  ${overwrite_arg[*]}
" 2>&1 | tee "${log}"
}

run_backend cpu cpu_cpp_hybrid "${CPU_LOG}"
run_backend cuda cuda_hybrid "${CUDA_LOG}"

echo
echo "Logs:"
echo "CPU:  ${CPU_LOG}"
echo "CUDA: ${CUDA_LOG}"
echo
"${REPO_ROOT}/scripts/summarize_real_times.py" "${CPU_LOG}" "${CUDA_LOG}"
