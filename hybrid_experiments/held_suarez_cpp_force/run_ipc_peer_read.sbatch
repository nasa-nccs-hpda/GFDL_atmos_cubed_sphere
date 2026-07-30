#!/usr/bin/env bash
# Batch wrapper for the CUDA IPC cross-process peer-read feasibility check
# (tests/poc/ipc_peer_read.cu). This is the Phase 0 gate for the NVLink
# peer-copy halo experiment: it confirms one rank can read another rank's
# device memory directly via cudaIpcOpenMemHandle inside this container.
#
# Only two distinct GPUs are needed (rank 0 on GPU 0, rank 1 on GPU 1), so this
# requests --gres=gpu:2, which schedules faster than the full 4-GPU node. The
# 4-GPU node is only needed later, at Phase 1/2.
#
# Submit from the repo root:
#   sbatch hybrid_experiments/held_suarez_cpp_force/run_ipc_peer_read.sbatch
#
# PASS in the log => cross-process peer read works here; proceed to Phase 1.
# A cudaIpcOpenMemHandle failure => the container blocks CUDA IPC; STOP.
#SBATCH --job-name=ipc_peer_read
#SBATCH --nodes=1
#SBATCH --gres=gpu:2
#SBATCH -c 10
#SBATCH --time=00:20:00
#SBATCH --output=logs/ipc_peer_read_%j.out
#SBATCH --error=logs/ipc_peer_read_%j.out
set -euo pipefail

# Pin the base to the logical /explore path (Slurm records the submit dir as the
# resolved /panfs path, but the checkout lives under the /explore string).
REPO="${REPO:-/explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere}"
cd "${REPO}"
mkdir -p logs

# The container lives only in node-local /lscratch (no shared copy), so whichever
# node this job lands on may not have it. Build the sandbox from the public image
# when missing -- one-time per node, idempotent (a node that has it skips this).
CONTAINER="${CONTAINER:-/lscratch/rlgill/isca-debian_latest}"
IMAGE="${IMAGE:-docker://nasanccs/isca-debian:latest}"
if [ ! -e "${CONTAINER}" ]; then
  echo "Container not on $(hostname): staging sandbox from ${IMAGE} (one-time)..."
  mkdir -p "$(dirname "${CONTAINER}")"
  BUILDER=$(command -v singularity || command -v apptainer || true)
  if [ -z "${BUILDER}" ]; then
    echo "FATAL: neither singularity nor apptainer on PATH to build ${CONTAINER}" >&2
    exit 1
  fi
  TMP_SANDBOX="${CONTAINER}.building.$$"
  rm -rf "${TMP_SANDBOX}"
  "${BUILDER}" build --sandbox "${TMP_SANDBOX}" "${IMAGE}"
  mv "${TMP_SANDBOX}" "${CONTAINER}"
  echo "Container staged at ${CONTAINER}"
fi

echo "=== ipc peer read: gpus=${SLURM_GPUS_ON_NODE:-?} job=${SLURM_JOB_ID:-none} node=$(hostname) start=$(date) ==="

apptainer exec --nv \
  --bind /explore/nobackup/people/rlgill:/explore/nobackup/people/rlgill \
  "${CONTAINER}" \
  bash -lc "
set -e
cd ${REPO}/tests/poc

# Compile first (one small file; the binary is reused if this reruns).
nvcc -ccbin mpicxx -O2 ipc_peer_read.cu -o ipc_peer_read

# Interactive-launch MPI settings, same as the model run scripts.
export OMPI_MCA_plm=isolated
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none

nvidia-smi topo -m
mpirun -np 2 ./ipc_peer_read
"

echo "=== ipc peer read done: job=${SLURM_JOB_ID:-none} end=$(date) ==="
