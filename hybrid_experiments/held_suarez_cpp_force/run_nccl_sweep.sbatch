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
# One rank per GPU over intra-node NVLink. --gres=gpu:4 on a single node claims
# the node's full 4x V100; at np=4 T340's per-GPU memory ~halves (np=2 pinned it
# at 96% of 32 GB and could not finish one day inside 4 h). Note: `-G 4`
# (--gpus=4) was granting only 2 GPUs on these gpu:4 nodes; --gres=gpu:4 -N1 is
# the request that reliably yields SLURM_GPUS_ON_NODE=4.
#SBATCH --job-name=nccl_sweep
#SBATCH --nodes=1
#SBATCH --gres=gpu:4
#SBATCH -c 10
#SBATCH --time=08:00:00
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

# The container lives only in node-local /lscratch (no shared copy), so whichever
# node this job lands on may not have it. Build the sandbox from the public image
# when missing -- one-time per node, idempotent (a node that has it skips this).
CONTAINER="${CONTAINER:-/lscratch/rlgill/isca-debian_latest}"
export CONTAINER
IMAGE="${IMAGE:-docker://nasanccs/isca-debian:latest}"
if [ ! -e "${CONTAINER}" ]; then
  echo "Container not on $(hostname): staging sandbox from ${IMAGE} (one-time)..."
  mkdir -p "$(dirname "${CONTAINER}")"
  BUILDER=$(command -v singularity || command -v apptainer || true)
  if [ -z "${BUILDER}" ]; then
    echo "FATAL: neither singularity nor apptainer on PATH to build ${CONTAINER}" >&2
    exit 1
  fi
  # Build to a temp path then rename, so an interrupted build never leaves a
  # partial sandbox that the -e check would wrongly accept.
  TMP_SANDBOX="${CONTAINER}.building.$$"
  rm -rf "${TMP_SANDBOX}"
  "${BUILDER}" build --sandbox "${TMP_SANDBOX}" "${IMAGE}"
  mv "${TMP_SANDBOX}" "${CONTAINER}"
  echo "Container staged at ${CONTAINER}"
fi

# Sweep knobs -- default to the T340 case; override any at submit time.
# NP follows the GPUs actually allocated (one rank per GPU), so changing the
# --gres=gpu:N above keeps the rank count in step.
export NP="${NP:-${SLURM_GPUS_ON_NODE:-4}}"
export RES="${RES:-T340}"
export DT_ATMOS="${DT_ATMOS:-75}"
export STACK="${STACK:-40000000}"
export REPEAT="${REPEAT:-3}"

echo "=== nccl sweep: NP=${NP} RES=${RES} DT_ATMOS=${DT_ATMOS} STACK=${STACK} REPEAT=${REPEAT}" \
     "job=${SLURM_JOB_ID:-none} node=$(hostname) start=$(date) ==="

bash hybrid_experiments/held_suarez_cpp_force/measure_nccl_halo.sh

echo "=== nccl sweep done: job=${SLURM_JOB_ID:-none} end=$(date) ==="
