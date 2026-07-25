#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

export FAST_GPU_RUN_MODE=cuda
export FAST_GPU_REBUILD="${FAST_GPU_REBUILD:-0}"
export USE_CUDA_TRANSFORMS="${USE_CUDA_TRANSFORMS:-0}"
export USE_CUDA_GRID_FOURIER="${USE_CUDA_GRID_FOURIER:-1}"
export USE_CUDA_SPHERICAL_FOURIER="${USE_CUDA_SPHERICAL_FOURIER:-1}"

"${SCRIPT_DIR}/compare_fastest_gpu_resolution.sh"
