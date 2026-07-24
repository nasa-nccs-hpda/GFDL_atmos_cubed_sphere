#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
RANKS="${FV_KERNELS_CUDA_RANK_SWEEP:-1 2 4 8 16}"

export FV_KERNELS_PROFILE="${FV_KERNELS_PROFILE:-1}"
export FV_KERNELS_OVERWRITE="${FV_KERNELS_OVERWRITE:-1}"

for ranks in ${RANKS}; do
  echo "=== CUDA rank sweep: ${ranks} MPI rank(s) ==="
  FV_KERNELS_CUDA_NUM_CORES="${ranks}" \
  FV_KERNELS_CUDA_EXP_NAME="held_suarez_fv_kernels_cuda_30day_r${ranks}" \
    "${REPO_ROOT}/scripts/run_fv_kernels_cuda_30day.sh"

  cp "${REPO_ROOT}/logs/fv_kernels_cuda_30day.log" \
     "${REPO_ROOT}/logs/fv_kernels_cuda_30day_r${ranks}.log"
done

echo "=== Rank sweep profile summary ==="
"${REPO_ROOT}/scripts/summarize_fv_kernel_profile.py" \
  "${REPO_ROOT}"/logs/fv_kernels_cuda_30day_r*.log
