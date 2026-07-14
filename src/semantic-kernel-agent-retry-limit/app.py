#!/usr/bin/env python3
"""Demonstrate deterministic retry limits around Semantic Kernel agents."""

from __future__ import annotations

import asyncio
import os
from collections.abc import Sequence
from dataclasses import dataclass
from enum import Enum
from typing import Protocol

from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv
from semantic_kernel.agents import ChatCompletionAgent
from semantic_kernel.connectors.ai.open_ai import AzureChatCompletion

MAX_ATTEMPTS = 3


class AgentClient(Protocol):
    async def get_response(self, messages: str) -> object: ...


class FlowState(Enum):
    INTENT_DETECTION = "intent_detection"
    AUTHENTICATION = "authentication"
    SUCCESS = "success"
    TERMINAL = "terminal"


@dataclass
class ConversationContext:
    state: FlowState = FlowState.INTENT_DETECTION
    failed_attempts: int = 0
    question_index: int = 0


class MockChallengeVerifier:
    """Deterministic placeholder for a real identity verification system."""

    def __init__(self) -> None:
        self.questions: Sequence[tuple[str, str]] = (
            ("What is 20 + 20?", "40"),
            ("What is 10 + 10?", "20"),
        )

    def current_question(self, index: int) -> str:
        return self.questions[index][0]

    def verify(self, answer: str, index: int) -> bool:
        return answer.strip().casefold() == self.questions[index][1].casefold()


def response_text(response: object) -> str:
    """Extract text from an AgentResponseItem without coupling to display formatting."""
    message = getattr(response, "message", response)
    content = getattr(message, "content", None)
    return str(content if content is not None else message).strip()


class RetryLimitOrchestrator:
    """Route between agents while owning all retry and terminal-state decisions."""

    def __init__(
        self,
        intent_agent: AgentClient,
        topic_guard_agent: AgentClient,
        verifier: MockChallengeVerifier | None = None,
    ) -> None:
        self.intent_agent = intent_agent
        self.topic_guard_agent = topic_guard_agent
        self.verifier = verifier or MockChallengeVerifier()
        self.context = ConversationContext()

    async def process(self, user_input: str) -> str:
        if self.context.state == FlowState.INTENT_DETECTION:
            return await self._detect_intent(user_input)
        if self.context.state == FlowState.AUTHENTICATION:
            return await self._authenticate(user_input)
        if self.context.state == FlowState.SUCCESS:
            return "The mock protected flow already completed successfully."
        return "This session has ended. Start a new process to try again."

    async def _detect_intent(self, user_input: str) -> str:
        classification = response_text(
            await self.intent_agent.get_response(messages=user_input)
        ).upper()
        if classification != "ACCOUNT_BALANCE":
            self.context.state = FlowState.TERMINAL
            return "This demo only handles the mock account-balance flow."

        self.context.state = FlowState.AUTHENTICATION
        return (
            "Starting the mock verification flow. "
            f"{self.verifier.current_question(self.context.question_index)}"
        )

    async def _authenticate(self, user_input: str) -> str:
        topic_classification = response_text(
            await self.topic_guard_agent.get_response(messages=user_input)
        ).upper()
        if topic_classification == "CHANGING_TOPIC":
            return self._record_failure("Topic changes do not bypass the current step.")

        if not self.verifier.verify(user_input, self.context.question_index):
            return self._record_failure("That answer is incorrect.")

        self.context.question_index += 1
        self.context.failed_attempts = 0
        if self.context.question_index == len(self.verifier.questions):
            self.context.state = FlowState.SUCCESS
            return "Mock verification completed successfully."

        return (
            "Correct. Next question: "
            f"{self.verifier.current_question(self.context.question_index)}"
        )

    def _record_failure(self, reason: str) -> str:
        self.context.failed_attempts += 1
        if self.context.failed_attempts >= MAX_ATTEMPTS:
            self.context.state = FlowState.TERMINAL
            return f"{reason} Maximum attempts reached; the session is closed."

        remaining = MAX_ATTEMPTS - self.context.failed_attempts
        question = self.verifier.current_question(self.context.question_index)
        return f"{reason} {question} Attempts remaining: {remaining}."


def required_setting(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Environment variable {name} is required.")
    return value


def create_agents() -> tuple[ChatCompletionAgent, ChatCompletionAgent, DefaultAzureCredential | None]:
    """Create specialized Semantic Kernel agents over one Azure chat service."""
    api_key = os.getenv("AZURE_OPENAI_API_KEY", "").strip() or None
    credential = None if api_key else DefaultAzureCredential()
    service = AzureChatCompletion(
        deployment_name=required_setting("AZURE_OPENAI_DEPLOYMENT_NAME"),
        endpoint=required_setting("AZURE_OPENAI_ENDPOINT"),
        api_version=required_setting("AZURE_OPENAI_API_VERSION"),
        api_key=api_key,
        credential=credential,
    )

    intent_agent = ChatCompletionAgent(
        service=service,
        name="IntentRouter",
        instructions=(
            "Classify the user's request. Return exactly ACCOUNT_BALANCE when the user "
            "asks to view an account balance or account details. Return exactly OTHER "
            "for every other request. Do not include punctuation or explanation."
        ),
    )
    topic_guard_agent = ChatCompletionAgent(
        service=service,
        name="TopicGuard",
        instructions=(
            "The user is answering a short arithmetic verification question. Return "
            "exactly ANSWERING when the message attempts an answer, even if wrong. "
            "Return exactly CHANGING_TOPIC when it avoids the question or asks for a "
            "different task. Do not include punctuation or explanation."
        ),
    )
    return intent_agent, topic_guard_agent, credential


async def run_demo() -> None:
    intent_agent, topic_guard_agent, credential = create_agents()
    orchestrator = RetryLimitOrchestrator(intent_agent, topic_guard_agent)

    print("Semantic Kernel retry-limit demo")
    print("This uses mock math questions. It is not an authentication design.")
    print("Ask to check an account balance, or type quit to exit.")

    try:
        while orchestrator.context.state not in {FlowState.SUCCESS, FlowState.TERMINAL}:
            user_input = (await asyncio.to_thread(input, "\nYou: ")).strip()
            if user_input.casefold() in {"quit", "exit", "bye"}:
                break
            response = await orchestrator.process(user_input)
            print(f"Assistant: {response}")
    finally:
        if credential:
            credential.close()


def main() -> None:
    load_dotenv()
    try:
        asyncio.run(run_demo())
    except KeyboardInterrupt:
        print("\nDemo stopped.")


if __name__ == "__main__":
    main()