**Summary**
- Goal: Compare production Held‑Suarez builddir to the hybrid helper `builddir` and identify missing setup steps causing `mkmf` to fail.

**Production builddir (found)**
- Path: /explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_isca/build/held_suarez
- Key artifacts present:
  - `compile.sh` (rendered with real `env_source`) — this script sources the environment and runs `mkmf` and `make`.
  - `path_names` (relative paths; contains `atmos_param/hs_forcing/hs_forcing.F90`)
  - `.held_suarez.x.cppdefs` (compile flags produced)
  - many compiled objects (`*.o`, `*.mod`) and final `held_suarez.x` executable
  - symlinks to postprocessing tools: `mppnccombine.x`, `mppnccombine_run.sh`

**Hybrid builddir (found)**
- Path: hybrid_experiments/held_suarez_cpp_force/builddir
- Key artifacts present:
  - `path_names` (modified by helper) — contains one absolute overlay entry: `/panfs/.../src/extra/local_overrides/hs_forcing/hs_forcing.F90`
  - `mkmf.template` (copied hybrid template)
  - `lib/` with `libhs_forcing.a`
  - `Makefile` created by `mkmf` is empty (no `SRC`/`OBJ` entries)
  - Missing: `compile.sh`, `.held_suarez.x.cppdefs`, compiled objects, symlinks to postprocessing tools

**Exact differences (concise)**
- `compile.sh` presence: production has a rendered `compile.sh` in the execdir that (1) sources an env file, (2) creates symlinks/compiles postprocessing tools, then runs `mkmf` and `make`. Hybrid helper invoked `mkmf` directly and did not render/run `compile.sh`.
- `path_names` formatting: production `path_names` uses relative entries (e.g., `atmos_param/hs_forcing/hs_forcing.F90`); hybrid `path_names` contains an absolute overlay entry. Mixed absolute entries appear early in the file.
- `codedir`/`sourcedir` layout: production `mkmf` is called with `-a` pointing to the `codedir/src` under the workdir (a checked-out or symlinked code location used by CodeBase). Hybrid helper passed `-a` pointing to the repository `src` directory directly.
- Generated helper files: production builddir contains `.held_suarez.x.cppdefs` and other metadata files that the compile flow produces; hybrid `builddir` lacks these.
- Symlinks and compiled postprocessing: production builds (or symlinks) `mppnccombine.x` into the execdir before `mkmf`; hybrid does not.

**Evidence (selected snippets)**
- Production `compile.sh` shows env sourcing and the full `mkmf` invocation (excerpt):
  - "source /isca/src/extra/env/ubuntu_conda"
  - "mkmf=.../code/src/../bin/mkmf"
  - "sourcedir=/explore/.../code/src"
  - "pathnames=/explore/.../build/held_suarez/path_names"
  - mkmf call: `... $mkmf  -a $sourcedir -t $template -p $executable -c "$cppDefs" $pathnames $sourcedir/shared/include $sourcedir/shared/mpp/include` (see production `compile.sh`)
- Production `path_names` begins with relative entries (excerpt):
  - `atmos_param/diffusivity/diffusivity.F90`
  - `atmos_param/hs_forcing/hs_forcing.F90`
- Hybrid `builddir/path_names` shows the overlay as an absolute path (excerpt):
  - `/panfs/ccds02/nobackup/.../src/extra/local_overrides/hs_forcing/hs_forcing.F90`
- Hybrid build log shows `mkmf` ran in hybrid `builddir` and produced an empty Makefile (only `all: a.out`), and verbose `mkmf` trace shows first missing file like `atmos_shared/interpolator/interpolator.F90`.

**Root cause hypothesis (single sentence)**
- The hybrid helper bypasses the canonical `compile.sh` workflow and writes an absolute overlay path into `builddir/path_names` while invoking `mkmf` with a `-a` source-root that differs in layout from the production `codedir` layout; this combination causes `mkmf`'s localization/scanning logic to fail to open some `path_names` entries and therefore produce an empty `SRC`/`OBJ` Makefile.

**Confidence**
- High for the diagnosis that (A) the absolute overlay path in `builddir/path_names` is different from production relative paths and (B) the hybrid helper did not render/run the `compile.sh` steps that create the expected workspace layout and helper files. (Confidence: ~0.85)

**Recommended fix (concrete)**
1. Reproduce the production setup by rendering and running the `compile.sh` produced by `CodeBase.compile()` instead of calling `mkmf` directly from the helper. This ensures env sourcing, `codedir` layout, `.cppdefs` generation, postprocessing symlinks, and any additional setup are identical to the production flow.

2. If you prefer minimal changes to the helper, apply both of the following:
   - Write overlay entries in `builddir/path_names` as relative paths with respect to the `-a <source-root>` you will pass to `mkmf` (do not insert an absolute `/panfs/...` path). Example: replace `/panfs/.../src/extra/local_overrides/hs_forcing/hs_forcing.F90` with `src/extra/local_overrides/hs_forcing/hs_forcing.F90` when passing `-a /panfs/...`.
   - Make the hybrid helper set up the same `codedir` and `execdir` layout used by `CodeBase.compile()` (i.e., create a `workdir/code/src` symlink or copy so `-a` points to the same structured source tree), and produce a `.held_<executable>.cppdefs` file or pass the identical `-c` string. This avoids localization mismatches inside `mkmf`.

**Why this will likely fix it**
- `mkmf` expects `path_names` entries to be resolvable relative to the `-a` source-root (or as consistent absolute paths). Mixing absolute overlay entries with a different `-a` or missing the canonical workspace layout can cause `mkmf` to fail when it attempts to `open`/localize files and therefore skip emitting compile rules.

**Next steps (if you want me to implement the fix)**
- Update `hybrid_experiments/held_suarez_cpp_force/build_hybrid.py` to either (A) call `CodeBase.compile()` (render+run `compile.sh`) or (B) write relative overlay paths and create a `workdir/code/src` symlink so `-a` points to the same layout. I can implement (B) quickly and re-run the helper, or implement (A) for the most faithful reproduction.

---
Generated on 2026-06-05 by automated diagnosis script.