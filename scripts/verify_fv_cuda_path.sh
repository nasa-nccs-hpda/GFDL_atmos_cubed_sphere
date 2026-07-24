#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
GFDL_BASE="${GFDL_BASE:-${REPO_ROOT}}"

COMPILE_LOG="${GFDL_BASE}/logs/fv_kernels_cuda_compile_latest.log"
RUN_LOG="${GFDL_BASE}/logs/fv_kernels_cuda_30day.log"

missing=0

check_log() {
  local label=$1
  local pattern=$2
  local file=$3
  if grep -q "${pattern}" "${file}"; then
    echo "PASS ${label}: ${pattern}"
  else
    echo "FAIL ${label}: ${pattern}"
    missing=1
  fi
}

if [[ ! -f "${COMPILE_LOG}" ]]; then
  echo "FAIL compile log missing: ${COMPILE_LOG}"
  missing=1
else
  check_log compile 'USE_CUDA_FV_ADVECTION_KERNELS= 1' "${COMPILE_LOG}"
  check_log compile 'Building press_and_geopot CUDA library' "${COMPILE_LOG}"
  check_log compile 'FV_KERNELS_FORCE_CLEAN_NATIVE= 1' "${COMPILE_LOG}"
  check_log compile 'Removing existing FV kernels native builddir for clean rebuild' "${COMPILE_LOG}"
  check_log compile 'Generated:' "${COMPILE_LOG}"
fi

if [[ ! -f "${RUN_LOG}" ]]; then
  echo "FAIL run log missing: ${RUN_LOG}"
  missing=1
else
  check_log runtime 'FV_CUDA_RUNTIME version=a_grid_stage_cuda_resident_20260724' "${RUN_LOG}"
  check_log runtime 'name=a_grid_advection_stage1' "${RUN_LOG}"
  check_log runtime 'name=a_grid_advection_stage2' "${RUN_LOG}"
  check_log runtime 'PROFILE_FV_ADVECTION_KERNEL backend=cuda' "${RUN_LOG}"
  check_log runtime 'PRESS_GEOPOT_CUDA_RUNTIME version=column_cuda_20260724' "${RUN_LOG}"
  check_log runtime 'PROFILE_PRESS_GEOPOT backend=cuda' "${RUN_LOG}"
fi

if [[ "${missing}" != "0" ]]; then
  echo
  echo "The latest CUDA run did not prove it used the widened FV plus press/geopot CUDA path."
  echo "Rebuild/rerun with:"
  echo "  FV_KERNELS_FORCE_CLEAN_NATIVE=1 FV_KERNELS_OVERWRITE=1 scripts/compare_fv_kernels_cpu_gpu.sh"
  exit 1
fi

echo
echo "CUDA widened FV plus press/geopot path verified."
