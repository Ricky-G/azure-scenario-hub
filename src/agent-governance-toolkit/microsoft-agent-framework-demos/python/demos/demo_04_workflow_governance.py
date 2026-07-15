"""Demo 4 — Governed multi-agent workflow.

The same AGT governance and a single shared audit chain apply across a sequential
MAF workflow of two agents. The first agent runs an allowed tool; the second agent's
attempt to tear down prod is denied by policy.

    python demos/demo_04_workflow_governance.py
"""

from __future__ import annotations

import asyncio
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from agt_maf import display  # noqa: E402
from agt_maf.runtime import GovernanceRuntime  # noqa: E402
from agt_maf.scenarios import run_workflow_governance, show_audit_trail  # noqa: E402


async def main() -> None:
    display.banner(
        "AGT × MAF — Governed Multi-Agent Workflow",
        "Governance and one shared audit chain span every agent in the workflow",
    )
    runtime = GovernanceRuntime()
    await run_workflow_governance(runtime)
    show_audit_trail(runtime.audit_log, demonstrate_tamper=False)
    print()


if __name__ == "__main__":
    asyncio.run(main())
