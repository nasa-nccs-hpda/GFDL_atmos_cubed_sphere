from __future__ import annotations

from pathlib import Path
from typing import Any, Literal, TypedDict

import anthropic
from langgraph.graph import END, START, StateGraph

from prompts import DEBUG_PROMPT, FORTRAN_EXPLAIN_PROMPT, TRANSLATE_PROMPT
from tools import (
    build_dependency_summary,
    find_fortran_files,
    grep_keywords,
    load_config,
    read_api_key,
    read_text,
    run_held_suarez_case,
    simple_netcdf_validation,
    write_json,
    write_text,
)


class HSMigrationState(TypedDict, total=False):
    config: dict[str, Any]

    fortran_files: list[str]
    candidate_files: list[dict[str, Any]]
    selected_file: str

    dependency_summary: dict[str, Any]
    source_text: str
    source_summary: str

    translated_code: str
    translated_path: str

    build_result: dict[str, Any]
    run_result: dict[str, Any]
    validation_result: dict[str, Any]

    debug_iterations: int
    status: str
    error: str


def call_llm(prompt: str, config: dict[str, Any]) -> str:
    llm_cfg = config["llm"]["anthropic"]

    api_key = read_api_key(llm_cfg["api_key_file"])

    client = anthropic.Anthropic(api_key=api_key)

    message = client.messages.create(
        model=llm_cfg.get("model", "claude-sonnet-4-5"),
        max_tokens=llm_cfg.get("max_tokens", 8192),
        temperature=llm_cfg.get("temperature", 0.1),
        system=(
            "You are an expert scientific software engineer. "
            "You specialize in Fortran, C++, CUDA, Kokkos, MPI, "
            "numerical weather/climate models, and careful code migration. "
            "Preserve scientific meaning and numerical behavior."
        ),
        messages=[
            {
                "role": "user",
                "content": prompt,
            }
        ],
    )

    return "\n".join(
        block.text
        for block in message.content
        if block.type == "text"
    )


def load_config_node(state: HSMigrationState) -> HSMigrationState:
    config = load_config("config.yaml")

    return {
        "config": config,
        "debug_iterations": 0,
        "status": "config_loaded",
    }


def scan_repo_node(state: HSMigrationState) -> HSMigrationState:
    config = state["config"]

    files = find_fortran_files(config["repo_root"])
    candidates = grep_keywords(files, config["target_module_keywords"])

    candidates = sorted(
        candidates,
        key=lambda x: x["num_matches"],
        reverse=True,
    )

    write_json("artifacts/held_suarez_candidates.json", candidates)

    return {
        "fortran_files": files,
        "candidate_files": candidates,
        "status": "repo_scanned",
    }


def select_module_node(state: HSMigrationState) -> HSMigrationState:
    candidates = state["candidate_files"]

    if not candidates:
        return {
            "status": "failed",
            "error": "No Held-Suarez candidate Fortran files found.",
        }

    selected = candidates[0]["file"]

    return {
        "selected_file": selected,
        "status": "module_selected",
    }


def dependency_node(state: HSMigrationState) -> HSMigrationState:
    selected_file = state["selected_file"]

    summary = build_dependency_summary([selected_file])

    write_json("artifacts/dependency_summary.json", summary)

    return {
        "dependency_summary": summary,
        "status": "dependencies_built",
    }


def explain_node(state: HSMigrationState) -> HSMigrationState:
    source = read_text(state["selected_file"])

    prompt = FORTRAN_EXPLAIN_PROMPT.format(source=source)

    summary = call_llm(prompt, state["config"])

    write_text("artifacts/source_summary.md", summary)

    return {
        "source_text": source,
        "source_summary": summary,
        "status": "source_explained",
    }


def translate_node(state: HSMigrationState) -> HSMigrationState:
    config = state["config"]

    prompt = TRANSLATE_PROMPT.format(
        target=config.get("translation_target", "cpp"),
        source=state["source_text"],
    )

    code = call_llm(prompt, config)

    out_path = "artifacts/translated/held_suarez_module.cpp"
    write_text(out_path, code)

    return {
        "translated_code": code,
        "translated_path": out_path,
        "status": "translated",
    }


