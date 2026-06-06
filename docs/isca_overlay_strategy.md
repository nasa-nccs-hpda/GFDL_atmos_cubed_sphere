# Isca Overlay Strategy

Generated: 2026-06-05

## Scope

This investigation follows the normal Isca compile path that already produces
the working Held-Suarez executable:

```python
cb = DryCodeBase.from_directory(GFDL_BASE)
cb.compile()
```

No manual `mkmf` invocation and no build were run for this phase.

## Files Read

- `exp/test_cases/held_suarez/held_suarez_test_case.py`
- `src/extra/python/isca/codebase.py`
- `src/extra/python/isca/templates/compile.sh`
- `src/extra/model/dry/path_names`
- successful production build files:
  - `/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_isca/build/held_suarez/compile.sh`
  - `/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_isca/build/held_suarez/path_names`
  - `/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_isca/build/held_suarez/Makefile`

## How The Original Build Is Generated

`held_suarez_test_case.py` creates the codebase with:

```python
cb = DryCodeBase.from_directory(GFDL_BASE)
```

`DryCodeBase` inherits from `GreyCodeBase`, disables RRTM and SOCRATES through
compile flags, and sets:

```python
name = 'dry'
executable_name = 'held_suarez.x'
```

`CodeBase.__init__()` maps this to:

```text
workdir  = $GFDL_WORK/codebase/<directory-token>
codedir  = <workdir>/code
srcdir   = <workdir>/code/src
builddir = <workdir>/build/held_suarez
```

For `from_directory(GFDL_BASE)`, `codedir` is a symlink to the provided source
directory. In the successful production build this appears as:

```text
/explore/.../_isca/code -> /isca
```

and `srcdir` becomes:

```text
/explore/.../_isca/code/src
```

## How `path_names` Is Generated

`CodeBase.compile()` does this:

```python
if not self.path_names:
    self.path_names = self.read_path_names(
        P(self.srcdir, 'extra', 'model', self.name, 'path_names')
    )
self.write_path_names(self.path_names)
```

For `DryCodeBase`, `self.name == 'dry'`, so the source list comes from:

```text
<srcdir>/extra/model/dry/path_names
```

The generated production build file is:

```text
<builddir>/path_names
```

It contains relative source paths such as:

```text
atmos_param/hs_forcing/hs_forcing.F90
```

Important: `self.path_names` is mutable before calling `compile()`. If it is
pre-populated, `compile()` does not reread the default file. That is the clean
injection point for a replacement path list.

## How `compile.sh` Is Generated

`CodeBase.compile()` renders `src/extra/python/isca/templates/compile.sh` with
Jinja variables:

```python
vars = {
    'execdir': self.builddir,
    'template_dir': self.templatedir,
    'srcdir': self.srcdir,
    'workdir': self.workdir,
    'compile_flags': compile_flags_str,
    'env_source': env,
    'path_names': path_names_str,
    'executable_name': self.executable_name,
    'run_idb': debug,
}
```

Then it runs:

```python
sh.bash(P(self.builddir, 'compile.sh'), ...)
```

The rendered production `compile.sh`:

- sources `/isca/src/extra/env/ubuntu_conda`
- chooses `mkmf.template.${GFDL_MKMF_TEMPLATE:-ia64}`
- uses `sourcedir=<workdir>/code/src`
- uses `pathnames=<builddir>/path_names`
- runs `mkmf` and then `make`

This is the compile path we should continue using.

## Source Directories And Precedence

There is no `cb.add_srcdir(...)` implementation in this checkout.

The only source root passed to `mkmf` by normal `CodeBase.compile()` is:

```bash
-a $sourcedir
```

Additional source files are included by adding entries to `cb.path_names`.
Those entries should be relative to `$sourcedir`.

`mkmf` source precedence is object-name based. In `bin/mkmf`, when a source file
maps to an object already seen, later duplicates are ignored:

```perl
if ( $suffix && !$actual_source_of{$object} ) {
    ...
}
```

For replacement modules, the safest strategy is therefore not to include both
the original and overlay source. Replace:

```text
atmos_param/hs_forcing/hs_forcing.F90
```

with:

```text
extra/local_overrides/hs_forcing/hs_forcing.F90
```

This keeps the normal source root and avoids duplicate `hs_forcing.o` ambiguity.

## Can Alternate Source Directories Override Original Source Files?

Not directly through an `add_srcdir` API in this repository.

But yes in practice through `cb.path_names`: any source path under `srcdir` can
be substituted for the original source path before `cb.compile()`. This is a
path-list overlay, not a directory-stack overlay.

If the overlay file lives outside `srcdir`, the normal compile path does not
provide a clean external source-root mechanism. The least invasive approach is
to keep overlays under a source-root-relative location such as:

```text
src/extra/local_overrides/...
```

or to create a separate custom code directory whose `src` tree contains the
overlay files.

## Custom Code Directories

`DryCodeBase.from_directory(directory)` accepts any directory that has a valid
Isca source tree. `CodeBase.link_source_to()` symlinks:

```text
<workdir>/code -> <directory>
```

Therefore a separate custom code directory can be used without modifying the
original production source tree. For example, a wrapper script could create a
scratch source tree or symlink tree, then call:

```python
cb = DryCodeBase.from_directory('/path/to/custom/isca-tree')
cb.compile()
```

