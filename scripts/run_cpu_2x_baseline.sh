#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

export FAST_GPU_RUN_MODE=cpu
export FAST_GPU_REBUILD="${FAST_GPU_REBUILD:-1}"
export FAST_GPU_RESOLUTION="${FAST_GPU_RESOLUTION:-T340}"
export FAST_GPU_DAYS="${FAST_GPU_DAYS:-1}"
export FAST_GPU_NUM_CORES="${FAST_GPU_NUM_CORES:-16}"
export FAST_GPU_PRODUCTION_DIAG="${FAST_GPU_PRODUCTION_DIAG:-0}"
export FAST_GPU_NO_TRACERS="${FAST_GPU_NO_TRACERS:-1}"
export HS_PROFILE="${HS_PROFILE:-0}"

"${SCRIPT_DIR}/compare_fastest_gpu_resolution.sh"
