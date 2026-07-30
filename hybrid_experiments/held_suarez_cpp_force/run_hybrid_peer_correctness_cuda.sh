#!/usr/bin/env bash
# FV transfer PoC (peer backend) correctness check: run the resident FV
# advection path twice at the same rank count, once with the host-routed q1
# halo (reference) and once with the direct NVLink peer-copy halo path, then
# compare the output field by field.
#
# The peer path is designed to reproduce the host mpp_update_domains(q1) and
# polar fold exactly -- it fills the same halo rows, just by a cudaMemcpy2DAsync
# pulled from the neighbor's resident buffer instead of packing/sending. So the
# two runs should match bit for bit. Any nonzero difference is a bug in the peer
# copy geometry, the IPC handle exchange, or the ordering.
#
# Pass = "MATCH: all variables identical". A "DIFF" line names the first field
# that disagrees and its largest absolute difference.
set -euo pipefail

CONTAINER=${CONTAINER:-/lscratch/rlgill/isca-debian_latest}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

export GFDL_BASE=${GFDL_BASE_OVERRIDE:-${SCRIPT_DIR}}
export GFDL_WORK=${GFDL_WORK:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_work}
export GFDL_DATA=${GFDL_DATA:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_data}

REF_EXP=peer_correctness_host
DEV_EXP=peer_correctness_device

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
# Fork ranks locally and ignore Slurm. Inside an interactive salloc, mpirun
# otherwise selects its Slurm launch module and shells out to srun, which is
# absent from the container; isolated launches on the local node directly.
export OMPI_MCA_plm=isolated

cd ${GFDL_BASE}
mkdir -p logs

# Rank/GPU count. np>=3 is what exercises the interior-rank device exchange
# (a rank with two real neighbors and no pole fold) that np=2 never reaches.
NP='${NP:-2}'

run_case () {
  local exp_name=\$1
  echo \"=== running \${exp_name} (FV_ADVECTION_PEER_HALO=\${FV_ADVECTION_PEER_HALO:-0}) np=\${NP} ===\"
  python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
    --exp-name \${exp_name} \
    --executable-name held_suarez_fv_kernels_cuda.x \
    --num-cores \${NP} \
    --days 1 \
    --overwrite
}

# Reference: host-routed halo (device halo path off).
unset FV_ADVECTION_PEER_HALO
run_case ${REF_EXP}

# Device: direct NVLink peer-copy halo path on.
export FV_ADVECTION_PEER_HALO=1
run_case ${DEV_EXP}

echo '=== both peer correctness runs produced; compare with compare_nccl_correctness.sh ==='
echo '=== (REF_EXP=${REF_EXP} DEV_EXP=${DEV_EXP}) ==='
"
