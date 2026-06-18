#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-/lscratch/jli30/isca-sandbox}"
export GFDL_BASE="${GFDL_BASE:-/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere}"
export GFDL_WORK="${GFDL_WORK:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work}"
export GFDL_DATA="${GFDL_DATA:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data}"
export T85_OVERWRITE="${T85_OVERWRITE:-0}"

LOG="${GFDL_BASE}/logs/T85L25_hybrid_cpu_30day.log"
mkdir -p "${GFDL_BASE}/logs"
exec > >(tee "${LOG}") 2>&1

echo "=== T85L25 CPU C++ hybrid forcing 30-day run ==="
echo "start_timestamp=$(date -Is)"
echo "CONTAINER=${CONTAINER}"
echo "GFDL_BASE=${GFDL_BASE}"
echo "GFDL_WORK=${GFDL_WORK}"
echo "GFDL_DATA=${GFDL_DATA}"
echo "T85_OVERWRITE=${T85_OVERWRITE}"

overwrite_arg=()
if [[ "${T85_OVERWRITE}" == "1" ]]; then
  overwrite_arg=(--overwrite)
fi

apptainer exec \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "${CONTAINER}" \
  bash -lc "
set -e
export GFDL_BASE='${GFDL_BASE}'
export GFDL_WORK='${GFDL_WORK}'
export GFDL_DATA='${GFDL_DATA}'
export GFDL_ENV=hybrid
export HS_FORCE_BACKEND=cpu
export HS_PROFILE=1
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd '${GFDL_BASE}'
time python3 scripts/run_T85L25_case.py \
  --exp-name held_suarez_hybrid_cpu_T85L25 \
  --executable-name held_suarez_hybrid.x \
  --backend-label cpu_cpp_hybrid \
  --resolution T85 \
  --levels 25 \
  --dt-atmos 300 \
  --days 30 \
  --num-cores 16 \
  ${overwrite_arg[*]}
"

echo "end_timestamp=$(date -Is)"
echo "Log written to ${LOG}"
