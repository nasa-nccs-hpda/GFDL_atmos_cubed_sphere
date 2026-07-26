#!/usr/bin/env bash
set -euo pipefail

CONTAINER=${CONTAINER:-/lscratch/jli30/isca-sandbox}
IMAGE=${IMAGE:-docker://nasanccs/isca-debian:latest}
TASKS=${TASKS:-${SLURM_NNODES:-1}}
TASKS_PER_NODE=${TASKS_PER_NODE:-1}
SRUN_MPI=${SRUN_MPI:-none}
FORCE=${FORCE:-0}

echo "=== Build/check Isca sandbox on allocated nodes ==="
echo "CONTAINER=${CONTAINER}"
echo "IMAGE=${IMAGE}"
echo "TASKS=${TASKS}"
echo "TASKS_PER_NODE=${TASKS_PER_NODE}"
echo "SRUN_MPI=${SRUN_MPI}"
echo "FORCE=${FORCE}"

if ! command -v srun >/dev/null 2>&1; then
  echo "ERROR: srun not found. Run this inside a Slurm allocation." >&2
  exit 1
fi

srun --mpi="${SRUN_MPI}" -n "${TASKS}" --ntasks-per-node="${TASKS_PER_NODE}" bash -lc '
set -euo pipefail

HOST=$(hostname)
CONTAINER='"${CONTAINER@Q}"'
IMAGE='"${IMAGE@Q}"'
FORCE='"${FORCE@Q}"'

echo "[$HOST] checking $CONTAINER"

if [ -d "$CONTAINER" ] && [ "$FORCE" != "1" ]; then
  echo "[$HOST] CONTAINER_OK $CONTAINER"
else
  if [ -d "$CONTAINER" ]; then
    echo "[$HOST] CONTAINER_FORCE_REBUILD $CONTAINER"
    rm -rf "$CONTAINER"
  else
    echo "[$HOST] CONTAINER_MISSING $CONTAINER"
  fi
  echo "[$HOST] building sandbox from $IMAGE"

  mkdir -p "$(dirname "$CONTAINER")"
  singularity build --sandbox "$CONTAINER" "$IMAGE"

  echo "[$HOST] build complete"
  ls -ld "$CONTAINER"
fi
'

echo "=== Verification ==="
srun --mpi="${SRUN_MPI}" -n "${TASKS}" --ntasks-per-node="${TASKS_PER_NODE}" bash -lc '
set -euo pipefail

HOST=$(hostname)
CONTAINER='"${CONTAINER@Q}"'

if [ -d "$CONTAINER" ]; then
  echo "[$HOST] CONTAINER_OK $CONTAINER"
else
  echo "[$HOST] CONTAINER_MISSING $CONTAINER"
fi
'
