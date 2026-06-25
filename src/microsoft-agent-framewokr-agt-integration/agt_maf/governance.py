"""AGT governance wired into the Microsoft Agent Framework middleware pipeline.

Three composable middleware layers turn an ordinary MAF agent into a governed one.
All three evaluate **real** Agent Governance Toolkit policies and write to a
tamper-evident audit log; none of them change how the agent or its tools are
written.

* :class:`PromptGovernanceMiddleware` (``AgentMiddleware``)
      Intercepts the outbound user prompt, runs deterministic static analysis +
      an AGT policy, and blocks the run before the model is ever called if the
      prompt is denied.

* :class:`ToolGovernanceMiddleware` (``FunctionMiddleware``)
      Intercepts every outbound tool call, evaluates an AGT capability policy over
      the tool name and its arguments, and prevents denied tools from executing.

* :class:`AuditTrailMiddleware` (``AgentMiddleware``)
      Anchors each run in the hash-chained audit log so the whole governed
      interaction can be replayed and integrity-checked afterwards.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import Any

from agent_framework import (
    AgentContext,
    AgentMiddleware,
    AgentResponse,
    Content,
    FunctionInvocationContext,
    FunctionMiddleware,
    Message,
    MiddlewareTermination,
)

from . import display
from .analyzers import StaticPromptAnalyzer, ToolCallAnalyzer
from .audit import AuditLog
from .model import GovernanceDecision

__all__ = [
    "GovernanceDecision",
    "PromptGovernanceMiddleware",
    "ToolGovernanceMiddleware",
    "AuditTrailMiddleware",
]


def _coerce_arguments(arguments: Any) -> dict[str, Any]:
    """Normalise MAF function arguments (mapping or pydantic model) to a dict."""
    if arguments is None:
        return {}
    if isinstance(arguments, dict):
        return dict(arguments)
    if hasattr(arguments, "model_dump"):
        try:
            return dict(arguments.model_dump())
        except (TypeError, ValueError):  # pragma: no cover - defensive
            pass
    try:
        return dict(arguments)
    except (TypeError, ValueError):  # pragma: no cover - defensive
        return {"value": arguments}


# ---------------------------------------------------------------------------
# Prompt governance (agent middleware)
# ---------------------------------------------------------------------------


class PromptGovernanceMiddleware(AgentMiddleware):
    """Govern the outbound prompt with AGT before the model is invoked."""

    def __init__(
        self,
        analyzer: StaticPromptAnalyzer,
        *,
        audit_log: AuditLog,
        agent_id: str,
        trace: bool = True,
    ) -> None:
        self._analyzer = analyzer
        self._audit = audit_log
        self._agent_id = agent_id
        self._trace = trace

    async def process(self, context: AgentContext, call_next: Callable[[], Awaitable[None]]) -> None:
        prompt = (context.messages[-1].text if context.messages else "") or ""
        decision, features = self._analyzer.analyze(prompt)

        self._audit.record(
            event_type="prompt_evaluation",
            layer="prompt",
            target=decision.target,
            action=decision.action,
            allowed=decision.allowed,
            rule=decision.rule,
            reason=decision.reason,
            agent_id=self._agent_id,
        )

        if self._trace:
            display.intercept("prompt → model", decision.target)
            display.info(
                "static analysis",
                f"pii={features.contains_pii} secret={features.contains_secret} "
                f"injection_markers={features.injection_markers or '[]'}",
            )
            _emit_outcome(decision)

        if not decision.allowed:
            blocked = AgentResponse(
                messages=[
                    Message(
                        role="assistant",
                        contents=[Content.from_text(f"🛡 Request blocked by AGT prompt policy: {decision.reason}")],
                    )
                ]
            )
            context.result = blocked
            raise MiddlewareTermination(result=blocked)

        await call_next()


# ---------------------------------------------------------------------------
# Tool governance (function middleware)
# ---------------------------------------------------------------------------


class ToolGovernanceMiddleware(FunctionMiddleware):
    """Govern every outbound tool call with an AGT capability policy."""

    def __init__(
        self,
        analyzer: ToolCallAnalyzer,
        *,
        audit_log: AuditLog,
        agent_id: str,
        trace: bool = True,
    ) -> None:
        self._analyzer = analyzer
        self._audit = audit_log
        self._agent_id = agent_id
        self._trace = trace

    async def process(
        self, context: FunctionInvocationContext, call_next: Callable[[], Awaitable[None]]
    ) -> None:
        tool_name = context.function.name
        arguments = _coerce_arguments(context.arguments)
        decision = self._analyzer.analyze(tool_name, arguments)

        self._audit.record(
            event_type="tool_evaluation",
            layer="tool",
            target=tool_name,
            action=decision.action,
            allowed=decision.allowed,
            rule=decision.rule,
            reason=decision.reason,
            agent_id=self._agent_id,
        )

        if self._trace:
            display.intercept("tool call", tool_name)
            display.info("arguments", str(arguments) if arguments else "{}")
            _emit_outcome(decision)

        if decision.allowed:
            await call_next()
            if self._trace:
                display.note(f"tool result → {_short(context.result)}")
            return

        # Denied or escalated: the tool must not execute. We feed a governance
        # message back as the tool result (instead of raising) so the agent can
        # still produce a graceful final answer explaining what happened.
        marker = "⚠️ ESCALATED" if decision.escalated else "⛔ DENIED"
        context.result = f"{marker} by AGT capability policy: {decision.reason}"


# ---------------------------------------------------------------------------
# Audit trail (agent middleware)
# ---------------------------------------------------------------------------


class AuditTrailMiddleware(AgentMiddleware):
    """Anchor each governed run as a record in the hash-chained audit log."""

    def __init__(self, *, audit_log: AuditLog, agent_id: str) -> None:
        self._audit = audit_log
        self._agent_id = agent_id

    async def process(self, context: AgentContext, call_next: Callable[[], Awaitable[None]]) -> None:
        prompt = (context.messages[-1].text if context.messages else "") or ""
        summary = (prompt[:57] + "…") if len(prompt) > 58 else prompt
        self._audit.record(
            event_type="agent_run",
            layer="run",
            target=summary,
            action="audit",
            allowed=True,
            rule=None,
            reason="Governed agent run started.",
            agent_id=self._agent_id,
        )
        await call_next()


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def _emit_outcome(decision: GovernanceDecision) -> None:
    detail = f"matched '{decision.rule}' — {decision.reason}" if decision.rule else decision.reason
    if decision.escalated:
        display.escalate(detail)
    elif decision.allowed:
        display.allowed(detail)
    else:
        display.denied(detail)


def _short(result: Any, limit: int = 90) -> str:
    text = ""
    if isinstance(result, list):
        for item in result:
            content_text = getattr(item, "text", None)
            if content_text:
                text = content_text
                break
            result_value = getattr(item, "result", None)
            if result_value is not None:
                text = str(result_value)
                break
        else:
            text = str(result)
    else:
        text = str(result)
    text = text.replace("\n", " ")
    return (text[:limit] + "…") if len(text) > limit else text
