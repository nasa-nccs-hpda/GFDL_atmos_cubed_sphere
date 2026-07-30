# Bootstrap: starting the next experiment from the FV transfer work

This is a self-contained handoff. A new session should be able to read only this
file and pick up the work — where things stand, how to build and run, where the
code lives, what is known to break, and the candidate next experiments with a
concrete first step for each.

Plain-language reader's summary is in
[`fv_transfer_algorithm_change_summary.md`](fv_transfer_algorithm_change_summary.md).
The deeper record lives in the persistent memory note `fv-transfer-poc-plan`.

---

## 1. Where the work stands (as of 2026-07-30)

The question was whether changing the numerical method — from the spectral core,
whose every step reshuffles data across all GPUs through the host, to a
local-stencil method that only swaps a thin edge with its two neighbors — is a
worthwhile way to beat the GPU data-transfer bottleneck.

We did **not** replace the spectral core. We used an FV advection kernel already
in the repository as a stand-in for a local-stencil method, and moved its three
neighbor edge-swaps off the host and directly between GPUs over NVLink using NCCL.
A runtime switch selects the old host-routed path or the new GPU-to-GPU path in one
binary.

Established results:

- **Bit-exact.** The GPU-to-GPU path matches the host-routed path bit for bit
  across all 20 output fields, at both 2 GPUs and 4 GPUs. The 4-GPU run is what
  proves the **interior-rank** case — a rank with a real neighbor on both sides and
  no pole to fold against — which the 2-GPU layout never produces.
- **All host MPI halo removed.** On the device path the count of host-side neighbor
  swaps in the advection inner loop is zero.
- **The win is set by slice height** (rows of latitude per GPU = latitude count ÷
  number of GPUs), not resolution by itself. The swap moves a fixed two-row strip;
  interior work grows with rows, so a taller slice makes the swap a smaller
  fraction. Measured: 32 rows → ~4.6% slower; 64 rows → wash to ~1% win; 128 rows →
  ~2% win. Finer resolution helps (taller slices); more GPUs at a fixed resolution
  hurts (shorter slices).
- **T340 is unmeasured** at both rank counts: 2 GPUs is memory-bound (96% of 32 GB,
  no finish in 4 h); 4 GPUs stepped for 4.5 h but the host-routed reference leg died
  with a bus error (host-memory limit) before the device path ran, leaving nothing
  to compare against.

Status: proof-of-concept, the live-model wiring (called Level 1), and the
resolution sweep are all complete. The thesis is demonstrated end-to-end in the
live model. Not production, not climate validation.

---

## 2. Environment and fixed facts

- **Machine:** NASA Explore/ADAPT GPU nodes, 4× NVIDIA V100 (32 GB) per node over
  intra-node NVLink. Nodes seen: gpu015, gpu019, gpu022. QOS `normal` limits are
  `cpu=800, node=4`; there is no per-user GPU cap.
- **Branch:** `gpu/fv-transfer-poc`. Base branch for PRs: `geos/main`.
- **Cluster checkout:**
  `/explore/nobackup/people/rlgill/innovation-lab-repositories/GFDL_atmos_cubed_sphere`
- **Local checkout:**
  `/Users/rlgill/Desktop/Source/innovation-lab-repositories/GFDL_atmos_cubed_sphere`
  The two are separate: commit and push locally, then `git pull` on the cluster
  checkout before every rebuild.
- **Container (node-local, no shared copy):** `/lscratch/rlgill/isca-debian_latest`.
  Build it if a node lacks it (the sbatch wrappers do this automatically):
  `singularity build --sandbox /lscratch/rlgill/isca-debian_latest docker://nasanccs/isca-debian:latest`
- **Isca work/data dirs:**
  - `GFDL_WORK=/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_work`
  - `GFDL_DATA=/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_data`
- **Resolution → timestep (CFL) and FMS stack:**
  - T42 dt=600; T85 dt=300 STACK=8000000; T170 dt=150 STACK=8000000; T340 dt=75
    STACK=40000000. (`STACK` sets `fms_nml domains_stack_size`; the default overflows
    the diag gather above T42.)
  - Rows of latitude by resolution: T85=128, T170=256, T340=512. Divide by the GPU
    count for slice height.

---

## 3. How to build and run

### Build (on the cluster, inside the container)

The device NCCL halo is behind a build flag so the default build is unchanged.
`compile_native_overlay.py` sets `USE_FV_ADVECTION_NCCL=1` when building CUDA,
which adds `-DFV_ADVECTION_USE_NCCL -ccbin mpicxx` and links `-lnccl`. The
executable is `held_suarez_fv_kernels_cuda.x`.

