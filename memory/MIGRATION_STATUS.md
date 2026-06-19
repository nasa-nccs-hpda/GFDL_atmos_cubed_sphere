# Migration Status

Tracking the Fortran-to-C++ translation progress for Held-Suarez physics kernels.

## Latest Integration Status

### `semi_y_3d` finite-volume kernel modernization

- Fortran baseline fixture generated and validated.
- CPU C++ `semi_y_3d` kernel validated exactly.
- CUDA `semi_y_3d` kernel validated exactly.
- Fortran `iso_c_binding` wrapper to CPU C++ validated exactly.
- Fortran `iso_c_binding` wrapper to CUDA validated exactly.
- Native Isca `fv_advection.F90` overlay implemented without modifying
  production source.
- CPU overlay executable generated:
  `held_suarez_fv_semi_y_3d.x`.
- CUDA overlay executable generated:
  `held_suarez_fv_semi_y_3d_cuda.x`.
- 1-day CPU/CUDA overlay smoke runs succeeded.
- 1-day model output comparison against all-Fortran baseline matched exactly.
- 30-day CPU/CUDA overlay runs succeeded.
- 30-day model output comparison against all-Fortran baseline matched exactly
  for `ps`, `temp`, `ucomp`, and `vcomp`.
- Key report:
  `tests/reports/semi_y_3d_30day_model_validation_report.md`.
- Next step: select the next finite-volume local kernel, likely from
  `semi_x_3d`, `slope_sphere`, `slope_x`, `vanleer_sphere_3d`, or
  `vanleer_x_3d`.

### Held-Suarez forcing module hybrid integration

- C++ forcing module validated against standalone Fortran baseline.
- C API validated through Fortran `iso_c_binding` wrapper.
- Native Isca overlay strategy implemented without modifying production Fortran source.
- Hybrid executable generated:
  `held_suarez_hybrid.x`.
- 1-day smoke run succeeded and wrote model output.
- 30-day hybrid run succeeded and wrote `atmos_monthly.nc` plus restart archive.
- Next step: compare 30-day all-Fortran vs hybrid outputs and/or apply this workflow to the next Held-Suarez module.

## Completed Translations

| Routine | Status | Test Result | Accuracy | Fortran Baseline | C++ Translation |
|---------|--------|-------------|----------|------------------|-----------------|
| `calc_ecc_anomaly` | ✅ Complete | PASS | Exact (0 diff) | `tests/fortran_baseline/calc_ecc_anomaly/` | `translated/held_suarez/cpp/calc_ecc_anomaly/` |
| `rayleigh_damping` | ✅ Complete | PASS | Exact (0 diff) | `tests/fortran_baseline/rayleigh_damping/` | `translated/held_suarez/cpp/rayleigh_damping/` |

## Forcing module (Held‑Suarez `forcing_module`)

- **Status:** ✅ Complete
- **Scope:** Translation and verification of Held‑Suarez forcing kernels (temperature relaxation and momentum damping) and orchestration harness for standalone verification.
- **What I implemented:**
    - C++ translation skeleton, library, and test drivers added at `translated/held_suarez/cpp/forcing_module/`.
    - Fortran baseline harness created at `tests/fortran_baseline/forcing_module/` which generates canonical `inputs/` and `outputs/` binary blobs.
    - A C++ candidate runner was built and executed to read the Fortran inputs and produce candidate outputs (written to `translated/held_suarez/cpp/forcing_module/outputs/`).
    - A comparator (`compare_outputs.py`) was added and executed to compare Fortran baseline vs C++ candidate outputs; it produces `tests/reports/forcing_module_compare_report.json`.

- **Test results:** All output variables (`output_tdt.bin`, `output_teq.bin`, `output_udt.bin`, `output_vdt.bin`) matched exactly between Fortran baseline and C++ candidate (max abs = 0.0, max rel = 0.0, RMSE = 0.0). Report: `tests/reports/forcing_module_compare_report.json`.

- **Artifacts produced:**
    - Fortran harness binary: `tests/fortran_baseline/forcing_module/test_forcing_module`
    - Fortran baseline data: `tests/fortran_baseline/forcing_module/inputs/` and `.../outputs/`
    - C++ artifacts: `translated/held_suarez/cpp/forcing_module/libhs_forcing.a`, `translated/held_suarez/cpp/forcing_module/bin/driver_forcing_module`, `translated/held_suarez/cpp/forcing_module/bin/run_candidate_forcing` and `.../outputs/` (candidate blobs)
    - Comparison report: `tests/reports/forcing_module_compare_report.json`

- **Blockers / Notes:** None remaining for basic functional parity; the original workflow hit a missing `numpy` in the environment, so the comparator was converted to a pure-Python binary reader to avoid that dependency and ran successfully.

- **Suggested next steps:** Integrate these harnesses into the repository test driver (CI), add edge-case tests (varying grid sizes, extreme parameter values), and document invocation in `translated/held_suarez/cpp/forcing_module/README.md`.

| `newtonian_damping` | ✅ Complete | PASS | Exact (0 diff) | `tests/fortran_baseline/newtonian_damping/` | `translated/held_suarez/cpp/newtonian_damping/` |
| `calc_hour_angle` | ✅ Complete | PASS | Exact (0 diff) | `tests/fortran_baseline/calc_hour_angle/` | `translated/held_suarez/cpp/calc_hour_angle/` |
| `top_down_newtonian_damping` | ✅ Complete | PASS | Near-exact (rel_diff < 1e-14) | `tests/fortran_baseline/top_down_newtonian_damping/` | `translated/held_suarez/cpp/top_down_newtonian_damping/` |

