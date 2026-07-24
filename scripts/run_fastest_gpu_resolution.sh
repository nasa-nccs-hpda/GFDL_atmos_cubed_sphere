#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

export FAST_GPU_RUN_MODE=cuda
export FAST_GPU_REBUILD="${FAST_GPU_REBUILD:-0}"

"${SCRIPT_DIR}/compare_fastest_gpu_resolution.sh"
