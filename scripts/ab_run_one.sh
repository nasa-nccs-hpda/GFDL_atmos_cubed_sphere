#!/usr/bin/env bash
# In-container model run for the metrics-resident A/B. Expects LABEL in env;
# resolution/levels/dt/days come from AB_RES/AB_LEVELS/AB_DT/AB_DAYS (T85 defaults).
# Runs with the CURRENTLY-BUILT held_suarez_fv_kernels_cuda.x exe.
set -e
export GFDL_BASE=/explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_data
export GFDL_ENV=hybrid
export FV_KERNELS_CUDA_MODE=resident
export FV_KERNELS_PROFILE=1
export OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_MCA_btl_vader_single_copy_mechanism=none
RES="${AB_RES:-T85}"
LEVELS="${AB_LEVELS:-25}"
DT="${AB_DT:-300}"
DAYS="${AB_DAYS:-5}"
cd "$GFDL_BASE"
time python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --executable-name held_suarez_fv_kernels_cuda.x \
  --exp-name "held_suarez_ab_${LABEL}_${RES}L${LEVELS}_${DAYS}day" \
  --resolution "$RES" --levels "$LEVELS" --dt-atmos "$DT" --days "$DAYS" \
  --production-diag --num-cores 16 --overwrite
