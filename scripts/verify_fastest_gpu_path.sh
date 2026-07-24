#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
GFDL_BASE="${GFDL_BASE:-${REPO_ROOT}}"

LOG="${1:-}"
if [[ -z "${LOG}" ]]; then
  LOG=$(ls -t "${GFDL_BASE}"/logs/fastest_gpu_*_cuda.log 2>/dev/null | head -n 1 || true)
fi

if [[ -z "${LOG}" || ! -f "${LOG}" ]]; then
  echo "FAIL: CUDA fastest-GPU log not found."
  echo "Pass a log path or run scripts/run_fastest_gpu_resolution.sh first."
  exit 1
fi

missing=0

check_log() {
  local pattern=$1
  if grep -q "${pattern}" "${LOG}"; then
    echo "PASS runtime: ${pattern}"
  else
    echo "FAIL runtime: ${pattern}"
    missing=1
  fi
}

echo "Checking ${LOG}"
check_log 'HS_FORCE_RUNTIME version=combined_cuda_20260724 backend=cuda'
check_log 'HS_FORCE_CUDA_RUNTIME version=fused_persistent_20260724'
check_log 'copy_teq=0'
check_log 'TRANSFORMS_CUDA_RUNTIME version=horizontal_fused_20260724'

if [[ "${missing}" != "0" ]]; then
  echo
  echo "This log did not use the latest fused CUDA forcing plus transform runtime."
  echo "Rebuild and rerun with:"
  echo "  FAST_GPU_REBUILD=1 FAST_GPU_RESOLUTION=T170 FAST_GPU_DAYS=2 scripts/run_fastest_gpu_resolution.sh"
  exit 1
fi

echo
echo "Fastest GPU fused CUDA forcing plus transform path verified."
