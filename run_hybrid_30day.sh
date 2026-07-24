#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-/lscratch/jacaraba/isca-sandbox}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_PROJECT_ROOT=/explore/nobackup/people/jacaraba/projects/AgenticAI

export GFDL_BASE="${GFDL_BASE:-${SCRIPT_DIR}}"
export GFDL_WORK="${GFDL_WORK:-${DEFAULT_PROJECT_ROOT}/isca_work}"
export GFDL_DATA="${GFDL_DATA:-${DEFAULT_PROJECT_ROOT}/isca_data}"
export HYBRID_OVERWRITE="${HYBRID_OVERWRITE:-0}"
export HYBRID_NUM_CORES="${HYBRID_NUM_CORES:-16}"
export HS_FORCE_BACKEND="${HS_FORCE_BACKEND:-cpu}"
export HS_PROFILE="${HS_PROFILE:-1}"
export HS_FORCE_COPY_TEQ="${HS_FORCE_COPY_TEQ:-0}"
export APPTAINER_BIND_ROOT="${APPTAINER_BIND_ROOT:-/explore/nobackup/people/jacaraba}"

LOG="${GFDL_BASE}/logs/hybrid_${HS_FORCE_BACKEND}_30day.log"
mkdir -p "${GFDL_BASE}/logs"
exec > >(tee "${LOG}") 2>&1

echo "=== Held-Suarez hybrid 30-day run ==="
echo "start_timestamp=$(date -Is)"
echo "CONTAINER=${CONTAINER}"
echo "GFDL_BASE=${GFDL_BASE}"
echo "GFDL_WORK=${GFDL_WORK}"
echo "GFDL_DATA=${GFDL_DATA}"
echo "HYBRID_OVERWRITE=${HYBRID_OVERWRITE}"
echo "HYBRID_NUM_CORES=${HYBRID_NUM_CORES}"
echo "HS_FORCE_BACKEND=${HS_FORCE_BACKEND}"
echo "HS_PROFILE=${HS_PROFILE}"
echo "HS_FORCE_COPY_TEQ=${HS_FORCE_COPY_TEQ}"

overwrite_arg=()
if [[ "${HYBRID_OVERWRITE}" == "1" ]]; then
  overwrite_arg=(--overwrite)
fi

apptainer exec --nv \
  --bind "${APPTAINER_BIND_ROOT}:${APPTAINER_BIND_ROOT}" \
  "${CONTAINER}" \
  bash -lc "
set -e
export GFDL_BASE='${GFDL_BASE}'
export GFDL_WORK='${GFDL_WORK}'
export GFDL_DATA='${GFDL_DATA}'
export GFDL_ENV=hybrid
export HS_FORCE_BACKEND='${HS_FORCE_BACKEND}'
export HS_PROFILE='${HS_PROFILE}'
export HS_FORCE_COPY_TEQ='${HS_FORCE_COPY_TEQ}'
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd '${GFDL_BASE}'
time python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name held_suarez_hybrid.x \
  --exp-name 'held_suarez_hybrid_${HS_FORCE_BACKEND}_30day' \
  --days 30 \
  --production-diag \
  --num-cores '${HYBRID_NUM_CORES}' \
  ${overwrite_arg[*]}
"

echo "end_timestamp=$(date -Is)"
echo "Log written to ${LOG}"
