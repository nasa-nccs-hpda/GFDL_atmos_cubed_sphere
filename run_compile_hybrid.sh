#!/bin/bash
set -euo pipefail

CONTAINER=/lscratch/jli30/isca-sandbox

export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
export USE_CUDA_HS_FORCE=${USE_CUDA_HS_FORCE:-0}
export NVCC=${NVCC:-nvcc}

mkdir -p "${GFDL_BASE}/logs"
LOG="${GFDL_BASE}/logs/hybrid_compile_$(date +%Y%m%d_%H%M%S).log"
LATEST="${GFDL_BASE}/logs/hybrid_compile_latest.log"

set +e
apptainer exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  ${CONTAINER} \
  bash -lc "
set -e

export GFDL_BASE=${GFDL_BASE}
export GFDL_WORK=${GFDL_WORK}
export GFDL_DATA=${GFDL_DATA}
export GFDL_ENV=hybrid
export USE_CUDA_HS_FORCE=${USE_CUDA_HS_FORCE}
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
echo 'USE_CUDA_HS_FORCE=' \${USE_CUDA_HS_FORCE}
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
