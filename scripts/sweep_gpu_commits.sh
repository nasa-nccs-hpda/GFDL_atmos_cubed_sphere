#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

COMMITS="${GPU_COMMIT_SWEEP:-b7229d0 5299271 36448d7 b6f8c4b HEAD}"
SWEEP_ROOT="${GPU_COMMIT_SWEEP_ROOT:-${REPO_ROOT}/.gpu_commit_sweep}"
SUMMARY="${GPU_COMMIT_SWEEP_SUMMARY:-${REPO_ROOT}/logs/gpu_commit_sweep_summary.tsv}"

FAST_GPU_RESOLUTION="${FAST_GPU_RESOLUTION:-T170}"
FAST_GPU_DAYS="${FAST_GPU_DAYS:-2}"
FAST_GPU_NUM_CORES="${FAST_GPU_NUM_CORES:-16}"
FAST_GPU_REBUILD="${FAST_GPU_REBUILD:-1}"
FAST_GPU_PRODUCTION_DIAG="${FAST_GPU_PRODUCTION_DIAG:-0}"
FAST_GPU_NO_TRACERS="${FAST_GPU_NO_TRACERS:-1}"
HS_PROFILE="${HS_PROFILE:-0}"

mkdir -p "${SWEEP_ROOT}" "$(dirname "${SUMMARY}")"
printf "commit\tstatus\treal_s\tlog\n" > "${SUMMARY}"

echo "=== GPU commit sweep ==="
echo "repo=${REPO_ROOT}"
echo "worktrees=${SWEEP_ROOT}"
echo "summary=${SUMMARY}"
echo "commits=${COMMITS}"
echo "resolution=${FAST_GPU_RESOLUTION} days=${FAST_GPU_DAYS} ranks=${FAST_GPU_NUM_CORES}"
echo

for commit in ${COMMITS}; do
  short=$(git -C "${REPO_ROOT}" rev-parse --short "${commit}")
  worktree="${SWEEP_ROOT}/${short}"
  log="${REPO_ROOT}/logs/gpu_commit_sweep_${short}_${FAST_GPU_RESOLUTION}_${FAST_GPU_DAYS}day.log"

  if [[ ! -d "${worktree}/.git" && ! -f "${worktree}/.git" ]]; then
    git -C "${REPO_ROOT}" worktree add --detach "${worktree}" "${commit}"
  fi

  echo "=== Benchmark ${commit} (${short}) ==="
  set +e
  (
    cd "${worktree}"
    FAST_GPU_REBUILD="${FAST_GPU_REBUILD}" \
    FAST_GPU_RESOLUTION="${FAST_GPU_RESOLUTION}" \
    FAST_GPU_DAYS="${FAST_GPU_DAYS}" \
    FAST_GPU_NUM_CORES="${FAST_GPU_NUM_CORES}" \
    FAST_GPU_PRODUCTION_DIAG="${FAST_GPU_PRODUCTION_DIAG}" \
    FAST_GPU_NO_TRACERS="${FAST_GPU_NO_TRACERS}" \
    FAST_GPU_CASE_SUFFIX="_${short}" \
    HS_PROFILE="${HS_PROFILE}" \
    scripts/run_gpu_2x_target.sh
  ) 2>&1 | tee "${log}"
  status=${PIPESTATUS[0]}
  set -e

  real_s=$(python3 - "${log}" <<'PY'
import re
import sys
from pathlib import Path

real_re = re.compile(r"^real\s+(?:(?P<min>\d+)m)?(?P<sec>[0-9.]+)s$")
values = []
for line in Path(sys.argv[1]).read_text(errors="replace").splitlines():
    match = real_re.match(line.strip())
    if match:
        values.append(int(match.group("min") or 0) * 60.0 + float(match.group("sec")))
print(f"{values[-1]:.3f}" if values else "NA")
PY
)
  printf "%s\t%s\t%s\t%s\n" "${short}" "${status}" "${real_s}" "${log}" >> "${SUMMARY}"
done

echo
echo "=== Sweep summary ==="
column -t -s $'\t' "${SUMMARY}" || cat "${SUMMARY}"
