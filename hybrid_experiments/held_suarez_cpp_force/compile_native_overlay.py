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
ORIGINAL_SPECTRAL_DYNAMICS = "atmos_spectral/model/spectral_dynamics.F90"
OVERLAY_SPECTRAL_DYNAMICS = (
    "extra/local_overrides/spectral_dynamics/spectral_dynamics.F90"
)
ORIGINAL_VERT_ADVECTION = "atmos_shared/vert_advection/vert_advection.F90"
OVERLAY_VERT_ADVECTION = "extra/local_overrides/vert_advection/vert_advection.F90"

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
        use_cuda = os.environ.get("USE_CUDA_HS_FORCE") == "1"

        if not lib_workdir.is_dir():
            raise RuntimeError("Hybrid forcing library source dir not found: %s" % lib_workdir)

        cxx = os.environ.get("CXX", "g++")
        ar = os.environ.get("AR", "ar")
        nvcc = os.environ.get("NVCC", "nvcc")
        print("Building hybrid forcing C++ library")
        print("  workdir:", lib_workdir)
        print("  CXX:", shutil.which(cxx) or cxx)
        print("  AR:", shutil.which(ar) or ar)
        print("  USE_CUDA_HS_FORCE:", "1" if use_cuda else "0")
        if use_cuda:
            print("  NVCC:", shutil.which(nvcc) or nvcc)
            if shutil.which(nvcc) is None and not Path(nvcc).exists():
                raise RuntimeError(
                    "USE_CUDA_HS_FORCE=1 was requested, but NVCC was not found. "
                    "Set NVCC to a valid CUDA compiler path or use a container "
                    "with nvcc available. Example: "
                    "USE_CUDA_HS_FORCE=1 NVCC=/path/to/nvcc ./run_compile_hybrid.sh"
                )
        try:
            target = subprocess.check_output(
                [cxx, "-dumpmachine"], text=True
            ).strip()
            print("  CXX target:", target)
        except (OSError, subprocess.CalledProcessError):
            print("  CXX target: unavailable")

        subprocess.check_call(["make", "clean"], cwd=str(lib_workdir))
        make_cmd = ["make", "CXX=%s" % cxx, "AR=%s" % ar]
        if use_cuda:
            make_cmd.extend(["USE_CUDA_HS_FORCE=1", "NVCC=%s" % nvcc])
        make_cmd.append("lib")
        subprocess.check_call(make_cmd, cwd=str(lib_workdir))

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
        template = "hybrid_cuda" if os.environ.get("USE_CUDA_HS_FORCE") == "1" else "hybrid"
        with temporary_env("GFDL_MKMF_TEMPLATE", template):
            return super(HeldSuarezHybridCodeBase, self).compile(*args, **kwargs)


class HeldSuarezFourInOneProfileCodeBase(DryCodeBase):
    """Held-Suarez executable with timing around spectral_dynamics::four_in_one."""

    executable_name = "held_suarez_profile_four_in_one.x"

    def configure_overlay(self):
        paths = self.read_path_names(
            P(self.srcdir, "extra", "model", self.name, "path_names")
        )

        replaced = 0
        overlay_paths = []
        for path in paths:
            if path == ORIGINAL_SPECTRAL_DYNAMICS:
                overlay_paths.append(OVERLAY_SPECTRAL_DYNAMICS)
                replaced += 1
            else:
                overlay_paths.append(path)

        if replaced != 1:
            raise RuntimeError(
                "Expected exactly one %s entry in dry path_names, found %d"
                % (ORIGINAL_SPECTRAL_DYNAMICS, replaced)
            )

        self.path_names = overlay_paths
        if "-DPROFILE_FOUR_IN_ONE" not in self.compile_flags:
            self.compile_flags.append("-DPROFILE_FOUR_IN_ONE")

    def compile(self, *args, **kwargs):
        self.configure_overlay()
        return super(HeldSuarezFourInOneProfileCodeBase, self).compile(*args, **kwargs)


class HeldSuarezVertAdvectionProfileCodeBase(DryCodeBase):
    """Held-Suarez executable with timing around vert_advection call sites."""

    executable_name = "held_suarez_profile_vert_advection.x"

    def configure_overlay(self):
        paths = self.read_path_names(
            P(self.srcdir, "extra", "model", self.name, "path_names")
        )

        replaced = 0
        overlay_paths = []
        for path in paths:
            if path == ORIGINAL_SPECTRAL_DYNAMICS:
                overlay_paths.append(OVERLAY_SPECTRAL_DYNAMICS)
                replaced += 1
            else:
                overlay_paths.append(path)

        if replaced != 1:
            raise RuntimeError(
                "Expected exactly one %s entry in dry path_names, found %d"
                % (ORIGINAL_SPECTRAL_DYNAMICS, replaced)
            )

        self.path_names = overlay_paths
        if "-DPROFILE_VERT_ADVECTION" not in self.compile_flags:
            self.compile_flags.append("-DPROFILE_VERT_ADVECTION")

    def compile(self, *args, **kwargs):
        self.configure_overlay()
        return super(HeldSuarezVertAdvectionProfileCodeBase, self).compile(*args, **kwargs)


