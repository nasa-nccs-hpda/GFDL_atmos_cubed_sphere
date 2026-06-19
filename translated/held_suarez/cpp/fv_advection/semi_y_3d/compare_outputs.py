#!/usr/bin/env python3
import json
import math
import os
import struct
import sys


def read_doubles(path):
    values = []
    with open(path, "rb") as handle:
        while True:
            data = handle.read(8)
            if not data:
                break
            if len(data) != 8:
                raise RuntimeError("partial double at end of %s" % path)
            values.append(struct.unpack("d", data)[0])
    return values


def compare_arrays(reference, candidate, atol=1.0e-13, rtol=1.0e-13):
    if len(reference) != len(candidate):
        return {
            "pass": False,
            "reason": "size mismatch",
            "reference_size": len(reference),
            "candidate_size": len(candidate),
        }

    max_abs = 0.0
    max_rel = 0.0
    sum_sq = 0.0
    mismatches = 0
    mismatch_tol = max(atol, rtol)

    for ref, cand in zip(reference, candidate):
        diff = cand - ref
        abs_diff = abs(diff)
        denom = max(abs(ref), 1.0e-30)
        rel = abs_diff / denom
        max_abs = max(max_abs, abs_diff)
        max_rel = max(max_rel, rel)
        sum_sq += diff * diff
        if abs_diff > atol and rel > rtol:
            mismatches += 1

    rmse = math.sqrt(sum_sq / len(reference)) if reference else float("nan")
    return {
        "pass": mismatches == 0,
        "count": len(reference),
        "max_abs_error": max_abs,
        "max_rel_error": max_rel,
        "rmse": rmse,
        "mismatches_above_tolerance": mismatches,
        "atol": atol,
        "rtol": rtol,
        "mismatch_rule": "abs_error > atol and rel_error > rtol",
        "effective_mismatch_tolerance_note": mismatch_tol,
    }


def main():
    if len(sys.argv) not in (4, 5):
        print(
            "usage: compare_outputs.py <baseline_outputs_dir> "
            "<candidate_outputs_dir> <report_json> [candidate_filename]",
            file=sys.stderr,
        )
        return 2

    baseline_outputs = sys.argv[1]
    candidate_outputs = sys.argv[2]
    report_path = sys.argv[3]
    candidate_filename = sys.argv[4] if len(sys.argv) == 5 else "output_dq_cpp.bin"

    reference_path = os.path.join(baseline_outputs, "output_dq.bin")
    candidate_path = os.path.join(candidate_outputs, candidate_filename)

    report = {
        "kernel": "semi_y_3d",
        "reference": reference_path,
        "candidate": candidate_path,
        "variables": {},
        "overall_pass": True,
    }

    if not os.path.exists(reference_path):
        report["variables"]["dq"] = {
            "pass": False,
            "reason": "missing reference output",
        }
        report["overall_pass"] = False
    elif not os.path.exists(candidate_path):
        report["variables"]["dq"] = {
            "pass": False,
            "reason": "missing candidate output",
        }
        report["overall_pass"] = False
    else:
        result = compare_arrays(read_doubles(reference_path), read_doubles(candidate_path))
        report["variables"]["dq"] = result
        report["overall_pass"] = bool(result["pass"])

    os.makedirs(os.path.dirname(report_path), exist_ok=True)
    with open(report_path, "w") as handle:
        json.dump(report, handle, indent=2)
    print(json.dumps(report, indent=2))

    return 0 if report["overall_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
