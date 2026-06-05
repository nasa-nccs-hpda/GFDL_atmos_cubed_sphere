#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from collections import defaultdict


FORTRAN_EXTS = {".f90", ".F90", ".f", ".F", ".for", ".FOR"}
PYTHON_EXTS = {".py"}
SCRIPT_EXTS = {".sh", ".bash", ".csh"}


RE_MODULE = re.compile(r"^\s*module\s+(\w+)", re.I)
RE_END_MODULE = re.compile(r"^\s*end\s+module", re.I)
RE_USE = re.compile(r"^\s*use\s+(?:,\s*intrinsic\s*::\s*)?(\w+)", re.I)
RE_SUBROUTINE = re.compile(r"^\s*subroutine\s+(\w+)", re.I)
RE_FUNCTION = re.compile(r"^\s*(?:[\w(),=*]+\s+)*function\s+(\w+)", re.I)
RE_CALL = re.compile(r"\bcall\s+(\w+)", re.I)


def read_text(path: Path) -> str:
    try:
        return path.read_text(errors="ignore")
    except Exception:
        return ""


def is_source(path: Path) -> bool:
    return path.suffix in FORTRAN_EXTS | PYTHON_EXTS | SCRIPT_EXTS


def iter_source_files(repo: Path):
    ignore_dirs = {
        ".git",
        "__pycache__",
        "build",
        "_build",
        ".venv",
        "venv",
        "env",
        ".mypy_cache",
        ".pytest_cache",
    }

    for path in repo.rglob("*"):
        if any(part in ignore_dirs for part in path.parts):
            continue
        if path.is_file() and is_source(path):
            yield path


def strip_fortran_comment(line: str) -> str:
    return line.split("!")[0]


def parse_fortran(path: Path, repo: Path) -> dict:
    text = read_text(path)

    modules = []
    uses = []
    subroutines = []
    functions = []
    calls = []

    for raw_line in text.splitlines():
        line = strip_fortran_comment(raw_line)

        m = RE_MODULE.match(line)
        if m and not RE_END_MODULE.match(line):
            mod = m.group(1)
            if mod.lower() != "procedure":
                modules.append(mod)

        m = RE_USE.match(line)
        if m:
            uses.append(m.group(1))

        m = RE_SUBROUTINE.match(line)
        if m:
            subroutines.append(m.group(1))

        m = RE_FUNCTION.match(line)
        if m:
            functions.append(m.group(1))

        for m in RE_CALL.finditer(line):
            calls.append(m.group(1))

    return {
        "path": str(path.relative_to(repo)),
        "language": "fortran",
        "n_lines": len(text.splitlines()),
        "modules": sorted(set(modules), key=str.lower),
        "uses": sorted(set(uses), key=str.lower),
        "subroutines": sorted(set(subroutines), key=str.lower),
        "functions": sorted(set(functions), key=str.lower),
        "calls": sorted(set(calls), key=str.lower),
    }


def parse_text_file(path: Path, repo: Path) -> dict:
    text = read_text(path)
    lower = text.lower()

    return {
        "path": str(path.relative_to(repo)),
        "language": "python" if path.suffix in PYTHON_EXTS else "script",
        "n_lines": len(text.splitlines()),
        "mentions": {
            "held_suarez": "held_suarez" in lower or "held suarez" in lower,
            "namelist": "namelist" in lower,
            "compile": "compile" in lower,
            "run": "run" in lower,
            "fms": "fms" in lower,
            "mpp": "mpp" in lower,
        },
    }


def relevance_score(item: dict, keywords: list[str]) -> int:
    score = 0
    path = item["path"].lower()

    for kw in keywords:
        kw = kw.lower()

        if kw in path:
            score += 20

        if item["language"] == "fortran":
            for field in ["modules", "uses", "subroutines", "functions", "calls"]:
                for name in item.get(field, []):
                    if kw in name.lower():
                        score += 10
        else:
            for value in item.get("mentions", {}).values():
                if value:
                    score += 2

    return score


def build_module_index(items: list[dict]) -> dict:
    index = {}

    for item in items:
        if item["language"] != "fortran":
            continue

        for mod in item["modules"]:
            index[mod.lower()] = {
                "module": mod,
                "path": item["path"],
            }

    return index


