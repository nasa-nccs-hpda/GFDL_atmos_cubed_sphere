#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


def load_array(path: Path) -> np.ndarray:
    if path.suffix == ".npy":
        return np.load(path)
    if path.suffix in [".txt", ".dat", ".csv"]:
        return np.loadtxt(path, delimiter="," if path.suffix == ".csv" else None)
    raise ValueError(f"Unsupported file type: {path}")


def compare_array(a: np.ndarray, b: np.ndarray, atol: float, rtol: float) -> dict:
    if a.shape != b.shape:
        return {
            "pass": False,
            "reason": f"shape mismatch: baseline {a.shape}, candidate {b.shape}",
        }

    diff = b - a
    abs_diff = np.abs(diff)

    denom = np.maximum(np.abs(a), 1.0e-30)
    rel_diff = abs_diff / denom

    max_abs = float(np.max(abs_diff))
    max_rel = float(np.max(rel_diff))
    rmse = float(np.sqrt(np.mean(diff**2)))
    mean_abs = float(np.mean(abs_diff))

    passed = bool(np.allclose(a, b, atol=atol, rtol=rtol))

    return {
        "pass": passed,
        "shape": list(a.shape),
        "max_abs_error": max_abs,
        "max_rel_error": max_rel,
        "rmse": rmse,
        "mean_abs_error": mean_abs,
        "atol": atol,
        "rtol": rtol,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-dir", required=True)
    parser.add_argument("--candidate-dir", required=True)
    parser.add_argument("--out", default="tests/reports/compare_report.json")
    parser.add_argument("--atol", type=float, default=1.0e-12)
    parser.add_argument("--rtol", type=float, default=1.0e-12)
    args = parser.parse_args()

    baseline_dir = Path(args.baseline_dir)
    candidate_dir = Path(args.candidate_dir)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    baseline_files = sorted(
        list(baseline_dir.glob("*.npy"))
        + list(baseline_dir.glob("*.txt"))
        + list(baseline_dir.glob("*.dat"))
        + list(baseline_dir.glob("*.csv"))
    )

    report = {
        "baseline_dir": str(baseline_dir),
        "candidate_dir": str(candidate_dir),
        "variables": {},
        "overall_pass": True,
    }

    for bfile in baseline_files:
        cfile = candidate_dir / bfile.name

        if not cfile.exists():
            report["variables"][bfile.name] = {
                "pass": False,
                "reason": "missing candidate file",
            }
            report["overall_pass"] = False
            continue

        baseline = load_array(bfile)
        candidate = load_array(cfile)

        result = compare_array(baseline, candidate, args.atol, args.rtol)
        report["variables"][bfile.name] = result

        if not result["pass"]:
            report["overall_pass"] = False

    out_path.write_text(json.dumps(report, indent=2))

    print(json.dumps(report, indent=2))

    if not report["overall_pass"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()