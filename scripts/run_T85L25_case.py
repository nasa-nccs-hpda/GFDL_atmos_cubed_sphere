#!/usr/bin/env python3
"""Run one T85L25 Held-Suarez forcing performance case.

This helper is intentionally non-invasive: it reuses the original
Held-Suarez namelist and diagnostic table, overrides only resolution,
vertical levels, timestep, and run length, then selects a prebuilt
executable by name.
"""

import argparse
import os
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
HELD_SUAREZ_CASE_DIR = REPO_ROOT / "exp" / "test_cases" / "held_suarez"


EXTRA_RESOLUTIONS = {
    "T340": {
        "lon_max": 1024,
        "lat_max": 512,
        "num_fourier": 340,
        "num_spherical": 341,
    },
    "T341": {
        "lon_max": 1024,
        "lat_max": 512,
        "num_fourier": 341,
        "num_spherical": 342,
    },
    "T682": {
        "lon_max": 2048,
        "lat_max": 1024,
        "num_fourier": 682,
        "num_spherical": 683,
    },
}


def set_case_resolution(exp, res, num_levels):
    if res in EXTRA_RESOLUTIONS:
        delta = EXTRA_RESOLUTIONS[res].copy()
        delta["num_levels"] = num_levels
        exp.update_namelist({"spectral_dynamics_nml": delta})
        return
    exp.set_resolution(res, num_levels)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exp-name", required=True)
    parser.add_argument("--executable-name", required=True)
    parser.add_argument("--backend-label", required=True)
    parser.add_argument(
        "--codebase-dir",
        default=None,
        help=(
            "Directory to use for DryCodeBase.from_directory(). Defaults to "
            "$GFDL_BASE. Use /isca for the stock all-Fortran container build."
        ),
    )
    parser.add_argument("--resolution", default="T85")
    parser.add_argument("--levels", type=int, default=25)
    parser.add_argument("--dt-atmos", type=int, default=300)
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--num-cores", type=int, default=16)
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing run0001 output. Default preserves existing output.",
    )
    parser.add_argument(
        "--diag-frequency-days",
        type=int,
        default=30,
        help="Diagnostic output cadence in days when not using --production-diag.",
    )
    parser.add_argument(
        "--production-diag",
        action="store_true",
        help="Use the original Held-Suarez diagnostic cadence exactly.",
    )
    parser.add_argument(
        "--no-tracer-field-table",
        action="store_true",
        help="Use an empty field_table for dry-core performance benchmarking.",
    )
    args = parser.parse_args()

    sys.path.insert(0, str(HELD_SUAREZ_CASE_DIR))

    import held_suarez_test_case as original
    from isca import DryCodeBase, Experiment, GFDL_BASE

    class RuntimeCodeBase(DryCodeBase):
        pass

    RuntimeCodeBase.executable_name = args.executable_name
    codebase_dir = args.codebase_dir or GFDL_BASE
    cb = RuntimeCodeBase.from_directory(codebase_dir)
    executable_path = Path(cb.executable_fullpath)
    if not executable_path.exists():
        raise FileNotFoundError(
            "Executable not found: %s\nBuild the requested executable first."
            % executable_path
        )

    exp = Experiment(args.exp_name, codebase=cb)
    exp.namelist = original.namelist.copy()
    exp.diag_table = original.diag.copy()
    set_case_resolution(exp, args.resolution, args.levels)
    exp.update_namelist(
        {
            "main_nml": {
                "days": args.days,
                "dt_atmos": args.dt_atmos,
            }
        }
    )
    if not args.production_diag:
        for output_file in exp.diag_table.files.values():
            output_file["freq"] = args.diag_frequency_days
            output_file["units"] = "days"
            output_file["time_units"] = "days"

    if args.no_tracer_field_table:
        empty_field_table = Path(os.environ["GFDL_WORK"]) / "empty_dry_field_table"
        empty_field_table.parent.mkdir(parents=True, exist_ok=True)
        empty_field_table.write_text("\n")
        exp.field_table_file = str(empty_field_table)
        exp.update_namelist(
            {
                "spectral_dynamics_nml": {
                    "do_water_correction": False,
                    "use_virtual_temperature": False,
                }
            }
        )

    print("Experiment =", exp.name)
    print("Backend =", args.backend_label)
    print("Executable =", executable_path)
    print("Resolution =", args.resolution)
    print("Levels =", args.levels)
    print("Days =", args.days)
    print("dt_atmos =", args.dt_atmos)
    print("num_cores =", args.num_cores)
    print("production_diag =", args.production_diag)
    print("diag_frequency_days =", args.diag_frequency_days)
    print("no_tracer_field_table =", args.no_tracer_field_table)
    print("overwrite =", args.overwrite)
    print("GFDL_BASE =", os.environ.get("GFDL_BASE"))
    print("Codebase dir =", codebase_dir)
    print("GFDL_WORK =", os.environ.get("GFDL_WORK"))
    print("GFDL_DATA =", os.environ.get("GFDL_DATA"))
    print("GFDL_ENV =", os.environ.get("GFDL_ENV"))
    print("HS_FORCE_BACKEND =", os.environ.get("HS_FORCE_BACKEND", ""))
    print("HS_PROFILE =", os.environ.get("HS_PROFILE", ""))
    print("Data dir =", exp.datadir)
    print("Run dir =", exp.rundir)

    exp.run(
        1,
        num_cores=args.num_cores,
        use_restart=False,
        overwrite_data=args.overwrite,
    )


if __name__ == "__main__":
    main()