def build_dependency_graph(items: list[dict], module_index: dict) -> dict:
    graph = defaultdict(list)

    for item in items:
        if item["language"] != "fortran":
            continue

        src = item["path"]

        for used in item["uses"]:
            key = used.lower()
            if key in module_index:
                graph[src].append(module_index[key]["path"])
            else:
                graph[src].append(f"UNRESOLVED_OR_EXTERNAL::{used}")

    return {k: sorted(set(v)) for k, v in graph.items()}


def write_markdown(
    path: Path,
    repo: Path,
    keywords: list[str],
    relevant: list[dict],
    graph: dict,
):
    lines = []

    lines.append("# Code Map Report")
    lines.append("")
    lines.append(f"Repository: `{repo}`")
    lines.append(f"Keywords: `{', '.join(keywords)}`")
    lines.append("")

    lines.append("## Most relevant files")
    lines.append("")

    for item in relevant:
        lines.append(f"### `{item['path']}`")
        lines.append("")
        lines.append(f"- Language: `{item['language']}`")
        lines.append(f"- Lines: `{item['n_lines']}`")
        lines.append(f"- Relevance score: `{item['relevance_score']}`")

        if item["language"] == "fortran":
            if item["modules"]:
                lines.append(f"- Modules: `{', '.join(item['modules'])}`")
            if item["uses"]:
                lines.append(f"- Uses: `{', '.join(item['uses'])}`")
            if item["subroutines"]:
                lines.append(f"- Subroutines: `{', '.join(item['subroutines'])}`")
            if item["functions"]:
                lines.append(f"- Functions: `{', '.join(item['functions'])}`")
            if item["calls"]:
                preview = ", ".join(item["calls"][:30])
                lines.append(f"- Calls: `{preview}`")
        else:
            mentions = [
                name for name, value in item.get("mentions", {}).items() if value
            ]
            if mentions:
                lines.append(f"- Mentions: `{', '.join(mentions)}`")

        lines.append("")

    lines.append("## Local dependency graph for relevant Fortran files")
    lines.append("")

    relevant_paths = {item["path"] for item in relevant}

    for src in sorted(graph):
        if src not in relevant_paths:
            continue

        lines.append(f"### `{src}`")
        for target in graph[src]:
            lines.append(f"- uses `{target}`")
        lines.append("")

    path.write_text("\n".join(lines))


def main():
    parser = argparse.ArgumentParser(
        description="Map Fortran/Python/script structure for Held-Suarez or GEOS-style code."
    )
    parser.add_argument("--repo", required=True, help="Path to repo or code directory")
    parser.add_argument(
        "--keywords",
        nargs="+",
        default=["held_suarez", "held", "suarez"],
        help="Keywords for relevance ranking",
    )
    parser.add_argument(
        "--out-prefix",
        default="artifacts/code_map",
        help="Output prefix without extension",
    )
    parser.add_argument("--top", type=int, default=30)

    args = parser.parse_args()

    repo = Path(args.repo).expanduser().resolve()
    out_prefix = Path(args.out_prefix)
    out_prefix.parent.mkdir(parents=True, exist_ok=True)

    if not repo.exists():
        raise FileNotFoundError(f"Repo path does not exist: {repo}")

    items = []

    for src in iter_source_files(repo):
        if src.suffix in FORTRAN_EXTS:
            item = parse_fortran(src, repo)
        else:
            item = parse_text_file(src, repo)

        item["relevance_score"] = relevance_score(item, args.keywords)
        items.append(item)

    items_sorted = sorted(
        items,
        key=lambda x: x["relevance_score"],
        reverse=True,
    )

    relevant = [x for x in items_sorted if x["relevance_score"] > 0][: args.top]

    module_index = build_module_index(items)
    dependency_graph = build_dependency_graph(items, module_index)

    data = {
        "repo": str(repo),
        "keywords": args.keywords,
        "n_files_scanned": len(items),
        "n_relevant_files": len(relevant),
        "relevant_files": relevant,
        "module_index": module_index,
        "dependency_graph": dependency_graph,
    }

    json_path = out_prefix.with_suffix(".json")
    md_path = out_prefix.with_suffix(".md")

    json_path.write_text(json.dumps(data, indent=2))
    write_markdown(md_path, repo, args.keywords, relevant, dependency_graph)

    print(f"Scanned files: {len(items)}")
    print(f"Relevant files: {len(relevant)}")
    print(f"Wrote: {json_path}")
    print(f"Wrote: {md_path}")


if __name__ == "__main__":
    main()