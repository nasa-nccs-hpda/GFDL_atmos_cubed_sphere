#!/usr/bin/env bash
# Level 1, Phase A, Step 4 measurement: run the resident FV advection np=2 case
# twice (host-routed q1 halo, then the GPU-to-GPU NCCL halo) and compare the
# transfer cost. Shows what moving the q1 halo onto the GPU removed:
#   PROFILE_FV_ADVECTION_HALO  time= : host mpp_update_domains(q1) wall time
#                                      (should fall on the device path; only the
#                                      remaining non-q1 host swaps are left)
#   PROFILE_FV_ADVECTION_CUDA  h2d=  : host->device copy per resident call
#                                      (should fall: the q1 halo upload and the
#                                      begin q1-edge download are gone)
#                              kernel=: device compute (the NCCL exchange + fold
#                                      now show up here)
# Correctness (bit-for-bit) is checked separately by compare_nccl_correctness.sh.
set -euo pipefail

CONTAINER=${CONTAINER:-/lscratch/rlgill/isca-debian_latest}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

export GFDL_BASE=${GFDL_BASE_OVERRIDE:-${SCRIPT_DIR}}
export GFDL_WORK=${GFDL_WORK:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_work}
export GFDL_DATA=${GFDL_DATA:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_data}

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

run_case () {
  local exp_name=\$1 log=\$2
  echo \"=== running \${exp_name} (FV_ADVECTION_NCCL_HALO=\${FV_ADVECTION_NCCL_HALO:-0}) ===\"
  python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
    --exp-name \${exp_name} \
    --executable-name held_suarez_fv_kernels_cuda.x \
    --num-cores 2 \
    --days 1 \
    --overwrite > \${log} 2>&1
}

HOST_LOG=logs/nccl_measure_host.log
DEV_LOG=logs/nccl_measure_device.log

unset FV_ADVECTION_NCCL_HALO
run_case nccl_measure_host \${HOST_LOG}

export FV_ADVECTION_NCCL_HALO=1
run_case nccl_measure_device \${DEV_LOG}

echo '=== transfer cost: host-routed halo vs GPU-to-GPU NCCL halo ==='
python3 - \"\${HOST_LOG}\" \"\${DEV_LOG}\" <<'PY'
import re, sys

def avg(path, pattern, keys):
    sums = {k: 0.0 for k in keys}; n = 0
    with open(path) as f:
        for line in f:
            m = pattern.search(line)
            if not m:
                continue
            n += 1
            for k in keys:
                sums[k] += float(m.group(k))
    return ({k: sums[k] / n for k in keys}, n) if n else ({}, 0)

halo_re = re.compile(
    r'PROFILE_FV_ADVECTION_HALO .*?calls=\s*(?P<calls>\d+).*?'
    r'time=\s*(?P<time>[-+0-9.eE]+).*?avg=\s*(?P<avg>[-+0-9.eE]+)')
cuda_re = re.compile(
    r'PROFILE_FV_ADVECTION_CUDA backend=\S+ rank=\S+ calls=\d+ .*?'
    r'h2d=(?P<h2d>[-+0-9.eE]+) kernel=(?P<kernel>[-+0-9.eE]+) '
    r'sync=(?P<sync>[-+0-9.eE]+) d2h=(?P<d2h>[-+0-9.eE]+) .*?'
    r'total=(?P<total>[-+0-9.eE]+)')

host_log, dev_log = sys.argv[1], sys.argv[2]

def show(label, log):
    print('--- %s (%s) ---' % (label, log))
    h, hn = avg(log, halo_re, ['calls', 'time', 'avg'])
    if hn:
        print('  host halo timer: per-rank calls=%.0f time=%.4fs avg=%.6fs (n=%d ranks)'
              % (h['calls'], h['time'], h['avg'], hn))
    else:
        print('  host halo timer: no PROFILE_FV_ADVECTION_HALO lines'
              ' (all host halo skipped)')
    c, cn = avg(log, cuda_re, ['h2d', 'kernel', 'sync', 'd2h', 'total'])
    if cn:
        print('  resident CUDA: h2d=%.6f kernel=%.6f sync=%.6f d2h=%.6f total=%.6f'
              ' (n=%d counters)'
              % (c['h2d'], c['kernel'], c['sync'], c['d2h'], c['total'], cn))
    return h, c

hh, hc = show('host-routed halo', host_log)
dh, dc = show('GPU-to-GPU NCCL halo', dev_log)

print('--- delta (device - host) ---')
if hh and dh:
    print('  host halo time/rank: %.4fs -> %.4fs' % (hh['time'], dh.get('time', 0.0)))
if hc and dc:
    print('  resident h2d:  %.6f -> %.6f' % (hc['h2d'], dc['h2d']))
    print('  resident d2h:  %.6f -> %.6f' % (hc['d2h'], dc['d2h']))
    print('  resident kernel: %.6f -> %.6f' % (hc['kernel'], dc['kernel']))
    print('  resident total:  %.6f -> %.6f' % (hc['total'], dc['total']))
PY
"
