"""Demo 3 — Argument-level governance.

AGT inspects the *arguments* of a tool call, not just its name. The transfer_budget
tool is allowed, but a transfer over $50,000 is escalated for human approval rather
than executed.

    python demos/demo_03_argument_inspection.py
"""

from __future__ import annotations

import asyncio
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from agt_maf import display  # noqa: E402
from agt_maf.runtime import GovernanceRuntime  # noqa: E402
from agt_maf.scenarios import run_argument_inspection  # noqa: E402


async def main() -> None:
    display.banner(
        "AGT × MAF — Argument-Level Governance",
        "AGT escalates risky tool arguments (large budget transfers) for human approval",
    )
    runtime = GovernanceRuntime()
    await run_argument_inspection(runtime)
    print()


if __name__ == "__main__":
    asyncio.run(main())
