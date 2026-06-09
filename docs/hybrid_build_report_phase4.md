# Hybrid Build Report Phase 4

Generated: 2026-06-08

## Latest Log

Newest log inspected:

```text
logs/hybrid_compile_latest.log
```

The C++ archive architecture issue is fixed.  The log shows the library is now
rebuilt inside the container before the Isca compile:

```text
Building hybrid forcing C++ library
  CXX: /usr/bin/g++
  AR: /usr/bin/ar
  CXX target: aarch64-linux-gnu
```

The build reaches the final link step.

## Latest Error

First real linker error:

```text
/usr/bin/ld: ... undefined reference to `update_orbit_'
/usr/bin/ld: ... undefined reference to `calc_hour_angle_'
/usr/bin/ld: ... undefined reference to `calc_hour_angle_'
collect2: error: ld returned 1 exit status
make: *** [Makefile:682: held_suarez_hybrid.x] Error 1
```

## Classification

Fortran overlay source error.

This is not a missing `path_names` source file and not a C++ forcing/library
problem.  The unresolved references are caused by the overlay replacing the
original `hs_forcing.F90` while omitting helper procedures that the original
file defined inside `hs_forcing_mod`.

## Source Trace

Search over `src/` found the definitions in the original production source:

```text
src/atmos_param/hs_forcing/hs_forcing.F90:823: subroutine update_orbit(...)
src/atmos_param/hs_forcing/hs_forcing.F90:842: subroutine calc_hour_angle(...)
src/atmos_param/hs_forcing/hs_forcing.F90:864: subroutine calc_ecc_anomaly(...)
```

The overlay referenced `update_orbit` and `calc_hour_angle` in:

```text
src/extra/local_overrides/hs_forcing/hs_forcing.F90
```

but the retained helper include did not define them.

## Path Names Comparison

Baseline path_names:

```text
atmos_param/hs_forcing/hs_forcing.F90
shared/astronomy/astronomy.f90
```

Hybrid path_names:

```text
../translated/held_suarez/cpp/forcing_module/fortran/hs_forcing_c_interface.F90
extra/local_overrides/hs_forcing/hs_forcing.F90
shared/astronomy/astronomy.f90
```

The only substantive path_names difference is the intended source overlay plus
the added C interface.  `shared/astronomy/astronomy.f90` is present in both
builds.

## Object Evidence

Baseline all-Fortran object:

```text
hs_forcing.o defines __hs_forcing_mod_MOD_update_orbit
hs_forcing.o defines __hs_forcing_mod_MOD_calc_hour_angle
```

Hybrid object before this fix:

```text
hs_forcing.o has U update_orbit_
hs_forcing.o has U calc_hour_angle_
```

That confirms the missing symbols belong to the replaced overlay source, not to
a separate missing object file.

## Files Changed

Changed:

```text
src/extra/local_overrides/hs_forcing/hs_forcing_rest.inc
docs/hybrid_build_report_phase4.md
```

No original production source was modified.  No C++ forcing logic was modified.

## Fix Prepared

Restored the original helper procedures into the overlay include:

```text
update_orbit
calc_hour_angle
calc_ecc_anomaly
```

These are copied from the production `hs_forcing.F90` helper implementation so
the overlay `hs_forcing.o` should once again define the module-local symbols
used by the Held-Suarez initialization/top-down forcing paths.

## Next Command

Run from a shell with the working Apptainer container available:

```bash
./run_compile_hybrid.sh
```

## Expected Next Failure Or Success Condition

Expected next state:

- `hs_forcing.o` should define the restored helper procedures.
- The final link should pass the previous `update_orbit_` and
  `calc_hour_angle_` undefined references.

Stop at either:

- the first new compile/link failure after this point, or
- successful generation of:

```text
held_suarez_hybrid.x
```
