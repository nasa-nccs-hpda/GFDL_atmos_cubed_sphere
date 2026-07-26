#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/run_matrix_sweep.sh

Environment filters:
  ACTION       prepare | run | both    default: prepare
  CONFIGS      space-separated configs default: all configs
  RESOLUTIONS  space-separated res     default: T42 T85 T170 T340
  DAYS_LIST    space-separated days    default: 30 60 90 120
  CONTAINER    container path          default: /lscratch/jli30/isca-sandbox

Configs:
  fortran_16cpu
  fv_cuda_a_grid_1gpu
  fv_cuda_a_grid_4gpu
  fv_cuda_a_grid_16gpu

Resolution -> dt_atmos defaults:
  T42  -> 600
  T85  -> 300
  T170 -> 150
  T340 -> 75

Examples:
  ACTION=prepare scripts/run_matrix_sweep.sh

  ACTION=run \
  CONFIGS="fv_cuda_a_grid_16gpu" \
  RESOLUTIONS="T85 T170" \
  DAYS_LIST="30 60" \
  CONTAINER=/lscratch/jli30/isca-sandbox \
    scripts/run_matrix_sweep.sh

  ACTION=both \
  CONFIGS="fortran_16cpu fv_cuda_a_grid_16gpu" \
  RESOLUTIONS="T85" \
  DAYS_LIST="30" \
    scripts/run_matrix_sweep.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

ACTION="${ACTION:-prepare}"
CONTAINER="${CONTAINER:-/lscratch/jli30/isca-sandbox}"

CONFIGS="${CONFIGS:-fortran_16cpu fv_cuda_a_grid_1gpu fv_cuda_a_grid_4gpu fv_cuda_a_grid_16gpu}"
RESOLUTIONS="${RESOLUTIONS:-T42 T85 T170 T340}"
DAYS_LIST="${DAYS_LIST:-30 60 90 120}"

DRY_RUN="${DRY_RUN:-0}"

dt_for_resolution() {
  case "$1" in
    T42)  echo 600 ;;
    T85)  echo 300 ;;
    T170) echo 150 ;;
    T340) echo 75 ;;
    *)
      echo "Unknown resolution: $1" >&2
      return 2
      ;;
  esac
}

validate_config() {
  case "$1" in
    fortran_16cpu|fv_cuda_a_grid_1gpu|fv_cuda_a_grid_4gpu|fv_cuda_a_grid_16gpu)
      ;;
    *)
      echo "Unknown config: $1" >&2
      return 2
      ;;
  esac
}

case "${ACTION}" in
  prepare|run|both)
    ;;
  *)
    echo "Unknown ACTION=${ACTION}; expected prepare, run, or both" >&2
    exit 2
    ;;
esac

echo "=== Held-Suarez FV matrix sweep ==="
echo "ACTION=${ACTION}"
echo "CONFIGS=${CONFIGS}"
echo "RESOLUTIONS=${RESOLUTIONS}"
echo "DAYS_LIST=${DAYS_LIST}"
echo "CONTAINER=${CONTAINER}"
echo "DRY_RUN=${DRY_RUN}"

for config in ${CONFIGS}; do
  validate_config "${config}"

  for res in ${RESOLUTIONS}; do
    dt="$(dt_for_resolution "${res}")"

    for days in ${DAYS_LIST}; do
      echo "============================================================"
      echo "config=${config} res=${res} days=${days} dt=${dt} action=${ACTION}"
      echo "============================================================"

      prepare_cmd=(scripts/prepare_matrix_case.sh "${config}" "${res}" "${days}" "${dt}")
      run_cmd=(scripts/run_matrix_case.sh "${config}" "${res}" "${days}")

      if [[ "${DRY_RUN}" == "1" ]]; then
        case "${ACTION}" in
          prepare)
            printf 'CONTAINER=%q ' "${CONTAINER}"
            printf '%q ' "${prepare_cmd[@]}"
            printf '\n'
            ;;
          run)
            printf 'CONTAINER=%q ' "${CONTAINER}"
            printf '%q ' "${run_cmd[@]}"
            printf '\n'
            ;;
          both)
            printf 'CONTAINER=%q ' "${CONTAINER}"
            printf '%q ' "${prepare_cmd[@]}"
            printf '\n'
            printf 'CONTAINER=%q ' "${CONTAINER}"
            printf '%q ' "${run_cmd[@]}"
            printf '\n'
            ;;
        esac
        continue
      fi

      case "${ACTION}" in
        prepare)
          CONTAINER="${CONTAINER}" "${prepare_cmd[@]}"
          ;;
        run)
          CONTAINER="${CONTAINER}" "${run_cmd[@]}"
          ;;
        both)
          CONTAINER="${CONTAINER}" "${prepare_cmd[@]}"
          CONTAINER="${CONTAINER}" "${run_cmd[@]}"
          ;;
      esac
    done
  done
done
