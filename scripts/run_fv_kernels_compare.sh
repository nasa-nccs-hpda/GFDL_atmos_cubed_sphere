#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Run comparable Held-Suarez FV kernel CPU and CUDA experiments.

Defaults reproduce the current performance comparison:
  CPU C++ FV bundle vs resident CUDA FV bundle, 30 days, 16 MPI ranks.

Usage:
  scripts/run_fv_kernels_compare.sh [options]

Options:
  --no-build              Skip native executable builds.
  --no-fixture            Skip standalone translated-kernel fixture checks.
  --no-run                Skip model runs.
  --no-validate           Skip NetCDF validation.
  --cuda-mode MODE        stateless, persistent, or resident. Default: resident.
  --days N                Simulation length. Default: 30.
  --num-cores N           MPI rank count. Default: 16.
  --overwrite             Overwrite existing run0001 outputs.
  --production-diag       Use production diagnostic cadence. Default for 30 days.
  --smoke-diag            Use daily diagnostics instead of production cadence.
  -h, --help              Show this help.

Environment:
  CONTAINER               Apptainer/Singularity image. Default: /lscratch/jli30/isca-sandbox
  GFDL_BASE               Repository path inside the container. Default: this repo.
  GFDL_WORK               Isca work directory.
  GFDL_DATA               Isca data/output directory.
  NVCC                    CUDA compiler inside the container. Default: /usr/local/cuda/bin/nvcc
  APPTAINER_BIND          Extra bind args, e.g. "--bind /host:/container".
  FV_KERNELS_PROFILE      Enable kernel profile counters. Default: 1.

Examples:
  FV_KERNELS_OVERWRITE=1 scripts/run_fv_kernels_compare.sh
  scripts/run_fv_kernels_compare.sh --cuda-mode persistent --no-build
  scripts/run_fv_kernels_compare.sh --days 1 --overwrite --no-validate --smoke-diag
USAGE
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

CONTAINER="${CONTAINER:-/lscratch/jli30/isca-sandbox}"
GFDL_BASE="${GFDL_BASE:-${REPO_ROOT}}"
GFDL_WORK="${GFDL_WORK:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work}"
GFDL_DATA="${GFDL_DATA:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data}"
NVCC="${NVCC:-/usr/local/cuda/bin/nvcc}"
FV_KERNELS_PROFILE="${FV_KERNELS_PROFILE:-1}"
FV_KERNELS_OVERWRITE="${FV_KERNELS_OVERWRITE:-0}"
APPTAINER_BIND="${APPTAINER_BIND:-}"

DO_BUILD=1
DO_FIXTURE=1
DO_RUN=1
DO_VALIDATE=1
CUDA_MODE="resident"
DAYS=30
NUM_CORES=16
PRODUCTION_DIAG=auto

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build)
      DO_BUILD=0
      ;;
    --no-fixture)
      DO_FIXTURE=0
      ;;
    --no-run)
      DO_RUN=0
      ;;
    --no-validate)
      DO_VALIDATE=0
      ;;
    --cuda-mode)
      CUDA_MODE="${2:?--cuda-mode requires stateless, persistent, or resident}"
      shift
      ;;
    --days)
      DAYS="${2:?--days requires an integer}"
      shift
      ;;
    --num-cores)
      NUM_CORES="${2:?--num-cores requires an integer}"
      shift
      ;;
    --overwrite)
      FV_KERNELS_OVERWRITE=1
      ;;
    --production-diag)
      PRODUCTION_DIAG=1
      ;;
    --smoke-diag)
      PRODUCTION_DIAG=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "${CUDA_MODE}" in
  stateless|persistent|resident)
    ;;
  *)
    echo "Invalid --cuda-mode '${CUDA_MODE}'; expected stateless, persistent, or resident." >&2
    exit 2
    ;;
esac

if [[ "${PRODUCTION_DIAG}" == "auto" ]]; then
  if [[ "${DAYS}" -ge 30 ]]; then
    PRODUCTION_DIAG=1
  else
    PRODUCTION_DIAG=0
  fi
