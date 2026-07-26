#!/usr/bin/env python3
"""Parse Held-Suarez FV matrix logs into tidy analysis tables."""

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOG_DIR = REPO_ROOT / "logs"
DEFAULT_OUT_DIR = REPO_ROOT / "performance_analysis" / "data"

LOG_NAME_RE = re.compile(
    r"matrix_(?P<resolution>T\d+L25)_(?P<config>.+)_(?P<days>\d+)day(?:.*)?\.log$"
)

TOTAL_RUNTIME_RE = re.compile(
    r"Total runtime\s+"
    r"(?P<tmin>[0-9.Ee+-]+)\s+"
    r"(?P<tmax>[0-9.Ee+-]+)\s+"
    r"(?P<tavg>[0-9.Ee+-]+)\s+"
    r"(?P<tstd>[0-9.Ee+-]+)"
)

FV_PROFILE_RE = re.compile(
    r"PROFILE_FV_ADVECTION_CUDA\s+"
    r"backend=(?P<backend>\S+).*?"
    r"calls=(?P<calls>\d+)\s+"
    r"allocation=(?P<allocation>[0-9.Ee+-]+)\s+"
    r"h2d=(?P<h2d>[0-9.Ee+-]+)\s+"
    r"kernel=(?P<kernel>[0-9.Ee+-]+)\s+"
    r"sync=(?P<sync>[0-9.Ee+-]+)\s+"
    r"d2h=(?P<d2h>[0-9.Ee+-]+)\s+"
    r"free=(?P<free>[0-9.Ee+-]+)\s+"
    r"total=(?P<total>[0-9.Ee+-]+)"
)


def parse_key(text: str, key: str) -> str:
    match = re.search(rf"^{re.escape(key)}=(.*)$", text, re.MULTILINE)
    return match.group(1).strip() if match else ""


def parse_total_runtime(text: str) -> Optional[Dict[str, float]]:
    matches = list(TOTAL_RUNTIME_RE.finditer(text))
    if not matches:
        return None
    match = matches[-1]
    return {key: float(value) for key, value in match.groupdict().items()}


def parse_fv_profile(text: str) -> Optional[Dict[str, Any]]:
    profiles = []
    for match in FV_PROFILE_RE.finditer(text):
        item = {"backend": match.group("backend")}
        item["calls"] = int(match.group("calls"))
        for key in ("allocation", "h2d", "kernel", "sync", "d2h", "free", "total"):
            item[key] = float(match.group(key))
        profiles.append(item)
    if not profiles:
        return None
    return max(profiles, key=lambda item: float(item["total"]))


def parse_log(path: Path) -> Optional[Dict[str, Any]]:
    name_match = LOG_NAME_RE.match(path.name)
    if not name_match:
        return None

    text = path.read_text(errors="ignore")
    total = parse_total_runtime(text)
    fv = parse_fv_profile(text)
    output = parse_key(text, "output")
    completed_markers = len(re.findall(r"Integration completed through", text))
    hit_time_limit = bool(re.search(r"TIME LIMIT|CANCELLED.*TIME LIMIT", text))
    gpu_maps = text.count("PROFILE_FV_GPU_MAPPING")
    mpi_abort = any(
        marker in text
        for marker in ("MPI_ABORT", "MPI_Init", "MPI_ERRORS_ARE_FATAL")
    )

    status = "complete"
    if not total or not output or hit_time_limit:
        if hit_time_limit:
            status = "partial_time_limit"
        elif completed_markers:
            status = "partial_no_total"
        else:
            status = "failed_or_started"

    row = {
        "log": str(path),
        "log_name": path.name,
        "resolution": name_match.group("resolution"),
        "config": name_match.group("config"),
        "days": int(name_match.group("days")),
        "status": status,
        "completed": status == "complete",
        "completed_markers": completed_markers,
        "hit_time_limit": hit_time_limit,
        "mpi_abort": mpi_abort,
        "gpu_mapping_markers": gpu_maps,
        "experiment": parse_key(text, "experiment"),
        "output": output,
        "mpp_tmin_s": total["tmin"] if total else "",
        "mpp_tmax_s": total["tmax"] if total else "",
        "mpp_tavg_s": total["tavg"] if total else "",
        "mpp_tstd_s": total["tstd"] if total else "",
        "runtime_per_day_s": total["tmax"] / int(name_match.group("days"))
        if total
        else "",
        "fv_backend": fv["backend"] if fv else "",
        "fv_calls": fv["calls"] if fv else "",
        "fv_allocation_s": fv["allocation"] if fv else "",
        "fv_h2d_s": fv["h2d"] if fv else "",
        "fv_kernel_s": fv["kernel"] if fv else "",
        "fv_sync_s": fv["sync"] if fv else "",
        "fv_d2h_s": fv["d2h"] if fv else "",
        "fv_free_s": fv["free"] if fv else "",
        "fv_total_s": fv["total"] if fv else "",
        "fv_fraction_of_mpp": float(fv["total"]) / total["tmax"]
        if fv and total
        else "",
    }

    row["outlier_note"] = ""
    if (
        row["resolution"] == "T170L25"
        and row["config"] == "fv_cuda_a_grid_4gpu"
        and row["days"] == 30
        and row["completed"]
    ):
        row["outlier_note"] = "completed but performance outlier"

    return row


def write_csv(path: Path, rows: List[Dict[str, Any]]) -> None:
    if not rows:
        path.write_text("")
        return
    fieldnames = list(rows[0].keys())
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def build_completion_rows(rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    configs = ["fortran_16cpu", "fv_cuda_a_grid_1gpu", "fv_cuda_a_grid_4gpu"]
    resolutions = ["T42L25", "T85L25", "T170L25", "T340L25"]
    days_values = [30, 60, 90, 120]
    lookup = {
        (row["resolution"], row["days"], row["config"]): row for row in rows
    }
    out = []
    for resolution in resolutions:
        for days in days_values:
            item = {"resolution": resolution, "days": days}
            for config in configs:
                row = lookup.get((resolution, days, config))
                item[config] = row["status"] if row else "missing"
            out.append(item)
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log-dir", type=Path, default=DEFAULT_LOG_DIR)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument(
        "--include-16gpu",
        action="store_true",
        help="Include 16-GPU logs. Default excludes them.",
    )
    args = parser.parse_args()

    rows = []
    for path in sorted(args.log_dir.glob("matrix*.log")):
        if not args.include_16gpu and "16gpu" in path.name:
            continue
        row = parse_log(path)
        if row is not None:
            rows.append(row)

    resolution_order = {"T42L25": 0, "T85L25": 1, "T170L25": 2, "T340L25": 3}
    config_order = {
        "fortran_16cpu": 0,
        "fv_cuda_a_grid_1gpu": 1,
        "fv_cuda_a_grid_4gpu": 2,
    }
    rows.sort(
        key=lambda row: (
            resolution_order.get(str(row["resolution"]), 99),
            int(row["days"]),
            config_order.get(str(row["config"]), 99),
            str(row["log_name"]),
        )
    )

    args.out_dir.mkdir(parents=True, exist_ok=True)
    write_csv(args.out_dir / "matrix_runs.csv", rows)
    (args.out_dir / "matrix_runs.json").write_text(json.dumps(rows, indent=2))
    write_csv(args.out_dir / "matrix_completion.csv", build_completion_rows(rows))

    print("Wrote", args.out_dir / "matrix_runs.csv")
    print("Wrote", args.out_dir / "matrix_runs.json")
    print("Wrote", args.out_dir / "matrix_completion.csv")
    print("Rows:", len(rows))


if __name__ == "__main__":
    main()