## Translation Details

### 1. calc_ecc_anomaly

| Attribute | Value |
|-----------|-------|
| **Source** | `src/atmos_param/hs_forcing/hs_forcing.F90:864-890` |
| **LOC** | 27 |
| **Purpose** | Newton-Raphson solver for Kepler's equation (eccentric anomaly) |
| **Dependencies** | None (pure math intrinsics) |
| **Test Result** | PASS |
| **Max Absolute Diff** | 0.0 |
| **Max Relative Diff** | 0.0 |

### 2. rayleigh_damping

| Attribute | Value |
|-----------|-------|
| **Source** | `src/atmos_param/hs_forcing/hs_forcing.F90:615-679` |
| **LOC** | 65 |
| **Purpose** | Boundary layer friction for u, v winds (Held-Suarez Eq. 3) |
| **Dependencies** | None for default Held-Suarez case |
| **Test Result** | PASS |
| **Max Absolute Diff** | 0.0 |
| **Max Relative Diff** | 0.0 |

### 3. newtonian_damping

| Attribute | Value |
|-----------|-------|
| **Source** | `src/atmos_param/hs_forcing/hs_forcing.F90:508-611` |
| **LOC** | 104 |
| **Purpose** | Temperature relaxation to equilibrium profile (Held-Suarez Eq. 1-2) |
| **Dependencies** | KAPPA constant only for default Held-Suarez case |
| **Test Result** | PASS |
| **Max Absolute Diff** | 0.0 |
| **Max Relative Diff** | 0.0 |

**Test output summary:**
- teq range: [200.0, 311.77] K (correctly capped at t_strat=200K)
- tdt range: [-1.9e-5, 8.1e-5] K/s
- All 5 levels match exactly between C++ and Fortran

### 4. calc_hour_angle

| Attribute | Value |
|-----------|-------|
| **Source** | `src/atmos_param/hs_forcing/hs_forcing.F90:842-860` |
| **LOC** | 19 |
| **Purpose** | Compute solar hour angle from latitude and solar declination |
| **Dependencies** | None (pure intrinsics: tan, acos) |
| **Test Result** | PASS |
| **Max Absolute Diff** | 0.0 |
| **Max Relative Diff** | 0.0 |

**Test output summary:**
- First 2D array kernel in translation sequence
- Demonstrates `where` construct → clamp pattern
- hour_angle range: [0, π] rad correctly spanning polar night to polar day
- All 6 latitude bands match exactly between C++ and Fortran

### 5. top_down_newtonian_damping

| Attribute | Value |
|-----------|-------|
| **Source** | `src/atmos_param/hs_forcing/hs_forcing.F90:894-1026` |
| **LOC** | 133 |
| **Purpose** | Temperature relaxation with tropopause-aware vertical structure |
| **Dependencies** | Embeds calc_ecc_anomaly, update_orbit, calc_hour_angle |
| **Test Result** | PASS |
| **Max Absolute Diff** | 5.7e-14 (teq) |
| **Max Relative Diff** | 7.1e-15 (tdt) |

**Test output summary:**
- Most complex routine in translation sequence (133 LOC)
- Demonstrates stateful → stateless conversion (tg_prev → tg_new)
- Includes orbital mechanics, radiative balance, heat capacity
- h_trop range: [0, 10.7] km across latitudes
- All outputs within machine precision

## Pending Translations

| Order | Routine | LOC | Translation Spec | Status |
|-------|---------|-----|------------------|--------|
| 3 | `update_orbit` | 16 | ❌ | Embedded in top_down_newtonian_damping |
| 7 | `local_heating` | 42 | ❌ | Not started |

## Summary

- **Total routines translated:** 5
- **Total LOC translated:** 348 (27 + 65 + 104 + 19 + 133)
- **All tests passing:** Yes
- **Accuracy:** Bit-reproducible or near-exact (max rel_diff < 1e-14)

## Validation Criteria

All translations are validated against Fortran baseline with:
- Relative tolerance: `1e-14`
- Absolute tolerance: `1e-20`

## File Organization

```
tests/
└── fortran_baseline/
    ├── calc_ecc_anomaly/              # Fortran test harness + reference data
    ├── rayleigh_damping/              # Fortran test harness + reference data
    ├── newtonian_damping/             # Fortran test harness + reference data
    ├── calc_hour_angle/               # Fortran test harness + reference data
    └── top_down_newtonian_damping/    # Fortran test harness + reference data

translated/
└── held_suarez/
    └── cpp/
        ├── calc_ecc_anomaly/              # C++ translation + test driver
        ├── rayleigh_damping/              # C++ translation + test driver
        ├── newtonian_damping/             # C++ translation + test driver
        ├── calc_hour_angle/               # C++ translation + test driver
        └── top_down_newtonian_damping/    # C++ translation + test driver

docs/
├── porting_targets.md                         # Initial analysis
├── porting_targets_ranked.md                  # Ranked candidates with GPU suitability
├── translation_spec_rayleigh_damping.md       # Detailed spec
├── translation_spec_newtonian_damping.md      # Detailed spec
├── translation_spec_calc_hour_angle.md        # Detailed spec
└── translation_spec_top_down_newtonian_damping.md  # Detailed spec
```
