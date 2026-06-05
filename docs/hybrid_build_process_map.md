Hybrid Held-Suarez Build / Run Process Map
=========================================

Purpose
-------
Brief map of how the all-Fortran Held‑Suarez executable is built and run in this repository, where the build artifacts live, and safe injection points to introduce a hybrid (Fortran driver + alternate C/C++ forcing) without editing production source files.

Found artifacts (how the repo builds/runs Held‑Suarez)
----------------------------------------------------
- Build driver: Python `isca` helper (`src/extra/python/isca/CodeBase` / `DryCodeBase`).
  - `exp/test_cases/held_suarez/held_suarez_test_case.py` calls `cb.compile()` then `exp.run()`.
  - `DryCodeBase.executable_name` = `held_suarez.x` and `DryCodeBase.name` = `dry`.

- Compilation steps (what `cb.compile()` does):
  1. CodeBase constructs a working tree under `$GFDL_WORK` (default env var). Typical layout:
     - `$GFDL_WORK/codebase/` (code symlink or checkout)
     - `$GFDL_WORK/<hash>/build/held_suarez/` (the `builddir` = `CodeBase.builddir` / `execdir`)
     - executable path: `<builddir>/held_suarez.x`
  2. The codebase writes a `path_names` file (from `src/extra/model/dry/path_names`) into the builddir.
  3. The Jinja `compile.sh` template is rendered into `builddir/compile.sh` and executed.
     - `compile.sh` invokes `mkmf` with the `path_names` list and a selected `mkmf.template.*`.
     - `mkmf` generates a Makefile in `builddir` and `make` is run to compile all listed sources.
     - `make` then builds the executable `held_suarez.x` in `builddir`.

- Which source files are compiled for Held‑Suarez:
  - The authoritative list is `src/extra/model/dry/path_names` (examples: `atmos_param/hs_forcing/hs_forcing.F90`, `atmos_spectral/driver/solo/atmosphere.F90`, spectral/transforms, shared/fms, etc.).
  - These entries are passed to `mkmf` which expands them, compiles `.F90`/`.c` into object files, and links into `held_suarez.x`.

- Where the build directory and executable live:
  - Build directory: `CodeBase.builddir` → by default `P($GFDL_WORK, '...workdir...', 'build', 'held_suarez')`. In practice: `$GFDL_WORK/.../build/held_suarez/`.
  - Executable: `<builddir>/held_suarez.x` (and `mppnccombine.x`, helper tools are symlinked into builddir).

- How the run script launches it:
  - `exp.run()` writes a runscript from template `src/extra/python/isca/templates/run.sh` into the per‑run `rundir` and runs it.
  - `run.sh` copies `{{ execdir }}/{{ executable }}` into the run directory and then executes `mpirun -np N {{ execdir }}/held_suarez.x` (or `exec idb` in debug mode).
  - `run_held_suarez.sh` (top-level helper) runs `held_suarez_test_case.py` inside a container (apptainer) which in turn calls `cb.compile()` and `exp.run()`.

Safe injection points (do not edit production source files)
--------------------------------------------------------
The requirement is to avoid modifying original model source files (the ones under `src/...` referenced by `path_names`). The build system offers several practical injection points that let you alter the compiled product at build-time or runtime without editing those original files:

1) Override `path_names` used for the build (recommended for source-level substitution)
   - `CodeBase.write_path_names()` writes a `path_names` file into the `builddir` before calling `mkmf`.
   - Edit or replace that `builddir/path_names` to point one entry to an alternate Fortran file (for example a replacement `hs_forcing.F90` or a small wrapper) that lives outside the original production file but is compiled instead.
   - Where to put the replacement source:
     - Inside the code tree but in a new folder (e.g., `src/extra/local_overrides/hs_forcing_wrapper.F90`) and add that path into the `builddir/path_names` (this does not alter the original `atmos_param/hs_forcing/hs_forcing.F90`).
     - Or place the replacement in the builddir itself (e.g., `build/held_suarez/overrides/hs_forcing.F90`) and point `builddir/path_names` to that file (mkmf can accept relative/absolute paths).
   - Pros: produces a single, consistent executable; Fortran modules compile in-place; minimal runtime changes.
   - Cons: must ensure module names and interface are compatible with the rest of the model (module replacement is a natural way to swap `hs_forcing`).

2) Link C/C++ object or static library at link time (recommended for providing C API implementation)
   - After `mkmf` generates the Makefile (but before `make` link step), inject linking flags or object files into the generated Makefile in the builddir.
   - Options:
     - Place `libhs_forcing.a` (or `.so`) in `builddir` and add `-L$(PWD) -lhs_forcing` to the link line (LDFLAGS / LD variable in Makefile). The `mkmf.template.*` files define `LDFLAGS`; editing the generated Makefile is the simplest per-build approach.
     - Append compiled `.o` files from your C/C++ build into the Makefile object list so they are included in the final link.
     - Alternative: create a small make fragment (e.g., `extra_link.mk`) and `include` it from the generated Makefile (or patch Makefile to include it).
   - Where to build the C++ library:
     - Build it separately (e.g., in `translated/held_suarez/cpp/forcing_module/build`) and copy `libhs_forcing.a` into the model `builddir` before running `make`.
   - Pros: no change to Fortran sources; best for an implementation that exposes a C ABI (the existing C API header `translated/held_suarez/cpp/forcing_module/include/held_suarez_c_api.h` fits this model).
   - Cons: you must ensure Fortran→C symbols/memory layout match (use `iso_c_binding` wrappers), and you must patch Makefile link options.

