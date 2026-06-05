FORTRAN_EXPLAIN_PROMPT = """
You are analyzing a Fortran atmospheric model module.

Explain:
1. What this file/module does.
2. Main subroutines/functions.
3. Important inputs/outputs.
4. Physical meaning.
5. Numerical patterns relevant for GPU porting.
6. Risks in translating this code to C++/CUDA/Kokkos.

Fortran source:
{source}
"""

TRANSLATE_PROMPT = """
Translate the following Fortran module or routine into clean {target}.

Rules:
- Preserve numerical behavior.
- Do not invent missing variables.
- Add comments where array shapes or physical meaning are unclear.
- Prefer explicit loops.
- Keep a close one-to-one mapping first.
- Do not over-optimize yet.

Fortran source:
{source}
"""

DEBUG_PROMPT = """
The translated code failed to build or run.

Original source summary:
{summary}

Generated code:
{code}

Build/test error:
{error}

Suggest a minimal patch. Return only corrected code.
"""