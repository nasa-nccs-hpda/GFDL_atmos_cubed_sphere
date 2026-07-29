#!/usr/bin/env bash
# Batch wrapper for the NCCL halo bit-exactness check at a chosen rank count.
# Runs under its own Slurm allocation (disconnect-safe). The point at np>=3 is
# to exercise the interior-rank device exchange -- a rank with two real
# neighbors and no pole fold -- which np=2 never reaches; before trusting any
# np=4 measurement, this must still report "MATCH: all variables identical".
#
# Submit from the repo root:
#   sbatch hybrid_experiments/held_suarez_cpp_force/run_nccl_correctness.sbatch
# Change the rank count with the --gres=gpu:N below (NP follows the allocation).
# Note: `-G 4` was granting only 2 GPUs on these gpu:4 nodes; --gres=gpu:4 -N1
# reliably yields SLURM_GPUS_ON_NODE=4.
#
# Default resolution (cheap) is enough: at np=4 ranks 1 and 2 are interior.
#SBATCH --job-name=nccl_correct
#SBATCH --nodes=1
#SBATCH --gres=gpu:4
#SBATCH -c 10
#SBATCH --time=01:00:00
#SBATCH --output=logs/nccl_correct_%j.out
#SBATCH --error=logs/nccl_correct_%j.out
set -euo pipefail

# Pin the base to the logical /explore path (see run_nccl_sweep.sbatch for why:
# Slurm records the submit dir as the resolved /panfs path, but the build lives
# under the /explore-keyed Isca codebase dir).
REPO="${REPO:-/explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere}"
export GFDL_BASE_OVERRIDE="${REPO}"
cd "${REPO}"
mkdir -p logs

# Node-local container preflight (no shared copy) -- fail fast with a clear msg.
CONTAINER="${CONTAINER:-/lscratch/rlgill/isca-debian_latest}"
export CONTAINER
if [ ! -e "${CONTAINER}" ]; then
  echo "FATAL: container not found on $(hostname): ${CONTAINER}" >&2
  echo "       node-local /lscratch is not staged here; resubmit or stage it." >&2
  exit 1
fi

# One rank per GPU; follows the allocation.
export NP="${NP:-${SLURM_GPUS_ON_NODE:-4}}"

echo "=== nccl correctness: NP=${NP} job=${SLURM_JOB_ID:-none} node=$(hostname) start=$(date) ==="

# Run the two cases (host-routed vs GPU-to-GPU NCCL halo)...
bash hybrid_experiments/held_suarez_cpp_force/run_hybrid_nccl_correctness_cuda.sh || true
# ...then bit-compare with the ctypes-netcdf reader (the container has no
# python netCDF4 backend, so the runner's own inline compare cannot run).
bash hybrid_experiments/held_suarez_cpp_force/compare_nccl_correctness.sh

echo "=== nccl correctness done: job=${SLURM_JOB_ID:-none} end=$(date) ==="
