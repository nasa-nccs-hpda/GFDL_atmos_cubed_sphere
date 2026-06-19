#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-/lscratch/jli30/isca-sandbox}"
export GFDL_BASE="${GFDL_BASE:-/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere}"
export GFDL_WORK="${GFDL_WORK:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work}"
export GFDL_DATA="${GFDL_DATA:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data}"
export FV_SEMI_Y_OVERWRITE="${FV_SEMI_Y_OVERWRITE:-0}"

LOG="${GFDL_BASE}/logs/fv_semi_y_cpu_30day.log"
mkdir -p "${GFDL_BASE}/logs"
exec > >(tee "${LOG}") 2>&1

echo "=== Held-Suarez semi_y_3d CPU C++ overlay 30-day run ==="
echo "start_timestamp=$(date -Is)"
echo "CONTAINER=${CONTAINER}"
echo "GFDL_BASE=${GFDL_BASE}"
echo "GFDL_WORK=${GFDL_WORK}"
echo "GFDL_DATA=${GFDL_DATA}"
echo "FV_SEMI_Y_OVERWRITE=${FV_SEMI_Y_OVERWRITE}"
echo "executable=held_suarez_fv_semi_y_3d.x"
echo "experiment=held_suarez_fv_semi_y_3d_30day"

overwrite_arg=()
if [[ "${FV_SEMI_Y_OVERWRITE}" == "1" ]]; then
  overwrite_arg=(--overwrite)
fi

apptainer exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "${CONTAINER}" \
  bash -lc "
set -e
export GFDL_BASE='${GFDL_BASE}'
export GFDL_WORK='${GFDL_WORK}'
export GFDL_DATA='${GFDL_DATA}'
export GFDL_ENV=hybrid
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd '${GFDL_BASE}'
time python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name held_suarez_fv_semi_y_3d.x \
  --exp-name held_suarez_fv_semi_y_3d_30day \
  --days 30 \
  --production-diag \
  --num-cores 16 \
  ${overwrite_arg[*]}
"

echo "end_timestamp=$(date -Is)"
echo "Log written to ${LOG}"
