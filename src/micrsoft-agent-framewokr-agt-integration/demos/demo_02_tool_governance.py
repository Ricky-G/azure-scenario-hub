"""Demo 2 — Outbound tool-call governance (zero-trust capability sandbox).

AGT intercepts every outbound tool call inside the MAF function-middleware pipeline
and evaluates it against a default-deny capability policy. Read-only FinOps tools
run; destructive/privileged and unknown tools are structurally prevented from
executing.

    python demos/demo_02_tool_governance.py
"""

from __future__ import annotations

import asyncio
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from agt_maf import display  # noqa: E402
from agt_maf.runtime import GovernanceRuntime  # noqa: E402
from agt_maf.scenarios import run_tool_governance  # noqa: E402


async def main() -> None:
    display.banner(
        "AGT × MAF — Outbound Tool-Call Governance",
        "Every tool call is intercepted and checked against an AGT capability policy",
    )
    runtime = GovernanceRuntime()
    await run_tool_governance(runtime)
    print()


if __name__ == "__main__":
    asyncio.run(main())
