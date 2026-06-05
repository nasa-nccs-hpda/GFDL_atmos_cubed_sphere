Hybrid build diagnosis
======================

Summary
-------
Performed inspection of the generated build artifacts in:
- `hybrid_experiments/held_suarez_cpp_force/builddir/path_names`
- `hybrid_experiments/held_suarez_cpp_force/builddir/Makefile`

Findings
--------
1. How many source files mkmf discovered
- `mkmf` produced an empty `SRC` in the generated Makefile (see evidence below). So the generated Makefile discovered 0 source files (no entries in `SRC`).

2. Whether any .o targets were generated
- No. The Makefile contains `OBJ =` (empty) and no `.o` target rules were generated; the link rule tried to link `a.out` from an empty `$(OBJ)`.

3. Whether the hybrid overlay source appears in the dependency list
- Yes: `builddir/path_names` contains the overlay with an absolute path:
  - `/panfs/.../src/extra/local_overrides/hs_forcing/hs_forcing.F90` is present (the overlay replacement was written).

4. Whether path_names format differs from the original successful Held‑Suarez build
- Yes. The repository canonical `path_names` (example: `src/extra/model/dry/path_names`) uses relative paths like `atmos_param/hs_forcing/hs_forcing.F90`.
- The generated `builddir/path_names` contains one absolute path entry for the overlay, e.g. `/panfs/.../src/extra/local_overrides/hs_forcing/hs_forcing.F90`.

5. Comparison against known-working all-Fortran Makefile/path_names
- Example (from repository docs `bin/mkmf.html`) shows how a healthy Makefile looks: it contains per-source `.o` rules and populated `SRC` and `OBJ` lines (for example `OBJ = c.o a.o b.o`).
- Our generated `Makefile` instead shows empty `SRC` and `OBJ` and no per-source compile rules. See evidence below.

Evidence (exact excerpts)
-------------------------
- `hybrid_experiments/held_suarez_cpp_force/builddir/path_names` (snippet):

  atmos_param/diffusivity/diffusivity.F90
  atmos_param/edt/edt.F90
  atmos_param/entrain/entrain.F90
  /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/src/extra/local_overrides/hs_forcing/hs_forcing.F90
  atmos_param/lscale_cond/lscale_cond.F90
  ...

- `src/extra/model/dry/path_names` (canonical repo version, snippet):

  atmos_param/diffusivity/diffusivity.F90
  atmos_param/edt/edt.F90
  atmos_param/entrain/entrain.F90
  atmos_param/hs_forcing/hs_forcing.F90
  atmos_param/lscale_cond/lscale_cond.F90
  ...

- `hybrid_experiments/held_suarez_cpp_force/builddir/Makefile` (complete relevant part):

  # Makefile created by mkmf $Id: mkmf,v 16.1 2010/05/19 18:49:19 fms Exp $

  .DEFAULT:
	-echo $@ does not exist.
  all: a.out
  SRC =
  OBJ =
  clean: neat
	-rm -f .a.out.cppdefs $(OBJ) a.out
  neat:
	-rm -f $(TMPFILES)
  a.out: $(OBJ)
	$(LD) $(OBJ) -o a.out  $(LDFLAGS)

- `mkmf` reference (from `bin/mkmf.html`) shows expected form with `OBJ = c.o a.o b.o` and `.o` rules.

Root cause hypothesis
---------------------
Primary cause: `mkmf` was invoked without the required arguments that tell it where the base source tree is and which `path_names` file to use. In the repository usage pattern `mkmf` is typically invoked as:

  mkmf path_names /path/to/base/source

Invoking `mkmf` with no arguments in an otherwise-empty working directory produces a Makefile with empty `SRC`/`OBJ` (no per-source rules), which is exactly what we observed.

Secondary contributor: the overlay replacement in `path_names` was written as an absolute path. While `mkmf` can handle absolute paths, mixing absolute overlay entries with an invocation that omits the base source directory may further confuse mapping/localization behavior. The immediate blocker, however, is the way `mkmf` was invoked.

Evidence supporting hypothesis
-----------------------------
- `builddir/Makefile` shows empty `SRC` and `OBJ` (typical when `mkmf` has no source list to process).
- `builddir/path_names` exists and includes many files, including the overlay; this indicates the script prepared path_names but did not pass it to `mkmf` properly.
- `mkmf` documentation and repository examples (see `bin/mkmf.html`) show the correct usage includes the path_names argument and base source directory; the generated Makefile in that example contains populated `SRC`/`OBJ` and per-source rules.

Recommended fix (conservative, minimal changes)
---------------------------------------------
1. Re-run `mkmf` with explicit arguments pointing to the `path_names` file and the repository root (or base source dir). Example command (run inside `hybrid_experiments/held_suarez_cpp_force/builddir`):

  mkmf path_names /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere

This will let `mkmf` map relative source names to the base source tree and generate per-source `.o` rules.

2. (Optional but recommended) Use relative overlay path entries instead of absolute paths when writing `builddir/path_names` (replace `/.../src/extra/local_overrides/hs_forcing/hs_forcing.F90` with `src/extra/local_overrides/hs_forcing/hs_forcing.F90` or `extra/local_overrides/...` depending on the base dir). That keeps the `path_names` consistent with the canonical format and avoids unexpected localization behavior.

3. Ensure the custom `mkmf.template.hybrid` remains compatible with the project's `mkmf` invocation. Initially do not change the template; test with the canonical invocation above. If `mkmf` still produces incomplete Makefile, revert to the standard template and re-run to isolate template vs invocation issues.

4. To enable the C API path compilation, pass compile-time defs to `mkmf` via the `-c` option or create a `.cppdefs` file. Example:

  mkmf -c "-DUSE_CPP_HS_FORCE" path_names /path/to/repo

or after generating Makefile, create `.cppdefs` with desired CPPDEFS and re-run `mkmf -c`.

Quick validation steps
----------------------
Run (from `hybrid_experiments/held_suarez_cpp_force/builddir`):

  mkmf path_names /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere
  make -j2

If successful, the Makefile will contain populated `SRC` and `OBJ` lines and per-source `.o` rules and `a.out` will link from `.o` files.

If you want, I can perform these steps now (no template modifications) and capture the resulting Makefile and logs.
