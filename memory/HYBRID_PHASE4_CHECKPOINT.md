# Objective

Ultimate goal:

- Modernize GEOS atmospheric model components through a staged translation path.
- Establish GPU portability for selected physics/dynamics kernels.
- Validate an AI-assisted Fortran -> C++ -> GPU modernization workflow.

Current prototype:

- Held-Suarez idealized atmosphere benchmark from Isca.

# Completed Milestones

## Code understanding

- Code mapping completed.
- Held-Suarez/Isca architecture documented.
- Key production call path identified:
  - `exp/test_cases/held_suarez/held_suarez_test_case.py`
  - `DryCodeBase.from_directory(GFDL_BASE)`
  - `CodeBase.compile()`
  - `src/extra/model/dry/path_names`
  - `src/extra/python/isca/templates/compile.sh`
  - `bin/mkmf`

## Routine translation

Validated Fortran -> C++ routine translations:

- `calc_ecc_anomaly`
  - Report: `tests/reports/calc_ecc_anomaly_compare_report.json`
  - Status: passed numerical comparison.
- Held-Suarez forcing routine: Rayleigh damping path
  - Status: translated and validated in standalone forcing-module work.
- Held-Suarez forcing routine: Newtonian damping path
  - Status: translated and validated in standalone forcing-module work.
- Held-Suarez top-down Newtonian damping support
  - Status: included in forcing-module translation/validation scope.

## Forcing module translation

Fortran forcing module:

- Original production source:
  - `src/atmos_param/hs_forcing/hs_forcing.F90`
- Standalone Fortran baseline harness:
  - `tests/fortran_baseline/forcing_module/test_forcing_module.F90`
  - `tests/fortran_baseline/forcing_module/inputs/`
  - `tests/fortran_baseline/forcing_module/outputs/`

C++ forcing module:

- Location:
  - `translated/held_suarez/cpp/forcing_module/`
- Key files:
  - `translated/held_suarez/cpp/forcing_module/include/held_suarez_forcing.hpp`
  - `translated/held_suarez/cpp/forcing_module/include/held_suarez_config.hpp`
  - `translated/held_suarez/cpp/forcing_module/include/held_suarez_c_api.h`
  - `translated/held_suarez/cpp/forcing_module/src/held_suarez_c_api.cpp`
  - `translated/held_suarez/cpp/forcing_module/libhs_forcing.a`

Validation results:

- `output_tdt.bin`: exact agreement.
- `output_teq.bin`: exact agreement.
- `output_udt.bin`: exact agreement.
- `output_vdt.bin`: exact agreement.
- Current report location:
  - `translated/held_suarez/cpp/forcing_module/tests/reports/forcing_module_compare_report.json`
- Requested reference path for future checkpoint convention:
  - `tests/reports/forcing_module_compare_report.json`

## Hybrid validation

Validated integration chain:

```text
Fortran
-> C API
-> C++ forcing module
```

Fortran interface:

- `translated/held_suarez/cpp/forcing_module/fortran/hs_forcing_c_interface.F90`

C API:

- `translated/held_suarez/cpp/forcing_module/include/held_suarez_c_api.h`
- `translated/held_suarez/cpp/forcing_module/src/held_suarez_c_api.cpp`

Result:

- Exact agreement with Fortran baseline for validated output arrays.

Reference:

- `tests/reports/forcing_module_compare_report.json`
- Actual current file:
  - `translated/held_suarez/cpp/forcing_module/tests/reports/forcing_module_compare_report.json`

## Build-system investigation

Custom helper experiments:

- Early helper:
  - `hybrid_experiments/held_suarez_cpp_force/build_hybrid.py`
- Early reports:
  - `docs/hybrid_build_diagnosis.md`
  - `docs/hybrid_build_report_phase1.md`
  - `docs/hybrid_build_diagnosis_phase2.md`
  - `docs/hybrid_build_report_phase3.md`
  - `docs/hybrid_environment_diagnosis.md`

`mkmf` diagnosis:

- Manual/custom helper initially produced empty Makefiles.
- Root cause was not the Fortran overlay itself; it was a mismatch with the canonical Isca build workflow.
- `mkmf` expects paths in `path_names` to be resolved relative to a coherent `-a <source-root>`.
- Absolute overlay entries and non-production source-root layout caused scanner/localization confusion.

`path_names` findings:

- Production `path_names` comes from:
  - `src/extra/model/dry/path_names`
- `CodeBase.compile()` writes a build-local copy:
  - `$GFDL_WORK/codebase/<source-token>/build/held_suarez/path_names`
