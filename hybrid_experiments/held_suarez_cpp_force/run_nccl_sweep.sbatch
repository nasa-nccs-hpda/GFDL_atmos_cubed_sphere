#!/usr/bin/env bash
# Batch wrapper for the NCCL halo resolution sweep. Runs under its own Slurm
# allocation, so it survives a login disconnect -- unlike an interactive
# `salloc` session, which is torn down when the session drops (that teardown
# killed the overnight T340 run: squeue empty, log frozen at the first step).
#
# Submit from the repo root:
#   sbatch hybrid_experiments/held_suarez_cpp_force/run_nccl_sweep.sbatch
# Override any knob at submit time (sbatch exports the submit environment):
#   REPEAT=1 sbatch hybrid_experiments/held_suarez_cpp_force/run_nccl_sweep.sbatch
#   RES=T170 DT_ATMOS=150 STACK=8000000 REPEAT=3 sbatch .../run_nccl_sweep.sbatch
#
# Allocation matches the interactive one you used (salloc -G2 -c10).
#SBATCH --job-name=nccl_sweep
#SBATCH -G 2
#SBATCH -c 10
#SBATCH --time=04:00:00
#SBATCH --output=logs/nccl_sweep_%j.out
#SBATCH --error=logs/nccl_sweep_%j.out
set -euo pipefail

# Pin the base to the logical /explore path. Slurm records the submit dir as the
# resolved physical path (/panfs/ccds02/...), and Isca keys its codebase workdir
# by that string; the interactive build lives under the /explore-keyed dir, so
# without this the batch job looks under an empty _panfs_ccds02_... key and fails
# with "Hybrid executable not found". GFDL_BASE_OVERRIDE feeds the measure script.
REPO="${REPO:-/explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere}"
export GFDL_BASE_OVERRIDE="${REPO}"
cd "${REPO}"
mkdir -p logs

# The container lives only in node-local /lscratch (no shared copy). Fail fast
# with a clear message if this node lacks it, rather than deep in apptainer.
CONTAINER="${CONTAINER:-/lscratch/rlgill/isca-debian_latest}"
export CONTAINER
if [ ! -e "${CONTAINER}" ]; then
  echo "FATAL: container not found on $(hostname): ${CONTAINER}" >&2
  echo "       node-local /lscratch is not staged here; resubmit or stage it." >&2
  exit 1
fi

# Sweep knobs -- default to the T340 case; override any at submit time.
export RES="${RES:-T340}"
export DT_ATMOS="${DT_ATMOS:-75}"
export STACK="${STACK:-40000000}"
export REPEAT="${REPEAT:-3}"

echo "=== nccl sweep: RES=${RES} DT_ATMOS=${DT_ATMOS} STACK=${STACK} REPEAT=${REPEAT}" \
     "job=${SLURM_JOB_ID:-none} node=$(hostname) start=$(date) ==="

bash hybrid_experiments/held_suarez_cpp_force/measure_nccl_halo.sh

echo "=== nccl sweep done: job=${SLURM_JOB_ID:-none} end=$(date) ==="
