# Held-Suarez Hybrid Integration Handoff

## Project Goal

Modernize legacy Fortran atmospheric models (ultimately GEOS) by validating a staged Fortran → C++ → GPU migration workflow.

Current prototype: Held-Suarez model from Isca.

## Completed

### Code Understanding

* Generated code map
* Created memory/CLAUDE.md
* Created porting target list

### Routine Translation

Validated Fortran → C++ translations:

* calc_ecc_anomaly
* forcing routine #1
* forcing routine #2

All passed numerical comparison.

### Forcing Module

Completed standalone C++ Held-Suarez forcing module.

Location:

translated/held_suarez/cpp/forcing_module/

Validation:

Fortran baseline vs C++ candidate:

* output_tdt.bin PASS
* output_teq.bin PASS
* output_udt.bin PASS
* output_vdt.bin PASS

All errors exactly zero.

### Hybrid Validation

Completed:

Fortran runner
→ C API
→ C++ forcing module

Outputs match Fortran baseline exactly.

## Current Milestone

Build a hybrid Held-Suarez executable without modifying the original production Held-Suarez source tree.

## Current Branch

<fill in branch>

## Current Blocker

Hybrid build helper does not yet generate a working executable.

### Findings

Production build:

/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_isca/build/held_suarez

Hybrid build:

hybrid_experiments/held_suarez_cpp_force/builddir

mkmf invocation updated to match compile.sh.

Remaining issue:

mkmf fails while scanning sources and generates no object rules.

Latest diagnosis:

See:
docs/hybrid_build_diagnosis_phase2.md

Current recommendation:

Implement minimal fix:

* relative overlay path
* codedir/symlink layout matching production build
* rerun mkmf
* rerun make

Do NOT switch to CodeBase.compile() yet.

## Next Task

Attempt minimal-fix hybrid build and determine whether object compilation begins.

Stop after:

* successful executable generation
  OR
* first new compile/link failure.
