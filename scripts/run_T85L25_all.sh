#!/usr/bin/env bash
set -euo pipefail

# Run the three T85L25 forcing performance cases sequentially.
#
# This script assumes the correct executables already exist:
# - held_suarez_fortran.x for the all-Fortran run,
# - CUDA-enabled held_suarez_hybrid.x for both hybrid runs.
#
# CPU and CUDA hybrid runs select the backend with HS_FORCE_BACKEND=cpu/cuda.
# A CUDA-enabled hybrid executable can still run the CPU C++ backend.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

mkdir -p logs
LOG="logs/T85L25_all_30day.log"
exec > >(tee "${LOG}") 2>&1

echo "=== T85L25 all forcing performance runs ==="
echo "start_timestamp=$(date -Is)"
echo "T85_OVERWRITE=${T85_OVERWRITE:-0}"

echo "=== 1/3 all-Fortran ==="
scripts/run_T85L25_fortran_30day.sh

echo "=== 2/3 CPU C++ hybrid ==="
scripts/run_T85L25_cpu_hybrid_30day.sh

if [[ "${T85_SKIP_CUDA:-0}" == "1" ]]; then
  echo "T85_SKIP_CUDA=1; stopping before CUDA hybrid run."
  exit 0
fi

echo "=== 3/3 CUDA hybrid ==="
scripts/run_T85L25_cuda_hybrid_30day.sh

echo "end_timestamp=$(date -Is)"
echo "Log written to ${LOG}"
