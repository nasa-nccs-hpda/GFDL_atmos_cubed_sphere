#!/usr/bin/env bash
set -euo pipefail

TARGET="$1"

echo "=== Running Fortran baseline: $TARGET ==="
cd tests/fortran_baseline/$TARGET
make clean || true
make
./run_baseline
cd -

echo "=== Running C++ candidate: $TARGET ==="
cd translated/held_suarez/cpp/$TARGET
make clean || true
make
./run_candidate
cd -

echo "=== Comparing outputs: $TARGET ==="
python tests/compare_outputs.py \
  --baseline-dir tests/fortran_baseline/$TARGET \
  --candidate-dir translated/held_suarez/cpp/$TARGET \
  --out tests/reports/${TARGET}_compare_report.json \
  --atol 1e-12 \
  --rtol 1e-12 \
  --include outputs.dat

echo "=== Done: $TARGET ==="