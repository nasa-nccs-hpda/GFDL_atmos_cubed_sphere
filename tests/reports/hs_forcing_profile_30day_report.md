# Held-Suarez Forcing 30-Day Profile Report

Date: 2026-06-15

Log inspected:

```text
logs/hybrid_hs_profile_30day.log
```

Run command recorded in context:

```bash
python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --days 30 \
  --production-diag \
  --overwrite
```

## Executive Summary

The 30-day Held-Suarez hybrid run completed successfully, but the log does not
contain any `HS_PROFILE` timer summaries.  Therefore the actual measured
Held-Suarez forcing runtime, average forcing time per call, and forcing fraction
of model wall-clock time cannot be extracted from this log.

What can be concluded from this log:

- The hybrid executable ran successfully for 30 model days.
- The model wrote `atmos_monthly.nc`.
- The restart archive was created.
- Total wall-clock time is available from `/usr/bin/time`.
- FMS `mpp_clock` total runtime is available.
- No Fortran wrapper or C++ forcing timer lines were emitted.

Recommendation for performance work: **C. Skip CUDA forcing as a speedup target
and profile/port a larger module instead.**  If a CUDA forcing implementation is
still desired, treat it as a proof-of-interface exercise, not as an expected
end-to-end speedup.

CUDA forcing expected speedup impact: **negligible** from the current evidence,
because the forcing timer data is absent and the forcing source contains only a
small number of simple per-grid-cell loops.  A direct CUDA offload would also
need to overcome host-device transfer and launch overhead.

## Run Completion

The log confirms completion:

```text
Run 1 complete
atmos_monthly.nc combined and copied to data directory
Restart archive created at /explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_hybrid/restarts/res0001.tar.gz
```

Output directory:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_hybrid
```

Generated output files observed:

| File | Size |
|---|---:|
| `/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_hybrid/run0001/atmos_monthly.nc` | 4,153,576 bytes |
| `/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_hybrid/restarts/res0001.tar.gz` | 25,261,604 bytes |
| `/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_hybrid/run0001/input.nml` | 929 bytes |
| `/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_hybrid/run0001/diag_table` | 864 bytes |
| `/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_hybrid/run0001/field_table` | 355 bytes |
| `/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_hybrid/run0001/git_hash_used.txt` | 220 bytes |

## Extracted Timing Summary

| Metric | Value | Source |
|---|---:|---|
| Simulation length | 30 days | run script output |
| `dt_atmos` | 600 s | run script output |
| MPI ranks | 16 | run script output |
| `/usr/bin/time` real | 27.702 s | log tail |
| `/usr/bin/time` user | 355.499 s | log tail |
| `/usr/bin/time` sys | 39.987 s | log tail |
| FMS `mpp_clock` total runtime min | 24.569877 s | `Total runtime` row |
| FMS `mpp_clock` total runtime max | 24.569939 s | `Total runtime` row |
| FMS `mpp_clock` total runtime avg | 24.569881 s | `Total runtime` row |
| HS_PROFILE blocks present | no | full-log search |
| Measured forcing total runtime | not available | missing `HS_PROFILE` output |
| Measured forcing calls | not available | missing `HS_PROFILE` output |
| Measured average forcing time/call | not available | missing `HS_PROFILE` output |
| Measured forcing fraction | not available | missing `HS_PROFILE` output |

The model-side wall-clock fraction requested by the profiling plan would be:

```text
forcing_time_fraction = fortran_iso_c_wrapper.total_seconds / 27.702
```

The required numerator is not present in this log.

## Expected Call Count From Runtime Settings

The expected number of atmosphere steps is:

```text
30 days * 86400 s/day / 600 s = 4320 steps
```

The Held-Suarez atmosphere driver calls `hs_forcing` once per atmosphere step in
this configuration, so the expected forcing-call count is approximately:

```text
4320 forcing calls
```

Expected calls per model day:

```text
86400 s/day / 600 s = 144 calls/day
```

Average total wall time per model day:

```text
27.702 s / 30 days = 0.9234 s/day
```

The average forcing time per model day and average forcing time per call cannot
be computed from this log because the forcing timer totals are absent.

## Missing HS_PROFILE Output

Expected profiler blocks:

```text
HS_PROFILE Fortran wrapper profile summary
region,calls,total_seconds,avg_seconds
fortran_iso_c_wrapper,...

