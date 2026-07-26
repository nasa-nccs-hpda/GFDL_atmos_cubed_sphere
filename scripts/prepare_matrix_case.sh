#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/prepare_matrix_case.sh <config> <resolution> <days> <dt_atmos>

Configs:
  fortran_16cpu
  fv_cuda_a_grid_1gpu
  fv_cuda_a_grid_4gpu
  fv_cuda_a_grid_16gpu

Examples:
  CONTAINER=/lscratch/jli30/isca-sandbox \
    scripts/prepare_matrix_case.sh fortran_16cpu T85 30 300

  CONTAINER=/lscratch/jli30/isca-sandbox \
    scripts/prepare_matrix_case.sh fv_cuda_a_grid_16gpu T170 30 150

This script writes the Isca run directory and copies the selected executable.
It does not launch the model.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$#" -ne 4 ]]; then
  usage >&2
  exit 2
fi

CONFIG="$1"
RES="$2"
DAYS="$3"
DT="$4"

CONTAINER="${CONTAINER:-/lscratch/jli30/isca-sandbox}"
GFDL_BASE="${GFDL_BASE:-/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere}"
GFDL_WORK="${GFDL_WORK:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work}"
GFDL_DATA="${GFDL_DATA:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data}"

LEVELS="${LEVELS:-25}"
NUM_CORES="${NUM_CORES:-16}"
CONTAINER_CMD="${CONTAINER_CMD:-singularity}"

case "${CONFIG}" in
  fortran_16cpu)
    EXECUTABLE_NAME="held_suarez.x"
    CODEBASE_DIR="/isca"
    GFDL_ENV_INNER="ubuntu_conda"
    CONTAINER_GPU_FLAG=()
    ;;
  fv_cuda_a_grid_1gpu|fv_cuda_a_grid_4gpu|fv_cuda_a_grid_16gpu)
    EXECUTABLE_NAME="held_suarez_fv_kernels_cuda.x"
    CODEBASE_DIR=""
    GFDL_ENV_INNER="hybrid"
    CONTAINER_GPU_FLAG=(--nv)
    ;;
  *)
    echo "Unknown config: ${CONFIG}" >&2
    usage >&2
    exit 2
    ;;
esac

EXP_NAME="held_suarez_${CONFIG}_${RES}L${LEVELS}_${DAYS}day"
LOG="${GFDL_BASE}/logs/prepare_matrix_${RES}L${LEVELS}_${CONFIG}_${DAYS}day.log"

mkdir -p "${GFDL_BASE}/logs"

echo "=== Prepare Held-Suarez matrix case ===" | tee "${LOG}"
echo "config=${CONFIG}" | tee -a "${LOG}"
echo "resolution=${RES}" | tee -a "${LOG}"
echo "levels=${LEVELS}" | tee -a "${LOG}"
echo "days=${DAYS}" | tee -a "${LOG}"
echo "dt_atmos=${DT}" | tee -a "${LOG}"
echo "num_cores=${NUM_CORES}" | tee -a "${LOG}"
echo "container=${CONTAINER}" | tee -a "${LOG}"
echo "GFDL_BASE=${GFDL_BASE}" | tee -a "${LOG}"
echo "GFDL_WORK=${GFDL_WORK}" | tee -a "${LOG}"
echo "GFDL_DATA=${GFDL_DATA}" | tee -a "${LOG}"
echo "experiment=${EXP_NAME}" | tee -a "${LOG}"
echo "executable=${EXECUTABLE_NAME}" | tee -a "${LOG}"

codebase_arg=()
if [[ -n "${CODEBASE_DIR}" ]]; then
  codebase_arg=(--codebase-dir "${CODEBASE_DIR}")
fi

"${CONTAINER_CMD}" exec "${CONTAINER_GPU_FLAG[@]}" \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "${CONTAINER}" \
  bash -lc "
set -e
export GFDL_BASE='${GFDL_BASE}'
export GFDL_WORK='${GFDL_WORK}'
export GFDL_DATA='${GFDL_DATA}'
export GFDL_ENV='${GFDL_ENV_INNER}'
cd '${GFDL_BASE}'
python3 scripts/run_T85L25_case.py \
  --exp-name '${EXP_NAME}' \
  --executable-name '${EXECUTABLE_NAME}' \
  --backend-label '${CONFIG}' \
  ${codebase_arg[*]} \
  --resolution '${RES}' \
  --levels '${LEVELS}' \
  --dt-atmos '${DT}' \
  --days '${DAYS}' \
  --num-cores '${NUM_CORES}' \
  --overwrite \
  --prepare-only
" 2>&1 | tee -a "${LOG}"

echo "prepared_run_dir=${GFDL_WORK}/experiment/${EXP_NAME}/run" | tee -a "${LOG}"
echo "log=${LOG}" | tee -a "${LOG}"
