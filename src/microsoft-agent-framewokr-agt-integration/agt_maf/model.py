"""Shared, dependency-light data types used across the governance layers."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

# The exact phrase the Agent Governance Toolkit uses to signal "allowed only with
# human approval". We follow AGT's own policy-as-code convention: an escalation is
# a *denied* decision whose reason contains this marker.
ESCALATION_MARKER = "requires human approval"


@dataclass
class GovernanceDecision:
    """A normalized governance decision produced by an AGT policy evaluation.

    This wraps AGT's native ``PolicyDecision`` into a small, display-friendly shape
    that is consistent across the prompt layer and the tool layer.
    """

    layer: str  # "prompt" or "tool"
    target: str  # prompt summary, or the tool name
    allowed: bool
    action: str  # "allow" | "deny" | "escalate" | "audit"
    rule: str | None
    reason: str
    evaluator: str = "AGT PolicyEvaluator"
    features: dict[str, Any] = field(default_factory=dict)

    @property
    def escalated(self) -> bool:
        return self.action == "escalate"

    @classmethod
    def from_policy_decision(
        cls,
        decision: Any,
        *,
        layer: str,
        target: str,
        features: dict[str, Any] | None = None,
    ) -> "GovernanceDecision":
        """Map an AGT ``PolicyDecision`` onto a :class:`GovernanceDecision`.

        AGT has no first-class "approval" action, so — following AGT's own
        policy-as-code tutorials — an escalation is modelled as a denied decision
        whose ``reason`` contains :data:`ESCALATION_MARKER`.
        """
        reason = decision.reason or ""
        if decision.allowed:
            action = "allow"
        elif ESCALATION_MARKER in reason.lower():
            action = "escalate"
        else:
            action = "deny"
        return cls(
            layer=layer,
            target=target,
            allowed=bool(decision.allowed),
            action=action,
            rule=getattr(decision, "matched_rule", None),
            reason=reason or "No rule matched; default action applied.",
            features=features or {},
        )