HS_PROFILE C++ forcing profile summary
region,calls,total_seconds,avg_seconds,cells,seconds_per_cell,fraction_of_cpp_driver
...
```

These strings do not occur in `logs/hybrid_hs_profile_30day.log`.

Likely causes:

1. The hybrid executable was not rebuilt after adding `HS_PROFILE` instrumentation.
2. The C++ static library was not rebuilt inside the same container architecture
   and copied into the hybrid build before linking.
3. `HS_PROFILE=1` was set for the Python launcher but not propagated into the
   MPI model process/container environment.
4. The profiling run used an older `held_suarez_hybrid.x`.

Recommended check before another profiling run:

```bash
./run_compile_hybrid.sh
```

Then run with environment propagation into the container/MPI process.  For an
Apptainer launch from outside the container, prefer:

```bash
APPTAINERENV_HS_PROFILE=1 apptainer exec \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  /lscratch/jli30/isca-sandbox \
  bash -lc 'cd /explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere && /usr/bin/time -p python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py --days 30 --production-diag --overwrite' \
  2>&1 | tee logs/hybrid_hs_profile_30day.log
```

Inside an already-entered container:

```bash
export HS_PROFILE=1
/usr/bin/time -p python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --days 30 \
  --production-diag \
  --overwrite \
  2>&1 | tee logs/hybrid_hs_profile_30day.log
