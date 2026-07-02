#!/usr/bin/env bash
set -euo pipefail

# Held-Suarez fv_advection kernel-bundle CPU C++ baseline run.
#
# Container/paths are env-overridable (default to rlgill's AAI roots + container).
# Resolution is optional: set RES/LEVELS/DT for a scaling point, e.g.
#   RES=T170 LEVELS=25 DT=150 GFDL_BASE=$PWD FV_KERNELS_OVERWRITE=1 scripts/run_fv_kernels_cpu_30day.sh
# With RES unset it keeps the legacy default-resolution behavior + exp name.

CONTAINER="${CONTAINER:-/lscratch/rlgill/isca-debian_latest}"
export GFDL_BASE="${GFDL_BASE:-/explore/nobackup/people/rlgill/SystemTesting/AAI/GFDL_atmos_cubed_sphere}"
export GFDL_WORK="${GFDL_WORK:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_work}"
export GFDL_DATA="${GFDL_DATA:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_data}"
export FV_KERNELS_OVERWRITE="${FV_KERNELS_OVERWRITE:-0}"
export FV_KERNELS_PROFILE="${FV_KERNELS_PROFILE:-1}"
DAYS="${DAYS:-30}"
NUM_CORES="${NUM_CORES:-16}"

# Optional resolution parameterization (empty => original test-case resolution).
RES="${RES:-}"
LEVELS="${LEVELS:-25}"
DT="${DT:-}"

res_args=()
if [[ -n "${RES}" ]]; then
  label="${RES}L${LEVELS}"
  EXPERIMENT="${EXPERIMENT:-held_suarez_fv_kernels_cpu_${label}_${DAYS}day}"
  res_args=(--resolution "${RES}" --levels "${LEVELS}")
  [[ -n "${DT}" ]] && res_args+=(--dt-atmos "${DT}")
else
  EXPERIMENT="${EXPERIMENT:-held_suarez_fv_kernels_${DAYS}day}"
fi

LOG="${GFDL_BASE}/logs/fv_kernels_cpu_${EXPERIMENT}.log"
mkdir -p "${GFDL_BASE}/logs"
exec > >(tee "${LOG}") 2>&1

echo "=== Held-Suarez fv_advection kernel-bundle CPU C++ run ==="
echo "start_timestamp=$(date -Is)"
echo "CONTAINER=${CONTAINER}"
echo "GFDL_BASE=${GFDL_BASE}"
echo "GFDL_WORK=${GFDL_WORK}"
echo "GFDL_DATA=${GFDL_DATA}"
echo "resolution=${RES:-<default>} levels=${LEVELS} dt=${DT:-<namelist>} days=${DAYS}"
echo "FV_KERNELS_OVERWRITE=${FV_KERNELS_OVERWRITE} FV_KERNELS_PROFILE=${FV_KERNELS_PROFILE}"
echo "executable=held_suarez_fv_kernels.x experiment=${EXPERIMENT}"

overwrite_arg=()
if [[ "${FV_KERNELS_OVERWRITE}" == "1" ]]; then
  overwrite_arg=(--overwrite)
fi

apptainer exec --nv \
  --bind /explore/nobackup/people/rlgill:/explore/nobackup/people/rlgill \
  "${CONTAINER}" \
  bash -lc "
set -e
export GFDL_BASE='${GFDL_BASE}'
export GFDL_WORK='${GFDL_WORK}'
export GFDL_DATA='${GFDL_DATA}'
export GFDL_ENV=hybrid
export FV_KERNELS_PROFILE='${FV_KERNELS_PROFILE}'
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
cd '${GFDL_BASE}'
time python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name held_suarez_fv_kernels.x \
  --exp-name '${EXPERIMENT}' \
  ${res_args[*]} \
  --days '${DAYS}' \
  --production-diag \
  --num-cores '${NUM_CORES}' \
  ${overwrite_arg[*]}
"

echo "end_timestamp=$(date -Is)"
echo "output=${GFDL_DATA}/${EXPERIMENT}/run0001/atmos_monthly.nc"
echo "Log written to ${LOG}"