def build_node(state: HSMigrationState) -> HSMigrationState:
    translated_path = Path(state["translated_path"])

    if not translated_path.exists():
        return {
            "status": "build_failed",
            "error": f"Translated file not found: {translated_path}",
        }

    import subprocess

    cmd = [
        "g++",
        "-std=c++17",
        "-fsyntax-only",
        str(translated_path),
    ]

    p = subprocess.run(
        cmd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    result = {
        "cmd": " ".join(cmd),
        "returncode": p.returncode,
        "stdout": p.stdout,
        "stderr": p.stderr,
    }

    write_json("artifacts/build_result.json", result)

    if p.returncode != 0:
        return {
            "build_result": result,
            "status": "build_failed",
            "error": p.stderr,
        }

    return {
        "build_result": result,
        "status": "build_passed",
    }


def debug_node(state: HSMigrationState) -> HSMigrationState:
    iterations = state.get("debug_iterations", 0) + 1

    prompt = DEBUG_PROMPT.format(
        summary=state.get("source_summary", ""),
        code=state.get("translated_code", ""),
        error=state.get("error", ""),
    )

    patched_code = call_llm(prompt, state["config"])

    out_path = state["translated_path"]
    write_text(out_path, patched_code)

    return {
        "translated_code": patched_code,
        "debug_iterations": iterations,
        "status": "debugged",
    }


def run_model_node(state: HSMigrationState) -> HSMigrationState:
    result = run_held_suarez_case(state["config"])

    write_json("artifacts/run_result.json", result)

    if result["returncode"] != 0:
        return {
            "run_result": result,
            "status": "run_failed",
            "error": result["stderr"],
        }

    return {
        "run_result": result,
        "status": "run_passed",
    }


def validate_node(state: HSMigrationState) -> HSMigrationState:
    result = simple_netcdf_validation(state["config"]["data_root"])

    write_json("artifacts/validation_result.json", result)

    if not result["passed"]:
        return {
            "validation_result": result,
            "status": "validation_failed",
            "error": "No NetCDF output files found.",
        }

    return {
        "validation_result": result,
        "status": "validation_passed",
    }


def route_after_select(
    state: HSMigrationState,
) -> Literal["dependency", "end"]:
    if state["status"] == "failed":
        return "end"
    return "dependency"


def route_after_build(
    state: HSMigrationState,
) -> Literal["run_model", "debug", "end"]:
    if state["status"] == "build_passed":
        return "run_model"

    if state.get("debug_iterations", 0) >= state["config"].get(
        "max_debug_iterations", 3
    ):
        return "end"

    return "debug"


def route_after_run(
    state: HSMigrationState,
) -> Literal["validate", "debug", "end"]:
    if state["status"] == "run_passed":
        return "validate"

    if state.get("debug_iterations", 0) >= state["config"].get(
        "max_debug_iterations", 3
    ):
        return "end"

    return "debug"


def build_graph():
    graph = StateGraph(HSMigrationState)

    graph.add_node("load_config", load_config_node)
    graph.add_node("scan_repo", scan_repo_node)
    graph.add_node("select_module", select_module_node)
    graph.add_node("dependency", dependency_node)
    graph.add_node("explain", explain_node)
    graph.add_node("translate", translate_node)
    graph.add_node("build", build_node)
    graph.add_node("debug", debug_node)
    graph.add_node("run_model", run_model_node)
    graph.add_node("validate", validate_node)

    graph.add_edge(START, "load_config")
    graph.add_edge("load_config", "scan_repo")
    graph.add_edge("scan_repo", "select_module")

    graph.add_conditional_edges(
        "select_module",
        route_after_select,
        {
            "dependency": "dependency",
            "end": END,
        },
    )

    graph.add_edge("dependency", "explain")
    graph.add_edge("explain", "translate")
    graph.add_edge("translate", "build")

    graph.add_conditional_edges(
        "build",
        route_after_build,
        {
            "run_model": "run_model",
            "debug": "debug",
            "end": END,
        },
    )

    graph.add_edge("debug", "build")

    graph.add_conditional_edges(
        "run_model",
        route_after_run,
        {
            "validate": "validate",
            "debug": "debug",
            "end": END,
        },
    )

    graph.add_edge("validate", END)

    return graph.compile()


if __name__ == "__main__":
    app = build_graph()
    final_state = app.invoke({})

    print("\n===== FINAL STATE =====")
    for k, v in final_state.items():
        if k in {"source_text", "translated_code"}:
            print(f"{k}: <{len(v)} chars>")
        else:
            print(f"{k}: {v}")