class HeldSuarezDynamicsRegionsProfileCodeBase(DryCodeBase):
    """Held-Suarez executable with coarse spectral dynamics region timers."""

    executable_name = "held_suarez_profile_dynamics_regions.x"

    def configure_overlay(self):
        paths = self.read_path_names(
            P(self.srcdir, "extra", "model", self.name, "path_names")
        )

        replaced = 0
        overlay_paths = []
        for path in paths:
            if path == ORIGINAL_SPECTRAL_DYNAMICS:
                overlay_paths.append(OVERLAY_SPECTRAL_DYNAMICS)
                replaced += 1
            else:
                overlay_paths.append(path)

        if replaced != 1:
            raise RuntimeError(
                "Expected exactly one %s entry in dry path_names, found %d"
                % (ORIGINAL_SPECTRAL_DYNAMICS, replaced)
            )

        self.path_names = overlay_paths
        if "-DPROFILE_DYNAMICS_REGIONS" not in self.compile_flags:
            self.compile_flags.append("-DPROFILE_DYNAMICS_REGIONS")

    def compile(self, *args, **kwargs):
        self.configure_overlay()
        return super(HeldSuarezDynamicsRegionsProfileCodeBase, self).compile(*args, **kwargs)


class HeldSuarezDynamicsDeepProfileCodeBase(DryCodeBase):
    """Held-Suarez executable with second-level spectral dynamics timers."""

    executable_name = "held_suarez_profile_dynamics_deep.x"

    def configure_overlay(self):
        paths = self.read_path_names(
            P(self.srcdir, "extra", "model", self.name, "path_names")
        )

        replaced = 0
        overlay_paths = []
        for path in paths:
            if path == ORIGINAL_SPECTRAL_DYNAMICS:
                overlay_paths.append(OVERLAY_SPECTRAL_DYNAMICS)
                replaced += 1
            else:
                overlay_paths.append(path)

        if replaced != 1:
            raise RuntimeError(
                "Expected exactly one %s entry in dry path_names, found %d"
                % (ORIGINAL_SPECTRAL_DYNAMICS, replaced)
            )

        self.path_names = overlay_paths
        if "-DPROFILE_DYNAMICS_DEEP" not in self.compile_flags:
            self.compile_flags.append("-DPROFILE_DYNAMICS_DEEP")

    def compile(self, *args, **kwargs):
        self.configure_overlay()
        return super(HeldSuarezDynamicsDeepProfileCodeBase, self).compile(*args, **kwargs)


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


def build_profile_four_in_one():
    cb = HeldSuarezFourInOneProfileCodeBase.from_directory(GFDL_BASE)
    use_gfdl_base_templates(cb)
    cb.compile()
    return cb.executable_fullpath


def build_profile_vert_advection():
    cb = HeldSuarezVertAdvectionProfileCodeBase.from_directory(GFDL_BASE)
    use_gfdl_base_templates(cb)
    cb.compile()
    return cb.executable_fullpath


def build_profile_dynamics_regions():
    cb = HeldSuarezDynamicsRegionsProfileCodeBase.from_directory(GFDL_BASE)
    use_gfdl_base_templates(cb)
    cb.compile()
    return cb.executable_fullpath


def build_profile_dynamics_deep():
    cb = HeldSuarezDynamicsDeepProfileCodeBase.from_directory(GFDL_BASE)
    use_gfdl_base_templates(cb)
    cb.compile()
    return cb.executable_fullpath


def main():
    parser = argparse.ArgumentParser(
        description="Build Held-Suarez native Isca overlay variants."
    )
    parser.add_argument(
        "target",
        choices=(
            "fortran",
            "hybrid",
            "profile_four_in_one",
            "profile_vert_advection",
            "profile_dynamics_regions",
            "profile_dynamics_deep",
            "both",
        ),
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

    if args.target == "profile_four_in_one":
        print("Building Held-Suarez four_in_one profile via CodeBase.compile()")
        print("Generated:", build_profile_four_in_one())

    if args.target == "profile_vert_advection":
        print("Building Held-Suarez vert_advection profile via CodeBase.compile()")
        print("Generated:", build_profile_vert_advection())

    if args.target == "profile_dynamics_regions":
        print("Building Held-Suarez dynamics-region profile via CodeBase.compile()")
        print("Generated:", build_profile_dynamics_regions())

    if args.target == "profile_dynamics_deep":
        print("Building Held-Suarez deep dynamics profile via CodeBase.compile()")
        print("Generated:", build_profile_dynamics_deep())


if __name__ == "__main__":
    main()
