"""Demo 1 — Outbound prompt governance.

AGT intercepts every outbound prompt, runs deterministic static analysis (PII,
secrets, prompt-injection signatures), and blocks denied prompts before the model
is ever called.

    python demos/demo_01_prompt_governance.py
"""

from __future__ import annotations

import asyncio
import pathlib
import sys

# Make the agt_maf package importable when run as a standalone script.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from agt_maf import display  # noqa: E402
from agt_maf.runtime import GovernanceRuntime  # noqa: E402
from agt_maf.scenarios import run_prompt_governance  # noqa: E402


async def main() -> None:
    display.banner(
        "AGT × MAF — Outbound Prompt Governance",
        "Every prompt is statically analysed and governed by AGT before the model runs",
    )
    runtime = GovernanceRuntime()
    await run_prompt_governance(runtime)
    print()


if __name__ == "__main__":
    asyncio.run(main())
