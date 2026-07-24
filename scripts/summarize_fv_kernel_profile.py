#!/usr/bin/env python3
import argparse
import re
from pathlib import Path


PROFILE_RE = re.compile(
    r"PROFILE_FV_ADVECTION_KERNEL backend=(?P<backend>\S+) "
    r"rank=(?P<rank>\S+) name=(?P<name>\S+) calls=(?P<calls>\d+) "
    r"time=(?P<time>[0-9.eE+-]+) avg=(?P<avg>[0-9.eE+-]+)"
)
REAL_RE = re.compile(r"^real\s+(?:(?P<min>\d+)m)?(?P<sec>[0-9.]+)s$")


def parse_log(path):
    rows = []
    for line in Path(path).read_text(errors="replace").splitlines():
        match = PROFILE_RE.search(line)
        if not match:
            continue
        item = match.groupdict()
        item["calls"] = int(item["calls"])
        item["time"] = float(item["time"])
        item["avg"] = float(item["avg"])
        rows.append(item)
    return rows


def parse_real_seconds(path):
    values = []
    for line in Path(path).read_text(errors="replace").splitlines():
        match = REAL_RE.match(line.strip())
        if not match:
            continue
        minutes = int(match.group("min") or 0)
        seconds = float(match.group("sec"))
        values.append(minutes * 60.0 + seconds)
    return values


def summarize(rows):
    by_name = {}
    for row in rows:
        key = (row["backend"], row["name"])
        by_name.setdefault(key, []).append(row)

    summaries = []
    for (backend, name), items in sorted(by_name.items()):
        times = [item["time"] for item in items]
        calls = [item["calls"] for item in items]
        max_time = max(times)
        mean_time = sum(times) / len(times)
        min_time = min(times)
        summaries.append(
            {
                "backend": backend,
                "name": name,
                "ranks": len(items),
                "calls": max(calls),
                "min": min_time,
                "mean": mean_time,
                "max": max_time,
                "avg_at_max": max_time / max(calls) if max(calls) else 0.0,
            }
        )
    return summaries


def print_table(title, summaries):
    print(title)
    print("| backend | name | ranks | calls | min_s | mean_s | max_s | avg_at_max_s |")
    print("|---|---|---:|---:|---:|---:|---:|---:|")
    for item in summaries:
        print(
            f"| {item['backend']} | {item['name']} | {item['ranks']} | "
            f"{item['calls']} | {item['min']:.6f} | {item['mean']:.6f} | "
            f"{item['max']:.6f} | {item['avg_at_max']:.6e} |"
        )


def main():
    parser = argparse.ArgumentParser(description="Summarize FV kernel profile markers.")
    parser.add_argument("logs", nargs="+", help="Log files containing PROFILE_FV_ADVECTION_KERNEL lines")
    args = parser.parse_args()

    all_rows = []
    for log in args.logs:
        rows = parse_log(log)
        real_times = parse_real_seconds(log)
        if real_times:
            real_text = ", ".join(f"{value:.3f}s" for value in real_times)
            print(f"{log}: {len(rows)} profile rows, real={real_text}")
        else:
            print(f"{log}: {len(rows)} profile rows")
        all_rows.extend(rows)

    summaries = summarize(all_rows)
    if not summaries:
        raise SystemExit("No PROFILE_FV_ADVECTION_KERNEL markers found.")

    print()
    print_table("FV Kernel Profile Summary", summaries)


if __name__ == "__main__":
    main()
