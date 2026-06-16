"""Demo 0 — START HERE: govern tool-call ARGUMENTS at the agent level.

This is the direct answer to the most common Agent-Governance-Toolkit-on-MAF
question:

    "Is there a way to inject policy at an agent level that will govern tool-call
     args? From what I can tell, agent policy only lets you disable tools at the
     tool level, and you have to provide individual @tool governance to go do
     that next level."

Yes. You attach ONE FunctionMiddleware at the agent level. It fires on every tool
call and sees the tool name AND the argument values, and evaluates them against a
single AGT policy. The tools themselves contain no governance code.

    python demos/demo_00_tool_argument_boundaries.py
"""

from __future__ import annotations

import asyncio
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from agt_maf import display  # noqa: E402
from agt_maf.runtime import GovernanceRuntime  # noqa: E402
from agt_maf.scenarios import explain_tool_argument_governance, run_argument_inspection  # noqa: E402


async def main() -> None:
    display.banner(
        "AGT × MAF — Govern tool-call ARGUMENTS at the agent level",
        "One agent-attached policy checks every tool call's argument values — no per-@tool code",
    )
    explain_tool_argument_governance()
    runtime = GovernanceRuntime()
    await run_argument_inspection(runtime)

    print()
    display.section("What just happened")
    display.note(
        "Every call above went through ONE ToolGovernanceMiddleware attached to the agent. "
        "Allowed / escalated / denied was decided purely from the argument VALUES, by the "
        "rules in policies/tool-governance.yaml — not by any code inside the tools."
    )
    print()


if __name__ == "__main__":
    asyncio.run(main())
