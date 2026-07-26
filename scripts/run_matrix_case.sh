#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/run_matrix_case.sh <config> <resolution> <days>

Configs:
  fortran_16cpu
  fv_cuda_a_grid_1gpu
  fv_cuda_a_grid_4gpu
  fv_cuda_a_grid_16gpu

Examples:
  CONTAINER=/lscratch/jli30/isca-sandbox \
    scripts/run_matrix_case.sh fortran_16cpu T85 30

  CONTAINER=/lscratch/jli30/isca-sandbox \
    scripts/run_matrix_case.sh fv_cuda_a_grid_16gpu T170 30

The run directory must already exist. Prepare it first with:
  scripts/prepare_matrix_case.sh <config> <resolution> <days> <dt_atmos>
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$#" -ne 3 ]]; then
  usage >&2
  exit 2
fi

CONFIG="$1"
RES="$2"
DAYS="$3"

CONTAINER="${CONTAINER:-/lscratch/jli30/isca-sandbox}"
GFDL_BASE="${GFDL_BASE:-/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere}"
GFDL_WORK="${GFDL_WORK:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work}"
GFDL_DATA="${GFDL_DATA:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data}"

LEVELS="${LEVELS:-25}"
NUM_RANKS="${NUM_RANKS:-16}"
CONTAINER_CMD="${CONTAINER_CMD:-singularity}"
SRUN_MPI="${SRUN_MPI:-pmix}"

EXP_NAME="held_suarez_${CONFIG}_${RES}L${LEVELS}_${DAYS}day"
RUN_DIR="${GFDL_WORK}/experiment/${EXP_NAME}/run"
LOG="${GFDL_BASE}/logs/matrix_${RES}L${LEVELS}_${CONFIG}_${DAYS}day.log"

case "${CONFIG}" in
  fortran_16cpu)
    EXECUTABLE_NAME="held_suarez.x"
    GFDL_ENV_INNER="ubuntu_conda"
    ENV_SOURCE="/isca/src/extra/env/ubuntu_conda"
    CONTAINER_GPU_FLAG=()
    NTASKS_PER_NODE="${NTASKS_PER_NODE:-16}"
    GPU_ENV='unset FV_KERNELS_CUDA_MODE FV_KERNELS_RESIDENT_BOUNDARY FV_KERNELS_RESIDENT_STATIC_METRICS FV_KERNELS_RESIDENT_Q1_TRANSFER FV_KERNELS_PROFILE FV_KERNELS_GPU_MAPPING FV_KERNELS_REQUIRE_UNIQUE_GPU'
    ;;
  fv_cuda_a_grid_1gpu)
    EXECUTABLE_NAME="held_suarez_fv_kernels_cuda.x"
    GFDL_ENV_INNER="hybrid"
    ENV_SOURCE="${GFDL_BASE}/src/extra/env/hybrid"
    CONTAINER_GPU_FLAG=(--nv)
    NTASKS_PER_NODE="${NTASKS_PER_NODE:-16}"
    GPU_ENV='export FV_KERNELS_CUDA_MODE=resident; export FV_KERNELS_RESIDENT_BOUNDARY=a_grid; export FV_KERNELS_RESIDENT_STATIC_METRICS=1; export FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only; export FV_KERNELS_PROFILE=1; export FV_KERNELS_GPU_MAPPING=local_rank; export FV_KERNELS_REQUIRE_UNIQUE_GPU=0'
    ;;
  fv_cuda_a_grid_4gpu)
    EXECUTABLE_NAME="held_suarez_fv_kernels_cuda.x"
    GFDL_ENV_INNER="hybrid"
    ENV_SOURCE="${GFDL_BASE}/src/extra/env/hybrid"
    CONTAINER_GPU_FLAG=(--nv)
    NTASKS_PER_NODE="${NTASKS_PER_NODE:-4}"
    GPU_ENV='export FV_KERNELS_CUDA_MODE=resident; export FV_KERNELS_RESIDENT_BOUNDARY=a_grid; export FV_KERNELS_RESIDENT_STATIC_METRICS=1; export FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only; export FV_KERNELS_PROFILE=1; export FV_KERNELS_GPU_MAPPING=local_rank; export FV_KERNELS_REQUIRE_UNIQUE_GPU=0'
    ;;
  fv_cuda_a_grid_16gpu)
    EXECUTABLE_NAME="held_suarez_fv_kernels_cuda.x"
    GFDL_ENV_INNER="hybrid"
    ENV_SOURCE="${GFDL_BASE}/src/extra/env/hybrid"
    CONTAINER_GPU_FLAG=(--nv)
    NTASKS_PER_NODE="${NTASKS_PER_NODE:-1}"
    GPU_ENV='export FV_KERNELS_CUDA_MODE=resident; export FV_KERNELS_RESIDENT_BOUNDARY=a_grid; export FV_KERNELS_RESIDENT_STATIC_METRICS=1; export FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only; export FV_KERNELS_PROFILE=1; export FV_KERNELS_GPU_MAPPING=local_rank; export FV_KERNELS_REQUIRE_UNIQUE_GPU=1'
    ;;
  *)
    echo "Unknown config: ${CONFIG}" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ ! -d "${RUN_DIR}" ]]; then
  echo "Run directory does not exist: ${RUN_DIR}" >&2
  echo "Prepare it first, for example:" >&2
  echo "  scripts/prepare_matrix_case.sh ${CONFIG} ${RES} ${DAYS} <dt_atmos>" >&2
  exit 1
