#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
ITERATIONS=${ITERATIONS:-100}
NVCC=${NVCC:-/usr/local/cuda/bin/nvcc}
LOG=${LOG:-${ROOT_DIR}/logs/fv_advection_cuda_microbenchmark.log}

mkdir -p "${ROOT_DIR}/logs"
cd "${SCRIPT_DIR}"

make clean all NVCC="${NVCC}"

{
  echo "timestamp=$(date -Is)"
  echo "iterations=${ITERATIONS}"
  for resolution in T42 T85 T170; do
    ./bin/fv_advection_cuda_benchmark \
      --resolution "${resolution}" \
      --iterations "${ITERATIONS}" \
      --mode all
  done
} 2>&1 | tee "${LOG}"

echo "Log written to ${LOG}"
