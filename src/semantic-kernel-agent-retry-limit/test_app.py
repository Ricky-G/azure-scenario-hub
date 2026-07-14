from __future__ import annotations

import unittest

from app import FlowState, RetryLimitOrchestrator


class ScriptedAgent:
    def __init__(self, responses: list[str]) -> None:
        self.responses = iter(responses)

    async def get_response(self, messages: str) -> str:
        del messages
        return next(self.responses)


class RetryLimitTests(unittest.IsolatedAsyncioTestCase):
    async def test_third_failed_attempt_closes_session(self) -> None:
        orchestrator = RetryLimitOrchestrator(
            ScriptedAgent(["ACCOUNT_BALANCE"]),
            ScriptedAgent(["ANSWERING", "ANSWERING", "ANSWERING"]),
        )

        await orchestrator.process("Check my balance")
        await orchestrator.process("wrong")
        await orchestrator.process("still wrong")
        result = await orchestrator.process("wrong again")

        self.assertEqual(FlowState.TERMINAL, orchestrator.context.state)
        self.assertIn("Maximum attempts reached", result)

    async def test_success_resets_attempts_between_questions(self) -> None:
        orchestrator = RetryLimitOrchestrator(
            ScriptedAgent(["ACCOUNT_BALANCE"]),
            ScriptedAgent(["ANSWERING", "ANSWERING", "ANSWERING"]),
        )

        await orchestrator.process("Check my balance")
        await orchestrator.process("wrong")
        next_question = await orchestrator.process("40")
        result = await orchestrator.process("20")

        self.assertIn("Next question", next_question)
        self.assertEqual(FlowState.SUCCESS, orchestrator.context.state)
        self.assertEqual(0, orchestrator.context.failed_attempts)
        self.assertIn("completed successfully", result)

    async def test_topic_change_consumes_an_attempt(self) -> None:
        orchestrator = RetryLimitOrchestrator(
            ScriptedAgent(["ACCOUNT_BALANCE"]),
            ScriptedAgent(["CHANGING_TOPIC"]),
        )

        await orchestrator.process("Check my balance")
        result = await orchestrator.process("Do something else")

        self.assertEqual(1, orchestrator.context.failed_attempts)
        self.assertIn("Attempts remaining: 2", result)


if __name__ == "__main__":
    unittest.main()