However, for the Held-Suarez forcing replacement, a full custom tree is not
required if the overlay file already exists under `srcdir` and `cb.path_names`
is edited before `compile()`.

## C++ Hybrid Link Requirement

A Fortran-only replacement module can be compiled through the normal path with
only a `path_names` substitution.

The current hybrid forcing module delegates to C++ through
`hs_forcing_c_interface` and `libhs_forcing.a`. Normal `CodeBase.compile()` has
two relevant hooks:

- `cb.compile_flags`: inserted only into the `cppDefs` string passed to `mkmf`
- selected `mkmf.template.*`: controls `FC`, `CC`, `FFLAGS`, `LDFLAGS`, etc.

`compile_flags` is sufficient for:

```text
-DUSE_CPP_HS_FORCE
```

It is not sufficient for:

```text
-L... -lhs_forcing -lstdc++
```

because those must enter link flags, normally through the selected
`mkmf.template.*`.

Also, this `mkmf` recognizes `.F`, `.F90`, `.c`, `.f`, and `.f90` as source
suffixes. It does not compile `.cpp` sources from `path_names`. A C++ static
library therefore needs either:

- a hybrid mkmf template selected by the normal compile script, or
- a C/Fortran-only integration unit that avoids separate C++ link flags, or
- a small normal-workflow wrapper that prepares the C++ library and exposes its
  link flags through the selected template.

## Answers

### A. Can a modified Held-Suarez forcing module be compiled through the normal Isca build process?

Yes, for the Fortran module replacement itself.

The normal path is:

1. create a `DryCodeBase`
2. set `cb.path_names` to the dry path list with the `hs_forcing.F90` entry
   replaced by the overlay path
3. optionally append `-DUSE_CPP_HS_FORCE` to `cb.compile_flags`
4. call `cb.compile()`

For the C++ hybrid, the Fortran overlay can enter through normal `cb.compile()`,
but the C++ link dependency still needs a normal-workflow link hook, most likely
a selected `mkmf.template.hybrid` or equivalent template.

### B. Can we create `held_suarez_fortran.x` and `held_suarez_hybrid.x` without modifying the original source tree?

Yes.

Use two `DryCodeBase` subclasses or equivalent small driver-side classes with
different `executable_name` values:

```python
class HeldSuarezFortranCodeBase(DryCodeBase):
    executable_name = 'held_suarez_fortran.x'

class HeldSuarezHybridCodeBase(DryCodeBase):
    executable_name = 'held_suarez_hybrid.x'
```

Because `builddir` is computed from `executable_name` during `CodeBase`
construction, this creates separate build directories:

```text
<workdir>/build/held_suarez_fortran
<workdir>/build/held_suarez_hybrid
```

The Fortran executable uses the default dry `path_names`.

The hybrid executable uses a modified in-memory `path_names` list and hybrid
compile/link settings. The original production source files remain untouched.

### C. What is the minimal implementation required?

Minimal implementation should be a small Python driver that uses
`CodeBase.compile()` twice.

1. Define two subclasses for distinct executable names.

2. Build the original executable:

```python
cb_fortran = HeldSuarezFortranCodeBase.from_directory(GFDL_BASE)
cb_fortran.compile()
```

3. Build the hybrid executable through the same compile path:

```python
cb_hybrid = HeldSuarezHybridCodeBase.from_directory(GFDL_BASE)
paths = cb_hybrid.read_path_names(
    P(cb_hybrid.srcdir, 'extra', 'model', cb_hybrid.name, 'path_names')
)
cb_hybrid.path_names = [
    'extra/local_overrides/hs_forcing/hs_forcing.F90'
    if p == 'atmos_param/hs_forcing/hs_forcing.F90' else p
    for p in paths
]
cb_hybrid.compile_flags.append('-DUSE_CPP_HS_FORCE')
cb_hybrid.compile()
```

4. Add the C++ link path through the normal template selection mechanism.

Preferred minimal link strategy:

- keep using `compile.sh` rendered by `CodeBase.compile()`
- set `GFDL_MKMF_TEMPLATE=hybrid` only for the hybrid build
- provide/select `mkmf.template.hybrid` with the extra link flags:

```make
LDFLAGS = -lnetcdff -lnetcdf -lmpi -L<hybrid-lib-dir> -lhs_forcing -lstdc++
```

This keeps the Isca compile workflow intact: `CodeBase.compile()` still renders
`compile.sh`, writes `path_names`, invokes `mkmf`, and runs `make`.

5. If the hybrid C++ library is not already built inside the container, build it
before `cb_hybrid.compile()` using the same container compiler stack. Do this as
a preparation step, not by reimplementing the Isca Fortran build.

## Recommended Next Step

Implement a small `hybrid_experiments/held_suarez_cpp_force/compile_with_isca.py`
or equivalent script that:

- imports `DryCodeBase`
- defines the two executable-name subclasses
- builds the baseline with default `path_names`
- builds the hybrid with only:
  - `path_names` substitution
  - `-DUSE_CPP_HS_FORCE`
  - `GFDL_MKMF_TEMPLATE=hybrid` or a local template selection equivalent

Before building, verify that the existing overlay Fortran is legal in the full
Isca compile context and that `hs_forcing_c_interface.F90` is included in
`cb_hybrid.path_names` if the overlay uses that module.
