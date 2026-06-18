#!/usr/bin/env python3
"""Validate T85L25 Held-Suarez forcing experiment NetCDF outputs.

Compares:

- all-Fortran vs CPU C++ hybrid
- all-Fortran vs CUDA hybrid
- CPU C++ hybrid vs CUDA hybrid

The script writes a machine-readable JSON report and a Markdown summary.
"""

import argparse
import json
import math
import os
import re
import subprocess
from pathlib import Path
from typing import Iterable, Optional


REQUESTED_FIELD_ALIASES = {
    "temperature": ("temperature", "temp"),
    "ucomp": ("ucomp",),
    "vcomp": ("vcomp",),
    "ps": ("ps",),
}

FORCING_KEYWORDS = (
    "forcing",
    "hs",
    "teq",
    "tdt",
    "udt",
    "vdt",
    "dtemp",
    "dt_",
)

NUMBER_PATTERN = re.compile(
    r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[EeDd][-+]?\d+)?|[-+]?\d+"
)


def default_file(data_root: Path, exp_name: str, run: int, filename: str) -> Path:
    return data_root / exp_name / ("run%04d" % run) / filename


class SimpleDataArray:
    def __init__(self, name, values, dims):
        self.name = name
        self.values = values
        self.dims = tuple(dims)
        self.shape = values.shape
        self.dtype = values.dtype


class SimpleDataset:
    def __init__(self, path, variables, sizes, data_vars):
        self.path = path
        self.variables = variables
        self.sizes = sizes
        self.data_vars = data_vars

    def __contains__(self, name):
        return name in self.variables

    def __getitem__(self, name):
        return self.variables[name]


def is_numeric(data_array, np_module) -> bool:
    return np_module.issubdtype(data_array.dtype, np_module.number)


def first_present(dataset, aliases: Iterable[str]) -> Optional[str]:
    for name in aliases:
        if name in dataset:
            return name
    return None


def forcing_related_fields(datasets, np_module):
    names = set()
    for dataset in datasets:
        for name, data_array in dataset.data_vars.items():
            lname = name.lower()
            if is_numeric(data_array, np_module) and any(k in lname for k in FORCING_KEYWORDS):
                names.add(name)
    return sorted(names)


def compare_arrays(baseline, candidate, np_module, rel_eps: float) -> dict:
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
    valid = np_module.isfinite(base) & np_module.isfinite(cand)

    if not np_module.any(valid):
        return {
            "pass": bool(np_module.array_equal(base, cand)),
            "reason": "no finite values",
            "dims": list(baseline.dims),
            "shape": list(base.shape),
            "finite_values": 0,
        }

    b = base[valid]
    c = cand[valid]
    diff = c - b
    abs_diff = np_module.abs(diff)

    denom = np_module.maximum(np_module.abs(b), rel_eps)
    rel = abs_diff / denom
    base_rms = math.sqrt(float(np_module.mean(b**2)))
    rel_l2 = float(math.sqrt(float(np_module.mean(diff**2))) / max(base_rms, rel_eps))

    max_abs = float(np_module.max(abs_diff))
    rmse = float(math.sqrt(float(np_module.mean(diff**2))))
    max_rel = float(np_module.max(rel))
    mean_abs = float(np_module.mean(abs_diff))

    return {
        "pass": bool(max_abs == 0.0),
        "dims": list(baseline.dims),
        "shape": list(base.shape),
        "finite_values": int(np_module.count_nonzero(valid)),
        "baseline_mean": float(np_module.nanmean(base)),
        "candidate_mean": float(np_module.nanmean(cand)),
        "mean_difference": float(np_module.nanmean(cand) - np_module.nanmean(base)),
        "max_abs_error": max_abs,
        "rmse": rmse,
        "max_relative_error": max_rel,
        "relative_l2_error": rel_l2,
        "mean_abs_error": mean_abs,
    }


def compare_pair(name: str, baseline_ds, candidate_ds, field_names, np_module, rel_eps: float) -> dict:
    result = {
        "name": name,
        "baseline_dims": dict(baseline_ds.sizes),
        "candidate_dims": dict(candidate_ds.sizes),
        "dimension_match": dict(baseline_ds.sizes) == dict(candidate_ds.sizes),
        "variables": {},
        "missing": {},
    }

    for field in field_names:
        if field not in baseline_ds or field not in candidate_ds:
            result["missing"][field] = {
                "in_baseline": field in baseline_ds,
                "in_candidate": field in candidate_ds,
            }
            continue

        if not is_numeric(baseline_ds[field], np_module) or not is_numeric(candidate_ds[field], np_module):
            result["missing"][field] = {
                "reason": "non-numeric variable",
                "in_baseline": field in baseline_ds,
                "in_candidate": field in candidate_ds,
            }
            continue

        result["variables"][field] = compare_arrays(
            baseline_ds[field], candidate_ds[field], np_module, rel_eps
        )

    return result