3) Runtime wrapper / executable replacement (quick experiment option)
   - After successful build, replace `<builddir>/held_suarez.x` with a wrapper executable (same name) that sets up the environment and invokes your hybrid binary (or loads a shared library). Since `run.sh` copies the executable from `execdir` into the run directory, replacing the builddir executable changes what runs without touching sources.
   - Pros: zero changes to compile-time pipeline.
   - Cons: brittle and less reproducible than proper build-time linking; you must ensure MPI and argv semantics are respected by the wrapper.

Linking notes / practical steps
------------------------------
- The `mkmf` templates are under `src/extra/python/isca/templates/mkmf.template.*` and define `FFLAGS`, `LD`, and `LDFLAGS`. You can either:
  - Edit the generated Makefile in `builddir` to add your `-L`/`-l` flags (recommended per-build edit), or
  - Provide a custom `mkmf.template.*` that adds the required `LDFLAGS`, and set `GFDL_MKMF_TEMPLATE` environment variable prior to compile (this changes template selection for `mkmf`).

- Typical minimal steps to link `libhs_forcing.a` into the final executable:
  1. Build your C++ static library (outside model); put `libhs_forcing.a` into `builddir`.
  2. Edit `builddir/Makefile` (or the mkmf template) to add `-L$(PWD) -lhs_forcing` into the link flags (LDFLAGS/LD variable) before running `make`.
  3. Run `make held_suarez.x` (or re-run the `compile.sh` flow).

Environment / runtime caveats
-----------------------------
- Compiler/runtime environment: `KNOWN_ISSUES.md` documents that a GCC module must be loaded on some systems and that `-fdefault-real-8` and other flags are used. The compile template sources an environment file (`env_source`) before building; ensure it sets `F90`/`F90FLAGS`/`LD` as required.
- The Python driver (`compile.sh` template) uses `nf-config` / `nc-config` for NetCDF flags—ensure `netcdf` dev libs are available in the environment used for compilation.

Recommended safe approach to create a hybrid executable (summary)
--------------------------------------------------------------
1. Build your C++ forcing library independently and produce a static archive `libhs_forcing.a` (or `.so`).
2. Create a replacement Fortran wrapper or small stub that implements the same Fortran `module`/routine interface as `hs_forcing` but calls the C API via `iso_c_binding`. Place that wrapper in a new folder (e.g., `src/extra/local_overrides/hs_forcing_wrapper.F90`).
3. Arrange for the model build to use the wrapper instead of the original module by replacing the `builddir/path_names` entry for `atmos_param/hs_forcing/hs_forcing.F90` with the path to your wrapper (this keeps original sources untouched).
4. Copy `libhs_forcing.a` into `builddir` and add linking flags to the generated `builddir/Makefile` (or use a custom `mkmf.template` or small `extra_link.mk` that the Makefile includes) so the C++ library is linked into `held_suarez.x`.
5. Run the normal Python flow (`cb.compile(); exp.run()`). The produced binary will contain your linked C++ forcing implementation called from Fortran wrapper code.

Where to look in this repo
-------------------------
- `run_held_suarez.sh` — top-level helper that runs the Python test case inside a container.
- `exp/test_cases/held_suarez/held_suarez_test_case.py` — Python driver that calls `cb.compile()` and `exp.run()`.
- `src/extra/python/isca/codebase.py` — `CodeBase.compile()` and builddir / path_names handling.
- `src/extra/python/isca/templates/compile.sh` — the compile script used by `CodeBase.compile()` (renders `mkmf` invocation and `make`).
- `src/extra/python/isca/templates/mkmf.template.*` — compiler/linker template variables (`LDFLAGS`, `FFLAGS`, etc.).
- `src/extra/model/dry/path_names` — authoritative list of source files used to build Held‑Suarez (includes `atmos_param/hs_forcing/hs_forcing.F90`).

Final notes
-----------
- The most reproducible, low-risk approach is to (A) provide a replacement Fortran module file (wrapper) and include it in the `builddir/path_names` so it is compiled in place of the original, and (B) link `libhs_forcing.a` into the builddir's link step by adjusting the generated Makefile (or using a custom mkmf template). This preserves the original production sources and yields a single executable built by the normal workflow.

Docker / container runtime
--------------------------
- This repository includes a runtime Docker image described by `requirements/Dockerfile` which prepares an Ubuntu-based environment with `gfortran`, `netcdf` dev libs, Python, and the `isca` Python package installed.
- Use the Dockerfile to build a reproducible container for compile/run steps instead of the Apptainer image used by `run_held_suarez.sh`.
- Typical build & run commands:

```bash
docker build -t isca-runtime -f requirements/Dockerfile .
docker run --rm -v $PWD:/isca -v $GFDL_DATA:/data -e GFDL_WORK=/tmp isca-runtime bash -lc "cd /isca && python3 exp/test_cases/held_suarez/held_suarez_test_case.py"
```

Note: `run_held_suarez.sh` runs inside an Apptainer container by default; if you prefer Docker, either build from `requirements/Dockerfile` or adapt that file to your environment. The Dockerfile is useful for ensuring the same compilers and libraries are available during `cb.compile()` and `exp.run()`.

-- end
