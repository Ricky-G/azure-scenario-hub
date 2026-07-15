"""Deterministic static analysis backed by the Agent Governance Toolkit (AGT).

Two analyzers live here:

* :class:`StaticPromptAnalyzer` — extracts deterministic features from an outbound
  prompt (PII, secrets, prompt-injection signatures) and evaluates them with a real
  AGT :class:`~agent_os.policies.PolicyEvaluator`. This is the analyzer the prompt
  governance middleware uses on every user turn.

* :class:`ToolCallAnalyzer` — evaluates an outbound tool call (the tool name plus its
  flattened arguments) with a real AGT ``PolicyEvaluator``. This is the analyzer the
  tool governance middleware uses on every tool call.

* :class:`PromptHardeningAuditor` — a *build-time* static analysis that grades an
  agent's **system instructions** for prompt-injection resistance across AGT's
  12-vector PromptDefense model (OWASP LLM Top-10 aligned). Use this to check that
  your agent's own instructions are hardened — it is not a per-request attack filter.

Everything here is deterministic: the same input always yields the same decision,
which is exactly what makes it a usable control surface for autonomous agents.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from agent_os.policies import PolicyEvaluator
from agent_os.policies.schema import PolicyDocument

from .model import GovernanceDecision

# ---------------------------------------------------------------------------
# Deterministic feature extraction for prompts
# ---------------------------------------------------------------------------

# Well-known sensitive-data signatures.
_SSN_RE = re.compile(r"\b\d{3}-\d{2}-\d{4}\b")
_CREDIT_CARD_RE = re.compile(r"\b(?:\d[ -]?){15,16}\b")
_SECRET_RE = re.compile(
    r"(?i)\b("
    r"AKIA[0-9A-Z]{16}"  # AWS access key id
    r"|sk-[A-Za-z0-9]{20,}"  # OpenAI-style secret key
    r"|ghp_[A-Za-z0-9]{20,}"  # GitHub PAT
    r"|xox[baprs]-[A-Za-z0-9-]{10,}"  # Slack token
    r"|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"  # JWT
    r")\b"
)
_SECRET_KEYWORD_RE = re.compile(
    r"(?i)\b(password|passwd|api[_ -]?key|secret[_ -]?key|connection[_ -]?string|bearer\s+token)\b"
)

# Prompt-injection / jailbreak signatures (deterministic phrase list).
_INJECTION_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"(?i)ignore (all |any |the )?(previous|prior|above) instructions"),
    re.compile(r"(?i)disregard (the|all|your) (above|previous|prior|system)"),
    re.compile(r"(?i)reveal (your|the) (system|developer) prompt"),
    re.compile(r"(?i)you are now (in )?(developer|dan|jailbreak) mode"),
    re.compile(r"(?i)\bjailbreak\b"),
    re.compile(r"(?i)exfiltrate|leak (the )?(data|secrets|credentials)"),
    re.compile(r"(?i)pretend (to be|you are)|act as (an?|the) (unrestricted|uncensored)"),
)


@dataclass
class PromptFeatures:
    """Deterministic signals extracted from a prompt by static analysis."""

    prompt_length: int
    contains_pii: bool
    contains_secret: bool
    injection_marker_count: int
    injection_markers: list[str]

    def as_context(self, prompt: str) -> dict[str, Any]:
        """Flatten into the context dict an AGT policy evaluates against."""
        return {
            "input_text": prompt,
            "prompt_length": self.prompt_length,
            "contains_pii": self.contains_pii,
            "contains_secret": self.contains_secret,
            "injection_marker_count": self.injection_marker_count,
        }


def extract_prompt_features(prompt: str) -> PromptFeatures:
    """Run deterministic static analysis over a prompt and return its signals."""
    markers: list[str] = []
    for pat in _INJECTION_PATTERNS:
        m = pat.search(prompt)
        if m:
            markers.append(m.group(0))
    contains_pii = bool(_SSN_RE.search(prompt) or _CREDIT_CARD_RE.search(prompt))
    contains_secret = bool(_SECRET_RE.search(prompt) or _SECRET_KEYWORD_RE.search(prompt))
    return PromptFeatures(
        prompt_length=len(prompt),
        contains_pii=contains_pii,
        contains_secret=contains_secret,
        injection_marker_count=len(markers),
        injection_markers=markers,
    )


# ---------------------------------------------------------------------------
# Prompt analyzer (AGT PolicyEvaluator over the prompt + its derived features)
# ---------------------------------------------------------------------------


class StaticPromptAnalyzer:
    """Govern an outbound prompt with deterministic features + a real AGT policy."""

    def __init__(self, policy: str | Path | PolicyDocument | PolicyEvaluator) -> None:
        self.evaluator = _as_evaluator(policy)

    def analyze(self, prompt: str) -> tuple[GovernanceDecision, PromptFeatures]:
        features = extract_prompt_features(prompt)
        decision = self.evaluator.evaluate(features.as_context(prompt))
        summary = (prompt[:57] + "…") if len(prompt) > 58 else prompt
        gov = GovernanceDecision.from_policy_decision(
            decision,
            layer="prompt",
            target=summary,
            features={
                "contains_pii": features.contains_pii,
                "contains_secret": features.contains_secret,
                "injection_markers": features.injection_markers,
            },
        )
        return gov, features


# ---------------------------------------------------------------------------
# Tool-call analyzer (AGT PolicyEvaluator over tool name + flattened arguments)
# ---------------------------------------------------------------------------


class ToolCallAnalyzer:
    """Govern an outbound tool call with a real AGT policy."""

    def __init__(self, policy: str | Path | PolicyDocument | PolicyEvaluator) -> None:
        self.evaluator = _as_evaluator(policy)

    def analyze(self, tool_name: str, arguments: dict[str, Any]) -> GovernanceDecision:
        context: dict[str, Any] = {"tool_name": tool_name}
        # Flatten the arguments into the evaluation context so a single, agent-level
        # policy can reason about tool-call ARGUMENTS — not just tool names. Each
        # argument is exposed two ways:
        #
        #   * flat        e.g. ``amount``                 -> a rule applies to *any*
        #                                                    tool that takes ``amount``
        #   * namespaced  e.g. ``transfer_budget.amount`` -> a rule applies to *only*
        #                                                    that tool's argument
        #
        # The namespaced key is what makes precise, per-tool argument boundaries
        # possible from one central policy (the evaluator does a flat key lookup, so
        # ``transfer_budget.amount`` is just a literal context key it can match on).
        for key, value in (arguments or {}).items():
            context[key] = value
            context[f"{tool_name}.{key}"] = value
        decision = self.evaluator.evaluate(context)
        return GovernanceDecision.from_policy_decision(
            decision,
            layer="tool",
            target=tool_name,
            features={"arguments": dict(arguments or {})},
        )


# ---------------------------------------------------------------------------
# Build-time prompt hardening audit (AGT PromptDefense — 12 OWASP vectors)
# ---------------------------------------------------------------------------


@dataclass
class HardeningFinding:
    vector_id: str
    name: str
    owasp: str
    defended: bool
    severity: str
    evidence: str


@dataclass
class HardeningReport:
    grade: str
    score: int
    findings: list[HardeningFinding]

    @property
    def defended_count(self) -> int:
        return sum(1 for f in self.findings if f.defended)

    @property
    def gaps(self) -> list[HardeningFinding]:
        return [f for f in self.findings if not f.defended]


class PromptHardeningAuditor:
    """Statically grade an agent's *system instructions* for injection resistance.

    This wraps the Agent Governance Toolkit's ``PromptDefenseEvaluator`` (shipped in
    the ``agent_compliance`` package). It scans text for defensive guardrail patterns
    across 12 OWASP-LLM-aligned vectors and assigns a letter grade. Use it at build
    time to confirm an agent's own instructions are hardened — higher grade = more
    injection-resistant instructions.
    """

    def __init__(self, min_grade: str = "B") -> None:
        from agent_compliance import PromptDefenseConfig, PromptDefenseEvaluator

        self._evaluator = PromptDefenseEvaluator(PromptDefenseConfig(min_grade=min_grade))
        self.min_grade = min_grade

    def audit(self, instructions: str) -> HardeningReport:
        report = self._evaluator.evaluate(instructions)
        findings = [
            HardeningFinding(
                vector_id=f.vector_id,
                name=f.name,
                owasp=f.owasp,
                defended=f.defended,
                severity=f.severity,
                evidence=f.evidence,
            )
            for f in report.findings
        ]
        return HardeningReport(grade=report.grade, score=report.score, findings=findings)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def _as_evaluator(policy: str | Path | PolicyDocument | PolicyEvaluator) -> PolicyEvaluator:
    if isinstance(policy, PolicyEvaluator):
        return policy
    if isinstance(policy, PolicyDocument):
        return PolicyEvaluator(policies=[policy])
    # Load the YAML ourselves as UTF-8 and validate via the pydantic model. This is
    # equivalent to ``PolicyDocument.from_yaml`` but encoding-correct on every OS:
    # some installed AGT builds open policy files with the platform default encoding
    # (cp1252 on Windows), which fails on any non-ASCII byte in the file.
    import yaml

    data = yaml.safe_load(Path(policy).read_text(encoding="utf-8"))
    doc = PolicyDocument.model_validate(data)
    return PolicyEvaluator(policies=[doc])
