# End-to-End Hybrid Modernization Workflow

Generated: 2026-06-08

## 1. Project Goal

The long-term goal is to develop a repeatable workflow for modernizing GEOS
physics and dynamics code toward GPU portability.  The intended path is:

```text
legacy Fortran -> validated C++ -> mixed Fortran/C++ hybrid executable -> future GPU-aware redesign
```

Held-Suarez in Isca is the prototype because it is scientifically meaningful,
small enough to reason about, and integrated into a real model workflow.  The
current prototype focuses on the Held-Suarez forcing module:

```text
src/atmos_param/hs_forcing/hs_forcing.F90
```

The experiment demonstrates that a translated C++ forcing implementation can be
validated independently, wrapped through a C ABI, injected through a native Isca
source overlay, built with the normal Isca build path, and run inside the model.

## 2. Completed Milestones

Routine-level translation:

```text
calc_ecc_anomaly
calc_hour_angle
newtonian_damping
rayleigh_damping
top_down_newtonian_damping
```

Forcing-module C++ translation:

```text
translated/held_suarez/cpp/forcing_module/
```

Standalone Fortran baseline harness:

```text
tests/fortran_baseline/forcing_module/
```

C++ comparison:

```text
translated/held_suarez/cpp/forcing_module/compare_outputs.py
tests/reports/forcing_module_compare_report.json
```

Fortran -> C API -> C++ validation:

```text
translated/held_suarez/cpp/forcing_module/fortran/hs_forcing_c_interface.F90
translated/held_suarez/cpp/forcing_module/fortran/test_hs_forcing_integration.F90
```

Result:

```text
Fortran baseline -> C API -> C++ forcing module produced exact agreement.
```

Native Isca overlay build:

```text
hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py
src/extra/local_overrides/hs_forcing/hs_forcing.F90
src/extra/local_overrides/hs_forcing/hs_forcing_rest.inc
src/extra/env/hybrid
src/extra/python/isca/templates/mkmf.template.hybrid
```

