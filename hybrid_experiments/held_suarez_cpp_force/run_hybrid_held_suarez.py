#!/usr/bin/env python3
"""Run the Held-Suarez experiment with the native hybrid executable.

This reuses the original Held-Suarez test-case namelist, diagnostic fields, and
resolution setup, but points the Experiment at held_suarez_hybrid.x and writes
to a separate experiment directory.
"""

import argparse
import os
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
HELD_SUAREZ_CASE_DIR = REPO_ROOT / "exp" / "test_cases" / "held_suarez"
DEFAULT_EXP_NAME = "held_suarez_hybrid"


def load_original_case():
    sys.path.insert(0, str(HELD_SUAREZ_CASE_DIR))
    import held_suarez_test_case as original

    return original


def make_experiment(args):
    from isca import DryCodeBase, Experiment, GFDL_BASE

    class HeldSuarezHybridRuntimeCodeBase(DryCodeBase):
        """Dry codebase wrapper that selects the hybrid executable."""

        executable_name = "held_suarez_hybrid.x"

    original = load_original_case()

    cb = HeldSuarezHybridRuntimeCodeBase.from_directory(GFDL_BASE)
    if not Path(cb.executable_fullpath).exists():
        raise FileNotFoundError(
            "Hybrid executable not found: %s\n"
            "Build it first with ./run_compile_hybrid.sh." % cb.executable_fullpath
        )

    exp = Experiment(args.exp_name, codebase=cb)
    exp.namelist = original.namelist.copy()
    exp.diag_table = original.diag.copy()
    exp.set_resolution(*original.RESOLUTION)

    exp.update_namelist(
        {
            "main_nml": {
                "days": args.days,
            }
        }
    )

    if not args.production_diag:
        for output_file in exp.diag_table.files.values():
            output_file["freq"] = args.diag_frequency_days
            output_file["units"] = "days"
            output_file["time_units"] = "days"

    return exp, cb


def main():
    parser = argparse.ArgumentParser(
        description="Run a non-invasive Held-Suarez hybrid executable smoke test."
    )
    parser.add_argument(
        "--exp-name",
        default=DEFAULT_EXP_NAME,
        help="Experiment/output directory name under $GFDL_DATA.",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=1,
        help="Simulation length in days. Default is a short smoke run.",
    )
    parser.add_argument(
        "--num-cores",
        type=int,
        default=16,
        help="MPI rank count. Defaults to the original Held-Suarez test case.",
    )
    parser.add_argument(
        "--diag-frequency-days",
        type=int,
        default=1,
        help="Smoke-test diagnostic file cadence when not using --production-diag.",
    )
    parser.add_argument(
        "--production-diag",
        action="store_true",
        help="Use the original 30-day diagnostic cadence exactly.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite an existing run0001 in the hybrid output directory.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print selected paths and settings without launching the model.",
    )
    args = parser.parse_args()

    exp, cb = make_experiment(args)

    print("GFDL_BASE =", os.environ.get("GFDL_BASE"))
    print("GFDL_WORK =", os.environ.get("GFDL_WORK"))
    print("GFDL_DATA =", os.environ.get("GFDL_DATA"))
    print("Experiment =", exp.name)
    print("Data dir =", exp.datadir)
    print("Run dir =", exp.rundir)
    print("Executable =", cb.executable_fullpath)
    print("Days =", exp.namelist["main_nml"]["days"])
    print("dt_atmos =", exp.namelist["main_nml"]["dt_atmos"])
    print("num_cores =", args.num_cores)
    print("production_diag =", args.production_diag)

    if args.dry_run:
        return

    exp.run(
        1,
        num_cores=args.num_cores,
        use_restart=False,
        overwrite_data=args.overwrite,
    )


if __name__ == "__main__":
    main()
