"""
agt_maf — Governed agents with Microsoft Agent Framework (MAF) + Agent Governance Toolkit (AGT).

This package shows how to wrap **real** MAF agents and workflows with **real** AGT
governance so that:

* every outbound **prompt** is intercepted and evaluated by an AGT policy
  (deterministic static analysis: PII, secrets, prompt-injection signatures), and
* every outbound **tool call** is intercepted and evaluated by an AGT policy
  (capability allow/deny lists plus argument-level thresholds),

before anything reaches a model or executes a tool. Denied actions are not
"unlikely" — they are structurally impossible, because the deny happens in
deterministic application code, not inside the model's prompt.

Public building blocks:

* :class:`~agt_maf.governance.PromptGovernanceMiddleware` — agent middleware that
  governs the outbound user prompt.
* :class:`~agt_maf.governance.ToolGovernanceMiddleware` — function middleware that
  governs every outbound tool call.
* :class:`~agt_maf.governance.AuditTrailMiddleware` — agent middleware that records a
  tamper-evident audit trail of every governed run.
* :func:`~agt_maf.runtime.build_governed_agent` — wires the above onto a real MAF agent.
"""

from __future__ import annotations

# Silence the framework's first-run "experimental feature" notices so the demo
# trace stays clean. Installed before any agent_framework import below.
import warnings as _warnings

_warnings.filterwarnings("ignore", message=r".*is experimental.*")

from .analyzers import PromptHardeningAuditor, StaticPromptAnalyzer
from .audit import AuditLog, AuditRecord
from .governance import (
    AuditTrailMiddleware,
    GovernanceDecision,
    PromptGovernanceMiddleware,
    ToolGovernanceMiddleware,
)
from .runtime import GovernanceRuntime, build_governed_agent, build_governed_workflow
from .scripted_client import ScriptedChatClient, text, tool_call

__all__ = [
    "StaticPromptAnalyzer",
    "PromptHardeningAuditor",
    "AuditLog",
    "AuditRecord",
    "GovernanceDecision",
    "PromptGovernanceMiddleware",
    "ToolGovernanceMiddleware",
    "AuditTrailMiddleware",
    "GovernanceRuntime",
    "build_governed_agent",
    "build_governed_workflow",
    "ScriptedChatClient",
    "tool_call",
    "text",
]
