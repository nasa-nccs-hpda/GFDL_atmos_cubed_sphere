#!/usr/bin/env bash
set -euo pipefail

# Host-side wrapper for the T85L25 CUDA hybrid forcing smoke test.
# This enters the Isca Apptainer container with --nv, then runs the
# container-side script at scripts/run_T85L25_cuda_smoke.sh.

CONTAINER="${CONTAINER:-/lscratch/jli30/isca-sandbox}"

export GFDL_BASE="${GFDL_BASE:-/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere}"
export GFDL_WORK="${GFDL_WORK:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work}"
export GFDL_DATA="${GFDL_DATA:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data}"
export NVCC="${NVCC:-nvcc}"
export GFDL_ENV=hybrid

mkdir -p "${GFDL_BASE}/logs"

echo "=== Launching T85L25 CUDA smoke test in Apptainer ==="
echo "CONTAINER=${CONTAINER}"
echo "GFDL_BASE=${GFDL_BASE}"
echo "GFDL_WORK=${GFDL_WORK}"
echo "GFDL_DATA=${GFDL_DATA}"
echo "GFDL_ENV=${GFDL_ENV}"

apptainer exec --nv \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  "${CONTAINER}" \
  bash -lc "
set -e
export GFDL_BASE='${GFDL_BASE}'
export GFDL_WORK='${GFDL_WORK}'
export GFDL_DATA='${GFDL_DATA}'
export GFDL_ENV='${GFDL_ENV}'
export NVCC='${NVCC}'
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd '${GFDL_BASE}'
scripts/run_T85L25_cuda_smoke.sh
"
