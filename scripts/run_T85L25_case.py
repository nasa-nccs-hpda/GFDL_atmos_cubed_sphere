#!/usr/bin/env python3
"""Run one T85L25 Held-Suarez forcing performance case.

This helper is intentionally non-invasive: it reuses the original
Held-Suarez namelist and diagnostic table, overrides only resolution,
vertical levels, timestep, and run length, then selects a prebuilt
executable by name.
"""

import argparse
import os
import shutil
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
HELD_SUAREZ_CASE_DIR = REPO_ROOT / "exp" / "test_cases" / "held_suarez"


def prepare_run_directory(exp, cb, num_cores):
    """Write an Isca run directory without launching the generated mpirun."""
    exp.clear_rundir()

    rundir = Path(exp.rundir)
    input_dir = rundir / "INPUT"
    restart_dir = rundir / "RESTART"
    input_dir.mkdir(parents=True, exist_ok=True)
    restart_dir.mkdir(parents=True, exist_ok=True)
    Path(exp.restartdir).mkdir(parents=True, exist_ok=True)

    cb.write_source_control_status(str(rundir / "git_hash_used.txt"))
    exp.write_namelist(str(rundir))
    exp.write_field_table(str(rundir))
    exp.write_diag_table(str(rundir))

    for filename in exp.inputfiles:
        shutil.copy2(filename, input_dir / Path(filename).name)

    runscript = exp.templates.get_template("run.sh")
    runscript.stream(
        rundir=exp.rundir,
        execdir=cb.builddir,
        executable=cb.executable_name,
        env_source=exp.env_source,
        mpirun_opts="",
        num_cores=num_cores,
        run_idb=False,
        nice_score=0,
    ).dump(str(rundir / "run.sh"))

    shutil.copy2(cb.executable_fullpath, rundir / cb.executable_name)


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
        "--prepare-only",
        action="store_true",
        help=(
            "Write input.nml, tables, executable, and run.sh, then stop before "
            "launching the model. Useful for external srun/apptainer launches."
        ),
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
    exp.set_resolution(args.resolution, args.levels)
    exp.update_namelist(
        {
            "main_nml": {
                "days": args.days,
                "dt_atmos": args.dt_atmos,
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
    print("production_diag = True")
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

    if args.prepare_only:
        prepare_run_directory(exp, cb, args.num_cores)
        print("Prepared run directory =", exp.rundir)
        return

    exp.run(
        1,
        num_cores=args.num_cores,
        use_restart=False,
        overwrite_data=args.overwrite,
    )


if __name__ == "__main__":
    main()