Hybrid executable generation:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_hybrid/held_suarez_hybrid.x
```

1-day smoke test:

```text
logs/hybrid_run_1day.log
${GFDL_DATA}/held_suarez_hybrid/run0001/atmos_monthly.nc
```

30-day hybrid run:

```text
logs/hybrid_run_30day.log
```

The 30-day run completed, combined `atmos_monthly.nc`, and wrote restart output
under:

```text
${GFDL_DATA}/held_suarez_hybrid/
```

## 3. Directory Layout

`memory/`

Project state, handoff notes, checkpoints, and migration status.

`docs/`

Translation specs, build diagnoses, run reports, overlay strategy, and this
workflow.

`tests/fortran_baseline/`

Standalone Fortran harnesses and binary reference data for translated routines
and the forcing module.

`translated/held_suarez/cpp/`

C++ translations, standalone drivers, C API, Fortran `iso_c_binding` interface,
and C++ static library.

`src/extra/local_overrides/`

Native Isca source overlays.  For the hybrid forcing build:

```text
src/extra/local_overrides/hs_forcing/hs_forcing.F90
src/extra/local_overrides/hs_forcing/hs_forcing_rest.inc
```

`hybrid_experiments/held_suarez_cpp_force/`

Hybrid build and run scripts:

```text
compile_native_overlay.py
run_hybrid_held_suarez.py
setup_env.sh
```

`tests/reports/`

JSON comparison reports.

`logs/`

Build and runtime logs captured with `tee`.

## 4. Reusable Workflow For A New Module

Step A: identify target module

Choose a Fortran module or routine group with a clear model role and bounded
inputs/outputs.  Record the original path, call sites, module dependencies, and
namelist state.

Step B: create translation spec

Write a spec in `docs/` that captures equations, array shapes, units, Fortran
control flow, dependencies, expected numerical tolerances, and candidate GPU
parallel structure.

Step C: translate isolated routines

Start with pure or mostly pure kernels.  Translate them into small C++ headers
or source files under:

```text
translated/held_suarez/cpp/<MODULE_NAME>/
```

Step D: build Fortran baseline harness

Create a standalone Fortran harness under:

```text
tests/fortran_baseline/<MODULE_NAME>/
```

Emit deterministic inputs and reference outputs as binary or text artifacts.

Step E: build C++ standalone module

Create a C++ driver that reads the same inputs and writes candidate outputs.
Keep the first implementation simple and CPU-only.

Step F: compare outputs

Compare Fortran reference outputs against C++ candidate outputs.  Report:

```text
max abs error
max relative error
RMSE
shape/dimension match
pass/fail tolerance
```

Step G: expose C API

Add an `extern "C"` API so Fortran can call the translated C++ module without
C++ name mangling.

Step H: create Fortran `iso_c_binding` wrapper

Create a Fortran module that declares the C ABI and adapts Fortran arrays,
scalars, and kinds to the C++ API.

Step I: validate Fortran -> C API -> C++

Build a small Fortran integration harness that calls the C API wrapper.  Compare
its outputs against the standalone Fortran baseline and standalone C++ results.

Step J: create Isca overlay source

Copy only the minimum Fortran source needed into:

```text
src/extra/local_overrides/<MODULE_NAME>/
```

Replace the original implementation path through `path_names`, not by editing
the production source.

Step K: build native hybrid executable through `CodeBase.compile()`

Use a `DryCodeBase` or appropriate Isca `CodeBase` subclass and the normal
Isca compile path.  Add only the needed compile flags, source overlay, C
interface source, and mixed-language link template.

Step L: run smoke test

Run the shortest meaningful simulation.  Confirm the executable starts, runs,
writes diagnostics, and archives restart output.

Step M: run duration-matched baseline/hybrid comparison

Run all-Fortran and hybrid experiments with identical namelist, diagnostic
cadence, resolution, core count, and duration.  Compare NetCDF outputs field by
field.

Step N: document status

Update:

```text
docs/
memory/MIGRATION_STATUS.md
memory/HYBRID_PHASE*_CHECKPOINT.md
```

Record exact commands, logs, outputs, failures, and fixes.

## 5. Important Lessons Learned

Use `CodeBase.compile()`, not manual `mkmf`, for final integration.  Manual
`mkmf` experiments are useful for diagnosis but easy to make subtly different
from production.

Keep original source untouched.  Use source overlays to replace only the target
file.

Use source overlays and explicit path replacement.  For this project,
`atmos_param/hs_forcing/hs_forcing.F90` was replaced by:

```text
extra/local_overrides/hs_forcing/hs_forcing.F90
```

Build the C++ static library inside the same container and architecture used for
the Fortran link.  A host-built archive caused an incompatible-library failure.

Use:

```text
GFDL_ENV=hybrid
src/extra/env/hybrid
src/extra/python/isca/templates/mkmf.template.hybrid
```

for mixed-language linking.

Log everything with `tee`, including container architecture, compiler paths,
compile target, and full linker command.

Compare progressively:

```text
unit -> module -> wrapper -> executable -> run output
```

Each layer should have its own report and stop condition.

## 6. Known Pitfalls And Fixes

Host vs container architecture mismatch:

The first `libhs_forcing.a` was x86_64 while the container link was aarch64.
Fix: rebuild `libhs_forcing.a` inside the Apptainer container immediately before
`CodeBase.compile()` links the executable.

Incompatible `libhs_forcing.a`:

Symptom:

```text
/usr/bin/ld: skipping incompatible .../libhs_forcing.a
/usr/bin/ld: cannot find -lhs_forcing
```

Fix: build the archive in `compile_native_overlay.py`, then copy it into the
actual hybrid builddir `lib/`.

Missing symbols from `path_names` or overlay source:

Symptom:

```text
undefined reference to `update_orbit_'
undefined reference to `calc_hour_angle_'
```

Diagnosis showed the symbols were helper procedures originally defined inside
`hs_forcing.F90`; the overlay include had omitted them.  Fix: restore the
helper procedures into the overlay include.

Fortran `USE` statement placement:

Fortran `use` statements must appear before declarations in a procedure/module
scope.  Fix: move `use hs_forcing_c_interface` to the module use block under
the relevant preprocessor guard.

Duplicated `INCLUDE`/helper routines:

Duplicating included helper procedures caused cascade errors.  Fix: keep one
copy of the original helper routine set in `hs_forcing_rest.inc`.

Wrong `path_names` source root:

The native Isca build resolves source paths relative to the checked-out/symlinked
codebase `src` root in `$GFDL_WORK/codebase/.../code/src`.  Fix: express overlay
paths relative to that root.

Linker order and `-lstdc++`:

The mixed Fortran/C++ link must place the C++ archive and `-lstdc++` in the
link line.  The hybrid mkmf template adds:

```text
-L... -lhs_forcing -lstdc++ -lm
```

Copilot/Codex session handoff issues:

Long multi-phase work needs explicit restart documents.  The most useful files
were:

```text
memory/CODEX_HANDOFF.md
memory/HYBRID_PHASE4_CHECKPOINT.md
memory/MIGRATION_STATUS.md
```

## 7. Commands Used

Build hybrid executable:

```bash
./run_compile_hybrid.sh
```

Equivalent inner command:

```bash
python3 hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py hybrid
```

Run 1-day smoke test:

```bash
python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --days 1 \
  --overwrite