def format_float(value) -> str:
    if value is None:
        return "NA"
    if isinstance(value, bool):
        return str(value)
    if isinstance(value, (int,)):
        return str(value)
    try:
        value = float(value)
    except (TypeError, ValueError):
        return str(value)
    if value == 0.0:
        return "0"
    return "%.6e" % value


def run_ncdump(args):
    try:
        return subprocess.check_output(
            args, universal_newlines=True, stderr=subprocess.STDOUT
        )
    except FileNotFoundError:
        raise RuntimeError(
            "Could not open NetCDF files with xarray, and `ncdump` was not found. "
            "Install one Python NetCDF backend such as netCDF4 or scipy, or run "
            "inside an environment with ncdump available."
        )
    except subprocess.CalledProcessError as exc:
        raise RuntimeError("ncdump failed:\n%s" % exc.output)


def parse_header(path):
    header = run_ncdump(["ncdump", "-h", str(path)])
    sizes = {}
    variables = {}
    in_variables = False
    current_var = None

    for raw_line in header.splitlines():
        line = raw_line.strip()
        if line == "dimensions:":
            in_variables = False
            continue
        if line == "variables:":
            in_variables = True
            continue
        if line == "data:":
            break

        if not in_variables:
            match = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\d+|UNLIMITED)\s*(?:;\s*//\s*\((\d+)\s+currently\))?", line)
            if match:
                size_text = match.group(3) or match.group(2)
                if size_text != "UNLIMITED":
                    sizes[match.group(1)] = int(size_text)
            continue

        decl = re.match(
            r"(byte|char|short|int|int64|float|double)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(([^)]*)\))?\s*;",
            line,
        )
        if decl:
            dims = []
            if decl.group(3):
                dims = [part.strip() for part in decl.group(3).split(",") if part.strip()]
            current_var = decl.group(2)
            variables[current_var] = {"type": decl.group(1), "dims": dims}
            continue

        attr = re.match(r"([A-Za-z_][A-Za-z0-9_]*):", line)
        if attr:
            current_var = attr.group(1)

    return sizes, variables


def parse_ncdump_values(path, variable):
    text = run_ncdump(["ncdump", "-v", variable, str(path)])
    match = re.search(r"(?:^|\n)\s*%s\s*=\s*(.*?);" % re.escape(variable), text, re.S)
    if not match:
        raise RuntimeError("Could not parse values for variable `%s` from %s" % (variable, path))
    payload = match.group(1)
    payload = re.sub(r"//.*", " ", payload)
    tokens = NUMBER_PATTERN.findall(payload.replace("_", " "))
    return [float(token.replace("D", "E").replace("d", "e")) for token in tokens]


def open_dataset_with_ncdump(path, field_names, np_module):
    sizes, metadata = parse_header(path)
    variables = {}
    data_vars = {}

    wanted = set(field_names)
    for name, meta in metadata.items():
        lname = name.lower()
        if any(k in lname for k in FORCING_KEYWORDS):
            wanted.add(name)

    for name in sorted(wanted):
        if name not in metadata:
            continue
        dims = metadata[name]["dims"]
        shape = tuple(sizes[dim] for dim in dims)
        values = np_module.array(parse_ncdump_values(path, name), dtype=float)
        if shape:
            expected = 1
            for size in shape:
                expected *= size
            if values.size != expected:
                raise RuntimeError(
                    "Variable `%s` in %s has %d values, expected %d from shape %s"
                    % (name, path, values.size, expected, shape)
                )
            values = values.reshape(shape)
        data_array = SimpleDataArray(name, values, dims)
        variables[name] = data_array
        data_vars[name] = data_array

    return SimpleDataset(path, variables, sizes, data_vars)


def open_datasets(files, field_names, np_module):
    try:
        import xarray as xr

        engines = [None, "netcdf4", "h5netcdf", "scipy"]
        last_error = None
        for engine in engines:
            try:
                kwargs = {"decode_times": False}
                if engine is not None:
                    kwargs["engine"] = engine
                datasets = [
                    xr.open_dataset(files["fortran"], **kwargs),
                    xr.open_dataset(files["cpu_hybrid"], **kwargs),
                    xr.open_dataset(files["cuda_hybrid"], **kwargs),
                ]
                return datasets, "xarray:%s" % (engine or "auto")
            except Exception as exc:
                last_error = exc

        print("xarray could not open NetCDF files; falling back to ncdump.")
        print("Last xarray error:", last_error)
    except ImportError:
        print("xarray is not installed; falling back to ncdump.")

    datasets = [
        open_dataset_with_ncdump(files["fortran"], field_names, np_module),
        open_dataset_with_ncdump(files["cpu_hybrid"], field_names, np_module),
        open_dataset_with_ncdump(files["cuda_hybrid"], field_names, np_module),
    ]
    return datasets, "ncdump"


def markdown_report(report: dict) -> str:
    lines = [
        "# T85L25 Forcing Numerical Validation Report",
        "",
        "Generated by `tests/validate_T85L25_forcing_outputs.py`.",
        "",
        "## Inputs",
        "",
        "| Case | File | Exists |",
        "|---|---|---|",
    ]

    for case_name, path in report["files"].items():
        lines.append("| `%s` | `%s` | %s |" % (case_name, path, Path(path).exists()))

    lines.extend(
        [
            "",
            "## Fields",
            "",
            "Requested fields use `temp` as the Held-Suarez `temperature` diagnostic when `temperature` is not present.",
            "",
            "| Logical Field | NetCDF Variable |",
            "|---|---|",
        ]
    )

    for logical_name, actual_name in report["field_mapping"].items():
        lines.append("| `%s` | `%s` |" % (logical_name, actual_name or "missing"))

    lines.extend(
        [
            "",
            "Forcing-related diagnostics are auto-detected by variable names containing:",
            "",
            "`%s`" % "`, `".join(FORCING_KEYWORDS),
            "",
            "Detected forcing-related diagnostics: `%s`"
            % ("`, `".join(report["forcing_related_fields"]) if report["forcing_related_fields"] else "none"),
            "",
            "## Summary",
            "",
            "| Comparison | Dimension Match | Variables Compared | Missing Variables | Max Abs Error | Max RMSE | Max Relative Error | Max Relative L2 Error |",
            "|---|---:|---:|---:|---:|---:|---:|---:|",
        ]
    )

    for pair in report["comparisons"]:
        variables = pair["variables"]
        max_abs = max((v.get("max_abs_error", 0.0) for v in variables.values()), default=None)
        max_rmse = max((v.get("rmse", 0.0) for v in variables.values()), default=None)
        max_rel = max((v.get("max_relative_error", 0.0) for v in variables.values()), default=None)
        max_rel_l2 = max((v.get("relative_l2_error", 0.0) for v in variables.values()), default=None)
        lines.append(
            "| %s | %s | %d | %d | %s | %s | %s | %s |"
            % (
                pair["name"],
                pair["dimension_match"],
                len(variables),
                len(pair["missing"]),
                format_float(max_abs),
                format_float(max_rmse),
                format_float(max_rel),
                format_float(max_rel_l2),
            )
        )

    lines.extend(
        [
            "",
            "## Variable-by-Variable Results",
            "",
        ]
    )

    for pair in report["comparisons"]:
        lines.extend(
            [
                "### %s" % pair["name"],
                "",
                "| Variable | Shape | Max Abs Error | RMSE | Max Relative Error | Relative L2 Error | Baseline Mean | Candidate Mean |",
                "|---|---|---:|---:|---:|---:|---:|---:|",
            ]
        )
        for variable, metrics in sorted(pair["variables"].items()):
            lines.append(
                "| `%s` | `%s` | %s | %s | %s | %s | %s | %s |"
                % (
                    variable,
                    "x".join(str(x) for x in metrics.get("shape", [])),
                    format_float(metrics.get("max_abs_error")),
                    format_float(metrics.get("rmse")),
                    format_float(metrics.get("max_relative_error")),
                    format_float(metrics.get("relative_l2_error")),
                    format_float(metrics.get("baseline_mean")),
                    format_float(metrics.get("candidate_mean")),
                )
            )
        if pair["missing"]:
            lines.extend(["", "Missing variables:", ""])
            for variable, info in sorted(pair["missing"].items()):
                lines.append("- `%s`: `%s`" % (variable, info))
        lines.append("")

    lines.extend(
        [
            "## Exact Commands",
            "",
            "From the repository root after all three 30-day runs have completed:",
            "",
            "```bash",
            "export GFDL_DATA=${GFDL_DATA:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data}",
            "python3 tests/validate_T85L25_forcing_outputs.py \\",
            "  --fortran-exp held_suarez_fortran_T85L25 \\",
            "  --cpu-exp held_suarez_hybrid_cpu_T85L25 \\",
            "  --cuda-exp held_suarez_hybrid_cuda_T85L25 \\",
            "  --filename atmos_monthly.nc \\",
            "  --fields temperature ucomp vcomp ps \\",
            "  --markdown-out tests/reports/T85L25_forcing_validation_report.md \\",
            "  --json-out tests/reports/T85L25_forcing_validation_report.json \\",
            "  2>&1 | tee logs/T85L25_forcing_validation.log",
            "```",
            "",
        ]
    )

    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fortran-exp", default="held_suarez_fortran_T85L25")
    parser.add_argument("--cpu-exp", default="held_suarez_hybrid_cpu_T85L25")
    parser.add_argument("--cuda-exp", default="held_suarez_hybrid_cuda_T85L25")
    parser.add_argument("--run", type=int, default=1)
    parser.add_argument("--filename", default="atmos_monthly.nc")
    parser.add_argument("--data-root", default=os.environ.get("GFDL_DATA", "."))
    parser.add_argument(
        "--fields",
        nargs="*",
        default=["temperature", "ucomp", "vcomp", "ps"],
        help="Logical or NetCDF variable names to compare.",
    )
    parser.add_argument("--relative-eps", type=float, default=1.0e-30)
    parser.add_argument(
        "--markdown-out",
        default="tests/reports/T85L25_forcing_validation_report.md",
    )
    parser.add_argument(
        "--json-out",
        default="tests/reports/T85L25_forcing_validation_report.json",
    )
    args = parser.parse_args()

    import numpy as np

    data_root = Path(args.data_root)
    files = {
        "fortran": default_file(data_root, args.fortran_exp, args.run, args.filename),
        "cpu_hybrid": default_file(data_root, args.cpu_exp, args.run, args.filename),
        "cuda_hybrid": default_file(data_root, args.cuda_exp, args.run, args.filename),
    }

    missing_files = [str(path) for path in files.values() if not path.exists()]
    if missing_files:
        raise FileNotFoundError(
            "Missing required NetCDF output file(s):\n" + "\n".join(missing_files)
        )

    requested_variable_candidates = []
    for logical_name in args.fields:
        for alias in REQUESTED_FIELD_ALIASES.get(logical_name, (logical_name,)):
            if alias not in requested_variable_candidates:
                requested_variable_candidates.append(alias)

    datasets, reader = open_datasets(files, requested_variable_candidates, np)
    try:
        fortran_ds, cpu_ds, cuda_ds = datasets

        field_mapping = {}
        field_names = []
        for logical_name in args.fields:
            aliases = REQUESTED_FIELD_ALIASES.get(logical_name, (logical_name,))
            actual = None
            for dataset in datasets:
                actual = first_present(dataset, aliases)
                if actual:
                    break
            field_mapping[logical_name] = actual
            if actual and actual not in field_names:
                field_names.append(actual)

        forcing_fields = forcing_related_fields(datasets, np)
        for field in forcing_fields:
            if field not in field_names:
                field_names.append(field)

        report = {
            "reader": reader,
            "files": {name: str(path) for name, path in files.items()},
            "field_mapping": field_mapping,
            "forcing_related_fields": forcing_fields,
            "comparisons": [
                compare_pair(
                    "Fortran vs CPU hybrid",
                    fortran_ds,
                    cpu_ds,
                    field_names,
                    np,
                    args.relative_eps,
                ),
                compare_pair(
                    "Fortran vs CUDA hybrid",
                    fortran_ds,
                    cuda_ds,
                    field_names,
                    np,
                    args.relative_eps,
                ),
                compare_pair(
                    "CPU hybrid vs CUDA hybrid",
                    cpu_ds,
                    cuda_ds,
                    field_names,
                    np,
                    args.relative_eps,
                ),
            ],
        }
    finally:
        for dataset in datasets:
            close = getattr(dataset, "close", None)
            if close is not None:
                close()

    json_out = Path(args.json_out)
    markdown_out = Path(args.markdown_out)
    json_out.parent.mkdir(parents=True, exist_ok=True)
    markdown_out.parent.mkdir(parents=True, exist_ok=True)
    json_out.write_text(json.dumps(report, indent=2))
    markdown_out.write_text(markdown_report(report))

    print("Wrote JSON report:", json_out)
    print("Wrote Markdown report:", markdown_out)


if __name__ == "__main__":
    main()
