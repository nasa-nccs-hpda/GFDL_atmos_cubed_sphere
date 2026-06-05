from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path
from typing import Any

import yaml


def load_config(path: str = "config.yaml") -> dict[str, Any]:
    with open(path, "r") as f:
        return yaml.safe_load(f)


def read_api_key(api_key_file: str) -> str:
    path = Path(api_key_file).expanduser()
    if not path.exists():
        raise FileNotFoundError(f"Anthropic API key file not found: {path}")
    return path.read_text().strip()


def run_cmd(
    cmd: list[str],
    cwd: str | None = None,
    timeout: int = 600,
) -> dict[str, Any]:
    p = subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )

    return {
        "cmd": " ".join(cmd),
        "cwd": cwd,
        "returncode": p.returncode,
        "stdout": p.stdout,
        "stderr": p.stderr,
    }


def find_fortran_files(repo_root: str) -> list[str]:
    root = Path(repo_root)
    patterns = ["*.F90", "*.f90", "*.F", "*.f", "*.inc"]

    files = []
    for pat in patterns:
        files.extend(str(p) for p in root.rglob(pat))

    return sorted(files)


def grep_keywords(
    files: list[str],
    keywords: list[str],
) -> list[dict[str, Any]]:
    results = []
    regex = re.compile("|".join(re.escape(k) for k in keywords), re.IGNORECASE)

    for f in files:
        try:
            text = Path(f).read_text(errors="ignore")
        except Exception:
            continue

        matches = []
        for i, line in enumerate(text.splitlines(), start=1):
            if regex.search(line):
                matches.append(
                    {
                        "line": i,
                        "text": line.strip(),
                    }
                )

        if matches:
            results.append(
                {
                    "file": f,
                    "matches": matches[:40],
                    "num_matches": len(matches),
                }
            )

    return results


def extract_fortran_units(path: str) -> dict[str, list[str]]:
    text = Path(path).read_text(errors="ignore")

    modules = re.findall(r"^\s*module\s+(\w+)", text, re.I | re.M)
    subroutines = re.findall(r"^\s*subroutine\s+(\w+)", text, re.I | re.M)
    functions = re.findall(r"^\s*function\s+(\w+)", text, re.I | re.M)
    uses = re.findall(r"^\s*use\s+(\w+)", text, re.I | re.M)

    return {
        "modules": sorted(set(modules)),
        "subroutines": sorted(set(subroutines)),
        "functions": sorted(set(functions)),
        "uses": sorted(set(uses)),
    }


def build_dependency_summary(files: list[str]) -> dict[str, Any]:
    summary = {}

    for f in files:
        units = extract_fortran_units(f)
        if units["modules"] or units["subroutines"] or units["functions"]:
            summary[f] = units

    return summary


def read_text(path: str, max_chars: int = 30000) -> str:
    return Path(path).read_text(errors="ignore")[:max_chars]


def write_text(path: str, text: str) -> None:
    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text)


def write_json(path: str, obj: Any) -> None:
    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(obj, indent=2))


def run_held_suarez_case(config: dict[str, Any]) -> dict[str, Any]:
    case_script = Path(config["repo_root"]) / config["target_case"]

    return run_cmd(
        ["python3", str(case_script)],
        cwd=config["repo_root"],
        timeout=3600,
    )


def simple_netcdf_validation(data_root: str) -> dict[str, Any]:
    root = Path(data_root)
    nc_files = sorted(root.rglob("*.nc"))

    return {
        "data_root": data_root,
        "num_netcdf_files": len(nc_files),
        "sample_files": [str(p) for p in nc_files[:10]],
        "passed": len(nc_files) > 0,
    }