```

Run 30-day hybrid run:

```bash
python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --days 30 \
  --production-diag \
  --overwrite
```

Compare outputs:

```bash
python3 tests/compare_hybrid_outputs.py \
  --baseline-exp held_suarez_default \
  --candidate-exp held_suarez_hybrid \
  --run 1 \
  --out tests/reports/hybrid_30day_compare_report.json
```

Create a duration-matched 1-day all-Fortran baseline:

```bash
python3 - <<'PY'
import sys
from pathlib import Path

from isca import DryCodeBase, Experiment, GFDL_BASE

sys.path.insert(0, str(Path(GFDL_BASE) / "exp" / "test_cases" / "held_suarez"))
from held_suarez_test_case import namelist, diag, RESOLUTION

cb = DryCodeBase.from_directory(GFDL_BASE)
exp = Experiment("held_suarez_fortran_1day", codebase=cb)
exp.namelist = namelist.copy()
exp.diag_table = diag.copy()
exp.set_resolution(*RESOLUTION)
exp.update_namelist({"main_nml": {"days": 1}})

for output_file in exp.diag_table.files.values():
    output_file["freq"] = 1
    output_file["units"] = "days"
    output_file["time_units"] = "days"

exp.run(1, num_cores=16, use_restart=False, overwrite_data=True)
PY
```

Compare 1-day outputs:

```bash
python3 tests/compare_hybrid_outputs.py \
  --baseline-exp held_suarez_fortran_1day \
  --candidate-exp held_suarez_hybrid \
  --run 1 \
  --out tests/reports/hybrid_1day_compare_report.json
```

## 8. Template For Applying To Next Module

Checklist:

```text
MODULE_NAME = <module_or_kernel_name>
ORIGINAL_FORTRAN_PATH = src/<path/to/original>.F90
OVERLAY_FORTRAN_PATH = src/extra/local_overrides/<MODULE_NAME>/<file>.F90
CPP_MODULE_PATH = translated/held_suarez/cpp/<MODULE_NAME>/
C_API_NAME = <module>_c_api
WRAPPER_NAME = <module>_c_interface.F90
BASELINE_OUTPUT_DIR = tests/fortran_baseline/<MODULE_NAME>/outputs/
HYBRID_OUTPUT_DIR = ${GFDL_DATA}/<experiment_name>/
```

Work items:

```text
[ ] Identify original source and call sites.
[ ] Write docs/translation_spec_<MODULE_NAME>.md.
[ ] Build standalone Fortran harness.
[ ] Translate isolated routines to C++.
[ ] Build C++ standalone driver.
[ ] Compare Fortran and C++ outputs.
[ ] Add extern "C" API.
[ ] Add Fortran iso_c_binding wrapper.
[ ] Validate Fortran -> C API -> C++.
[ ] Create overlay Fortran source.
[ ] Add CodeBase subclass/path_names replacement.
[ ] Add compile flag if needed.
[ ] Add hybrid mkmf template/library flags if needed.
[ ] Build C++ archive inside container.
[ ] Build hybrid executable through CodeBase.compile().
[ ] Run 1-day smoke test.
[ ] Run duration-matched all-Fortran baseline.
[ ] Compare NetCDF outputs.
[ ] Update docs and memory status.
```

## 9. Current Status

Held-Suarez forcing module hybrid path is validated through successful
translation, C API integration, native Isca overlay build, hybrid executable
generation, 1-day smoke run, and successful 30-day hybrid run.

Current executable:

```text
held_suarez_hybrid.x
```

Current hybrid output:

```text
${GFDL_DATA}/held_suarez_hybrid/run0001/atmos_monthly.nc
```

Next validation step:

```text
compare 30-day all-Fortran Held-Suarez output against 30-day hybrid output
```

Next modernization step:

```text
apply this workflow to the next Held-Suarez module or kernel
```
