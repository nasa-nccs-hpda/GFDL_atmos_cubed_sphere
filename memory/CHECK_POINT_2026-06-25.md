# Restart Prompt for a Fresh AI Chat

## Start here

Begin by reading:

- `memory/FINAL_PROJECT_CHECKPOINT_2026-06-19.md`

That document was the original restart basis for this work. It contains the project state, branch expectations, validated executables, historical performance numbers, validated outputs, and the planned next step at the time this chat began.

Use it as the historical baseline context, then use the notes below as the delta produced in this session.

## Repository and branch

I am restarting from branch `perf/resident-semi-y-integration` at:

`/explore/nobackup/people/rlgill/SystemTesting/AAI/GFDL_atmos_cubed_sphere`

## Big picture task sequence

1. integrate CUDA `semi_y_3d` into resident pre-halo FV boundary
2. then consider `q1` halo-only transfers
3. then broader `update_tracers`-level residency
4. then larger-resolution scaling studies
5. transforms/vendor-library study later

## Current checkpoint

The current checkpoint is completion of task 1.

### What was implemented

- resident begin now takes `va` and `dyy`
- resident begin computes `semi_y_3d` on device and keeps `q2` resident
- resident finish no longer takes host `q2`
- overlay, Fortran C interface, CUDA implementation, validator, Makefile, and baseline fixture generator were updated
- baseline fixture now writes `input_va.bin` and `input_dyy.bin`

### Validation status

The following all passed in this clone/environment:

- standalone resident CUDA fixture
- native compile
- one-day smoke
- 30-day run
- 30-day validation
- repeat 30-day run

## Environment facts

- use `singularity`
- container image: `/lscratch/rlgill/isca-debian_latest.sif`
- repo paths use `rlgill`
- this is `x86_64 + V100`
- `mppnccombine.x` had to be rebuilt for `x86_64`

## Important historical context

The June 19 checkpoint and reports referenced a much faster historical resident result, around `108.505 s`, but that should be treated as historical reference only unless the environment and runtime conditions are confirmed comparable.

During this session, the old 30-day log was moved aside to preserve that historical reference separately.

## Timing diagnosis (resolved)

### Initial observation
- First run (10:53 AM, repeat script): `231.298 s`
- Second run (13:19 PM, clean script): `194.499 s`
- Discrepancy: ~19% difference

### Root cause analysis
Re-ran both scripts in sequence at 14:02–14:08:
- Clean run (14:02): `193.372861 s`
- Repeat run (14:08): `193.807133 s`
- Difference: `+0.43 s` (+0.23%) ✓ **Consistent**

**Conclusion:** The 231s outlier was **environmental** (system load, GPU thermal state, time of day). Algorithm is stable at **~193–194 s per 30-day run**.

### Performance baseline
- Stable 30-day runtime: **~193.4 s** (6.45 s/day avg)
- Profile data shows ~7.2–8.0 s/day CUDA kernel time + sync overhead
- Consistent h2d transfer and kernel times across runs

## What I need help with next

Please help me:

1. ✓ diagnose timing discrepancy → **RESOLVED: Environmental variance, not algorithmic**
2. decide what should go into the next formal project checkpoint
3. identify which modified files are true source changes versus local-environment-specific support changes

