# Full CUDA Modernization Module Table

Date: 2026-06-18

Source inventory basis:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_hybrid/path_names
src/
translated/held_suarez/
docs/dynamics_deep_profile_recommendation.md
docs/a_grid_horiz_advection_3d_feasibility_analysis.md
docs/fv_advection_kernel_modernization_plan.md
docs/T85L25_forcing_performance_results.md
```

Strategy classes:

```text
A = CUDA candidate now
B = C++ first, CUDA later
C = Keep Fortran wrapper, CUDA inner kernels
D = Keep Fortran permanently for now
E = External/library strategy
```

| Priority | Module/File | Current Language | Target Strategy | Runtime Evidence | CUDA Suitability | Difficulty | Validation Path | Status |
|---:|---|---|---|---|---|---|---|---|
| 0 | `src/extra/local_overrides/hs_forcing/hs_forcing.F90` + `translated/held_suarez/cpp/forcing_module/` + `translated/held_suarez/cuda/forcing_module/` | Fortran overlay + C++ + CUDA | Freeze as reference implementation | T85L25 CPU hybrid 1.031x; CUDA 0.644x; forcing fraction about 4.23% | Architecture reference, not speedup target | Done | Existing unit/module/wrapper/hybrid/30-day/T85 validation | Completed |
| 1 | `src/atmos_spectral/model/fv_advection.F90::semi_y_3d` | Fortran private local kernel | A. CUDA candidate now | Part of `tracer_grid_horizontal_advection`, 12.04% region | High: local 3D loops, no MPI/callees | Medium | Standalone Fortran baseline -> C++ -> CUDA -> C API -> overlay wrapper | Selected next |
| 2 | `src/atmos_spectral/model/fv_advection.F90::semi_x_3d` | Fortran private local kernel | A. CUDA candidate after `semi_y_3d` | Same finite-volume advection path | High but has `find_cell_x` dependency | Medium | Extend `semi_y_3d` harness style; compare `dq`/departure indices | Planned |
| 3 | `src/atmos_spectral/model/fv_advection.F90::slope_sphere` | Fortran private local kernel | A. CUDA candidate after semi kernels | Used by y-direction Van Leer path | High: limiter loop over local arrays | Medium | Synthetic + captured limiter fixtures | Planned |
| 4 | `src/atmos_spectral/model/fv_advection.F90::slope_x` | Fortran private local kernel | A. CUDA candidate after semi kernels | Used by x-direction Van Leer path | High: regular x limiter | Medium | Synthetic periodic-x fixtures | Planned |
| 5 | `src/atmos_spectral/model/fv_advection.F90::find_cell_x` | Fortran private helper | A. CUDA candidate / helper | Called by `semi_x_3d` and `vanleer_x_3d` | Medium: simple but small integer/index kernel | Low-medium | Exact integer output comparison | Planned |
| 6 | `src/atmos_spectral/model/fv_advection.F90::vanleer_sphere_3d` | Fortran private local kernel | C. Fortran wrapper, CUDA inner kernel | Same finite-volume advection path | High, but limiter and pole handling sensitive | High | Module fixture from `advection_sphere_3d`; compare flux/tendency | Planned |
| 7 | `src/atmos_spectral/model/fv_advection.F90::vanleer_x_3d` | Fortran private local kernel | C. Fortran wrapper, CUDA inner kernel | Same finite-volume advection path | Medium-high; branchy periodic sums | High | Captured model fixtures; exact/near-exact tendency comparison | Planned |
| 8 | `src/atmos_spectral/model/fv_advection.F90::integer_flux_x` | Fortran private helper | B/C. C++ first, CUDA later | Conditional helper under x Van Leer | Low-medium; variable-length sums | High | Edge-case periodic tests and captured fixtures | Planned |
| 9 | `src/atmos_spectral/model/fv_advection.F90::advection_sphere_3d` | Fortran orchestrator | C. Keep Fortran wrapper, CUDA inner kernels | Owned by `a_grid_horiz_advection_3d` path | Medium; contains halo update between local kernels | High | Validate after local kernels; keep halo in Fortran | Planned |
| 10 | `src/atmos_spectral/model/fv_advection.F90::a_grid_horiz_advection_3d` | Fortran module routine | C. Keep Fortran wrapper, CUDA inner kernels | `tracer_grid_horizontal_advection`: 12.04%; `update_tracers`: 17.55% | Promising if enough local kernels moved | High | 1-day/30-day model comparison after local kernel accumulation | PARTIAL GO / Strategy 3 |
| 11 | `src/atmos_spectral/model/press_and_geopot.F90` | Fortran | B. C++ first, CUDA later | Broad `press_geopot`: about 4.8% at T42L25 | Medium-high: column/3D thermodynamic loops likely | Medium-high | Standalone pressure/geopotential fixtures; compare `p_full`, `p_half`, geopotential | Fallback target |
| 12 | `src/atmos_spectral/model/spectral_damping.F90` | Fortran | B/C. C++ first or CUDA inner loops | Damping section present in timestep; no dominant split yet | Medium: array loops, spectral state coupling | Medium-high | Timer split first; then standalone damping fixtures | Candidate later |
| 13 | `src/atmos_spectral/model/implicit.F90` | Fortran | B. C++ first, CUDA later | Part of dynamics update path; not separately timed | Medium: vertical implicit solves likely column-local | Medium-high | Unit harness for solver outputs | Candidate later |
| 14 | `src/atmos_spectral/model/leapfrog.F90` | Fortran | B. C++ first, CUDA later | Time integration central but not isolated as hotspot | Medium: state update loops | Medium | Golden state update fixtures | Candidate later |
| 15 | `src/atmos_spectral/model/matrix_invert.F90` | Fortran | A/B. C++ first, possible CUDA batched solve later | Helper for implicit/vertical solves | Medium if batched over columns | Medium | Small matrix fixtures; compare solve residuals | Candidate later |
| 16 | `src/atmos_spectral/model/water_borrowing.F90` | Fortran | B. C++ first, CUDA later | Not identified as primary hotspot | Low-medium | Medium | Unit fixtures for conservation corrections | Defer |
| 17 | `src/atmos_spectral/model/global_integral.F90` | Fortran | D. Keep Fortran for now | Reduction/correction support | Low for local CUDA; global reductions | High | Leave in Fortran; validate callers | Keep |
| 18 | `src/atmos_spectral/model/every_step_diagnostics.F90` | Fortran | D. Keep Fortran | Deep profile: about 0.02% | Low; diagnostics | Low | Existing model output comparison | Keep |
| 19 | `src/atmos_spectral/model/spectral_dynamics.F90` | Fortran | C. Keep orchestration; CUDA selected inner regions | Contains timestep orchestration, transforms, advection, corrections | Mixed; central but coupled | Very high | Overlay timers; cumulative hybrid model tests | Fortran orchestrator |
| 20 | `src/atmos_shared/vert_advection/vert_advection.F90::vert_advection_3d` | Fortran | B. C++ first, CUDA later only if vertical scaling changes | u+v+t about 0.34% at T42L25 | Medium kernel shape, weak payoff | Medium | Existing profile harness; standalone fixtures later | No-go for now |
| 21 | `src/atmos_spectral/tools/transforms.F90` | Fortran | E. External/library strategy | Broad transforms about 38.9%; deep transform aggregate about 35.6% | High runtime, but algorithm/library coupled | Very high | Separate transform benchmark; compare spectral/grid round trips | Study separately |
| 22 | `src/atmos_spectral/tools/spherical.F90` | Fortran | E. External/library strategy | Transform-heavy stack | Potential cuFFT/cuBLAS/custom spherical harmonic path | Very high | Vendor/library prototype; bitwise/energy checks | Study separately |
| 23 | `src/atmos_spectral/tools/spherical_fourier.F90` | Fortran | E. External/library strategy | Transform-heavy stack | Potential vendor FFT strategy | Very high | Round-trip transform tests | Study separately |
| 24 | `src/atmos_spectral/tools/grid_fourier.F90` | Fortran | E. External/library strategy | Transform-heavy stack | Potential cuFFT strategy | High | 1D/2D transform fixtures | Study separately |
| 25 | `shared/fft/fft.F90`, `shared/fft/fft99.F90` | Fortran | E. External/library strategy | Used by spectral transforms | Use cuFFT or vendor FFT rather than hand translation | High | FFT equivalence and transform-level tests | Study separately |
| 26 | `src/atmos_spectral/tools/spec_mpp.F90` | Fortran | D/E. Keep Fortran or redesign with transforms | Spectral/MPI support | Low as local CUDA target; distributed coupling | Very high | Keep until transform redesign | Keep |
| 27 | `src/atmos_spectral/tools/gauss_and_legendre.F90` | Fortran | D. Keep Fortran for now | Initialization/tooling mostly | Low runtime | Low | Existing initialization | Keep |
| 28 | `src/atmos_spectral/model/tracer_type.F90` | Fortran | D. Keep Fortran | Type/metadata support | Not compute kernel | Low | Existing model tests | Keep |
| 29 | `src/atmos_solo/atmos_model.F90` | Fortran | D. Keep Fortran | Driver/orchestration | Not CUDA target | High | Whole-model tests | Keep |
| 30 | `src/atmos_spectral/driver/solo/atmosphere.F90` | Fortran | D/C. Keep driver; possible wrapper injection points | Model atmosphere driver | Orchestration, coupling | High | Whole-model tests | Keep |
| 31 | `src/atmos_spectral/driver/solo/idealized_moist_phys.F90` | Fortran | D. Keep Fortran in dry HS path | Physics driver mostly disabled/simple for HS | Low for current dry HS | Medium | Existing HS outputs | Keep |
| 32 | `src/atmos_spectral/driver/solo/mixed_layer.F90` | Fortran | D. Keep Fortran for current HS | Surface/mixed-layer support | Not selected | Medium | Existing outputs | Keep |
| 33 | `src/atmos_param/hs_forcing/hs_forcing.F90` original path | Fortran | Freeze; production untouched | Forcing completed through overlay | Already modernized through overlay | Done | Existing forcing validation ladder | Production source untouched |
| 34 | Other `src/atmos_param/*` physics files in path_names | Fortran | B or D depending future physics target | Mostly inactive or not priority in dry HS | Mixed | Medium-high | Per-module harness if selected | Defer |
| 35 | `src/atmos_param/damping_driver/damping_driver.f90` and drag modules | Fortran | B. C++ first if future profile warrants | Damping broad region exists but not top specific target | Medium | Medium | Timer split, then unit fixtures | Defer |
| 36 | `src/atmos_param/vert_diff/vert_diff.F90`, `vert_turb_driver.F90` | Fortran | B/C if moist/turbulence case targeted | Not primary dry HS hotspot | Medium | High | Case-specific profiling | Defer |
| 37 | Initialization files under `src/atmos_spectral/init/*` | Fortran | D. Keep Fortran | Initialization-only | Low | Low | Existing initialization/output tests | Keep |
| 38 | `shared/diag_manager/*` | Fortran | D. Keep Fortran permanently for now | Diagnostics/I/O metadata | Not CUDA target | Low | Existing diagnostics | Keep |
| 39 | `shared/fms/fms.F90`, `shared/fms/fms_io.F90`, read/write includes | Fortran | D. Keep Fortran permanently for now | FMS runtime and NetCDF I/O | Not CUDA target | High | Existing model I/O | Keep |
| 40 | `shared/mpp/*` and `shared/mpp/include/*` | Fortran/C/includes | D. Keep Fortran/C permanently for now | MPI, domain decomposition, reductions, halos | Not local CUDA target | Very high | Existing MPI correctness | Keep |
| 41 | `shared/time_manager/*`, `shared/constants/*`, `shared/platform/*` | Fortran/C | D. Keep Fortran for now | Support infrastructure | Not CUDA target | Low | Existing model tests | Keep |
| 42 | `shared/field_manager/*`, `shared/tracer_manager/*` | Fortran/includes | D. Keep Fortran | Metadata/config/tracer registry | Not CUDA target | Medium | Existing model tests | Keep |
| 43 | `shared/horiz_interp/*`, `shared/mosaic/*`, `shared/topography/*` | Fortran/C | D or B in future grid-remap project | Setup/interpolation/topography | Not current HS performance target | Medium-high | Dedicated remap fixtures if ever selected | Keep/defer |
| 44 | `shared/random_numbers/*`, `shared/sat_vapor_pres/*`, `shared/tridiagonal/*` | Fortran | B. C++ first only if selected by future physics | Support math/physics helpers | Mixed | Low-medium | Unit fixtures | Defer |
| 45 | `coupler/surface_flux.F90` | Fortran | D/B depending future coupled case | Not primary dry HS hotspot | Low for current HS | Medium | Existing surface tests | Keep/defer |
| 46 | `translated/held_suarez/cpp/forcing_module/fortran/hs_forcing_c_interface.F90` | Fortran wrapper | Reference wrapper pattern | Completed forcing C API integration | Good wrapper template | Done | Existing wrapper tests | Reuse pattern |
