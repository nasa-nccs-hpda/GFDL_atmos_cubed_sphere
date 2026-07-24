#!/usr/bin/env python3
import argparse
import re
from pathlib import Path


REAL_RE = re.compile(r"^real\s+(?:(?P<min>\d+)m)?(?P<sec>[0-9.]+)s$")
RANK_RE = re.compile(r"_r(?P<ranks>\d+)\.log$")


def real_seconds(path):
    values = []
    for line in Path(path).read_text(errors="replace").splitlines():
        match = REAL_RE.match(line.strip())
        if not match:
            continue
        values.append(int(match.group("min") or 0) * 60.0 + float(match.group("sec")))
    return values[-1] if values else None


def ranks_from_name(path):
    match = RANK_RE.search(str(path))
    return int(match.group("ranks")) if match else None


def main():
    parser = argparse.ArgumentParser(description="Summarize GPU-only rank sweep logs.")
    parser.add_argument("logs", nargs="+")
    args = parser.parse_args()

    rows = []
    for log in args.logs:
        seconds = real_seconds(log)
        ranks = ranks_from_name(log)
        if seconds is not None:
            rows.append((seconds, ranks, log))

    if not rows:
        raise SystemExit("No real times found.")

    best = min(rows)
    print("| ranks | real_s | speedup_vs_best | log |")
    print("|---:|---:|---:|---|")
    for seconds, ranks, log in sorted(rows, key=lambda item: (item[1] is None, item[1] or 0)):
        rank_text = str(ranks) if ranks is not None else "?"
        print(f"| {rank_text} | {seconds:.3f} | {best[0] / seconds:.3f}x | {log} |")
    print()
    print(f"Best: ranks={best[1]} real={best[0]:.3f}s log={best[2]}")


if __name__ == "__main__":
    main()
