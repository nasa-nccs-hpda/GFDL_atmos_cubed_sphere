#!/usr/bin/env bash
# Level 1, Phase A, Step 4 correctness check: run the resident FV advection
# path twice at np=2, once with the host-routed q1 halo (reference) and once
# with the GPU-to-GPU NCCL halo path, then compare the output field by field.
#
# The device path is designed to reproduce the host mpp_update_domains(q1) and
# polar fold exactly, so the two runs should match bit for bit. Any nonzero
# difference is a bug in the device exchange or fold.
#
# Pass = "MATCH: all variables identical". A "DIFF" line names the first field
# that disagrees and its largest absolute difference.
set -euo pipefail

CONTAINER=${CONTAINER:-/lscratch/rlgill/isca-debian_latest}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

export GFDL_BASE=${GFDL_BASE_OVERRIDE:-${SCRIPT_DIR}}
export GFDL_WORK=${GFDL_WORK:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_work}
export GFDL_DATA=${GFDL_DATA:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_data}

REF_EXP=nccl_correctness_host
DEV_EXP=nccl_correctness_device

apptainer exec --nv \
  --bind /explore/nobackup/people/rlgill:/explore/nobackup/people/rlgill \
  "${CONTAINER}" \
  bash -lc "
set -e

export GFDL_BASE=${GFDL_BASE}
export GFDL_WORK=${GFDL_WORK}
export GFDL_DATA=${GFDL_DATA}
export GFDL_ENV=hybrid
export HS_FORCE_BACKEND=cuda

export FV_KERNELS_CUDA_MODE=resident
export FV_KERNELS_PROFILE=1

export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none

cd ${GFDL_BASE}
mkdir -p logs

# Rank/GPU count. np>=3 is what exercises the interior-rank device exchange
# (a rank with two real neighbors and no pole fold) that np=2 never reaches.
NP='${NP:-2}'

run_case () {
  local exp_name=\$1
  echo \"=== running \${exp_name} (FV_ADVECTION_NCCL_HALO=\${FV_ADVECTION_NCCL_HALO:-0}) np=\${NP} ===\"
  python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
    --exp-name \${exp_name} \
    --executable-name held_suarez_fv_kernels_cuda.x \
    --num-cores \${NP} \
    --days 1 \
    --overwrite
}

# Reference: host-routed halo (device halo path off).
unset FV_ADVECTION_NCCL_HALO
run_case ${REF_EXP}

# Device: GPU-to-GPU NCCL halo path on.
export FV_ADVECTION_NCCL_HALO=1
run_case ${DEV_EXP}

echo '=== comparing output ==='
python3 - <<'PY'
import glob, os, sys
import numpy as np
from netCDF4 import Dataset

data = os.environ['GFDL_DATA']

def find_nc(exp):
    hits = sorted(glob.glob(os.path.join(data, exp, '**', '*.nc'), recursive=True))
    if not hits:
        sys.exit('no output .nc found for %s' % exp)
    return hits

ref = find_nc('${REF_EXP}')
dev = find_nc('${DEV_EXP}')

ref_names = {os.path.basename(p): p for p in ref}
dev_names = {os.path.basename(p): p for p in dev}
common = sorted(set(ref_names) & set(dev_names))
if not common:
    sys.exit('no output files in common between the two runs')

worst = 0.0
worst_var = None
n_checked = 0
for name in common:
    a = Dataset(ref_names[name])
    b = Dataset(dev_names[name])
    for v in a.variables:
        if v not in b.variables:
            continue
        va = np.asarray(a.variables[v][:], dtype='float64')
        vb = np.asarray(b.variables[v][:], dtype='float64')
        if va.shape != vb.shape:
            print('SHAPE MISMATCH %s/%s: %s vs %s' % (name, v, va.shape, vb.shape))
            worst = float('inf'); worst_var = '%s/%s' % (name, v); continue
        d = np.nanmax(np.abs(va - vb)) if va.size else 0.0
        n_checked += 1
        if d > worst:
            worst, worst_var = d, '%s/%s' % (name, v)
    a.close(); b.close()

print('checked %d variables across %d file(s)' % (n_checked, len(common)))
if worst == 0.0:
    print('MATCH: all variables identical')
else:
    print('DIFF: largest absolute difference %g in %s' % (worst, worst_var))
    sys.exit(1)
PY
"