fi

if [[ "${CUDA_MODE}" == "stateless" ]]; then
  CUDA_EXP="held_suarez_fv_kernels_cuda_${DAYS}day"
  CUDA_LOG_STEM="fv_kernels_cuda_${DAYS}day"
  CUDA_FIXTURE_TARGET="cuda_check"
else
  CUDA_EXP="held_suarez_fv_kernels_cuda_${CUDA_MODE}_${DAYS}day"
  CUDA_LOG_STEM="fv_kernels_cuda_${CUDA_MODE}_${DAYS}day"
  CUDA_FIXTURE_TARGET="cuda_${CUDA_MODE}_check"
fi

CPU_EXP="held_suarez_fv_kernels_${DAYS}day"
CPU_LOG_STEM="fv_kernels_cpu_${DAYS}day"
RUN_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${GFDL_BASE}/logs"
mkdir -p "${LOG_DIR}" "${GFDL_BASE}/tests/reports"
LOG="${LOG_DIR}/fv_kernels_compare_${CUDA_MODE}_${DAYS}day_${RUN_TIMESTAMP}.log"
LATEST="${LOG_DIR}/fv_kernels_compare_${CUDA_MODE}_${DAYS}day_latest.log"

echo "Writing detailed log to ${LOG}"
exec > "${LOG}" 2>&1

echo "=== Held-Suarez FV kernel CPU vs CUDA comparison ==="
echo "start_timestamp=$(date -Is)"
echo "repo=${REPO_ROOT}"
echo "CONTAINER=${CONTAINER}"
echo "GFDL_BASE=${GFDL_BASE}"
echo "GFDL_WORK=${GFDL_WORK}"
echo "GFDL_DATA=${GFDL_DATA}"
echo "NVCC=${NVCC}"
echo "APPTAINER_BIND=${APPTAINER_BIND}"
echo "cuda_mode=${CUDA_MODE}"
echo "days=${DAYS}"
echo "num_cores=${NUM_CORES}"
echo "production_diag=${PRODUCTION_DIAG}"
echo "overwrite=${FV_KERNELS_OVERWRITE}"
echo "profile=${FV_KERNELS_PROFILE}"
echo "cpu_experiment=${CPU_EXP}"
echo "cuda_experiment=${CUDA_EXP}"

if [[ "${DO_BUILD}" == "1" || "${DO_FIXTURE}" == "1" || "${DO_RUN}" == "1" ]]; then
  if ! command -v apptainer >/dev/null 2>&1; then
    echo "apptainer was not found on PATH. Run this on the CUDA-enabled Isca host/container node." >&2
    exit 127
  fi
  if [[ -z "${APPTAINER_BIND}" ]]; then
    for bind_dir in "${GFDL_BASE}" "${GFDL_WORK}" "${GFDL_DATA}"; do
      if [[ ! -d "${bind_dir}" ]]; then
        echo "Bind directory does not exist on the host: ${bind_dir}" >&2
        echo "Set GFDL_BASE/GFDL_WORK/GFDL_DATA or provide APPTAINER_BIND explicitly." >&2
        exit 2
      fi
    done
  fi
fi

apptainer_cmd=(apptainer exec --nv)
if [[ -n "${APPTAINER_BIND}" ]]; then
  # shellcheck disable=SC2206
  extra_bind=(${APPTAINER_BIND})
  apptainer_cmd+=("${extra_bind[@]}")
else
  apptainer_cmd+=(--bind "${GFDL_BASE}:${GFDL_BASE}")
  apptainer_cmd+=(--bind "${GFDL_WORK}:${GFDL_WORK}")
  apptainer_cmd+=(--bind "${GFDL_DATA}:${GFDL_DATA}")
fi
apptainer_cmd+=("${CONTAINER}")

container_run() {
  local script="$1"
  "${apptainer_cmd[@]}" bash -lc "${script}"
}

