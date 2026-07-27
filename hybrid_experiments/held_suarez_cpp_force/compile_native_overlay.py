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
ORIGINAL_FV_ADVECTION = "atmos_spectral/model/fv_advection.F90"
OVERLAY_FV_ADVECTION = "extra/local_overrides/fv_advection/fv_advection.F90"
OVERLAY_FV_ADVECTION_KERNELS = (
    "extra/local_overrides/fv_advection_kernels/fv_advection.F90"
)

# Relative to the normal Isca source root (<code>/src).  The repository has
# translated/ at the same level as src/.
HS_FORCE_INTERFACE = (
    "../translated/held_suarez/cpp/forcing_module/fortran/"
    "hs_forcing_c_interface.F90"
)
HS_FORCE_LIBRARY_DIR = "../translated/held_suarez/cpp/forcing_module"
HS_FORCE_LIBRARY = HS_FORCE_LIBRARY_DIR + "/libhs_forcing.a"
SEMI_Y_INTERFACE = (
    "../translated/held_suarez/cpp/fv_advection/semi_y_3d/fortran/"
    "semi_y_3d_c_interface.F90"
)
SEMI_Y_LIBRARY_DIR = "../translated/held_suarez/cpp/fv_advection/semi_y_3d"
SEMI_Y_LIBRARY = SEMI_Y_LIBRARY_DIR + "/libsemi_y_3d.a"
FV_KERNELS_INTERFACE = (
    "../translated/held_suarez/cpp/fv_advection/kernels/fortran/"
    "fv_advection_kernels_c_interface.F90"
)
FV_KERNELS_LIBRARY_DIR = "../translated/held_suarez/cpp/fv_advection/kernels"
FV_KERNELS_LIBRARY = FV_KERNELS_LIBRARY_DIR + "/libfv_advection_kernels.a"


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


