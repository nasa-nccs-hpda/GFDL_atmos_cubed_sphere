#!/usr/bin/env python3
"""
Minimal hybrid build helper that avoids depending on the Python `isca` module.

It performs the following (non-invasive):
 - Create a dedicated build directory under hybrid_experiments/held_suarez_cpp_force/builddir
 - Create a local `code` symlink so `code/src` matches the production build layout
 - Copy the repository `path_names` file and replace the `hs_forcing.F90` entry with the overlay,
   written relative to `code/src`
 - Copy `libhs_forcing.a` into `builddir/lib`
 - Copy our `mkmf.template.hybrid` into the builddir as `mkmf.template`
 - Run `bin/mkmf` (if available) then `make -j2` in the builddir
 - Save stdout/stderr into `hybrid_experiments/held_suarez_cpp_force/logs/build.log`
 - If the built executable exists, copy it to `builddir/held_suarez_hybrid.x` and run a very short smoke check

This script intentionally keeps all changes within `hybrid_experiments/held_suarez_cpp_force/` and
`translated/held_suarez/cpp/forcing_module/`.
"""
import os
import shutil
import subprocess
from pathlib import Path
import datetime

REPO = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LOG_DIR = HERE / 'logs'
LOG_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE = LOG_DIR / 'build.log'


def write_log(msg):
    timestamp = datetime.datetime.utcnow().isoformat() + 'Z'
    with open(LOG_FILE, 'a') as f:
        f.write(f"[{timestamp}] {msg}\n")


def run_cmd(cmd, cwd, env=None):
    write_log(f"RUN: {' '.join(cmd)} (cwd={cwd})")
    try:
        proc = subprocess.run(cmd, cwd=str(cwd), env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True, timeout=600)
        write_log(proc.stdout)
        return proc.returncode, proc.stdout
    except subprocess.SubprocessError as e:
        write_log(f"ERROR running {' '.join(cmd)}: {e}")
        return 99, str(e)


def find_path_names():
    # common locations - prefer the dry model path_names
    candidates = [
        REPO / 'src' / 'extra' / 'model' / 'dry' / 'path_names',
        REPO / 'path_names',
    ]
    for c in candidates:
        if c.exists():
            return c
    return None


def main():
    write_log('Starting hybrid build helper')

    path_names_src = find_path_names()
    if path_names_src is None:
        write_log('ERROR: could not find path_names in expected locations')
        print('ERROR: could not find path_names. See', LOG_FILE)
        return 2

    overlay = REPO / 'src' / 'extra' / 'local_overrides' / 'hs_forcing' / 'hs_forcing.F90'
    if not overlay.exists():
        write_log(f'ERROR: overlay not found at {overlay}')
        print('ERROR: overlay not found; see', LOG_FILE)
        return 3

    builddir = HERE / 'builddir'
    if builddir.exists():
        write_log(f'removing existing builddir {builddir}')
        shutil.rmtree(builddir)
    builddir.mkdir(parents=True)

    # Match the production CodeBase layout closely enough for mkmf localization:
    # production uses <workdir>/code/src as the source root.
    code_link = builddir / 'code'
    code_link.symlink_to(REPO, target_is_directory=True)
    sourcedir = code_link / 'src'
    overlay_rel = Path('extra') / 'local_overrides' / 'hs_forcing' / 'hs_forcing.F90'

    # copy and modify path_names
    pn_dest = builddir / 'path_names'
    with open(path_names_src, 'r') as f:
        lines = f.readlines()
    new_lines = []
    replaced = False
    for line in lines:
        if line.strip() == 'atmos_param/hs_forcing/hs_forcing.F90':
            new_lines.append(str(overlay_rel) + '\n')
            replaced = True
        else:
            new_lines.append(line)
    if not replaced:
        # try to find any line containing hs_forcing.F90
        new_lines = [ (str(overlay_rel) + '\n') if 'hs_forcing.F90' in l else l for l in lines ]

    with open(pn_dest, 'w') as f:
        f.writelines(new_lines)
    write_log(f'Created code symlink {code_link} -> {REPO}')
    write_log(f'Wrote modified path_names to {pn_dest} (replaced={replaced}, overlay={overlay_rel})')

    # copy libhs_forcing.a
    lib_src = REPO / 'translated' / 'held_suarez' / 'cpp' / 'forcing_module' / 'libhs_forcing.a'
    lib_dest = builddir / 'lib'
    lib_dest.mkdir()
    if lib_src.exists():
        shutil.copy2(lib_src, lib_dest / 'libhs_forcing.a')
        write_log(f'Copied {lib_src} -> {lib_dest}')
    else:
        write_log(f'WARNING: {lib_src} not found')

    # copy custom mkmf template into builddir
    template_src = REPO / 'src' / 'extra' / 'python' / 'isca' / 'templates' / 'mkmf.template.hybrid'
    if template_src.exists():
        shutil.copy2(template_src, builddir / 'mkmf.template')
        write_log(f'Copied mkmf template {template_src} -> {builddir}/mkmf.template')
    else:
        write_log(f'INFO: hybrid mkmf template not found at {template_src}; continuing')

    # Invoke mkmf to create Makefile using the same interface as compile.sh
    executable = 'held_suarez.x'
    # prefer hybrid template if available in repo templates
    template_repo = REPO / 'src' / 'extra' / 'python' / 'isca' / 'templates' / 'mkmf.template.hybrid'
    if template_repo.exists():
        template = str(template_repo)
    else:
        template = str(REPO / 'src' / 'extra' / 'python' / 'isca' / 'templates' / 'mkmf.template')

    cppDefs = '-Duse_libMPI -Duse_netCDF -Duse_LARGEFILE -DINTERNAL_FILE_NML -DOVERLOAD_C8 -DUSE_CPP_HS_FORCE'
    mkmf_cmd = [str(REPO / 'bin' / 'mkmf'), '-a', str(sourcedir), '-t', template, '-p', executable, '-c', cppDefs, str(pn_dest), str(sourcedir / 'shared' / 'include'), str(sourcedir / 'shared' / 'mpp' / 'include')]

    rc, out = run_cmd(mkmf_cmd, cwd=builddir, env=os.environ)
    if rc != 0:
        write_log('mkmf failed; aborting build step')
        print('mkmf failed; see', LOG_FILE)
        return rc

    # run make
    rc, out = run_cmd(['make', '-j2'], cwd=builddir, env=os.environ)
    if rc != 0:
        write_log('make failed; see above output')
        print('make failed; see', LOG_FILE)
        return rc

    # look for produced executable
    exe_candidates = list(builddir.glob('**/held_suarez*')) + list(builddir.glob('**/*.x'))
    exe_path = None
    for c in exe_candidates:
        if c.is_file() and os.access(c, os.X_OK):
            exe_path = c
            break

    if exe_path:
        saved = builddir / 'held_suarez_hybrid.x'
        shutil.copy2(exe_path, saved)
        write_log(f'Found executable {exe_path} -> copied to {saved}')
        # tiny smoke test: run with --help or -h if supported, else run and timeout quickly
        rc, out = run_cmd([str(saved), '-h'], cwd=builddir, env=os.environ)
        if rc != 0:
            # try without args for a short run
            rc, out = run_cmd([str(saved)], cwd=builddir, env=os.environ)
        write_log('Smoke test completed')
    else:
        write_log('No executable found after make')

    write_log('Hybrid build helper finished')
    print('Build helper finished. See', LOG_FILE)
    return 0


if __name__ == '__main__':
    exit(main())
