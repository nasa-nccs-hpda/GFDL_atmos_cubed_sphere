#!/usr/bin/env bash
set -euo pipefail

CONTAINER=${CONTAINER:-/lscratch/jli30/isca-sandbox}
IMAGE=${IMAGE:-docker://nasanccs/isca-debian:latest}
TASKS=${TASKS:-${SLURM_NNODES:-1}}
TASKS_PER_NODE=${TASKS_PER_NODE:-1}

echo "=== Build/check Isca sandbox on allocated nodes ==="
echo "CONTAINER=${CONTAINER}"
echo "IMAGE=${IMAGE}"
echo "TASKS=${TASKS}"
echo "TASKS_PER_NODE=${TASKS_PER_NODE}"

if ! command -v srun >/dev/null 2>&1; then
  echo "ERROR: srun not found. Run this inside a Slurm allocation." >&2
  exit 1
fi

srun -n "${TASKS}" --ntasks-per-node="${TASKS_PER_NODE}" bash -lc '
set -euo pipefail

HOST=$(hostname)
CONTAINER='"${CONTAINER@Q}"'
IMAGE='"${IMAGE@Q}"'

echo "[$HOST] checking $CONTAINER"

if [ -d "$CONTAINER" ]; then
  echo "[$HOST] CONTAINER_OK $CONTAINER"
else
  echo "[$HOST] CONTAINER_MISSING $CONTAINER"
  echo "[$HOST] building sandbox from $IMAGE"

  mkdir -p "$(dirname "$CONTAINER")"
  singularity build --sandbox "$CONTAINER" "$IMAGE"

  echo "[$HOST] build complete"
  ls -ld "$CONTAINER"
fi
'

echo "=== Verification ==="
srun -n "${TASKS}" --ntasks-per-node="${TASKS_PER_NODE}" bash -lc '
set -euo pipefail

HOST=$(hostname)
CONTAINER='"${CONTAINER@Q}"'

if [ -d "$CONTAINER" ]; then
  echo "[$HOST] CONTAINER_OK $CONTAINER"
else
  echo "[$HOST] CONTAINER_MISSING $CONTAINER"
fi
'