### Run — one binary, two paths, selected at runtime

Key environment variables (the scripts set these):

- `GFDL_ENV=hybrid`, `HS_FORCE_BACKEND=cuda`
- `FV_KERNELS_CUDA_MODE=resident` — keep fields resident on the GPU between steps
- `FV_KERNELS_PROFILE=1` — emit the `PROFILE_FV_ADVECTION_CUDA` timing lines
- `FV_ADVECTION_NCCL_HALO=1` — GPU-to-GPU path on; unset/0 = host-routed reference
- `OMPI_MCA_plm=isolated` — fork ranks on the local node, ignore Slurm (mpirun
  otherwise shells out to `srun`, which is absent from the container)
- `OMPI_MCA_rmaps_base_oversubscribe=1`, `OMPI_MCA_btl_vader_single_copy_mechanism=none`

### The two batch wrappers (disconnect-safe — always prefer these over `salloc`)

Both request a full node's 4 GPUs with `--gres=gpu:4 --nodes=1` (note: `-G 4` was
silently granting only 2 GPUs), pin `GFDL_BASE_OVERRIDE` to the `/explore` path
(Slurm records the submit dir as the resolved `/panfs/...` path, but Isca keys the
build under the `/explore` string), and stage the container if the node lacks it.
`NP` follows the allocation (one rank per GPU). Submit from the repo root:

- Correctness: `sbatch hybrid_experiments/held_suarez_cpp_force/run_nccl_correctness.sbatch`
  → runs host and device paths, bit-compares every field, prints
  `MATCH: all variables identical` or a `DIFF` line. **Always run this and confirm
  MATCH before trusting any timing**, especially after touching the exchange, the
  fold, or the rank layout.
- Sweep: `RES=T170 DT_ATMOS=150 STACK=8000000 REPEAT=3 sbatch hybrid_experiments/held_suarez_cpp_force/run_nccl_sweep.sbatch`
  → runs both paths REPEAT times and prints the transfer-cost table.

Watch a job: `squeue -j <id> -o "%.10i %.9T %.6M"`; results in `logs/nccl_*_<id>.out`.

### Reading the profile output

`PROFILE_FV_ADVECTION_CUDA` lines carry `total`, `h2d`, `d2h`, `kernel`, `sync`,
and host-halo counts. The counter `n` = REPEAT × ranks, so at REPEAT=3, `n=6`
means np=2 and `n=12` means np=4 — this is how a silent np=2 run gets caught. Also
check `world_size` and `device_count` in the `nccl_init` lines.

---

## 4. Where the code lives

- **Fortran spine (the runtime switch):**
  `src/extra/local_overrides/fv_advection_kernels/fv_advection.F90` — wraps the host
  `mpp_update_domains` calls and polar fold in `if (.not. use_device_halo)`.
- **CUDA kernels + NCCL exchange/fold:**
  `translated/held_suarez/cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu`
  (and `.h`) — `exchange_q1_halo_nccl` (pack / grouped `ncclSend`/`ncclRecv` /
  unpack), `polar_fold_q1_kernel`, sign-flipping `polar_fold_vx_kernel`, communicator
  setup, event-based ordering (`cudaStreamWaitEvent` on `halo_done`, no per-call
  blocking sync).
- **C interface (Fortran ↔ CUDA):**
  `translated/held_suarez/cpp/fv_advection/kernels/fortran/fv_advection_kernels_c_interface.F90`
- **Build wiring:** `hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py`
- **Driver:** `hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py`
  (`--num-cores` = ranks, `--days`, `--domains-stack-size`, `--overwrite`).
- **Correctness compare:** `hybrid_experiments/held_suarez_cpp_force/compare_nccl_correctness.sh`
  — the container has no python NetCDF backend and no `ncdump`; output is NETCDF3
  classic, so this reads it with a **ctypes bind to `libnetcdf.so.19`**.
- **Standalone NCCL benchmarks / smoke tests:** `tests/poc/` (`nccl_smoke.cu` = pass,
  `cuda_aware_mpi_smoke.cu` = negative control proving container MPI is not
  GPU-aware, `halo_exchange_bench.cu` = the PoC halo benchmark).
- **Prior write-ups:** `docs/fv_transfer_poc_plan.md`, `docs/fv_transfer_poc_results.md`,
  `docs/fv_nccl_advection_scope.md`, `docs/fv_nccl_algorithm_change_summary.md`,
  `docs/fv_transfer_algorithm_change_summary.md`.

