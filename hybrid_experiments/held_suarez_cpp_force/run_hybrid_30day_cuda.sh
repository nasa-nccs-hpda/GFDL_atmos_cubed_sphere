#!/usr/bin/env bash
set -euo pipefail

export HS_FORCE_BACKEND=cuda

python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --days 30 \
  --production-diag \
  --overwrite
