#!/usr/bin/env bash
set -euo pipefail

# Run Held-Suarez resolution-scaling profiles inside the Isca container.
#
# Defaults:
#   - 30 simulated days
#   - primary T42L25, T85L25, T170L25 matrix
#   - 16 MPI ranks
#
# Example pilot:
#   SCALING_DAYS=1 SCALING_RESOLUTIONS="T42:25:600 T85:25:300" \
#     scripts/run_resolution_scaling_profiles.sh
#
# Full primary matrix:
#   SCALING_DAYS=30 SCALING_RESOLUTIONS="T42:25:600 T85:25:300 T170:25:150" \
#     scripts/run_resolution_scaling_profiles.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

LOG_DIR="${SCALING_LOG_DIR:-logs/resolution_scaling}"
FORCING_LOG_DIR="${SCALING_FORCING_LOG_DIR:-logs}"
DAYS="${SCALING_DAYS:-30}"
NUM_CORES="${SCALING_NUM_CORES:-16}"
RESOLUTIONS="${SCALING_RESOLUTIONS:-T42:25:600 T85:25:300 T170:25:150}"
BUILD_EXECUTABLES="${SCALING_BUILD_EXECUTABLES:-1}"
OVERWRITE="${SCALING_OVERWRITE:-1}"
PRODUCTION_DIAG="${SCALING_PRODUCTION_DIAG:-1}"
BUILD_GFDL_ENV="${SCALING_GFDL_ENV:-ubuntu_conda}"
SCALING_USE_CUDA_HS_FORCE="${SCALING_USE_CUDA_HS_FORCE:-0}"

mkdir -p "${LOG_DIR}"
mkdir -p "${FORCING_LOG_DIR}"

if ! python3 - <<'PY'
import isca  # noqa: F401
PY
then
  echo "ERROR: python3 cannot import isca. Run this script inside the Isca container/environment." >&2
  exit 1
fi

build_target() {
  local target="$1"
  local env_name="${2:-${BUILD_GFDL_ENV}}"
  local log="${LOG_DIR}/build_${target}.log"
  echo "=== Building ${target}; GFDL_ENV=${env_name}; log=${log} ==="
  GFDL_ENV="${env_name}" USE_CUDA_HS_FORCE="${SCALING_USE_CUDA_HS_FORCE}" \
    python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py "${target}" \
    2>&1 | tee "${log}"
}

if [[ "${BUILD_EXECUTABLES}" == "1" ]]; then
  build_target fortran
  build_target hybrid hybrid
  build_target profile_dynamics_regions
  build_target profile_dynamics_deep
  build_target profile_four_in_one
  build_target profile_vert_advection
fi

run_case() {
  local res="$1"
  local levels="$2"
  local dt="$3"
  local variant="$4"
  local executable="$5"
  local hs_profile="${6:-0}"
  local hs_backend="${7:-}"
  local explicit_log="${8:-}"
  local label="${res}L${levels}_${variant}"
  local exp_name="held_suarez_scaling_${label}"
  local log="${LOG_DIR}/${label}.log"
  if [[ -n "${explicit_log}" ]]; then
    log="${explicit_log}"
  fi

  echo "=== Running ${label}; executable=${executable}; days=${DAYS}; dt=${dt}; log=${log} ==="

  HS_PROFILE="${hs_profile}" HS_FORCE_BACKEND="${hs_backend}" \
  /usr/bin/time -p python3 - "${exp_name}" "${executable}" "${res}" "${levels}" "${dt}" "${DAYS}" "${NUM_CORES}" "${OVERWRITE}" "${PRODUCTION_DIAG}" <<'PY' 2>&1 | tee "${log}"
import sys
import os
from pathlib import Path

repo_root = Path.cwd()
case_dir = repo_root / "exp" / "test_cases" / "held_suarez"
sys.path.insert(0, str(case_dir))

import held_suarez_test_case as original
from isca import DryCodeBase, Experiment, GFDL_BASE

exp_name = sys.argv[1]
executable_name = sys.argv[2]
resolution = sys.argv[3]
levels = int(sys.argv[4])
dt_atmos = int(sys.argv[5])
days = int(sys.argv[6])
num_cores = int(sys.argv[7])
overwrite = sys.argv[8] == "1"
production_diag = sys.argv[9] == "1"


class RuntimeCodeBase(DryCodeBase):
    pass


RuntimeCodeBase.executable_name = executable_name


cb = RuntimeCodeBase.from_directory(GFDL_BASE)
if not Path(cb.executable_fullpath).exists():
    raise FileNotFoundError(f"Executable not found: {cb.executable_fullpath}")

exp = Experiment(exp_name, codebase=cb)
exp.namelist = original.namelist.copy()
exp.diag_table = original.diag.copy()
exp.set_resolution(resolution, levels)
exp.update_namelist({"main_nml": {"days": days, "dt_atmos": dt_atmos}})

if not production_diag:
    for output_file in exp.diag_table.files.values():
        output_file["freq"] = 1
        output_file["units"] = "days"
        output_file["time_units"] = "days"

print("Experiment =", exp.name)
print("Executable =", cb.executable_fullpath)
print("Resolution =", resolution)
print("Levels =", levels)
print("Days =", days)
print("dt_atmos =", dt_atmos)
print("num_cores =", num_cores)
print("Data dir =", exp.datadir)
print("Run dir =", exp.rundir)
print("production_diag =", production_diag)
print("HS_PROFILE =", os.environ.get("HS_PROFILE"))
print("HS_FORCE_BACKEND =", os.environ.get("HS_FORCE_BACKEND"))

exp.run(1, num_cores=num_cores, use_restart=False, overwrite_data=overwrite)
PY
}

for spec in ${RESOLUTIONS}; do
  IFS=: read -r res levels dt <<< "${spec}"
  if [[ -z "${res}" || -z "${levels}" || -z "${dt}" ]]; then
    echo "ERROR: bad resolution spec '${spec}'. Expected RES:LEVELS:DT, e.g. T85:25:300" >&2
    exit 1
  fi

  run_case "${res}" "${levels}" "${dt}" baseline held_suarez_fortran.x
  run_case "${res}" "${levels}" "${dt}" forcing_profile held_suarez_hybrid.x 1 cpu \
    "${FORCING_LOG_DIR}/scaling_${res}L${levels}_forcing_profile.log"
  run_case "${res}" "${levels}" "${dt}" dynamics_region held_suarez_profile_dynamics_regions.x
  run_case "${res}" "${levels}" "${dt}" dynamics_deep held_suarez_profile_dynamics_deep.x
  run_case "${res}" "${levels}" "${dt}" four_in_one held_suarez_profile_four_in_one.x
  run_case "${res}" "${levels}" "${dt}" vert_advection held_suarez_profile_vert_advection.x
done

echo "Resolution scaling profiles complete. Logs: ${LOG_DIR}"
