# Held-Suarez Forcing Module Profiling Report

Date: 2026-06-15

## Question

Is the Held-Suarez forcing module large enough to justify CUDA offload?

Short answer: probably not as a first CUDA target for the current Held-Suarez
prototype unless full-model profiling shows that forcing is a surprisingly
large fraction of wall-clock time.  The module is small, called once per
atmosphere step, and dominated by a few simple loops plus `log`/`pow` in the
Newtonian temperature relaxation.  The most useful result of this work is a
low-overhead profiling path that can now measure the real fraction in a
30-day or longer hybrid run.

## Instrumented Call Path

The current hybrid path is:

```text
Fortran atmosphere
  -> hs_forcing_mod::hs_forcing
  -> hs_forcing_c_interface::hs_forcing_driver_c_wrapper
  -> hs_forcing_driver_c
  -> hs_forcing::hs_forcing_driver
  -> hs_forcing::rayleigh_damping
  -> hs_forcing::newtonian_damping
```

Top-level entry points called from Fortran:

- `hs_forcing_mod::hs_forcing`
  - File: `src/extra/local_overrides/hs_forcing/hs_forcing.F90`
  - This is the model-facing overlay replacement for the original
    `atmos_param/hs_forcing/hs_forcing.F90`.
- `hs_forcing_c_interface::hs_forcing_driver_c_wrapper`
  - File:
    `translated/held_suarez/cpp/forcing_module/fortran/hs_forcing_c_interface.F90`
  - This is the Fortran `iso_c_binding` wrapper.
- `hs_forcing_driver_c`
  - File:
    `translated/held_suarez/cpp/forcing_module/src/held_suarez_c_api.cpp`
  - This is the C ABI entry point.
- `hs_forcing::hs_forcing_driver`
  - File:
    `translated/held_suarez/cpp/forcing_module/include/held_suarez_forcing.hpp`
  - This is the C++ forcing implementation.

## Profiling Controls

Profiling is runtime-gated by:

```bash
HS_PROFILE=1
```

Default behavior is unchanged when `HS_PROFILE` is unset or set to `0`.

The C++ summary prints at process exit.  The Fortran wrapper summary prints from
`hs_forcing_end` in the hybrid overlay.  No Fortran/C API signatures were
changed.

## Timed Regions

Fortran wrapper:

- `fortran_iso_c_wrapper`
  - Measures the wrapper region around the C call.
  - Includes default-parameter loading, temporary 2D coordinate expansion, the
    C call, and deallocation.

C/C++ regions:

- `c_interface_entry`
- `cpp_forcing_driver`
- `rayleigh_damping`
- `rayleigh_mask`
- `newtonian_lat_precompute`
- `newtonian_vertical`
- `newtonian_mask`
- `topdown_lat_precompute`
- `topdown_orbit_hour_angle`
- `topdown_insolation`
- `topdown_radiative_balance`
- `topdown_tropopause`
- `topdown_surface_temperature`
- `topdown_stratosphere`
- `topdown_vertical`
- `topdown_temperature_tendency`
- `topdown_mask`
- `energy_conservation`
- `accumulate_wind`
- `accumulate_temperature`

The current model wrapper selects standard Held-Suarez mode, so the expected
full-model hotspots are:

1. `newtonian_vertical`
2. `newtonian_lat_precompute`
3. `rayleigh_damping`
4. `accumulate_wind`
5. `accumulate_temperature`

The `topdown_*` regions are instrumented for standalone tests and future
top-down configurations, but they should not appear in the current
`held_suarez_hybrid.x` run.

## Local Verification

The C++ library and standalone comparison driver compile locally:

```bash
cd translated/held_suarez/cpp/forcing_module
make all
```

The standalone C++ validation driver passes with profiling enabled:

```bash
HS_PROFILE=1 ./bin/driver_forcing_module ../../../../tests/fortran_baseline held_suarez
```

Validation result:

- Standard Held-Suarez mode: pass.
- Top-down Newtonian damping mode: pass.
- C API wrapper test: pass.

Example profiler output from the tiny standalone harness:

```text
region,calls,total_seconds,avg_seconds,cells,seconds_per_cell,fraction_of_cpp_driver
cpp_forcing_driver,1,6.240200000e-05,6.240200000e-05,160,3.900125000e-07,1.000000
rayleigh_damping,1,1.041000000e-06,1.041000000e-06,160,6.506250000e-09,0.016682
newtonian_lat_precompute,2,2.830300000e-05,1.415150000e-05,64,4.422343750e-07,0.453559
newtonian_vertical,2,4.553200000e-05,2.276600000e-05,320,1.422875000e-07,0.729656
accumulate_wind,1,3.410000000e-07,3.410000000e-07,160,2.131250000e-09,0.005465
accumulate_temperature,1,1.900000000e-07,1.900000000e-07,160,1.187500000e-09,0.003045
```

These numbers are only a profiler smoke test.  The grid is too small to answer
the CUDA-offload question.

Fortran integration harness status:

