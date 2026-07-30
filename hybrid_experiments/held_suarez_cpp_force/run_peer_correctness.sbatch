#!/usr/bin/env bash
# Batch wrapper for the peer-copy halo bit-exactness check at a chosen rank
# count. Runs under its own Slurm allocation (disconnect-safe). The point at
# np>=3 is to exercise the interior-rank device exchange -- a rank with two real
# neighbors and no pole fold -- which np=2 never reaches; before trusting any
# np=4 measurement, this must still report "MATCH: all variables identical".
#
# Submit from the repo root:
#   sbatch hybrid_experiments/held_suarez_cpp_force/run_peer_correctness.sbatch
# Change the rank count with the --gres=gpu:N below (NP follows the allocation).
# --gres=gpu:4 -N1 reliably yields SLURM_GPUS_ON_NODE=4 (plain -G 4 granted 2).
#
# Default resolution (cheap) is enough: at np=4 ranks 1 and 2 are interior.
#SBATCH --job-name=peer_correct
#SBATCH --nodes=1
#SBATCH --gres=gpu:4
#SBATCH -c 10
#SBATCH --time=01:00:00
#SBATCH --output=logs/peer_correct_%j.out
#SBATCH --error=logs/peer_correct_%j.out
set -euo pipefail

# Pin the base to the logical /explore path (Slurm records the submit dir as the
# resolved /panfs path, but the build lives under the /explore-keyed dir).
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

# One rank per GPU; follows the allocation.
export NP="${NP:-${SLURM_GPUS_ON_NODE:-4}}"

echo "=== peer correctness: NP=${NP} job=${SLURM_JOB_ID:-none} node=$(hostname) start=$(date) ==="

# Run the two cases (host-routed vs direct peer-copy halo)...
bash hybrid_experiments/held_suarez_cpp_force/run_hybrid_peer_correctness_cuda.sh || true
# ...then bit-compare with the ctypes-netcdf reader (the container has no python
# netCDF4 backend, so the runner cannot compare inline). Reuse the NCCL comparer,
# pointed at the peer experiment names.
REF_EXP=peer_correctness_host DEV_EXP=peer_correctness_device \
  bash hybrid_experiments/held_suarez_cpp_force/compare_nccl_correctness.sh

echo "=== peer correctness done: job=${SLURM_JOB_ID:-none} end=$(date) ==="
