#!/usr/bin/env bash
set -euo pipefail

export GFDL_BASE="${GFDL_BASE:-/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere}"
export GFDL_DATA="${GFDL_DATA:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data}"

LOG="${GFDL_BASE}/logs/fv_kernels_cuda_persistent_30day_validation.log"
mkdir -p "${GFDL_BASE}/logs" "${GFDL_BASE}/tests/reports"

cd "${GFDL_BASE}"

exec > >(tee "${LOG}") 2>&1

echo '=== Persistent CUDA vs Fortran and CPU C++ ==='
python3 tests/validate_T85L25_forcing_outputs.py \
  --fortran-exp held_suarez_default \
  --cpu-exp held_suarez_fv_kernels_30day \
  --cuda-exp held_suarez_fv_kernels_cuda_persistent_30day \
  --run 1 \
  --filename atmos_monthly.nc \
  --data-root "${GFDL_DATA}" \
  --markdown-out tests/reports/fv_kernels_persistent_30day_vs_cpu_validation.md \
  --json-out tests/reports/fv_kernels_persistent_30day_vs_cpu_validation.json

echo '=== Persistent CUDA vs stateless CUDA ==='
python3 tests/validate_T85L25_forcing_outputs.py \
  --fortran-exp held_suarez_default \
  --cpu-exp held_suarez_fv_kernels_cuda_30day \
  --cuda-exp held_suarez_fv_kernels_cuda_persistent_30day \
  --run 1 \
  --filename atmos_monthly.nc \
  --data-root "${GFDL_DATA}" \
  --markdown-out tests/reports/fv_kernels_persistent_30day_vs_stateless_validation.md \
  --json-out tests/reports/fv_kernels_persistent_30day_vs_stateless_validation.json
