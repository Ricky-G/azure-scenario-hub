"""Demo 5 — Build-time prompt hardening audit (AGT PromptDefense).

A static analysis of the agent's OWN system instructions across 12 OWASP-LLM-aligned
vectors. It contrasts a weak instruction string with a hardened one and shows the
grade improve. This runs at build/review time — it is not a per-request filter.

    python demos/demo_05_prompt_hardening_audit.py
"""

from __future__ import annotations

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from agt_maf import display  # noqa: E402
from agt_maf.scenarios import run_prompt_hardening_audit  # noqa: E402


def main() -> None:
    display.banner(
        "AGT × MAF — Prompt Hardening Audit",
        "AGT PromptDefense statically grades the agent's system instructions",
    )
    run_prompt_hardening_audit()
    print()


if __name__ == "__main__":
    main()
