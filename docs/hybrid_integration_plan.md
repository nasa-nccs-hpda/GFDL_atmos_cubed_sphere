Hybrid integration plan — non-invasive strategy
=============================================

Goal
----
Create a hybrid Held‑Suarez executable that calls a C++ Held‑Suarez forcing implementation without modifying original production Fortran source files.

Principles
----------
- Non‑invasive: do not edit files under `src/...` that are the canonical production sources.
- Reproducible: keep the normal all‑Fortran executable available and unchanged.
- Minimal patching: apply changes only in an experiment/overlay area and the per‑build artifacts (builddir / generated Makefile).
- Toggleable: control using a compile-time preprocessor flag `USE_CPP_HS_FORCE`.

Preferred approach (summary)
---------------------------
Follow the user's preferred options in order:
1. Copy the original `hs_forcing` Fortran source into an experiment overlay directory and modify only the copy used for the hybrid build.
2. Add a preprocessor conditional `#ifdef USE_CPP_HS_FORCE` inside the copied source to switch to a thin Fortran wrapper that calls the C API; otherwise compile the original Fortran implementation (so the copy can behave like original if flag unset).
3. Build the C++ forcing library separately and link it into the hybrid executable during the `mkmf`/Makefile link step.
4. Do not modify or remove the all‑Fortran executable; preserve it so users can still build/run the original.

Detailed steps
--------------
1) Create an overlay folder for experiment sources
   - Recommended path: `src/extra/local_overrides/hs_forcing/` (or `exp/overrides/held_suarez/`)
   - Copy original file: `src/atmos_param/hs_forcing/hs_forcing.F90` → `src/extra/local_overrides/hs_forcing/hs_forcing.F90`.

2) Modify the copied source to support compile-time switching
   - Wrap the C++-backed codepath using Fortran preprocessor directives or an `#ifdef` region. Example structure:

```fortran
! Original Fortran implementation (kept intact)
#ifndef USE_CPP_HS_FORCE
  contains
    subroutine newtonian_damping(...)  ! original code
    ...
#else
  ! Thin wrapper that calls C API
  use iso_c_binding
  interface
    function hs_forcing_driver_c(...) bind(C, name="hs_forcing_driver_c")
      import :: c_int, c_double, c_ptr
      ! C interface declarations
    end function
  end interface

  subroutine newtonian_damping(...) bind(C)
    ! call C API / C++ library via wrapper
  end subroutine
#endif
```

   - The copy must preserve the module/interface names expected by the rest of the model (i.e., module and public routine names remain the same).

3) Ensure the build uses the copied source instead of the original
   - The `CodeBase.compile()` step writes a `path_names` file into the `builddir` before `mkmf` runs.
   - Replace the single `atmos_param/hs_forcing/hs_forcing.F90` entry in the generated `builddir/path_names` with the path to the copied override file. This can be done:
     - Programmatically: modify `CodeBase.compile()` invocation to append a small post-processing step that edits `builddir/path_names` (preferred for automation), or
     - Manually: after `compile.sh` renders `builddir/compile.sh` and before running `make`, edit `builddir/path_names`.

4) Build C++ forcing library and link into model
   - Build the C++ library separately (e.g., in `translated/held_suarez/cpp/forcing_module/build`) to produce `libhs_forcing.a` or `libhs_forcing.so`.
   - Copy the resulting library into the model `builddir` (e.g., `$builddir/lib/`) before the final `make` link step.
   - Edit the generated `builddir/Makefile` (or supply a custom `mkmf.template.*`) to add `-L$(PWD)/lib -lhs_forcing` to `LDFLAGS`/`LD` so the C++ objects are linked into `held_suarez.x`.

5) Compile-time control
   - When building the hybrid executable, pass `-DUSE_CPP_HS_FORCE` in the `cppDefs` (the `compile.sh` template builds `cppDefs` passed to `mkmf`) or append it to `CodeBase.compile()`'s `compile_flags` before rendering `compile.sh`.
   - When `USE_CPP_HS_FORCE` is not defined, the copied source falls back to the original Fortran implementation, so the override is transparent.

6) Preserve the original all‑Fortran executable
   - Do not overwrite the canonical executable path or source files in place. Keep the original build workflow available by leaving the repository `src/...` files unchanged.
   - Use a separate build directory for the hybrid experiment (the CodeBase workdir is already isolated per compile/run), so users can still produce an all‑Fortran `held_suarez.x` by building without the flag / without the override path substitution.

Testing and validation plan (dry-run)
-----------------------------------
- Unit test the wrapper: compile a minimal Fortran program that calls the C API via `iso_c_binding` and validate memory layout and values on a tiny grid.
- Integration smoke test: build hybrid executable with `-DUSE_CPP_HS_FORCE` and run `run.sh` with small resolution (`T21`) and `days=0` or 1 to check startup and no segfaults.
- Parity check: run the existing comparator (`translated/held_suarez/cpp/forcing_module/compare_outputs.py`) comparing outputs produced by hybrid executable vs Fortran baseline on `tests/fortran_baseline/forcing_module/inputs`.

Risks and mitigations
---------------------
- Module interface mismatch: Ensure wrapper module names and routine signatures exactly match the original Fortran module so the rest of the model links without modification.
- Linking order or symbol clashes: Link the C++ library last and prefer static archive `libhs_forcing.a` to avoid runtime symbol resolution issues; if symbol conflicts occur, use `-Wl,--allow-multiple-definition` only as last resort.
- Build reproducibility: Automate the `builddir/path_names` modification and linking edits (scripted) to avoid manual errors.

Deliverables (what will be produced, but not implemented now)
-----------------------------------------------------------
1. `src/extra/local_overrides/hs_forcing/hs_forcing.F90` — copied + preprocessor conditional.
2. Build script/snippet that replaces `builddir/path_names` entry during `CodeBase.compile()`.
3. A small build helper to copy `libhs_forcing.a` into `builddir/lib` and patch `builddir/Makefile` (or a custom `mkmf.template` variant).
4. A short README with build and run instructions and the comparator invocation.

Next step (after your approval)
------------------------------
I can implement the plan in a non-invasive way by creating the override source, adding the compile-time flag via `CodeBase.compile()` hooks, and providing a small helper to place and link `libhs_forcing.a` into the `builddir`. Do you want me to proceed with creating the override files and build helpers now?