```

## C++ Forcing CUDA Candidate Loops

Source inspected:

```text
translated/held_suarez/cpp/forcing_module/include/held_suarez_forcing.hpp
```

Primary standard Held-Suarez mode functions:

- `hs_forcing::hs_forcing_driver`
- `hs_forcing::rayleigh_damping`
- `hs_forcing::newtonian_damping`

Secondary top-down functions are present but are not used by the current
standard Held-Suarez wrapper:

- `hs_forcing::top_down_newtonian_damping`
- `hs_forcing::update_orbit`
- `hs_forcing::calc_hour_angle`

Potential CUDA kernels:

| Function/loop | Source role | CUDA suitability |
|---|---|---|
| `rayleigh_damping` 3D loop | Computes wind damping tendencies `udt`, `vdt` | Easy to port, memory-bound, low standalone payoff |
| `newtonian_damping` 2D latitude precompute | Computes latitude-dependent temporary arrays | Easy to port, small 2D loop, low payoff |
| `newtonian_damping` 3D vertical loop | Computes `teq` and `tdt` using `log`/`pow` | Best forcing CUDA candidate, but still modest size |
| `hs_forcing_driver` wind accumulation | Adds `utnd`, `vtnd` into model tendencies | Memory-bound, should be fused |
| `hs_forcing_driver` temperature accumulation | Adds `ttnd` into model tendency | Memory-bound, should be fused |
| `top_down_newtonian_damping` 2D loops | Insolation/radiative balance/top-down setup | Only relevant if top-down mode is enabled |
| `top_down_newtonian_damping` 3D loop | Top-down `teq` and damping coefficient | Reasonable CUDA candidate for top-down mode |

## Arithmetic Intensity Estimate

Assume double precision, 8 bytes per scalar.

### Rayleigh damping

Approximate FLOPs per 3D cell:

- 1 divide.
- 2-4 multiplies.
- 1 subtract.
- Comparisons and branch.
- Total: about 5-8 scalar FLOPs.

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
- Poor standalone CUDA speedup target.

### Newtonian latitude precompute

Approximate FLOPs per 2D cell:

- 1 `sin`.
- About 8-10 scalar arithmetic operations.

Approximate bytes per 2D cell:

- Load: `lat`: 8 bytes.
- Stores: `sin_lat`, `sin_lat_2`, `cos_lat_2`, `cos_lat_4`, `t_star`,
  `tstr`: 48 bytes.
- Total: about 56 bytes.

Arithmetic intensity:

```text
~0.15-0.20 scalar FLOP/byte, plus one transcendental
```

Likely bound:

- Mixed memory and special-function latency.
- Too small to justify a standalone CUDA launch.

### Newtonian vertical loop

Approximate FLOPs per 3D cell:

- 2 divides.
- About 12-18 scalar arithmetic operations.
- 1 `log`.
- 1 `pow`.
- Comparisons and branch.

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

- Special-function latency may dominate scalar arithmetic.
- Best forcing-module CUDA candidate, but still a small kernel at this
  Held-Suarez resolution.
- Not promising if arrays move host-device each forcing call.

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

- Wind: 2 FLOPs and about 64 bytes per 3D cell.
- Temperature: 1 FLOP and about 24 bytes per 3D cell.

Likely bound:

- Strongly memory-bound.
- Should be fused into the producer kernels in any CUDA design.

## Interpretation

Because the `HS_PROFILE` summaries are absent, this log cannot prove the forcing
module's actual fraction of end-to-end runtime.  However, the source structure
and the 30-day model timing strongly suggest that forcing is not the right next
CUDA speedup target:

- The full 30-day run took only 27.702 seconds wall-clock including Python
  launch, model execution, monthly NetCDF combine, restart archive, and cleanup.
- FMS reports only 24.569881 seconds average model runtime across 16 PEs.
- The forcing module is called roughly 4320 times, but each call operates on a
  small Held-Suarez grid and only a few arrays.
- The biggest forcing loop is `newtonian_vertical`; it is compact and would need
  device-resident model state to benefit from CUDA.
- Rayleigh and accumulation loops are memory-bound and should be fused if ever
  ported.

CUDA offload of this module alone is unlikely to create measurable end-to-end
speedup.  It is better understood as an interface and architecture prototype for
Fortran -> C API -> C++ replacement, not as a performance target.

## Recommendation

Selected option:

```text
C. Skip CUDA forcing and profile/port a larger module instead.
```

Rationale:

- This 30-day log does not contain the forcing timer data needed to justify
  option A.
- The forcing source code is too small and too memory-bound to expect meaningful
  end-to-end speedup from standalone CUDA.
- A CUDA forcing implementation could still be useful as option B, a
  proof-of-interface, but it should not be prioritized for speedup.

Recommended larger modules to profile/port next:

1. `four_in_one` inside `src/atmos_spectral/model/spectral_dynamics.F90`
   - Every-timestep dynamics kernel.
   - Updates pressure, temperature, wind, and vertical mass-flux tendencies.
   - Better GPU-relevant arithmetic/array structure than forcing.
2. `press_and_geopot_mod` in `src/atmos_spectral/model/press_and_geopot.F90`
   - Pressure/geopotential/height calculations.
   - Regular vertical-column loops.
3. `vert_advection_mod` in `src/atmos_shared/vert_advection/vert_advection.F90`
   - Repeated every timestep for `u`, `v`, and `t`.
   - Larger transport kernel, more likely to matter for GPU acceleration.

## Final Conclusion

CUDA forcing expected speedup impact: **negligible**.

Why: the 30-day model run succeeded, but the log contains no forcing profiler
summary, so no measured forcing fraction can be computed.  The forcing source
itself is also small: mostly one 3D Rayleigh loop, one 2D latitude precompute,
one 3D Newtonian damping loop with `log`/`pow`, and simple memory-bound
accumulation loops.  A CUDA version may be useful as a proof of the interface
architecture, but the next performance-oriented port should target a larger
dynamics/state-update module.
