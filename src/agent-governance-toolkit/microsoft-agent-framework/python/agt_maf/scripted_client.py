"""A deterministic, offline MAF chat client for reproducible demos.

The demos must run identically for every developer, with no API keys and no
network calls — while still exercising the **real** MAF agent pipeline so that
function middleware genuinely fires on tool calls. :class:`ScriptedChatClient` is
a real ``agent_framework`` chat client that replays a fixed script:

    ScriptedChatClient([
        tool_call("get_cost_summary", {"scope": "subscription"}),
        text("Your month-to-date spend is $4,210."),
    ])

On the first model turn it emits the tool call (which flows through the tool
governance middleware and, if allowed, executes the real tool); on the next turn
it emits the final assistant text. Swap this for ``OpenAIChatClient`` /
``AzureOpenAIChatClient`` / ``FoundryChatClient`` to run the very same governed
agent against a live model — the governance layer does not change.
"""

from __future__ import annotations

import json
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any

from agent_framework import BaseChatClient, ChatResponse, Content, Message
from agent_framework._tools import FunctionInvocationLayer


@dataclass
class _ToolCallStep:
    name: str
    arguments: dict[str, Any]


@dataclass
class _TextStep:
    text: str


def tool_call(name: str, arguments: dict[str, Any] | None = None) -> _ToolCallStep:
    """A scripted step where the model asks to call ``name`` with ``arguments``."""
    return _ToolCallStep(name=name, arguments=arguments or {})


def text(message: str) -> _TextStep:
    """A scripted step where the model returns final assistant text."""
    return _TextStep(text=message)


class ScriptedChatClient(FunctionInvocationLayer[Any], BaseChatClient[Any]):
    """A real MAF chat client that deterministically replays a fixed script.

    It participates in the framework's function-invocation loop, so tool calls it
    emits are routed through any registered function middleware (this is how AGT
    tool governance gets a chance to allow/deny each call).
    """

    OTEL_PROVIDER_NAME = "ScriptedChatClient"

    def __init__(self, script: Sequence[_ToolCallStep | _TextStep]) -> None:
        FunctionInvocationLayer.__init__(self)
        BaseChatClient.__init__(self)
        self._script: list[_ToolCallStep | _TextStep] = list(script)
        self._index = 0

    def _inner_get_response(
        self,
        *,
        messages: Sequence[Message],
        stream: bool,
        options: Any,
        **kwargs: Any,
    ):
        if stream:  # pragma: no cover - the demos use non-streaming runs
            raise NotImplementedError("ScriptedChatClient is non-streaming for the demo.")

        async def _get_response() -> ChatResponse:
            step = self._next_step()
            if isinstance(step, _ToolCallStep):
                content = Content.from_function_call(
                    call_id=f"call_{self._index}",
                    name=step.name,
                    arguments=json.dumps(step.arguments),
                )
            else:
                content = Content.from_text(step.text)
            return ChatResponse(messages=[Message(role="assistant", contents=[content])])

        return _get_response()

    def _next_step(self) -> _ToolCallStep | _TextStep:
        if self._index < len(self._script):
            step = self._script[self._index]
        else:
            # Defensive fallback so the agent always terminates cleanly.
            step = _TextStep(text="Done.")
        self._index += 1
        return step