- Not compiled in this shell because `gfortran` is unavailable.
- The full model build should be checked in the same Apptainer environment used
  for the successful hybrid executable.

## Full-Model Profiling Command

Rebuild the hybrid executable in the container so the updated static library is
used:

```bash
./run_compile_hybrid.sh
```

Then run a profiled 30-day hybrid simulation inside the same container
environment:

```bash
cd /explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
HS_PROFILE=1 /usr/bin/time -p \
  python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
    --days 30 \
    --production-diag \
    --overwrite \
  2>&1 | tee logs/hybrid_hs_profile_30day.log
```

If launching through Apptainer from outside the container, pass the environment
explicitly:

```bash
APPTAINERENV_HS_PROFILE=1 apptainer exec \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  /lscratch/jli30/isca-sandbox \
  bash -lc 'cd /explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere && /usr/bin/time -p python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py --days 30 --production-diag --overwrite' \
  2>&1 | tee logs/hybrid_hs_profile_30day.log
```

The model fraction should be computed as:

```text
forcing_fraction = fortran_iso_c_wrapper.total_seconds / time_real_seconds
```

The C++ implementation fraction alone can also be computed:

```text
cpp_fraction = cpp_forcing_driver.total_seconds / time_real_seconds
```

## Metrics To Report From Full-Model Run

Required fields:

- Number of forcing calls:
  - `fortran_iso_c_wrapper.calls`
  - `cpp_forcing_driver.calls`
- Total forcing runtime:
  - `fortran_iso_c_wrapper.total_seconds`
  - `cpp_forcing_driver.total_seconds`
- Average time per call:
  - `fortran_iso_c_wrapper.avg_seconds`
  - `cpp_forcing_driver.avg_seconds`
- Fraction of total model wall-clock time:
  - `fortran_iso_c_wrapper.total_seconds / /usr/bin/time real`
  - `cpp_forcing_driver.total_seconds / /usr/bin/time real`
- Top hotspot loops/functions:
  - Sort C++ regions by `total_seconds`.

Suggested acceptance thresholds for CUDA exploration:

- If `fortran_iso_c_wrapper` is less than 5% of model wall time, CUDA offload of
  this module alone is not justified.
- If `fortran_iso_c_wrapper` is 5-15%, CUDA may be useful only if data movement
  is eliminated by keeping model state resident on device across many kernels.
- If `fortran_iso_c_wrapper` is greater than 15%, a CUDA prototype is worth
  considering, but the next step should still include data-transfer modeling.

## Arithmetic Intensity Estimate

Assume double precision, 8 bytes per scalar.

### Rayleigh damping

Main loop:

```text
for k, j, i:
  rps = 1 / ps
  sigma = p_full * rps
  if sigma in layer:
    vfactr = vcoeff * (sigma - sigma_b)
    udt = vfactr * u
    vdt = vfactr * v
  else:
    udt = 0
    vdt = 0
```

Approximate FLOPs per 3D cell:

- 1 divide.
- 2-4 multiplies.
- 1 subtract.
- Comparisons and branch.
- Total: about 5-8 scalar FLOPs, plus branch/control overhead.

Approximate bytes per 3D cell:

- Loads: `ps`, `p_full`, `u`, `v`: 32 bytes.
- Stores: `udt`, `vdt`: 16 bytes.
- Total: about 48 bytes.

Arithmetic intensity:

```text
~0.10-0.17 FLOP/byte
```

Likely bound:

- Memory-bound.
- Poor standalone CUDA target unless fused with other kernels or run on data
  already resident on GPU.

### Newtonian latitude precompute

Main loop:

```text
for j, i:
  sin_lat = sin(lat)
  sin_lat_2 = sin_lat^2
  cos_lat_2 = 1 - sin_lat_2
  cos_lat_4 = cos_lat_2^2
  t_star = t_zero - delh*sin_lat_2 - eps*sin_lat
  tstr = t_strat - eps*sin_lat
```

Approximate FLOPs per 2D cell:

- 1 `sin`.
- About 8-10 scalar arithmetic operations.

Approximate bytes per 2D cell:

- Load: `lat`: 8 bytes.
- Stores: `sin_lat`, `sin_lat_2`, `cos_lat_2`, `cos_lat_4`, `t_star`, `tstr`:
  48 bytes.
- Total: about 56 bytes.

Arithmetic intensity:

```text
~0.15-0.20 scalar FLOP/byte, plus one transcendental
```

Likely bound:

- Mixed memory and special-function latency.
- Small 2D loop; not attractive as a standalone CUDA kernel.

### Newtonian vertical loop

Main loop:

```text
for k, j, i:
  p_norm = p_full / P00
  the = t_star - delv*cos_lat_2*log(p_norm)
  teq = max(the * pow(p_norm, kappa), tstr)
  rps = 1 / ps
  sigma = p_full * rps
  tdamp = ...
  tdt = -tdamp * (t - teq)
```

Approximate FLOPs per 3D cell:

- 2 divides.
- About 12-18 scalar arithmetic operations.
- 1 `log`.
- 1 `pow`.
- Comparisons/branch.

