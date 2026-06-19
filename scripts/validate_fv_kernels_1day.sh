#!/usr/bin/env bash
set -euo pipefail

export GFDL_BASE="${GFDL_BASE:-/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere}"
export GFDL_DATA="${GFDL_DATA:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data}"

LOG="${GFDL_BASE}/logs/fv_kernels_1day_model_validation.log"
mkdir -p "${GFDL_BASE}/logs" "${GFDL_BASE}/tests/reports"

cd "${GFDL_BASE}"
python3 tests/validate_T85L25_forcing_outputs.py \
  --fortran-exp held_suarez_fortran_1day_baseline \
  --cpu-exp held_suarez_fv_kernels_1day \
  --cuda-exp held_suarez_fv_kernels_cuda_1day \
  --run 1 \
  --filename atmos_monthly.nc \
  --data-root "${GFDL_DATA}" \
  --markdown-out tests/reports/fv_advection_kernels_1day_model_validation_report.md \
  --json-out tests/reports/fv_advection_kernels_1day_model_validation_report.json \
  2>&1 | tee "${LOG}"

