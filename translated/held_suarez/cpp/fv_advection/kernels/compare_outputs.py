#!/usr/bin/env python3
import array
import json
import math
import os
import sys


DOUBLE_COMPARISONS = [
    ("semi_x_dq", "output_semi_x_dq.bin", "output_semi_x_dq"),
    ("slope_x", "output_slope_x.bin", "output_slope_x"),
    ("integer_flux_x", "output_integer_flux_x.bin", "output_integer_flux_x"),
    ("vanleer_x_dq_dt", "output_vanleer_x_dq_dt.bin", "output_vanleer_x_dq_dt"),
    ("slope_sphere", "output_slope_sphere.bin", "output_slope_sphere"),
    (
        "vanleer_sphere_dq_dt",
        "output_vanleer_sphere_dq_dt.bin",
        "output_vanleer_sphere_dq_dt",
    ),
]

INT_COMPARISONS = [
    ("find_cell_x_ii", "output_find_cell_x_ii.bin", "output_find_cell_x_ii"),
]


def read_array(path, typecode):
    values = array.array(typecode)
    with open(path, "rb") as handle:
        values.frombytes(handle.read())
    return values


def compare_float(name, ref_path, got_path, tolerance):
    ref = read_array(ref_path, "d")
    got = read_array(got_path, "d")
    if len(ref) != len(got):
        return {
            "name": name,
            "status": "FAIL",
            "reason": "length mismatch",
            "reference_count": len(ref),
            "candidate_count": len(got),
        }

    max_abs = 0.0
    sum_sq = 0.0
    mismatch_count = 0
    for ref_value, got_value in zip(ref, got):
        diff = abs(ref_value - got_value)
        max_abs = max(max_abs, diff)
        sum_sq += diff * diff
        if diff > tolerance:
            mismatch_count += 1

    rmse = math.sqrt(sum_sq / len(ref)) if ref else 0.0
    return {
        "name": name,
        "status": "PASS" if mismatch_count == 0 else "FAIL",
        "count": len(ref),
        "max_abs_error": max_abs,
        "rmse": rmse,
        "tolerance": tolerance,
        "mismatch_count": mismatch_count,
    }


def compare_int(name, ref_path, got_path):
    ref = read_array(ref_path, "i")
    got = read_array(got_path, "i")
    if len(ref) != len(got):
        return {
            "name": name,
            "status": "FAIL",
            "reason": "length mismatch",
            "reference_count": len(ref),
            "candidate_count": len(got),
        }

    mismatch_count = sum(1 for ref_value, got_value in zip(ref, got) if ref_value != got_value)
    return {
        "name": name,
        "status": "PASS" if mismatch_count == 0 else "FAIL",
        "count": len(ref),
        "mismatch_count": mismatch_count,
    }


def main():
    if len(sys.argv) not in (4, 5, 6):
        print(
            "usage: compare_outputs.py <reference_outputs_dir> <candidate_outputs_dir> "
            "<report.json> [tolerance] [candidate_suffix]",
            file=sys.stderr,
        )
        return 2

    reference_dir = sys.argv[1]
    candidate_dir = sys.argv[2]
    report_path = sys.argv[3]
    tolerance = float(sys.argv[4]) if len(sys.argv) == 5 else 1.0e-13
    if len(sys.argv) == 6:
        tolerance = float(sys.argv[4])
        candidate_suffix = sys.argv[5]
    else:
        candidate_suffix = "cpp"

    results = []
    for name, ref_name, got_base in DOUBLE_COMPARISONS:
        results.append(
            compare_float(
                name,
                os.path.join(reference_dir, ref_name),
                os.path.join(candidate_dir, f"{got_base}_{candidate_suffix}.bin"),
                tolerance,
            )
        )

    if candidate_suffix == "cpp":
        for name, ref_name, got_base in INT_COMPARISONS:
            results.append(
                compare_int(
                    name,
                    os.path.join(reference_dir, ref_name),
                    os.path.join(candidate_dir, f"{got_base}_{candidate_suffix}.bin"),
                )
            )

    overall_status = "PASS" if all(item["status"] == "PASS" for item in results) else "FAIL"
    report = {
        "status": overall_status,
        "reference_outputs_dir": reference_dir,
        "candidate_outputs_dir": candidate_dir,
        "results": results,
    }

    os.makedirs(os.path.dirname(report_path), exist_ok=True)
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, sort_keys=True)
        handle.write("\n")

    print(f"Wrote JSON report: {report_path}")
    print(f"overall status: {overall_status}")
    for item in results:
        if "max_abs_error" in item:
            print(
                f"{item['name']}: {item['status']} max_abs={item['max_abs_error']:.6e} "
                f"rmse={item['rmse']:.6e} mismatches={item['mismatch_count']}"
            )
        else:
            print(f"{item['name']}: {item['status']} mismatches={item['mismatch_count']}")

    return 0 if overall_status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