---

## 5. Known blockers and gotchas

- **GPU request:** use `--gres=gpu:4 --nodes=1`. `-G 4` (`--gpus=4`) silently grants
  only 2 GPUs on these nodes. Confirm `SLURM_GPUS_ON_NODE=4` and four devices in the
  log before trusting a "4-GPU" run.
- **Container:** node-local only. A job landing on a fresh node must build it first;
  the sbatch wrappers do this automatically, so a fresh node just costs one build.
- **`GFDL_BASE_OVERRIDE`:** must point at the `/explore` path or the build is not
  found ("Hybrid executable not found").
- **`salloc` teardown:** an interactive allocation dies when the SSH session drops
  and takes the run with it (this killed an overnight T340 run). Use `sbatch`.
- **Time limit:** users cannot raise a running job's `TimeLimit` here
  (`scontrol update ... TimeLimit=` is denied). Request enough up front.
- **The launcher fix** (`OMPI_MCA_plm=isolated`) is required for interactive
  `apptainer exec ... mpirun`; the sbatch path wires PMI directly and does not need
  it, but it is set in both scripts so the paths behave the same.
- **T340 host-memory bus error:** at np=4 the host-routed reference leg died with
  SIGBUS after ~4.5 h — a host-memory limit (shared memory / output buffers), not a
  code fault. Any T340 attempt must address this (see next section).

---

## 6. Candidate next experiments (pick one)

Each is a distinct experiment building on this one. Ordered roughly by size.

### A. Overlap the exchange with interior compute (small, high value)
The T85 loss and the shrinking win at np=4 come from the exchange not being fully
hidden behind computation. The event-based ordering is already in place
(`halo_done` + `cudaStreamWaitEvent`); the next step is to start the NCCL exchange
at the top of the step, run the interior flux kernels that do not touch the halo
concurrently, and only wait on the halo just before the kernels that read it. Goal:
turn the small-slice loss into a wash or win, which would push the crossover to
lower resolution and make the win survive more GPUs.
**First step:** profile where the compute stream currently stalls on `halo_done`;
reorder the interior kernels ahead of the wait.

### B. Capture the tallest-slice point (small, closes a gap)
Get one measurement at 128 rows per GPU at high resolution — T340 on 4 GPUs — by
getting past the host-memory bus error: lower `STACK`, trim the diag output, or run
a partial day just long enough for paired host-vs-device timing. This would confirm
the ~2% projection at the largest interior-to-edge ratio.
**First step:** reproduce the SIGBUS with memory instrumentation to identify which
allocation faults, then reduce it.

### C. Scale out (medium)
Push past one node: multi-node NCCL over the inter-node fabric (not just intra-node
NVLink), and/or rank-per-GPU at higher GPU counts. This tests whether the win holds
when the exchange leaves NVLink, and measures how slice height and interconnect
interact.
**First step:** a two-node NCCL smoke test in `tests/poc/`, then extend the sbatch
wrappers to `--nodes=2`.

### D. Replace the spectral core with the FV3 finite-volume core (large — the prize)
The real algorithm change. Retire the spectral method rather than tune it: the FV3
finite-volume cubed-sphere core drops the Fourier and Legendre transforms and the
host-staged transpose entirely, computes with local flux operators reading only
neighboring cells, and communicates only by nearest-neighbor halo exchange — the
exact GPU-to-GPU pattern this work validated. Note from the source survey: there is
no dry FV solo Held-Suarez driver in the repo, and nothing currently calls
`fv_dynamics`, so this is a new build, not a wiring change. Trade-offs: a much
larger solver; results match the spectral model only in a statistical (climate)
sense, not bit for bit, so validation changes from bit-compare to climate
statistics; and per-GPU memory becomes the leading constraint — the aborted T340
runs are the early warning.
**First step:** scope what a minimal dry FV3 Held-Suarez driver needs (which FV3
core sources, the grid/initialization path, the halo interface) and whether any of
it can be reused from elsewhere.

---

## 7. Working conventions for the next session

- Commit and push locally, then `git pull` on the cluster before every rebuild.
- During a runbook, give only the immediate next step, tersely, and emit the full
  environment/module block each step (do not send only the delta).
- Transfer scripts to the cluster through git, not large terminal pastes (the SSH
  terminal drops characters on big pastes).
- Long-running scripts must stream progress (`tee`), not run silently.
- Plain language. Avoid the word "honest". No slang, no whimsical status verbs.
- Commit and push only when asked.
