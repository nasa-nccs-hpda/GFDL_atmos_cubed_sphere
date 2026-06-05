# Held-Suarez Porting Targets

Analysis of `src/atmos_param/hs_forcing/hs_forcing.F90` (1028 lines) to identify routines suitable for isolated porting.

## Recommended First Target: `calc_ecc_anomaly`

**Location:** `src/atmos_param/hs_forcing/hs_forcing.F90:864-890`

**Lines:** 27

**Why this routine:**
1. **Smallest isolated routine** — Pure numerical computation with no FMS dependencies
2. **Zero external module dependencies** — Only uses intrinsic Fortran math functions (`sin`, `cos`, `tan`, `abs`)
3. **Clear interface** — 2 scalar inputs (`mean_anomaly`, `ecc`), 1 scalar output (`ecc_anomaly`)
4. **Self-contained algorithm** — Newton-Raphson iteration to solve Kepler's equation
5. **Testable** — Known analytical solutions exist for validation

**Signature:**
```fortran
subroutine calc_ecc_anomaly(mean_anomaly, ecc, ecc_anomaly)
  real, intent(in)  :: mean_anomaly, ecc
  real, intent(out) :: ecc_anomaly
```

**Algorithm:** Iterative solver for eccentric anomaly E from Kepler's equation: `E - e*sin(E) = M`

---

## Second Target: `calc_hour_angle`

**Location:** `src/atmos_param/hs_forcing/hs_forcing.F90:842-860`

**Lines:** 19

**Why:**
- Pure trigonometric computation on 2D arrays
- No FMS dependencies — uses only intrinsic functions (`tan`, `acos`)
- Simple `where` construct for bounds clamping
- Natural follow-on after `calc_ecc_anomaly`

**Signature:**
```fortran
subroutine calc_hour_angle(lat, dec, hour_angle)
  real, intent(in)               :: dec
  real, intent(in),  dimension(:,:) :: lat
  real, intent(out), dimension(:,:) :: hour_angle
```

---

## Third Target: `update_orbit`

**Location:** `src/atmos_param/hs_forcing/hs_forcing.F90:823-838`

**Lines:** 16

**Why:**
- Calls `calc_ecc_anomaly` (already ported)
- Uses module variables `orbital_period`, `peri_time`, `smaxis`, `ecc`, `obliq` — but these are namelist-controlled constants
- Only dependency: `astronomy_mod` for `obliq`, `ecc` (can be parameterized)

**Signature:**
```fortran
subroutine update_orbit(current_time, dec, orb_dist)
  integer, intent(in)  :: current_time
  real,    intent(out) :: dec, orb_dist
```

---

## Dependency Chain for Full Physics Porting

```
calc_ecc_anomaly (27 lines, 0 deps)
    └── update_orbit (16 lines, needs orbital constants)
        └── calc_hour_angle (19 lines, 0 deps)
            └── top_down_newtonian_damping (134 lines, needs FMS time_manager)
                └── newtonian_damping (104 lines, needs FMS interpolator, time_manager)
                    └── rayleigh_damping (66 lines, needs FMS time_manager)
```

## Routines NOT Recommended for Early Porting

| Routine | Lines | Reason |
|---------|-------|--------|
| `hs_forcing` | 125 | Main driver; orchestrates all physics; heavy FMS dependencies |
| `hs_forcing_init` | 195 | Complex initialization; file I/O; namelist parsing; diagnostics registration |
| `newtonian_damping` | 104 | Multiple equilibrium_t_option branches; interpolator calls |
| `top_down_newtonian_damping` | 134 | FMS time_manager dependency; module state (`tg_prev`) |
| `local_heating` | 42 | Interpolator dependency for `from_file` option |
| `tracer_source_sink` | 43 | Coupled to tracer framework |

## Porting Strategy

1. **Phase 1:** Port `calc_ecc_anomaly` — validate numerical accuracy
2. **Phase 2:** Port `calc_hour_angle` + `update_orbit` — build orbital mechanics kernel
3. **Phase 3:** Extract core damping logic from `newtonian_damping` (sigma calculation, teq computation) as standalone kernels
4. **Phase 4:** Port `rayleigh_damping` core loop
5. **Phase 5:** Integrate with time management abstraction layer

## Notes

- All routines use `real` (single precision by default) — consider `real(kind=8)` for GPU targets
- `where` constructs in `calc_hour_angle` and `rayleigh_damping` map well to GPU kernels
- Module-level state (`tg_prev`, interpolator types) will require refactoring for stateless GPU kernels