class HeldSuarezFvSemiYCodeBase(DryCodeBase):
    """Held-Suarez executable with fv_advection::semi_y_3d calling C++."""

    executable_name = "held_suarez_fv_semi_y_3d.x"
    use_cuda = False

    def configure_overlay(self):
        paths = self.read_path_names(
            P(self.srcdir, "extra", "model", self.name, "path_names")
        )

        replaced = 0
        overlay_paths = []
        for path in paths:
            if path == ORIGINAL_FV_ADVECTION:
                overlay_paths.append(SEMI_Y_INTERFACE)
                overlay_paths.append(OVERLAY_FV_ADVECTION)
                replaced += 1
            else:
                overlay_paths.append(path)

        if replaced != 1:
            raise RuntimeError(
                "Expected exactly one %s entry in dry path_names, found %d"
                % (ORIGINAL_FV_ADVECTION, replaced)
            )

        self.path_names = overlay_paths
        if self.use_cuda:
            flag = "-DUSE_CUDA_SEMI_Y_3D"
        else:
            flag = "-DUSE_CPP_SEMI_Y_3D"
        if flag not in self.compile_flags:
            self.compile_flags.append(flag)

    def prepare_semi_y_library(self):
        mkdir(self.builddir)
        lib_workdir = Path(self.srcdir) / SEMI_Y_LIBRARY_DIR
        lib_src = Path(self.srcdir) / SEMI_Y_LIBRARY
        lib_dest_dir = Path(self.builddir) / "lib"
        lib_dest_dir.mkdir(parents=True, exist_ok=True)

        if not lib_workdir.is_dir():
            raise RuntimeError("semi_y_3d library source dir not found: %s" % lib_workdir)

        cxx = os.environ.get("CXX", "g++")
        ar = os.environ.get("AR", "ar")
        nvcc = os.environ.get("NVCC", "nvcc")
        print("Building semi_y_3d C++/CUDA library")
        print("  workdir:", lib_workdir)
        print("  CXX:", shutil.which(cxx) or cxx)
        print("  AR:", shutil.which(ar) or ar)
        print("  USE_CUDA_SEMI_Y_3D:", "1" if self.use_cuda else "0")
        if self.use_cuda:
            print("  NVCC:", shutil.which(nvcc) or nvcc)
            if shutil.which(nvcc) is None and not Path(nvcc).exists():
                raise RuntimeError(
                    "USE_CUDA_SEMI_Y_3D was requested, but NVCC was not found. "
                    "Set NVCC to a valid CUDA compiler path or use a CUDA container."
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
        if self.use_cuda:
            make_cmd.extend(["USE_CUDA_SEMI_Y_3D=1", "NVCC=%s" % nvcc])
        make_cmd.append("lib")
        subprocess.check_call(make_cmd, cwd=str(lib_workdir))

        if not lib_src.exists():
            raise RuntimeError("semi_y_3d library not found: %s" % lib_src)

        shutil.copy2(str(lib_src), str(lib_dest_dir / "libsemi_y_3d.a"))

    def compile(self, *args, **kwargs):
        if os.environ.get("GFDL_ENV") != "hybrid":
            raise RuntimeError(
                "FV semi_y_3d hybrid build requires GFDL_ENV=hybrid so "
                "compile.sh sources src/extra/env/hybrid and selects the "
                "FV mkmf template."
            )
        self.configure_overlay()
        self.prepare_semi_y_library()
        template = "fv_hybrid_cuda" if self.use_cuda else "fv_hybrid"
        with temporary_env("GFDL_MKMF_TEMPLATE", template):
            return super(HeldSuarezFvSemiYCodeBase, self).compile(*args, **kwargs)


class HeldSuarezFvSemiYCudaCodeBase(HeldSuarezFvSemiYCodeBase):
    """Held-Suarez executable with fv_advection::semi_y_3d calling CUDA."""

    executable_name = "held_suarez_fv_semi_y_3d_cuda.x"
    use_cuda = True


class HeldSuarezFvKernelsCodeBase(DryCodeBase):
    """Held-Suarez executable with bundled fv_advection local kernels calling C++."""

    executable_name = "held_suarez_fv_kernels.x"
    use_cuda = False

    def configure_overlay(self):
        paths = self.read_path_names(
            P(self.srcdir, "extra", "model", self.name, "path_names")
        )

        replaced = 0
        overlay_paths = []
        for path in paths:
            if path == ORIGINAL_FV_ADVECTION:
                overlay_paths.append(FV_KERNELS_INTERFACE)
                overlay_paths.append(OVERLAY_FV_ADVECTION_KERNELS)
                replaced += 1
            else:
                overlay_paths.append(path)

        if replaced != 1:
            raise RuntimeError(
                "Expected exactly one %s entry in dry path_names, found %d"
                % (ORIGINAL_FV_ADVECTION, replaced)
            )

        self.path_names = overlay_paths
        if self.use_cuda:
            flag = "-DUSE_CUDA_FV_ADVECTION_KERNELS"
        else:
            flag = "-DUSE_CPP_FV_ADVECTION_KERNELS"
        if flag not in self.compile_flags:
            self.compile_flags.append(flag)

    def prepare_fv_kernels_library(self):
        mkdir(self.builddir)
        lib_workdir = Path(self.srcdir) / FV_KERNELS_LIBRARY_DIR
        lib_src = Path(self.srcdir) / FV_KERNELS_LIBRARY
        lib_dest_dir = Path(self.builddir) / "lib"
        lib_dest_dir.mkdir(parents=True, exist_ok=True)

        if not lib_workdir.is_dir():
            raise RuntimeError(
                "fv_advection kernels library source dir not found: %s" % lib_workdir
            )

        cxx = os.environ.get("CXX", "g++")
        ar = os.environ.get("AR", "ar")
        nvcc = os.environ.get("NVCC", "nvcc")
        print("Building fv_advection kernels C++/CUDA library")
        print("  workdir:", lib_workdir)
        print("  CXX:", shutil.which(cxx) or cxx)
        print("  AR:", shutil.which(ar) or ar)
        print("  USE_CUDA_FV_ADVECTION_KERNELS:", "1" if self.use_cuda else "0")
        if self.use_cuda:
            print("  NVCC:", shutil.which(nvcc) or nvcc)
            if shutil.which(nvcc) is None and not Path(nvcc).exists():
                raise RuntimeError(
                    "USE_CUDA_FV_ADVECTION_KERNELS was requested, but NVCC was not found. "
                    "Set NVCC to a valid CUDA compiler path or use a CUDA container."
                )
        try:
            target = subprocess.check_output([cxx, "-dumpmachine"], text=True).strip()
            print("  CXX target:", target)
        except (OSError, subprocess.CalledProcessError):
            print("  CXX target: unavailable")

        subprocess.check_call(["make", "clean"], cwd=str(lib_workdir))
        make_cmd = ["make", "CXX=%s" % cxx, "AR=%s" % ar]
        if self.use_cuda:
            make_cmd.extend(["USE_CUDA_FV_ADVECTION_KERNELS=1", "NVCC=%s" % nvcc])
            # Level 1: compile the CUDA halo exchange against NCCL for the model
            # build (the standalone validate targets leave this off).
            make_cmd.append("USE_FV_ADVECTION_NCCL=1")
        make_cmd.append("lib")
        subprocess.check_call(make_cmd, cwd=str(lib_workdir))

        if not lib_src.exists():
            raise RuntimeError("fv_advection kernels library not found: %s" % lib_src)

        shutil.copy2(str(lib_src), str(lib_dest_dir / "libfv_advection_kernels.a"))

        executable = Path(self.builddir) / self.executable_name
        if executable.exists():
            executable.unlink()

    def compile(self, *args, **kwargs):
        if os.environ.get("GFDL_ENV") != "hybrid":
            raise RuntimeError(
                "FV kernels hybrid build requires GFDL_ENV=hybrid so "
                "compile.sh sources src/extra/env/hybrid and selects the "
                "FV kernels mkmf template."
            )
        self.configure_overlay()
        self.prepare_fv_kernels_library()
        template = "fv_kernels_hybrid_cuda" if self.use_cuda else "fv_kernels_hybrid"
        with temporary_env("GFDL_MKMF_TEMPLATE", template):
            return super(HeldSuarezFvKernelsCodeBase, self).compile(*args, **kwargs)


class HeldSuarezFvKernelsCudaCodeBase(HeldSuarezFvKernelsCodeBase):
    """Held-Suarez executable with bundled fv_advection local kernels calling CUDA."""

    executable_name = "held_suarez_fv_kernels_cuda.x"
    use_cuda = True


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


def build_fv_semi_y():
    cb = HeldSuarezFvSemiYCodeBase.from_directory(GFDL_BASE)
    use_gfdl_base_templates(cb)
    cb.compile()
    return cb.executable_fullpath


def build_fv_semi_y_cuda():
    cb = HeldSuarezFvSemiYCudaCodeBase.from_directory(GFDL_BASE)
    use_gfdl_base_templates(cb)
    cb.compile()
    return cb.executable_fullpath


def build_fv_kernels():
    cb = HeldSuarezFvKernelsCodeBase.from_directory(GFDL_BASE)
    use_gfdl_base_templates(cb)
    cb.compile()
    return cb.executable_fullpath


def build_fv_kernels_cuda():
    cb = HeldSuarezFvKernelsCudaCodeBase.from_directory(GFDL_BASE)
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
            "fv_semi_y",
            "fv_semi_y_cuda",
            "fv_kernels",
            "fv_kernels_cuda",
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

    if args.target == "fv_semi_y":
        print("Building Held-Suarez fv semi_y_3d C++ overlay via CodeBase.compile()")
        print("Generated:", build_fv_semi_y())

    if args.target == "fv_semi_y_cuda":
        print("Building Held-Suarez fv semi_y_3d CUDA overlay via CodeBase.compile()")
        print("Generated:", build_fv_semi_y_cuda())

    if args.target == "fv_kernels":
        print("Building Held-Suarez fv_advection kernel bundle C++ overlay via CodeBase.compile()")
        print("Generated:", build_fv_kernels())

    if args.target == "fv_kernels_cuda":
        print("Building Held-Suarez fv_advection kernel bundle CUDA overlay via CodeBase.compile()")
        print("Generated:", build_fv_kernels_cuda())


if __name__ == "__main__":
    main()
