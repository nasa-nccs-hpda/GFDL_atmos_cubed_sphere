#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
DEFAULT_PROJECT_ROOT=/explore/nobackup/people/jacaraba/projects/AgenticAI

export CONTAINER="${CONTAINER:-/lscratch/jacaraba/isca-sandbox}"
export GFDL_BASE="${GFDL_BASE:-${REPO_ROOT}}"
export GFDL_WORK="${GFDL_WORK:-${DEFAULT_PROJECT_ROOT}/isca_work}"
export GFDL_DATA="${GFDL_DATA:-${DEFAULT_PROJECT_ROOT}/isca_data}"
export FV_KERNELS_PROFILE="${FV_KERNELS_PROFILE:-1}"
export FV_KERNELS_OVERWRITE="${FV_KERNELS_OVERWRITE:-0}"
export APPTAINER_BIND_ROOT="${APPTAINER_BIND_ROOT:-/explore/nobackup/people/jacaraba}"

echo "=== Build CPU fv_advection kernel bundle ==="
USE_CUDA_FV_ADVECTION_KERNELS=0 "${REPO_ROOT}/run_compile_fv_kernels.sh"

echo "=== Build CUDA fv_advection kernel bundle ==="
USE_CUDA_FV_ADVECTION_KERNELS=1 "${REPO_ROOT}/run_compile_fv_kernels.sh"

echo "=== Run 1-day CPU/CUDA smoke comparison ==="
"${REPO_ROOT}/scripts/run_fv_kernels_1day_smoke.sh"

echo "=== Run 30-day CPU profile ==="
"${REPO_ROOT}/scripts/run_fv_kernels_cpu_30day.sh"

echo "=== Run 30-day CUDA profile ==="
"${REPO_ROOT}/scripts/run_fv_kernels_cuda_30day.sh"

echo "=== Comparison artifacts ==="
echo "CPU log:  ${GFDL_BASE}/logs/fv_kernels_cpu_30day.log"
echo "CUDA log: ${GFDL_BASE}/logs/fv_kernels_cuda_30day.log"
echo "Profile marker: PROFILE_FV_ADVECTION_KERNEL"
echo "Set FV_KERNELS_OVERWRITE=1 to replace previous experiment outputs."

if ! grep -q 'FV_CUDA_RUNTIME version=a_grid_stage_cuda_resident_20260724' "${GFDL_BASE}/logs/fv_kernels_cuda_30day.log"; then
  echo "WARNING: CUDA runtime banner for the widened a_grid path was not found."
  echo "         The run may have used an old executable or old CUDA library."
fi

if ! grep -q 'name=a_grid_advection_stage1' "${GFDL_BASE}/logs/fv_kernels_cuda_30day.log"; then
  echo "WARNING: a_grid_advection_stage1 profile marker was not found in CUDA log."
fi

if ! grep -q 'name=a_grid_advection_stage2' "${GFDL_BASE}/logs/fv_kernels_cuda_30day.log"; then
  echo "WARNING: a_grid_advection_stage2 profile marker was not found in CUDA log."
fi
