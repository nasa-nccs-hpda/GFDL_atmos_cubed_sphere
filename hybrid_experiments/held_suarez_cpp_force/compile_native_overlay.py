#!/usr/bin/env python3
"""Build Held-Suarez variants through the native Isca CodeBase.compile path.

This intentionally does not invoke mkmf directly.  It prepares CodeBase state
and then delegates to CodeBase.compile(), preserving the normal Isca compile
workflow that generated the working production executable.
"""

import argparse
import os
import shutil
import subprocess
import sys
from contextlib import contextmanager
from pathlib import Path

from jinja2 import Environment, FileSystemLoader

from isca import DryCodeBase, GFDL_BASE
from isca.helpers import P, mkdir


ORIGINAL_HS_FORCE = "atmos_param/hs_forcing/hs_forcing.F90"
OVERLAY_HS_FORCE = "extra/local_overrides/hs_forcing/hs_forcing.F90"

# Relative to the normal Isca source root (<code>/src).  The repository has
# translated/ at the same level as src/.
HS_FORCE_INTERFACE = (
    "../translated/held_suarez/cpp/forcing_module/fortran/"
    "hs_forcing_c_interface.F90"
)
HS_FORCE_LIBRARY_DIR = "../translated/held_suarez/cpp/forcing_module"
HS_FORCE_LIBRARY = HS_FORCE_LIBRARY_DIR + "/libhs_forcing.a"


def use_gfdl_base_templates(codebase):
    template_dir = Path(GFDL_BASE) / "src" / "extra" / "python" / "isca" / "templates"
    if template_dir.is_dir():
        codebase.templatedir = str(template_dir)
        codebase.templates = Environment(loader=FileSystemLoader(str(template_dir)))


class HeldSuarezFortranCodeBase(DryCodeBase):
    """Baseline Held-Suarez executable using the default dry path_names."""

    executable_name = "held_suarez_fortran.x"


class HeldSuarezHybridCodeBase(DryCodeBase):
    """Hybrid Held-Suarez executable with the forcing overlay."""

    executable_name = "held_suarez_hybrid.x"

    def configure_overlay(self):
        paths = self.read_path_names(
            P(self.srcdir, "extra", "model", self.name, "path_names")
        )

        replaced = 0
        overlay_paths = []
        for path in paths:
            if path == ORIGINAL_HS_FORCE:
                overlay_paths.append(HS_FORCE_INTERFACE)
                overlay_paths.append(OVERLAY_HS_FORCE)
                replaced += 1
            else:
                overlay_paths.append(path)

        if replaced != 1:
            raise RuntimeError(
                "Expected exactly one %s entry in dry path_names, found %d"
                % (ORIGINAL_HS_FORCE, replaced)
            )

        self.path_names = overlay_paths
        if "-DUSE_CPP_HS_FORCE" not in self.compile_flags:
            self.compile_flags.append("-DUSE_CPP_HS_FORCE")

    def prepare_hybrid_library(self):
        mkdir(self.builddir)
        lib_workdir = Path(self.srcdir) / HS_FORCE_LIBRARY_DIR
        lib_src = Path(self.srcdir) / HS_FORCE_LIBRARY
        lib_dest_dir = Path(self.builddir) / "lib"
        lib_dest_dir.mkdir(parents=True, exist_ok=True)

        if not lib_workdir.is_dir():
            raise RuntimeError("Hybrid forcing library source dir not found: %s" % lib_workdir)

        cxx = os.environ.get("CXX", "g++")
        ar = os.environ.get("AR", "ar")
        print("Building hybrid forcing C++ library")
        print("  workdir:", lib_workdir)
        print("  CXX:", shutil.which(cxx) or cxx)
        print("  AR:", shutil.which(ar) or ar)
        try:
            target = subprocess.check_output(
                [cxx, "-dumpmachine"], text=True
            ).strip()
            print("  CXX target:", target)
        except (OSError, subprocess.CalledProcessError):
            print("  CXX target: unavailable")

        subprocess.check_call(["make", "clean"], cwd=str(lib_workdir))
        subprocess.check_call(
            ["make", "CXX=%s" % cxx, "AR=%s" % ar, "lib"],
            cwd=str(lib_workdir),
        )

        if not lib_src.exists():
            raise RuntimeError("Hybrid forcing library not found: %s" % lib_src)

        shutil.copy2(str(lib_src), str(lib_dest_dir / "libhs_forcing.a"))

    def compile(self, *args, **kwargs):
        if os.environ.get("GFDL_ENV") != "hybrid":
            raise RuntimeError(
                "Hybrid build requires GFDL_ENV=hybrid so compile.sh sources "
                "src/extra/env/hybrid and selects mkmf.template.hybrid."
            )
        self.configure_overlay()
        self.prepare_hybrid_library()
        with temporary_env("GFDL_MKMF_TEMPLATE", "hybrid"):
            return super(HeldSuarezHybridCodeBase, self).compile(*args, **kwargs)


@contextmanager
def temporary_env(name, value):
    old_value = os.environ.get(name)
    os.environ[name] = value
    try:
        yield
    finally:
        if old_value is None:
            os.environ.pop(name, None)
        else:
            os.environ[name] = old_value


def build_fortran():
    if os.environ.get("GFDL_ENV") == "hybrid":
        raise RuntimeError(
            "Baseline build should use the standard Isca env, e.g. "
            "GFDL_ENV=ubuntu_conda."
        )
    cb = HeldSuarezFortranCodeBase.from_directory(GFDL_BASE)
    use_gfdl_base_templates(cb)
    cb.compile()
    return cb.executable_fullpath


def build_hybrid():
    cb = HeldSuarezHybridCodeBase.from_directory(GFDL_BASE)
    use_gfdl_base_templates(cb)
    cb.compile()
    return cb.executable_fullpath


def main():
    parser = argparse.ArgumentParser(
        description="Build Held-Suarez native Isca overlay variants."
    )
    parser.add_argument(
        "target",
        choices=("fortran", "hybrid", "both"),
        nargs="?",
        default="hybrid",
        help="Executable variant to build.",
    )
    args = parser.parse_args()

    if args.target == "both":
        script = Path(__file__).resolve()
        env_fortran = os.environ.copy()
        env_fortran["GFDL_ENV"] = "ubuntu_conda"
        subprocess.check_call([sys.executable, str(script), "fortran"], env=env_fortran)

        env_hybrid = os.environ.copy()
        env_hybrid["GFDL_ENV"] = "hybrid"
        subprocess.check_call([sys.executable, str(script), "hybrid"], env=env_hybrid)
        return

    if args.target in ("fortran", "both"):
        print("Building baseline Held-Suarez via CodeBase.compile()")
        print("Generated:", build_fortran())

    if args.target in ("hybrid", "both"):
        print("Building hybrid Held-Suarez via CodeBase.compile()")
        print("Generated:", build_hybrid())


if __name__ == "__main__":
    main()
