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
export HYBRID_OVERWRITE="${HYBRID_OVERWRITE:-1}"
export HYBRID_NUM_CORES="${HYBRID_NUM_CORES:-16}"
export HS_PROFILE="${HS_PROFILE:-1}"

echo "=== Build fastest currently useful GPU executable ==="
echo "This builds Held-Suarez forcing with CUDA support and leaves FV CUDA out."
USE_CUDA_HS_FORCE=1 "${REPO_ROOT}/run_compile_hybrid.sh"

echo "=== Run CPU backend through same hybrid executable ==="
HS_FORCE_BACKEND=cpu "${REPO_ROOT}/run_hybrid_30day.sh"
cp "${GFDL_BASE}/logs/hybrid_cpu_30day.log" "${GFDL_BASE}/logs/fastest_gpu_cpu_30day.log"

echo "=== Run CUDA backend through same hybrid executable ==="
HS_FORCE_BACKEND=cuda "${REPO_ROOT}/run_hybrid_30day.sh"
cp "${GFDL_BASE}/logs/hybrid_cuda_30day.log" "${GFDL_BASE}/logs/fastest_gpu_cuda_30day.log"

echo "=== Fastest GPU comparison logs ==="
echo "CPU log:  ${GFDL_BASE}/logs/fastest_gpu_cpu_30day.log"
echo "CUDA log: ${GFDL_BASE}/logs/fastest_gpu_cuda_30day.log"

if ! grep -q 'HS_FORCE_RUNTIME version=combined_cuda_20260724 backend=cpu' "${GFDL_BASE}/logs/fastest_gpu_cpu_30day.log"; then
  echo "ERROR: CPU backend runtime banner missing."
  exit 30
fi

if ! grep -q 'HS_FORCE_RUNTIME version=combined_cuda_20260724 backend=cuda' "${GFDL_BASE}/logs/fastest_gpu_cuda_30day.log"; then
  echo "ERROR: CUDA backend runtime banner missing."
  exit 31
fi

echo
echo "Runtime summary:"
grep '^real' "${GFDL_BASE}/logs/fastest_gpu_cpu_30day.log" || true
grep '^real' "${GFDL_BASE}/logs/fastest_gpu_cuda_30day.log" || true