- The Held-Suarez forcing entry is:
  - `atmos_param/hs_forcing/hs_forcing.F90`
- Clean overlay mechanism is to replace only that entry with:
  - `extra/local_overrides/hs_forcing/hs_forcing.F90`
- The hybrid path list must also include the C interface source:
  - `../translated/held_suarez/cpp/forcing_module/fortran/hs_forcing_c_interface.F90`

Source-root findings:

- Production source root is:
  - `$GFDL_WORK/codebase/<source-token>/code/src`
- For `DryCodeBase.from_directory(GFDL_BASE)`, Isca symlinks:
  - `$GFDL_WORK/codebase/<source-token>/code -> GFDL_BASE`
- The generated `compile.sh` invokes:
  - `mkmf -a $sourcedir ...`
  - where `sourcedir=$GFDL_WORK/codebase/<source-token>/code/src`

Production builddir findings:

- Successful production build directory:
  - `/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_isca/build/held_suarez`
- Key artifacts:
  - `compile.sh`
  - `path_names`
  - `.held_suarez.x.cppdefs`
  - populated `Makefile`
  - many `.o` and `.mod` files
  - `held_suarez.x`
- Production `compile.sh` is generated by `CodeBase.compile()`.
- Production env:
  - `/isca/src/extra/env/ubuntu_conda`
  - `F90=mpifort`
  - `CC=mpicc`
  - `GFDL_MKMF_TEMPLATE=ubuntu_conda`
- Production executable metadata:
  - Ubuntu 22.04 aarch64
  - GCC/gfortran 11.4
  - OpenMPI/NetCDF dynamic dependencies.

## Native overlay strategy

Strategy document:

- `docs/isca_overlay_strategy.md`

Native build implementation:

- `hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py`

Baseline subclass:

- `HeldSuarezFortranCodeBase(DryCodeBase)`
- Executable:
  - `held_suarez_fortran.x`

Hybrid subclass:

- `HeldSuarezHybridCodeBase(DryCodeBase)`
- Executable:
  - `held_suarez_hybrid.x`

Overlay source:

- `src/extra/local_overrides/hs_forcing/hs_forcing.F90`
- Include remainder file:
  - `src/extra/local_overrides/hs_forcing/hs_forcing_rest.inc`

Source replacement:

```text
atmos_param/hs_forcing/hs_forcing.F90
-> extra/local_overrides/hs_forcing/hs_forcing.F90
```

Compile flag:

```text
-DUSE_CPP_HS_FORCE
```

Hybrid environment/template:

- `src/extra/env/hybrid`
- `src/extra/python/isca/templates/mkmf.template.hybrid`

Hybrid template link flags:

```make
LDFLAGS = -lnetcdff -lnetcdf -lmpi -L$(PWD)/lib -lhs_forcing -lstdc++ -lm
```

Hybrid library placement:

- `compile_native_overlay.py` copies:
  - `<srcdir>/../translated/held_suarez/cpp/forcing_module/libhs_forcing.a`
- to:
  - `<hybrid-builddir>/lib/libhs_forcing.a`

# Current Status

Current milestone:

- Attempt first native Isca hybrid build.

Build command:

```bash
apptainer exec \
  --bind /explore/nobackup/people/jli30:/explore/nobackup/people/jli30 \
  /lscratch/jli30/isca-sandbox \
  bash -lc '
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
cd ${GFDL_BASE}
GFDL_ENV=hybrid python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py hybrid
'
```

Alternative if already inside the container:

```bash
export GFDL_BASE=/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
export GFDL_WORK=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work
export GFDL_DATA=/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
cd ${GFDL_BASE}
GFDL_ENV=hybrid python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py hybrid
```

Expected executable:

- `held_suarez_hybrid.x`
- Expected location:
  - `$GFDL_WORK/codebase/<source-token>/build/held_suarez_hybrid/held_suarez_hybrid.x`

# Current Blocker

No blocker in source translation.

Remaining task:

- Build the hybrid executable inside the same Isca Apptainer container environment used by the successful production build.

Current Codex shell limitation:

- `apptainer` is not available in the current shell, even with escalation.
- Host shell also lacks container Python dependencies such as `f90nml`.
- Therefore the first native hybrid build must be launched from the known working container environment.

# Next Actions

1. Enter container.
2. Run `compile_native_overlay.py hybrid`.
3. Capture build log.
4. Verify `held_suarez_hybrid.x` exists.
5. If build succeeds, run 1 timestep test.
6. Compare against all-Fortran executable.

# Expected Future Milestones

Phase 5:

- Hybrid executable.