Approximate bytes per 3D cell:

- Loads: `p_full`, `ps`, `t`, `t_star`, `tstr`, `cos_lat_2`, `cos_lat_4`:
  about 56 bytes.
- Stores: `teq`, `tdt`: 16 bytes.
- Total: about 72 bytes.

Arithmetic intensity:

```text
~0.20-0.30 scalar FLOP/byte, plus log/pow special-function work
```

Likely bound:

- Special-function/compute latency can dominate the core arithmetic.
- On GPU this loop could use many threads, but the total work is still modest
  at Held-Suarez resolution.
- CUDA benefit is unlikely if host-device copies are required for every call.

### Accumulation loops

Wind accumulation:

```text
udt += utnd
vdt += vtnd
```

Temperature accumulation:

```text
tdt += ttnd
```

Approximate arithmetic intensity:

- Wind: 2 FLOPs and about 64 bytes per cell.
- Temperature: 1 FLOP and about 24 bytes per cell.

Likely bound:

- Strongly memory-bound.
- Should be fused with producer kernels for any GPU port.

## Preliminary CUDA Assessment

The forcing module is probably not large enough to justify CUDA offload by
itself in the current model structure.

Reasons:

- Standard Held-Suarez forcing has only a few simple grid loops per timestep.
- Rayleigh damping and accumulation are clearly memory-bound.
- Newtonian damping has heavier `log`/`pow` work, but it is still a compact
  column-local kernel.
- A naive CUDA port would require moving `u`, `v`, `t`, `ps`, `p_full`, `udt`,
  `vdt`, `tdt`, and `teq` across the PCIe/NVLink boundary unless the broader
  model state is already on device.
- If data movement happens per forcing call, transfer cost will likely exceed
  kernel speedup.
- The next Held-Suarez dynamics candidates, such as `four_in_one`,
  pressure/geopotential, vertical advection, and spectral transforms, are more
  likely to provide meaningful GPU work.

Current recommendation:

- Use the new profiler in a 30-day full-model run before CUDA work.
- Do not start with a standalone CUDA offload of only the forcing module unless
  the full-model forcing fraction is above about 5-10%.
- If the goal is GPU workflow development rather than speedup, forcing remains
  a useful low-risk CUDA plumbing exercise, but it should not be expected to
  move end-to-end model time much.

## CUDA Port Plan If Profiling Is Promising

If full-model profiling shows that forcing is a meaningful wall-clock fraction:

1. Create a CUDA build variant of `libhs_forcing`.
2. Keep the existing C API stable.
3. Add a runtime/backend selector, for example `HS_BACKEND=cpu|cuda`.
4. Start with standard Held-Suarez mode only:
   - Rayleigh damping.
   - Newtonian latitude precompute.
   - Newtonian vertical loop.
   - Fused tendency accumulation.
5. Fuse kernels where possible:
   - Combine Rayleigh damping and wind accumulation.
   - Combine Newtonian damping and temperature accumulation.
   - Avoid separate accumulation-only kernels.
6. Avoid per-call allocation:
   - Reuse device temporaries.
   - Precompute latitude-only arrays once if grid is fixed.
7. Avoid per-call host-device copies:
   - CUDA is only promising if the broader model state can stay on device, or
     if this prototype is explicitly testing an eventual device-resident model.
8. Validate progressively:
   - CPU C++ versus CUDA kernel on standalone baseline arrays.
   - Fortran -> C API -> CUDA on standalone harness.
   - 1-day hybrid CUDA smoke run.
   - 30-day CPU-hybrid versus CUDA-hybrid output comparison.
9. Profile again:
   - Kernel time.
   - Transfer time.
   - End-to-end model wall-clock time.

The CUDA port should be considered successful only if it improves end-to-end
runtime, not just isolated kernel time.

## Files Changed For Profiling

- `translated/held_suarez/cpp/forcing_module/include/held_suarez_forcing.hpp`
  - Added runtime-gated C++ profiling helpers and timers around driver,
    damping, top-down, and accumulation regions.
- `translated/held_suarez/cpp/forcing_module/src/held_suarez_c_api.cpp`
  - Added C ABI entry timer for `hs_forcing_driver_c`.
- `translated/held_suarez/cpp/forcing_module/fortran/hs_forcing_c_interface.F90`
  - Added runtime-gated Fortran wrapper timer and summary printer.
- `src/extra/local_overrides/hs_forcing/hs_forcing.F90`
  - Calls the Fortran wrapper profile printer during `hs_forcing_end`.

## Verification Performed

Local:

```bash
cd translated/held_suarez/cpp/forcing_module
make all
HS_PROFILE=1 ./bin/driver_forcing_module ../../../../tests/fortran_baseline held_suarez
```

Result:

- C++ compile succeeded.
- Standalone validation passed.
- C++ profiler emitted expected CSV-style summary.

Not performed locally:

- Fortran integration harness compile, because `gfortran` is unavailable in this
  shell.
- Full Apptainer/container model build and 30-day profiled run, because this
  shell does not provide the same container runtime path used for manual model
  runs.