common_env="
set -e
export GFDL_BASE='${GFDL_BASE}'
export GFDL_WORK='${GFDL_WORK}'
export GFDL_DATA='${GFDL_DATA}'
export GFDL_ENV=hybrid
export FV_KERNELS_PROFILE='${FV_KERNELS_PROFILE}'
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd '${GFDL_BASE}'
"

if [[ "${DO_BUILD}" == "1" ]]; then
  echo "=== Build CPU FV kernel executable ==="
  container_run "${common_env}
export USE_CUDA_FV_ADVECTION_KERNELS=0
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py fv_kernels
"

  echo "=== Build CUDA FV kernel executable ==="
  container_run "${common_env}
export USE_CUDA_FV_ADVECTION_KERNELS=1
export NVCC='${NVCC}'
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py fv_kernels_cuda
"
fi

if [[ "${DO_FIXTURE}" == "1" ]]; then
  echo "=== Standalone CPU fixture check ==="
  container_run "${common_env}
cd translated/held_suarez/cpp/fv_advection/kernels
make check
"

  echo "=== Standalone CUDA fixture check: ${CUDA_FIXTURE_TARGET} ==="
  container_run "${common_env}
export NVCC='${NVCC}'
cd translated/held_suarez/cpp/fv_advection/kernels
make USE_CUDA_FV_ADVECTION_KERNELS=1 ${CUDA_FIXTURE_TARGET}
"
fi

overwrite_arg=""
if [[ "${FV_KERNELS_OVERWRITE}" == "1" ]]; then
  overwrite_arg="--overwrite"
fi

diag_arg=""
if [[ "${PRODUCTION_DIAG}" == "1" ]]; then
  diag_arg="--production-diag"
fi

if [[ "${DO_RUN}" == "1" ]]; then
  echo "=== GPU visibility ==="
  container_run "${common_env}
nvidia-smi -L || true
"

  echo "=== Run CPU model experiment ==="
  container_run "${common_env}
time python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name held_suarez_fv_kernels.x \
  --exp-name '${CPU_EXP}' \
  --days '${DAYS}' \
  ${diag_arg} \
  --num-cores '${NUM_CORES}' \
  ${overwrite_arg}
" | tee "${LOG_DIR}/${CPU_LOG_STEM}.log"

  echo "=== Run CUDA model experiment: ${CUDA_MODE} ==="
  container_run "${common_env}
export FV_KERNELS_CUDA_MODE='${CUDA_MODE}'
time python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name held_suarez_fv_kernels_cuda.x \
  --exp-name '${CUDA_EXP}' \
  --days '${DAYS}' \
  ${diag_arg} \
  --num-cores '${NUM_CORES}' \
  ${overwrite_arg}
" | tee "${LOG_DIR}/${CUDA_LOG_STEM}.log"
fi

if [[ "${DO_VALIDATE}" == "1" ]]; then
  if [[ "${PRODUCTION_DIAG}" != "1" ]]; then
    echo "Skipping validation: production diagnostics are disabled for this run."
  elif [[ "${DAYS}" -lt 30 ]]; then
    echo "Skipping validation: ${DAYS}-day production-diagnostic output can contain fill values."
  else
    echo "=== Validate 30-day NetCDF outputs ==="
    python3 "${GFDL_BASE}/tests/validate_T85L25_forcing_outputs.py" \
      --fortran-exp held_suarez_default \
      --cpu-exp "${CPU_EXP}" \
      --cuda-exp "${CUDA_EXP}" \
      --run 1 \
      --filename atmos_monthly.nc \
      --data-root "${GFDL_DATA}" \
      --markdown-out "${GFDL_BASE}/tests/reports/fv_kernels_${CUDA_MODE}_${DAYS}day_vs_cpu_validation.md" \
      --json-out "${GFDL_BASE}/tests/reports/fv_kernels_${CUDA_MODE}_${DAYS}day_vs_cpu_validation.json"
  fi
fi

ln -sfn "$(basename "${LOG}")" "${LATEST}"
echo "end_timestamp=$(date -Is)"
echo "log=${LOG}"
