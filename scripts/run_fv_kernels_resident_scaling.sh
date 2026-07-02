#!/usr/bin/env bash
set -euo pipefail

# Held-Suarez resident CUDA FV-advection path: resolution-scaling sweep (task 4).
#
# Sweeps SCALING_RESOLUTIONS (RES:LEVELS:DT specs, dt scaled for CFL) and runs the
# resident CUDA executable at each, one experiment dir per resolution, with the
# FV_KERNELS_PROFILE mpp_clocks (kernel/h2d) captured in each per-resolution log.
#
# First cut (default): T85 -> T170. Add T42:25:600 later for the full primary matrix.
#   Full matrix:  SCALING_RESOLUTIONS="T42:25:600 T85:25:300 T170:25:150" scripts/run_fv_kernels_resident_scaling.sh
#
# Run from the HOST shell (self-wraps in apptainer --nv). GFDL_BASE=$PWD to use THIS branch.

CONTAINER=${CONTAINER:-/lscratch/rlgill/isca-debian_latest}
export GFDL_BASE="${GFDL_BASE:-/explore/nobackup/people/rlgill/SystemTesting/AAI/GFDL_atmos_cubed_sphere}"
export GFDL_WORK="${GFDL_WORK:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_work}"
export GFDL_DATA="${GFDL_DATA:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_data}"
export FV_KERNELS_OVERWRITE="${FV_KERNELS_OVERWRITE:-0}"
export FV_KERNELS_PROFILE="${FV_KERNELS_PROFILE:-1}"

DAYS="${SCALING_DAYS:-30}"
NUM_CORES="${SCALING_NUM_CORES:-16}"
RESOLUTIONS="${SCALING_RESOLUTIONS:-T85:25:300 T170:25:150}"
EXECUTABLE="${EXECUTABLE:-held_suarez_fv_kernels_cuda.x}"
EXP_PREFIX="${EXP_PREFIX:-held_suarez_fv_kernels_cuda_resident}"

mkdir -p "${GFDL_BASE}/logs/fv_kernels_scaling"

overwrite_arg=()
if [[ "${FV_KERNELS_OVERWRITE}" == "1" ]]; then
  overwrite_arg=(--overwrite)
fi

echo "=== Held-Suarez resident CUDA FV-advection: resolution-scaling sweep ==="
echo "start_timestamp=$(date -Is)"
echo "CONTAINER=${CONTAINER}"
echo "GFDL_BASE=${GFDL_BASE}"
echo "resolutions=${RESOLUTIONS}"
echo "days=${DAYS} num_cores=${NUM_CORES}"
echo "FV_KERNELS_CUDA_MODE=resident FV_KERNELS_PROFILE=${FV_KERNELS_PROFILE} FV_KERNELS_OVERWRITE=${FV_KERNELS_OVERWRITE}"

for spec in ${RESOLUTIONS}; do
  IFS=: read -r res levels dt <<< "${spec}"
  if [[ -z "${res}" || -z "${levels}" || -z "${dt}" ]]; then
    echo "ERROR: bad resolution spec '${spec}'. Expected RES:LEVELS:DT, e.g. T85:25:300" >&2
    exit 1
  fi
  label="${res}L${levels}"
  exp_name="${EXP_PREFIX}_${label}_${DAYS}day"
  log="${GFDL_BASE}/logs/fv_kernels_scaling/${label}_resident.log"

  echo "=== resident ${label}: exp=${exp_name} dt=${dt} log=${log} ==="

  apptainer exec --nv \
    --bind /explore/nobackup/people/rlgill:/explore/nobackup/people/rlgill \
    "${CONTAINER}" \
    bash -lc "
set -e
export GFDL_BASE='${GFDL_BASE}'
export GFDL_WORK='${GFDL_WORK}'
export GFDL_DATA='${GFDL_DATA}'
export GFDL_ENV=hybrid
export FV_KERNELS_CUDA_MODE=resident
export FV_KERNELS_PROFILE='${FV_KERNELS_PROFILE}'
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd '${GFDL_BASE}'
echo container_arch=\$(uname -m)
nvidia-smi -L || true

time python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name '${EXECUTABLE}' \
  --exp-name '${exp_name}' \
  --resolution '${res}' \
  --levels '${levels}' \
  --dt-atmos '${dt}' \
  --days '${DAYS}' \
  --production-diag \
  --num-cores '${NUM_CORES}' \
  ${overwrite_arg[*]}
" 2>&1 | tee "${log}"

  echo "output=${GFDL_DATA}/${exp_name}/run0001/atmos_monthly.nc"
done

echo "end_timestamp=$(date -Is)"
echo "logs: ${GFDL_BASE}/logs/fv_kernels_scaling/"