Phase 6:

- 1 timestep validation.

Phase 7:

- 1 day validation.

Phase 8:

- 1 month validation.

Phase 9:

- GPU-aware redesign.

# Important Files

Project memory:

- `memory/CODEX_HANDOFF.md`
- `memory/CLAUDE.md`
- `memory/KNOWN_ISSUES.md`
- `memory/HYBRID_PHASE4_CHECKPOINT.md`

Isca/Held-Suarez entry points:

- `exp/test_cases/held_suarez/held_suarez_test_case.py`
- `run_held_suarez.sh`
- `src/extra/python/isca/codebase.py`
- `src/extra/python/isca/templates/compile.sh`
- `src/extra/model/dry/path_names`

Original Fortran:

- `src/atmos_param/hs_forcing/hs_forcing.F90`

Overlay Fortran:

- `src/extra/local_overrides/hs_forcing/hs_forcing.F90`
- `src/extra/local_overrides/hs_forcing/hs_forcing_rest.inc`

C++ forcing module:

- `translated/held_suarez/cpp/forcing_module/Makefile`
- `translated/held_suarez/cpp/forcing_module/README.md`
- `translated/held_suarez/cpp/forcing_module/include/held_suarez_forcing.hpp`
- `translated/held_suarez/cpp/forcing_module/include/held_suarez_config.hpp`
- `translated/held_suarez/cpp/forcing_module/include/held_suarez_c_api.h`
- `translated/held_suarez/cpp/forcing_module/src/held_suarez_c_api.cpp`
- `translated/held_suarez/cpp/forcing_module/libhs_forcing.a`

Fortran/C interface:

- `translated/held_suarez/cpp/forcing_module/fortran/hs_forcing_c_interface.F90`

Validation:

- `tests/fortran_baseline/forcing_module/test_forcing_module.F90`
- `tests/fortran_baseline/forcing_module/inputs/`
- `tests/fortran_baseline/forcing_module/outputs/`
- `translated/held_suarez/cpp/forcing_module/tests/reports/forcing_module_compare_report.json`
- Target convention:
  - `tests/reports/forcing_module_compare_report.json`

Native overlay build:

- `hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py`
- `src/extra/env/hybrid`
- `src/extra/python/isca/templates/mkmf.template.hybrid`
- `docs/isca_overlay_strategy.md`
- `docs/native_overlay_build.md`

Build-system reports:

- `docs/hybrid_build_process_map.md`
- `docs/hybrid_build_diagnosis.md`
- `docs/hybrid_build_report_phase1.md`
- `docs/hybrid_build_diagnosis_phase2.md`
- `docs/hybrid_build_report_phase3.md`
- `docs/hybrid_environment_diagnosis.md`

Old/custom helper experiments:

- `hybrid_experiments/held_suarez_cpp_force/build_hybrid.py`
- `hybrid_experiments/held_suarez_cpp_force/setup_env.sh`
- `hybrid_experiments/held_suarez_cpp_force/logs/build.log`

# Lessons Learned

- The forcing physics was a good first modernization target because it is much more local than spectral dynamics and transform code.
- Standalone Fortran baselines are essential; they made exact numerical comparison possible before integration.
- The C API layer is the right bridge between Fortran production code and C++ kernels.
- Hybrid validation should proceed in stages:
  - standalone Fortran vs C++
  - Fortran -> C API -> C++
  - full Isca executable
  - short-run climate integration.
- Reimplementing the Isca build system was a distraction.
- The successful production build is generated by `CodeBase.compile()`; future hybrid builds should use that same path.
- `path_names` is the clean overlay injection point in this Isca checkout.
- There is no `cb.add_srcdir(...)` implementation in this repository.
- Source precedence in `mkmf` is object-name based; duplicate source entries for the same object should be avoided.
- Overlay entries should be relative to the normal Isca source root.
- The original source tree does not need to be modified to build a hybrid executable.
- Separate executable names via `DryCodeBase` subclasses create separate build directories.
- `compile_flags` is good for preprocessor flags like `-DUSE_CPP_HS_FORCE`.
- Link flags such as `-lhs_forcing` and `-lstdc++` must enter through the `mkmf.template.*` mechanism.
- The production build environment is container-specific:
  - `/usr/bin/mpifort`
  - `/usr/bin/mpicc`
  - NetCDF tools
  - OpenMPI libraries
  - Ubuntu 22.04 aarch64 userspace.
- The host/Codex shell is not equivalent to the container and should not be used to judge final build viability.
- Future GPU work should wait until the full hybrid executable and short-run validations are stable.
