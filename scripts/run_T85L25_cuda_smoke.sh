#!/usr/bin/env bash
set -euo pipefail

# T85L25 CUDA hybrid forcing smoke test.
#
# Run this inside the Isca/H100 container environment, from the repository root.
# It builds the CUDA-enabled hybrid executable through the native Isca
# CodeBase.compile() path, then runs a 1-day T85L25 smoke test with
# HS_FORCE_BACKEND=cuda and HS_PROFILE=1.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

mkdir -p logs
LOG="logs/T85L25_cuda_smoke.log"

exec > >(tee "${LOG}") 2>&1

echo "=== T85L25 CUDA forcing smoke test ==="
date
echo "ROOT_DIR=${ROOT_DIR}"

export GFDL_BASE="${GFDL_BASE:-${ROOT_DIR}}"
export GFDL_WORK="${GFDL_WORK:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work}"
export GFDL_DATA="${GFDL_DATA:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data}"
export GFDL_ENV=hybrid
export USE_CUDA_HS_FORCE=1
export GFDL_MKMF_TEMPLATE=hybrid_cuda
export NVCC="${NVCC:-nvcc}"
export HS_FORCE_BACKEND=cuda
export HS_PROFILE=1

export OMPI_MCA_rmaps_base_oversubscribe="${OMPI_MCA_rmaps_base_oversubscribe:-1}"
export OMPI_MCA_btl_vader_single_copy_mechanism="${OMPI_MCA_btl_vader_single_copy_mechanism:-none}"

echo "=== Environment ==="
echo "GFDL_BASE=${GFDL_BASE}"
echo "GFDL_WORK=${GFDL_WORK}"
echo "GFDL_DATA=${GFDL_DATA}"
echo "GFDL_ENV=${GFDL_ENV}"
echo "USE_CUDA_HS_FORCE=${USE_CUDA_HS_FORCE}"
echo "GFDL_MKMF_TEMPLATE=${GFDL_MKMF_TEMPLATE}"
echo "HS_FORCE_BACKEND=${HS_FORCE_BACKEND}"
echo "HS_PROFILE=${HS_PROFILE}"
echo "python3=$(command -v python3 || true)"
echo "mpifort=$(command -v mpifort || true)"
echo "nvcc=$(command -v "${NVCC}" || true)"
echo "nc-config=$(command -v nc-config || true)"
echo "nvidia-smi=$(command -v nvidia-smi || true)"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi || true
fi

echo "=== Preflight checks ==="
missing=0
require_command() {
  local name="$1"
  local command_name="$2"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "ERROR: required command '${name}' not found: ${command_name}"
    missing=1
  fi
}

require_command python3 python3
require_command mpifort mpifort
require_command nc-config nc-config
require_command nvcc "${NVCC}"

if ! python3 - <<'PY'
import isca  # noqa: F401
import jinja2  # noqa: F401
PY
then
  echo "ERROR: Python environment cannot import both isca and jinja2."
  missing=1
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "ERROR: nvidia-smi not found. Run on an H100/GPU node with CUDA visible."
  missing=1
else
  gpu_list="$(nvidia-smi -L 2>&1 || true)"
  echo "nvidia-smi -L output:"
  echo "${gpu_list}"
  if ! printf '%s\n' "${gpu_list}" | grep -q '^GPU '; then
    echo "ERROR: no CUDA GPU is visible to nvidia-smi."
    echo "Run on an allocated H100/GPU node and enter the container with apptainer exec --nv."
    missing=1
  fi
fi

if [[ "${missing}" != "0" ]]; then
  echo "Preflight failed. This script must run inside the Isca container on a GPU-visible node."
  exit 2
fi

run_with_time() {
  if [[ -x /usr/bin/time ]]; then
    /usr/bin/time -p "$@"
  else
    time "$@"
  fi
}

echo "=== Build CUDA-enabled hybrid executable ==="
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py hybrid

echo "=== Run 1-day T85L25 CUDA hybrid smoke test ==="
run_with_time python3 - <<'PY'
import os
import sys
from pathlib import Path

repo_root = Path.cwd()
sys.path.insert(0, str(repo_root / "exp" / "test_cases" / "held_suarez"))

import held_suarez_test_case as original
from isca import DryCodeBase, Experiment, GFDL_BASE


class RuntimeCodeBase(DryCodeBase):
    pass


RuntimeCodeBase.executable_name = "held_suarez_hybrid.x"

cb = RuntimeCodeBase.from_directory(GFDL_BASE)
if not Path(cb.executable_fullpath).exists():
    raise FileNotFoundError(f"Executable not found: {cb.executable_fullpath}")

exp = Experiment("held_suarez_T85L25_cuda_smoke", codebase=cb)
exp.namelist = original.namelist.copy()
exp.diag_table = original.diag.copy()
exp.set_resolution("T85", 25)
exp.update_namelist({"main_nml": {"days": 1, "dt_atmos": 300}})

# For smoke testing, write a 1-day diagnostic file so startup and output are
# both verified. The 30-day performance experiment keeps production cadence.
for output_file in exp.diag_table.files.values():
    output_file["freq"] = 1
    output_file["units"] = "days"
    output_file["time_units"] = "days"

print("Experiment =", exp.name)
print("Executable =", cb.executable_fullpath)
print("Resolution = T85")
print("Levels = 25")
print("Days =", exp.namelist["main_nml"]["days"])
print("dt_atmos =", exp.namelist["main_nml"]["dt_atmos"])
print("num_cores = 16")
print("HS_FORCE_BACKEND =", os.environ.get("HS_FORCE_BACKEND"))
print("HS_PROFILE =", os.environ.get("HS_PROFILE"))
print("Data dir =", exp.datadir)
print("Run dir =", exp.rundir)

exp.run(1, num_cores=16, use_restart=False, overwrite_data=True)
PY

echo "=== Smoke test complete ==="
date
echo "Log written to ${LOG}"
