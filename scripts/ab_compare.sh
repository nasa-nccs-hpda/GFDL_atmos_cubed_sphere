#!/usr/bin/env bash
# Same-node/same-container A/B: task-5 metrics-resident vs task-3 metrics-per-call.
# For each side: set the .cu source -> recompile the CUDA overlay -> run the model.
# The two sides differ ONLY in fv_advection_kernels_cuda.cu, so kernel time should
# match and the h2d gap is the isolated task-5 win. Launch detached, e.g.:
#   nohup bash scripts/ab_compare.sh >/dev/null 2>&1 & disown                 # T85 (default)
#   AB_RES=T170 AB_DT=150 AB_DAYS=3 nohup bash scripts/ab_compare.sh >/dev/null 2>&1 & disown
set -euo pipefail
cd /explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere
export GFDL_BASE=$PWD
export CONTAINER=/lscratch/rlgill/isca-debian_latest
AB_RES="${AB_RES:-T85}"
AB_LEVELS="${AB_LEVELS:-25}"
AB_DT="${AB_DT:-300}"
AB_DAYS="${AB_DAYS:-5}"
F=translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu
RUN="$GFDL_BASE/scripts/ab_run_one.sh"
OUT="logs/fv_kernels_scaling/ab_$(hostname)_${AB_RES}"
mkdir -p "$OUT"; : > "$OUT/RESULTS.txt"
log(){ echo "$*" | tee -a "$OUT/RESULTS.txt"; }

log "node=$(hostname) res=$AB_RES levels=$AB_LEVELS dt=$AB_DT days=$AB_DAYS start=$(date -Is)"
[ -e "$CONTAINER" ] || { log "ERROR: container $CONTAINER missing on this node"; exit 1; }
[ -f "$RUN" ]       || { log "ERROR: $RUN missing (git pull first)"; exit 1; }
trap 'git checkout 8d516b6 -- "$F"' EXIT

build_and_run(){          # $1 = label
  log "[$1] compile CUDA overlay ..."
  USE_CUDA_FV_ADVECTION_KERNELS=1 GFDL_BASE_OVERRIDE="$GFDL_BASE" CONTAINER="$CONTAINER" \
    ./run_compile_fv_kernels.sh > "$OUT/$1.compile.log" 2>&1
  log "[$1] run model ($AB_RES ${AB_DAYS}day) ..."
  apptainer exec --nv \
    --bind /explore/nobackup/people/rlgill:/explore/nobackup/people/rlgill \
    --env AB_RES="$AB_RES",AB_LEVELS="$AB_LEVELS",AB_DT="$AB_DT",AB_DAYS="$AB_DAYS",LABEL="$1" \
    "$CONTAINER" bash "$RUN" > "$OUT/$1.log" 2>&1
}

# Side A: task-5 metrics-resident (current HEAD source)
git checkout 8d516b6 -- "$F"
build_and_run task5_resident

# Side B: task-3 metrics-per-call source
git show 91eebe0:"$F" > "$F"
git diff --quiet -- "$F" && { log "ERROR: task-3 .cu == task-5 .cu (wrong commit)"; exit 1; }
build_and_run task3_percall
git checkout 8d516b6 -- "$F"

# Scrape per-rank averages (kernel should match; h2d gap = task-5 win)
for L in task3_percall task5_resident; do
  log "== $L =="
  grep -hE 'PROFILE_FV_ADVECTION_CUDA' "$OUT/$L.log" \
   | grep -oE 'h2d=[0-9.]+|kernel=[0-9.]+|total=[0-9.]+' \
   | awk -F= '{s[$1]+=$2;n[$1]++} END{for(k in s) printf "%s avg=%.4f (n=%d)\n",k,s[k]/n[k],n[k]}' \
   | tee -a "$OUT/RESULTS.txt"
done
log "done=$(date -Is)"
