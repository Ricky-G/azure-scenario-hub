"""A tiny tamper-evident audit log (hash-chained) for governed agent runs.

The Agent Governance Toolkit ships a Merkle-chained audit log in its full stack.
For a self-contained demo we implement the same *idea* in a few lines: every
record is hashed together with the previous record's hash, so any later edit to
an earlier record breaks the chain. :meth:`AuditLog.verify_integrity` walks the
chain and reports whether it is still intact.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass
class AuditRecord:
    """A single governed event in the audit trail."""

    event_type: str  # "prompt_evaluation" | "tool_evaluation" | "agent_run"
    layer: str  # which governance layer produced it (prompt / tool / run)
    target: str  # the prompt summary or the tool name
    action: str  # allow | deny | escalate | audit
    allowed: bool
    rule: str | None
    reason: str
    agent_id: str
    timestamp: str = field(default_factory=_utcnow)
    prev_hash: str = ""
    this_hash: str = ""

    def _payload(self) -> dict[str, Any]:
        data = asdict(self)
        data.pop("this_hash", None)
        return data

    def compute_hash(self) -> str:
        blob = json.dumps(self._payload(), sort_keys=True).encode("utf-8")
        return hashlib.sha256(blob).hexdigest()


class AuditLog:
    """An append-only, hash-chained list of :class:`AuditRecord`."""

    def __init__(self) -> None:
        self._records: list[AuditRecord] = []

    def record(
        self,
        *,
        event_type: str,
        layer: str,
        target: str,
        action: str,
        allowed: bool,
        rule: str | None,
        reason: str,
        agent_id: str,
    ) -> AuditRecord:
        prev_hash = self._records[-1].this_hash if self._records else "GENESIS"
        rec = AuditRecord(
            event_type=event_type,
            layer=layer,
            target=target,
            action=action,
            allowed=allowed,
            rule=rule,
            reason=reason,
            agent_id=agent_id,
            prev_hash=prev_hash,
        )
        rec.this_hash = rec.compute_hash()
        self._records.append(rec)
        return rec

    def __len__(self) -> int:
        return len(self._records)

    def __iter__(self):
        return iter(self._records)

    @property
    def records(self) -> list[AuditRecord]:
        return list(self._records)

    def verify_integrity(self) -> tuple[bool, str | None]:
        """Walk the chain and confirm no record has been altered or reordered."""
        prev = "GENESIS"
        for i, rec in enumerate(self._records):
            if rec.prev_hash != prev:
                return False, f"record #{i} prev_hash mismatch"
            if rec.compute_hash() != rec.this_hash:
                return False, f"record #{i} content hash mismatch (tampered)"
            prev = rec.this_hash
        return True, None
