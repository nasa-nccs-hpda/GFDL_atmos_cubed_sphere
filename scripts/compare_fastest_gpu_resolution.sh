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
FAST_GPU_RUN_MODE="${FAST_GPU_RUN_MODE:-both}"
FAST_GPU_CASE_SUFFIX="${FAST_GPU_CASE_SUFFIX:-}"
FAST_GPU_PRODUCTION_DIAG="${FAST_GPU_PRODUCTION_DIAG:-1}"
FAST_GPU_DIAG_FREQUENCY_DAYS="${FAST_GPU_DIAG_FREQUENCY_DAYS:-${FAST_GPU_DAYS}}"
FAST_GPU_NO_TRACERS="${FAST_GPU_NO_TRACERS:-0}"
HS_PROFILE="${HS_PROFILE:-1}"
HS_FORCE_COPY_TEQ="${HS_FORCE_COPY_TEQ:-0}"
USE_CUDA_TRANSFORMS="${USE_CUDA_TRANSFORMS:-0}"

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

CASE_TAG="${FAST_GPU_RESOLUTION}L${FAST_GPU_LEVELS}_dt${FAST_GPU_DT_ATMOS}_${FAST_GPU_DAYS}day${FAST_GPU_CASE_SUFFIX}"
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
echo "FAST_GPU_RUN_MODE=${FAST_GPU_RUN_MODE}"
echo "FAST_GPU_CASE_SUFFIX=${FAST_GPU_CASE_SUFFIX}"
echo "FAST_GPU_PRODUCTION_DIAG=${FAST_GPU_PRODUCTION_DIAG}"
echo "FAST_GPU_DIAG_FREQUENCY_DAYS=${FAST_GPU_DIAG_FREQUENCY_DAYS}"
echo "FAST_GPU_NO_TRACERS=${FAST_GPU_NO_TRACERS}"
echo "HS_PROFILE=${HS_PROFILE}"
echo "HS_FORCE_COPY_TEQ=${HS_FORCE_COPY_TEQ}"
echo "USE_CUDA_TRANSFORMS=${USE_CUDA_TRANSFORMS}"

if [[ "${FAST_GPU_RUN_MODE}" != "both" && "${FAST_GPU_RUN_MODE}" != "cpu" && "${FAST_GPU_RUN_MODE}" != "cuda" ]]; then
  echo "FAST_GPU_RUN_MODE must be one of: both, cpu, cuda"
  exit 3
fi

if [[ "${FAST_GPU_REBUILD}" == "1" ]]; then
  echo "=== Build CUDA-capable Held-Suarez forcing executable ==="
  USE_CUDA_HS_FORCE=1 USE_CUDA_TRANSFORMS="${USE_CUDA_TRANSFORMS}" "${REPO_ROOT}/run_compile_hybrid.sh"
fi

overwrite_arg=()
if [[ "${FAST_GPU_OVERWRITE}" == "1" ]]; then
  overwrite_arg=(--overwrite)
fi

production_diag_arg=()
if [[ "${FAST_GPU_PRODUCTION_DIAG}" == "1" ]]; then
  production_diag_arg=(--production-diag)
fi

no_tracer_arg=()
if [[ "${FAST_GPU_NO_TRACERS}" == "1" ]]; then
  no_tracer_arg=(--no-tracer-field-table)
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
export TRANSFORMS_BACKEND='${backend}'
export HS_PROFILE='${HS_PROFILE}'
export HS_FORCE_COPY_TEQ='${HS_FORCE_COPY_TEQ}'
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
  --diag-frequency-days '${FAST_GPU_DIAG_FREQUENCY_DAYS}' \
  ${production_diag_arg[*]} \
  ${no_tracer_arg[*]} \
  ${overwrite_arg[*]}
" 2>&1 | tee "${log}"
}

if [[ "${FAST_GPU_RUN_MODE}" == "both" || "${FAST_GPU_RUN_MODE}" == "cpu" ]]; then
  run_backend cpu cpu_cpp_hybrid "${CPU_LOG}"
fi

if [[ "${FAST_GPU_RUN_MODE}" == "both" || "${FAST_GPU_RUN_MODE}" == "cuda" ]]; then
  run_backend cuda cuda_hybrid "${CUDA_LOG}"
fi

if [[ "${FAST_GPU_RUN_MODE}" == "both" || "${FAST_GPU_RUN_MODE}" == "cpu" ]] && \
   ! grep -q 'HS_FORCE_RUNTIME version=combined_cuda_20260724 backend=cpu' "${CPU_LOG}"; then
  echo "ERROR: CPU backend runtime banner missing."
  exit 30
fi

if [[ "${FAST_GPU_RUN_MODE}" == "both" || "${FAST_GPU_RUN_MODE}" == "cuda" ]] && \
   ! grep -q 'HS_FORCE_RUNTIME version=combined_cuda_20260724 backend=cuda' "${CUDA_LOG}"; then
  echo "ERROR: CUDA backend runtime banner missing."
  exit 31
fi

if [[ "${FAST_GPU_RUN_MODE}" == "both" || "${FAST_GPU_RUN_MODE}" == "cuda" ]] && \
   ! grep -q 'HS_FORCE_CUDA_RUNTIME version=fused_persistent_20260724' "${CUDA_LOG}"; then
  echo "ERROR: fused persistent CUDA forcing runtime banner missing."
  exit 32
fi

if [[ "${USE_CUDA_TRANSFORMS}" == "1" ]] && \
   [[ "${FAST_GPU_RUN_MODE}" == "both" || "${FAST_GPU_RUN_MODE}" == "cuda" ]] && \
   ! grep -q 'TRANSFORMS_CUDA_RUNTIME version=horizontal_fused_20260724' "${CUDA_LOG}"; then
  echo "ERROR: CUDA transforms runtime banner missing."
  exit 33
fi

echo
echo "Logs:"
if [[ "${FAST_GPU_RUN_MODE}" == "both" || "${FAST_GPU_RUN_MODE}" == "cpu" ]]; then
  echo "CPU:  ${CPU_LOG}"
fi
if [[ "${FAST_GPU_RUN_MODE}" == "both" || "${FAST_GPU_RUN_MODE}" == "cuda" ]]; then
  echo "CUDA: ${CUDA_LOG}"
fi
echo
if [[ "${FAST_GPU_RUN_MODE}" == "both" ]]; then
  "${REPO_ROOT}/scripts/summarize_real_times.py" "${CPU_LOG}" "${CUDA_LOG}"
elif [[ "${FAST_GPU_RUN_MODE}" == "cpu" ]]; then
  "${REPO_ROOT}/scripts/summarize_real_times.py" "${CPU_LOG}"
else
  "${REPO_ROOT}/scripts/summarize_real_times.py" "${CUDA_LOG}"
fi