fi

if [[ ! -x "${RUN_DIR}/${EXECUTABLE_NAME}" ]]; then
  echo "Executable missing or not executable: ${RUN_DIR}/${EXECUTABLE_NAME}" >&2
  echo "Re-run prepare step or rebuild the executable." >&2
  exit 1
fi

mkdir -p "${GFDL_BASE}/logs"

{
  echo "=== Run Held-Suarez matrix case ==="
  echo "start_timestamp=$(date -Is)"
  echo "config=${CONFIG}"
  echo "resolution=${RES}"
  echo "levels=${LEVELS}"
  echo "days=${DAYS}"
  echo "num_ranks=${NUM_RANKS}"
  echo "ntasks_per_node=${NTASKS_PER_NODE}"
  echo "container=${CONTAINER}"
  echo "GFDL_BASE=${GFDL_BASE}"
  echo "GFDL_WORK=${GFDL_WORK}"
  echo "GFDL_DATA=${GFDL_DATA}"
  echo "experiment=${EXP_NAME}"
  echo "run_dir=${RUN_DIR}"
  echo "executable=${RUN_DIR}/${EXECUTABLE_NAME}"
  echo "log=${LOG}"
} | tee "${LOG}"

srun --mpi="${SRUN_MPI}" -n "${NUM_RANKS}" --ntasks-per-node="${NTASKS_PER_NODE}" \
  "${CONTAINER_CMD}" exec "${CONTAINER_GPU_FLAG[@]}" \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "${CONTAINER}" \
  bash -lc "
set -e
export GFDL_BASE='${GFDL_BASE}'
export GFDL_WORK='${GFDL_WORK}'
export GFDL_DATA='${GFDL_DATA}'
export GFDL_ENV='${GFDL_ENV_INNER}'
${GPU_ENV}
source '${ENV_SOURCE}'
cd '${RUN_DIR}'
echo hostname=\$(hostname)
echo CUDA_VISIBLE_DEVICES=\${CUDA_VISIBLE_DEVICES:-}
if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi -L || true; fi
./'${EXECUTABLE_NAME}'
" 2>&1 | tee -a "${LOG}"

{
  echo "end_timestamp=$(date -Is)"
  echo "output=${GFDL_DATA}/${EXP_NAME}/run0001/atmos_monthly.nc"
  echo "log=${LOG}"
} | tee -a "${LOG}"
