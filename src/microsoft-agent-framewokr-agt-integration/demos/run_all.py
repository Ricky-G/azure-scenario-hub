"""Run the complete AGT × MAF governance showcase end-to-end.

All six acts run in sequence. Acts 1-4 and 6 share one GovernanceRuntime (and one
audit chain), so the final audit trail shows every governed decision from the whole
session.

    python demos/run_all.py
"""

from __future__ import annotations

import asyncio
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from agt_maf import display  # noqa: E402
from agt_maf.runtime import GovernanceRuntime  # noqa: E402
from agt_maf.scenarios import (  # noqa: E402
    explain_tool_argument_governance,
    run_argument_inspection,
    run_prompt_governance,
    run_prompt_hardening_audit,
    run_tool_governance,
    run_workflow_governance,
    show_audit_trail,
)


async def main() -> None:
    display.banner(
        "Microsoft Agent Framework × Agent Governance Toolkit",
        "A governed Contoso FinOps assistant — prompts and tool calls intercepted by AGT",
    )
    runtime = GovernanceRuntime()

    await run_prompt_governance(runtime)
    await run_tool_governance(runtime)
    explain_tool_argument_governance()
    await run_argument_inspection(runtime)
    await run_workflow_governance(runtime)
    run_prompt_hardening_audit()
    show_audit_trail(runtime.audit_log, demonstrate_tamper=True)

    print()
    display.section("Summary")
    display.note(
        "Every prompt and every tool call above was evaluated by a real AGT policy inside "
        "the real MAF middleware pipeline. Swap ScriptedChatClient for a live model and the "
        "governance layer does not change."
    )
    print()


if __name__ == "__main__":
    asyncio.run(main())
