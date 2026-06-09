#!/usr/bin/env python3
"""Compare all-Fortran and hybrid Held-Suarez NetCDF outputs."""

import argparse
import json
import os
from pathlib import Path


DEFAULT_FIELDS = ("ps", "bk", "pk", "ucomp", "vcomp", "temp", "vor", "div")
np = None
xr = None


def default_file(exp_name, run, filename):
    data_root = Path(os.environ.get("GFDL_DATA", "."))
    return data_root / exp_name / ("run%04d" % run) / filename


def numeric_data_vars(dataset):
    names = []
    for name, data_array in dataset.data_vars.items():
        if np.issubdtype(data_array.dtype, np.number):
            names.append(name)
    return names


def compare_variable(baseline, candidate):
    if baseline.dims != candidate.dims:
        return {
            "pass": False,
            "reason": "dimension-name mismatch",
            "baseline_dims": list(baseline.dims),
            "candidate_dims": list(candidate.dims),
        }

    if baseline.shape != candidate.shape:
        return {
            "pass": False,
            "reason": "shape mismatch",
            "baseline_shape": list(baseline.shape),
            "candidate_shape": list(candidate.shape),
        }

    base = baseline.values
    cand = candidate.values
    valid = np.isfinite(base) & np.isfinite(cand)

    if not np.any(valid):
        return {
            "pass": bool(np.array_equal(base, cand)),
            "shape": list(base.shape),
            "finite_values": 0,
        }

    diff = cand[valid] - base[valid]
    abs_diff = np.abs(diff)

    return {
        "pass": bool(np.allclose(cand, base, equal_nan=True)),
        "dims": list(baseline.dims),
        "shape": list(base.shape),
        "baseline_global_mean": float(np.nanmean(base)),
        "candidate_global_mean": float(np.nanmean(cand)),
        "mean_difference": float(np.nanmean(cand) - np.nanmean(base)),
        "max_abs_error": float(np.max(abs_diff)),
        "rmse": float(np.sqrt(np.mean(diff**2))),
    }


def main():
    global np, xr

    parser = argparse.ArgumentParser(
        description="Compare Held-Suarez all-Fortran and hybrid NetCDF outputs."
    )
    parser.add_argument("--baseline-exp", default="held_suarez_default")
    parser.add_argument("--candidate-exp", default="held_suarez_hybrid")
    parser.add_argument("--run", type=int, default=1)
    parser.add_argument("--filename", default="atmos_monthly.nc")
    parser.add_argument("--baseline-file")
    parser.add_argument("--candidate-file")
    parser.add_argument(
        "--fields",
        nargs="*",
        default=list(DEFAULT_FIELDS),
        help="Variables to compare. Use --all-fields to compare every numeric variable.",
    )
    parser.add_argument("--all-fields", action="store_true")
    parser.add_argument(
        "--out",
        default="tests/reports/hybrid_output_compare_report.json",
        help="JSON report path.",
    )
    args = parser.parse_args()

    import numpy as np_module
    import xarray as xr_module

    np = np_module
    xr = xr_module

    baseline_file = (
        Path(args.baseline_file)
        if args.baseline_file
        else default_file(args.baseline_exp, args.run, args.filename)
    )
    candidate_file = (
        Path(args.candidate_file)
        if args.candidate_file
        else default_file(args.candidate_exp, args.run, args.filename)
    )

    report = {
        "baseline_file": str(baseline_file),
        "candidate_file": str(candidate_file),
        "variables": {},
        "missing_in_baseline": [],
        "missing_in_candidate": [],
        "dimension_match": None,
        "overall_pass": True,
    }

    with xr.open_dataset(baseline_file, decode_times=False) as base_ds:
        with xr.open_dataset(candidate_file, decode_times=False) as cand_ds:
            report["baseline_dims"] = dict(base_ds.sizes)
            report["candidate_dims"] = dict(cand_ds.sizes)
            report["dimension_match"] = report["baseline_dims"] == report["candidate_dims"]
            report["overall_pass"] = bool(report["dimension_match"])

            if args.all_fields:
                fields = sorted(set(numeric_data_vars(base_ds)) | set(numeric_data_vars(cand_ds)))
            else:
                fields = args.fields

            for field in fields:
                if field not in base_ds:
                    report["missing_in_baseline"].append(field)
                    report["overall_pass"] = False
                    continue
                if field not in cand_ds:
                    report["missing_in_candidate"].append(field)
                    report["overall_pass"] = False
                    continue

                result = compare_variable(base_ds[field], cand_ds[field])
                report["variables"][field] = result
                if not result["pass"]:
                    report["overall_pass"] = False

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))

    if not report["overall_pass"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
