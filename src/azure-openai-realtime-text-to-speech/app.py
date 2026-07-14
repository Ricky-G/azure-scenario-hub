#!/usr/bin/env python3
"""Send text to Azure OpenAI Realtime and play the audio response."""

from __future__ import annotations

import asyncio
import base64
import os

import sounddevice as sd
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv
from openai import AsyncOpenAI

SAMPLE_RATE = 24_000
AZURE_OPENAI_SCOPE = "https://ai.azure.com/.default"


def required_setting(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Environment variable {name} is required.")
    return value


def websocket_base_url(endpoint: str) -> str:
    """Build the GA Azure OpenAI WebSocket base URL."""
    normalized = endpoint.strip().rstrip("/")
    if normalized.lower().startswith("https://"):
        normalized = "wss://" + normalized[8:]
    elif not normalized.lower().startswith("wss://"):
        raise ValueError("AZURE_OPENAI_ENDPOINT must start with https:// or wss://.")
    return f"{normalized}/openai/v1"


def authentication_token() -> tuple[str, DefaultAzureCredential | None]:
    """Prefer Entra ID and fall back to a resource key when explicitly provided."""
    api_key = os.getenv("AZURE_OPENAI_API_KEY", "").strip()
    if api_key:
        return api_key, None

    credential = DefaultAzureCredential()
    token = credential.get_token(AZURE_OPENAI_SCOPE)
    return token.token, credential


async def play_response(connection: object, output_stream: sd.RawOutputStream) -> None:
    """Receive one response, play its PCM audio, and print its transcript."""
    async for event in connection:  # type: ignore[attr-defined]
        if event.type == "response.output_audio.delta":
            output_stream.write(base64.b64decode(event.delta))
        elif event.type == "response.output_audio_transcript.delta":
            print(event.delta, end="", flush=True)
        elif event.type == "error":
            raise RuntimeError(f"Realtime API error: {event.error.message}")
        elif event.type == "response.done":
            print()
            return


async def run_conversation() -> None:
    endpoint = required_setting("AZURE_OPENAI_ENDPOINT")
    deployment_name = required_setting("AZURE_OPENAI_DEPLOYMENT_NAME")
    voice = os.getenv("AZURE_OPENAI_VOICE", "alloy").strip() or "alloy"
    token, credential = authentication_token()
    client = AsyncOpenAI(
        websocket_base_url=websocket_base_url(endpoint),
        api_key=token,
    )

    try:
        async with client.realtime.connect(model=deployment_name) as connection:
            await connection.session.update(
                session={
                    "type": "realtime",
                    "instructions": (
                        "Speak the user's text faithfully and naturally. "
                        "Do not add commentary or change its meaning."
                    ),
                    "output_modalities": ["audio"],
                    "audio": {
                        "output": {
                            "voice": voice,
                            "format": {"type": "audio/pcm", "rate": SAMPLE_RATE},
                        }
                    },
                }
            )

            with sd.RawOutputStream(
                samplerate=SAMPLE_RATE,
                channels=1,
                dtype="int16",
            ) as output_stream:
                print("Connected. Enter text to speak, or q to quit.")
                while True:
                    text = (await asyncio.to_thread(input, "\nText: ")).strip()
                    if text.lower() in {"q", "quit", "exit"}:
                        break
                    if not text:
                        continue

                    await connection.conversation.item.create(
                        item={
                            "type": "message",
                            "role": "user",
                            "content": [{"type": "input_text", "text": text}],
                        }
                    )
                    await connection.response.create()
                    print("Voice transcript: ", end="", flush=True)
                    await play_response(connection, output_stream)
    finally:
        await client.close()
        if credential:
            credential.close()


def main() -> None:
    load_dotenv()
    try:
        asyncio.run(run_conversation())
    except KeyboardInterrupt:
        print("\nConversation stopped.")


if __name__ == "__main__":
    main()