#!/usr/bin/env python3
import argparse
import re
from pathlib import Path


REAL_RE = re.compile(r"^real\s+(?:(?P<min>\d+)m)?(?P<sec>[0-9.]+)s$")


def real_seconds(path):
    values = []
    for line in Path(path).read_text(errors="replace").splitlines():
        match = REAL_RE.match(line.strip())
        if not match:
            continue
        minutes = int(match.group("min") or 0)
        seconds = float(match.group("sec"))
        values.append(minutes * 60.0 + seconds)
    return values


def main():
    parser = argparse.ArgumentParser(description="Summarize shell time real lines.")
    parser.add_argument("logs", nargs="+")
    args = parser.parse_args()

    first = None
    for log in args.logs:
        values = real_seconds(log)
        text = ", ".join(f"{value:.3f}s" for value in values) if values else "none"
        print(f"{log}: real={text}")
        if values and first is None:
            first = values[-1]
        elif values and first:
            ratio = first / values[-1]
            print(f"speedup_vs_first={ratio:.3f}x")


if __name__ == "__main__":
    main()
