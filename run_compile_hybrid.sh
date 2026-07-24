#!/bin/bash
set -euo pipefail

CONTAINER=${CONTAINER:-/lscratch/jacaraba/isca-sandbox}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_PROJECT_ROOT=/explore/nobackup/people/jacaraba/projects/AgenticAI

export GFDL_BASE=${GFDL_BASE_OVERRIDE:-${SCRIPT_DIR}}
export GFDL_WORK=${GFDL_WORK:-${DEFAULT_PROJECT_ROOT}/isca_work}
export GFDL_DATA=${GFDL_DATA:-${DEFAULT_PROJECT_ROOT}/isca_data}
export USE_CUDA_HS_FORCE=${USE_CUDA_HS_FORCE:-0}
export HYBRID_FORCE_CLEAN_NATIVE=${HYBRID_FORCE_CLEAN_NATIVE:-1}
export NVCC=${NVCC:-nvcc}
export APPTAINER_BIND_ROOT=${APPTAINER_BIND_ROOT:-/explore/nobackup/people/jacaraba}
if [ "${USE_CUDA_HS_FORCE}" = "1" ]; then
  export GFDL_MKMF_TEMPLATE=hybrid_cuda
fi

mkdir -p "${GFDL_BASE}/logs"
LOG="${GFDL_BASE}/logs/hybrid_compile_$(date +%Y%m%d_%H%M%S).log"
LATEST="${GFDL_BASE}/logs/hybrid_compile_latest.log"

set +e
apptainer exec --nv \
  --bind "${APPTAINER_BIND_ROOT}:${APPTAINER_BIND_ROOT}" \
  ${CONTAINER} \
  bash -lc "
set -e

export GFDL_BASE=${GFDL_BASE}
export GFDL_WORK=${GFDL_WORK}
export GFDL_DATA=${GFDL_DATA}
export GFDL_ENV=hybrid
export USE_CUDA_HS_FORCE=${USE_CUDA_HS_FORCE}
export HYBRID_FORCE_CLEAN_NATIVE=${HYBRID_FORCE_CLEAN_NATIVE}
export NVCC=${NVCC}
if [ "\${USE_CUDA_HS_FORCE}" = "1" ]; then
  export GFDL_MKMF_TEMPLATE=hybrid_cuda
fi

export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none

echo '=== Inside container ==='
uname -m

echo 'python3=' \$(command -v python3 || true)
echo 'mpifort=' \$(command -v mpifort || true)
echo 'mpicc=' \$(command -v mpicc || true)
echo 'nc-config=' \$(command -v nc-config || true)
echo 'nf-config=' \$(command -v nf-config || true)
echo 'USE_CUDA_HS_FORCE=' \${USE_CUDA_HS_FORCE}
echo 'HYBRID_FORCE_CLEAN_NATIVE=' \${HYBRID_FORCE_CLEAN_NATIVE}
echo 'GFDL_MKMF_TEMPLATE=' \${GFDL_MKMF_TEMPLATE:-}
echo 'NVCC=' \$(command -v \${NVCC} || true)

cd ${GFDL_BASE}
mkdir -p logs
echo '=== Compile hybrid Held-Suarez ==='

python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py hybrid
" 2>&1 | tee "${LOG}"
status=${PIPESTATUS[0]}
set -e

ln -sfn "$(basename "${LOG}")" "${LATEST}"
exit ${status}
