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

DYN_PROFILE_RESOLUTION="${DYN_PROFILE_RESOLUTION:-T170}"
DYN_PROFILE_LEVELS="${DYN_PROFILE_LEVELS:-25}"
DYN_PROFILE_DAYS="${DYN_PROFILE_DAYS:-2}"
DYN_PROFILE_NUM_CORES="${DYN_PROFILE_NUM_CORES:-16}"
DYN_PROFILE_OVERWRITE="${DYN_PROFILE_OVERWRITE:-1}"
DYN_PROFILE_REBUILD="${DYN_PROFILE_REBUILD:-1}"
DYN_PROFILE_MODE="${DYN_PROFILE_MODE:-regions_deep}"

if [[ -z "${DYN_PROFILE_DT_ATMOS:-}" ]]; then
  case "${DYN_PROFILE_RESOLUTION}" in
    T42) DYN_PROFILE_DT_ATMOS=600 ;;
    T85) DYN_PROFILE_DT_ATMOS=300 ;;
    T170) DYN_PROFILE_DT_ATMOS=150 ;;
    T341) DYN_PROFILE_DT_ATMOS=75 ;;
    *)
      echo "DYN_PROFILE_DT_ATMOS is required for resolution ${DYN_PROFILE_RESOLUTION}."
      exit 2
      ;;
  esac
fi

CASE_TAG="${DYN_PROFILE_RESOLUTION}L${DYN_PROFILE_LEVELS}_dt${DYN_PROFILE_DT_ATMOS}_${DYN_PROFILE_DAYS}day"
REGION_LOG="${GFDL_BASE}/logs/dynamics_profile_${CASE_TAG}_regions.log"
DEEP_LOG="${GFDL_BASE}/logs/dynamics_profile_${CASE_TAG}_deep.log"

mkdir -p "${GFDL_BASE}/logs"

echo "=== Held-Suarez dynamics profile ==="
echo "CONTAINER=${CONTAINER}"
echo "GFDL_BASE=${GFDL_BASE}"
echo "GFDL_WORK=${GFDL_WORK}"
echo "GFDL_DATA=${GFDL_DATA}"
echo "DYN_PROFILE_RESOLUTION=${DYN_PROFILE_RESOLUTION}"
echo "DYN_PROFILE_LEVELS=${DYN_PROFILE_LEVELS}"
echo "DYN_PROFILE_DT_ATMOS=${DYN_PROFILE_DT_ATMOS}"
echo "DYN_PROFILE_DAYS=${DYN_PROFILE_DAYS}"
echo "DYN_PROFILE_NUM_CORES=${DYN_PROFILE_NUM_CORES}"
echo "DYN_PROFILE_OVERWRITE=${DYN_PROFILE_OVERWRITE}"
echo "DYN_PROFILE_REBUILD=${DYN_PROFILE_REBUILD}"
echo "DYN_PROFILE_MODE=${DYN_PROFILE_MODE}"

overwrite_arg=()
if [[ "${DYN_PROFILE_OVERWRITE}" == "1" ]]; then
  overwrite_arg=(--overwrite)
fi

build_target() {
  local target=$1
  echo "=== Build ${target} ==="
  apptainer exec \
    --bind "${APPTAINER_BIND_ROOT}:${APPTAINER_BIND_ROOT}" \
    "${CONTAINER}" \
    bash -lc "
set -e
export GFDL_BASE='${GFDL_BASE}'
export GFDL_WORK='${GFDL_WORK}'
export GFDL_DATA='${GFDL_DATA}'
export GFDL_ENV=ubuntu_conda
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd '${GFDL_BASE}'
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py '${target}'
"
}

run_profile() {
  local executable=$1
  local label=$2
  local log=$3
  echo "=== Run ${label}: ${CASE_TAG} ==="
  apptainer exec \
    --bind "${APPTAINER_BIND_ROOT}:${APPTAINER_BIND_ROOT}" \
    "${CONTAINER}" \
    bash -lc "
set -e
export GFDL_BASE='${GFDL_BASE}'
export GFDL_WORK='${GFDL_WORK}'
export GFDL_DATA='${GFDL_DATA}'
export GFDL_ENV=ubuntu_conda
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd '${GFDL_BASE}'
time python3 scripts/run_T85L25_case.py \
  --executable-name '${executable}' \
  --exp-name 'dynamics_profile_${CASE_TAG}_${label}' \
  --backend-label '${label}' \
  --resolution '${DYN_PROFILE_RESOLUTION}' \
  --levels '${DYN_PROFILE_LEVELS}' \
  --dt-atmos '${DYN_PROFILE_DT_ATMOS}' \
  --days '${DYN_PROFILE_DAYS}' \
  --num-cores '${DYN_PROFILE_NUM_CORES}' \
  ${overwrite_arg[*]}
" 2>&1 | tee "${log}"
}

if [[ "${DYN_PROFILE_REBUILD}" == "1" ]]; then
  if [[ "${DYN_PROFILE_MODE}" == "regions" || "${DYN_PROFILE_MODE}" == "regions_deep" ]]; then
    build_target profile_dynamics_regions
  fi
  if [[ "${DYN_PROFILE_MODE}" == "deep" || "${DYN_PROFILE_MODE}" == "regions_deep" ]]; then
    build_target profile_dynamics_deep
  fi
fi

logs=()
if [[ "${DYN_PROFILE_MODE}" == "regions" || "${DYN_PROFILE_MODE}" == "regions_deep" ]]; then
  run_profile held_suarez_profile_dynamics_regions.x regions "${REGION_LOG}"
  logs+=("${REGION_LOG}")
fi
if [[ "${DYN_PROFILE_MODE}" == "deep" || "${DYN_PROFILE_MODE}" == "regions_deep" ]]; then
  run_profile held_suarez_profile_dynamics_deep.x deep "${DEEP_LOG}"
  logs+=("${DEEP_LOG}")
fi

echo
echo "Logs:"
printf '%s\n' "${logs[@]}"
echo
"${REPO_ROOT}/scripts/summarize_dynamics_profile.py" "${logs[@]}"
