#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

FAST_GPU_RESOLUTION="${FAST_GPU_RESOLUTION:-T170}"
FAST_GPU_LEVELS="${FAST_GPU_LEVELS:-25}"
FAST_GPU_DAYS="${FAST_GPU_DAYS:-2}"
FAST_GPU_RANK_SWEEP="${FAST_GPU_RANK_SWEEP:-1 2 4 8 16}"
FAST_GPU_REBUILD_FIRST="${FAST_GPU_REBUILD_FIRST:-1}"
FAST_GPU_OVERWRITE="${FAST_GPU_OVERWRITE:-1}"
FAST_GPU_ALLOW_FAILURES="${FAST_GPU_ALLOW_FAILURES:-1}"

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

echo "=== GPU-only rank sweep ==="
echo "FAST_GPU_RESOLUTION=${FAST_GPU_RESOLUTION}"
echo "FAST_GPU_LEVELS=${FAST_GPU_LEVELS}"
echo "FAST_GPU_DT_ATMOS=${FAST_GPU_DT_ATMOS}"
echo "FAST_GPU_DAYS=${FAST_GPU_DAYS}"
echo "FAST_GPU_RANK_SWEEP=${FAST_GPU_RANK_SWEEP}"
echo "FAST_GPU_REBUILD_FIRST=${FAST_GPU_REBUILD_FIRST}"
echo "FAST_GPU_OVERWRITE=${FAST_GPU_OVERWRITE}"
echo "FAST_GPU_ALLOW_FAILURES=${FAST_GPU_ALLOW_FAILURES}"

first=1
logs=()
failed=()
for ranks in ${FAST_GPU_RANK_SWEEP}; do
  echo
  echo "=== GPU ranks=${ranks}: ${CASE_TAG} ==="
  if [[ "${first}" == "1" ]]; then
    rebuild="${FAST_GPU_REBUILD_FIRST}"
    first=0
  else
    rebuild=0
  fi

  rank_suffix="_r${ranks}"
  rank_case_tag="${CASE_TAG}${rank_suffix}"
  src_log="${REPO_ROOT}/logs/fastest_gpu_${rank_case_tag}_cuda.log"
  rank_log="${REPO_ROOT}/logs/fastest_gpu_${CASE_TAG}_cuda_r${ranks}.log"
  set +e
  FAST_GPU_RUN_MODE=cuda \
  FAST_GPU_REBUILD="${rebuild}" \
  FAST_GPU_RESOLUTION="${FAST_GPU_RESOLUTION}" \
  FAST_GPU_LEVELS="${FAST_GPU_LEVELS}" \
  FAST_GPU_DT_ATMOS="${FAST_GPU_DT_ATMOS}" \
  FAST_GPU_DAYS="${FAST_GPU_DAYS}" \
  FAST_GPU_NUM_CORES="${ranks}" \
  FAST_GPU_OVERWRITE="${FAST_GPU_OVERWRITE}" \
  FAST_GPU_CASE_SUFFIX="${rank_suffix}" \
    "${REPO_ROOT}/scripts/compare_fastest_gpu_resolution.sh"
  status=$?
  set -e

  if [[ -f "${src_log}" ]]; then
    cp "${src_log}" "${rank_log}"
  fi

  if [[ "${status}" == "0" ]]; then
    "${REPO_ROOT}/scripts/verify_fastest_gpu_path.sh" "${rank_log}"
    logs+=("${rank_log}")
  else
    echo "Rank ${ranks} failed with status ${status}."
    failed+=("${ranks}")
    run_dir="${GFDL_WORK:-/explore/nobackup/people/jacaraba/projects/AgenticAI/isca_work}/experiment/fastest_gpu_${rank_case_tag}_cuda/run"
    echo "Run dir: ${run_dir}"
    for candidate in "${run_dir}/logfile.000000.out" "${run_dir}/logfile.000000.err" "${run_dir}/fms.out" "${run_dir}/run.log"; do
      if [[ -f "${candidate}" ]]; then
        echo "--- tail ${candidate} ---"
        tail -n 80 "${candidate}" || true
      fi
    done
    if [[ "${FAST_GPU_ALLOW_FAILURES}" != "1" ]]; then
      exit "${status}"
    fi
  fi
done

echo
echo "=== Rank sweep summary ==="
if [[ "${#logs[@]}" -gt 0 ]]; then
  "${REPO_ROOT}/scripts/summarize_gpu_rank_sweep.py" "${logs[@]}"
else
  echo "No rank completed successfully."
fi
if [[ "${#failed[@]}" -gt 0 ]]; then
  echo "Failed ranks: ${failed[*]}"
fi
