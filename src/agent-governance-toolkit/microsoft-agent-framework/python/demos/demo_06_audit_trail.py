"""Demo 6 — Tamper-evident audit trail.

Runs a few governed interactions to populate the hash-chained audit log, prints the
trail, verifies its integrity, and then demonstrates that editing any earlier record
breaks the chain (so tampering is detectable).

    python demos/demo_06_audit_trail.py
"""

from __future__ import annotations

import asyncio
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from agt_maf import display  # noqa: E402
from agt_maf.runtime import GovernanceRuntime  # noqa: E402
from agt_maf.scenarios import (  # noqa: E402
    run_argument_inspection,
    run_tool_governance,
    show_audit_trail,
)


async def main() -> None:
    display.banner(
        "AGT × MAF — Tamper-Evident Audit Trail",
        "Every governed decision is recorded in a hash-chained, verifiable audit log",
    )
    runtime = GovernanceRuntime()
    # Generate some governed activity to fill the audit log.
    await run_tool_governance(runtime)
    await run_argument_inspection(runtime)
    show_audit_trail(runtime.audit_log, demonstrate_tamper=True)
    print()


if __name__ == "__main__":
    asyncio.run(main())
