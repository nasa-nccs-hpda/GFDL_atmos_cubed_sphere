#!/usr/bin/env python3
import argparse
import re
from pathlib import Path


REGION_RE = re.compile(
    r"PROFILE_DYNAMICS_REGION name=\s*(?P<name>\S+)\s+"
    r"calls_max=\s*(?P<calls>\d+)\s+"
    r"time_max=\s*(?P<time>[0-9.eE+-]+)\s+"
    r"avg_max=\s*(?P<avg>[0-9.eE+-]+)"
)
DEEP_RE = re.compile(
    r"PROFILE_DYNAMICS_DEEP name=\s*(?P<name>\S+)\s+"
    r"calls_max=\s*(?P<calls>\d+)\s+"
    r"time_max=\s*(?P<time>[0-9.eE+-]+)\s+"
    r"avg_max=\s*(?P<avg>[0-9.eE+-]+)"
)
REAL_RE = re.compile(r"^real\s+(?:(?P<min>\d+)m)?(?P<sec>[0-9.]+)s$")


def parse_real_seconds(path):
    values = []
    for line in Path(path).read_text(errors="replace").splitlines():
        match = REAL_RE.match(line.strip())
        if match:
            values.append(int(match.group("min") or 0) * 60.0 + float(match.group("sec")))
    return values


def parse_rows(path, pattern):
    rows = []
    for line in Path(path).read_text(errors="replace").splitlines():
        match = pattern.search(line)
        if not match:
            continue
        item = match.groupdict()
        item["calls"] = int(item["calls"])
        item["time"] = float(item["time"])
        item["avg"] = float(item["avg"])
        rows.append(item)
    return rows


def print_table(title, rows):
    if not rows:
        return
    total = sum(row["time"] for row in rows)
    print(title)
    print("| name | calls | time_s | avg_s | pct_of_profiled |")
    print("|---|---:|---:|---:|---:|")
    for row in sorted(rows, key=lambda item: item["time"], reverse=True):
        pct = 100.0 * row["time"] / total if total else 0.0
        print(
            f"| {row['name']} | {row['calls']} | {row['time']:.6f} | "
            f"{row['avg']:.6e} | {pct:.2f}% |"
        )
    print()


def main():
    parser = argparse.ArgumentParser(description="Summarize spectral dynamics profile logs.")
    parser.add_argument("logs", nargs="+")
    args = parser.parse_args()

    all_regions = []
    all_deep = []
    for log in args.logs:
        real_times = parse_real_seconds(log)
        real_text = ", ".join(f"{value:.3f}s" for value in real_times) if real_times else "none"
        regions = parse_rows(log, REGION_RE)
        deep = parse_rows(log, DEEP_RE)
        print(f"{log}: real={real_text}, regions={len(regions)}, deep={len(deep)}")
        all_regions.extend(regions)
        all_deep.extend(deep)

    print()
    print_table("Dynamics Region Profile", all_regions)
    print_table("Dynamics Deep Profile", all_deep)


if __name__ == "__main__":
    main()
