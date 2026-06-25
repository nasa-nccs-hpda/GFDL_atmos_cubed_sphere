#!/bin/bash
set -euo pipefail

CONTAINER=${CONTAINER:-/lscratch/rlgill/isca-debian_latest}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

export GFDL_BASE=${GFDL_BASE_OVERRIDE:-${SCRIPT_DIR}}
export GFDL_WORK=${GFDL_WORK:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_work}
export GFDL_DATA=${GFDL_DATA:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data}
export USE_CUDA_FV_ADVECTION_KERNELS=${USE_CUDA_FV_ADVECTION_KERNELS:-0}
export NVCC=${NVCC:-nvcc}

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
if [ "${USE_CUDA_FV_ADVECTION_KERNELS}" = "1" ]; then
  TARGET=fv_kernels_cuda
  TEMPLATE=fv_kernels_hybrid_cuda
  LOG_PREFIX=fv_kernels_cuda_compile
else
  TARGET=fv_kernels
  TEMPLATE=fv_kernels_hybrid
  LOG_PREFIX=fv_kernels_compile
fi

LOG="${LOG_DIR}/${LOG_PREFIX}_$(date +%Y%m%d_%H%M%S).log"
LATEST="${LOG_DIR}/${LOG_PREFIX}_latest.log"

set +e
apptainer exec --nv \
  --bind /explore/nobackup/people/rlgill:/explore/nobackup/people/rlgill \
  "${CONTAINER}" \
  bash -lc "
set -e

export GFDL_BASE=${GFDL_BASE}
export GFDL_WORK=${GFDL_WORK}
export GFDL_DATA=${GFDL_DATA}
export GFDL_ENV=hybrid
export GFDL_MKMF_TEMPLATE=${TEMPLATE}
export USE_CUDA_FV_ADVECTION_KERNELS=${USE_CUDA_FV_ADVECTION_KERNELS}
export NVCC=${NVCC}

export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none

echo '=== Inside container ==='
uname -m
echo 'python3=' \$(command -v python3 || true)
echo 'mpifort=' \$(command -v mpifort || true)
echo 'mpicc=' \$(command -v mpicc || true)
echo 'nc-config=' \$(command -v nc-config || true)
echo 'nf-config=' \$(command -v nf-config || true)
echo 'g++=' \$(command -v g++ || true)
echo 'nvcc=' \$(command -v \${NVCC} || true)
echo 'USE_CUDA_FV_ADVECTION_KERNELS=' \${USE_CUDA_FV_ADVECTION_KERNELS}
echo 'GFDL_MKMF_TEMPLATE=' \${GFDL_MKMF_TEMPLATE}
echo 'TARGET=' ${TARGET}

cd ${GFDL_BASE}
mkdir -p logs
echo '=== Compile Held-Suarez fv_advection kernel-bundle overlay ==='
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py ${TARGET}
" 2>&1 | tee "${LOG}"
status=${PIPESTATUS[0]}
set -e

ln -sfn "$(basename "${LOG}")" "${LATEST}"
exit ${status}
