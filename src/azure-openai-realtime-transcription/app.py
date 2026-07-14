#!/usr/bin/env python3
"""Stream microphone audio to Azure OpenAI Realtime transcription."""

from __future__ import annotations

import asyncio
import base64
import json
import os
from collections.abc import Mapping
from typing import Any

import sounddevice as sd
import websockets
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

SAMPLE_RATE = 24_000
CHANNELS = 1
DTYPE = "int16"
BLOCK_MILLISECONDS = 100
COMMIT_SECONDS = 3
AZURE_OPENAI_SCOPE = "https://ai.azure.com/.default"


def required_setting(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Environment variable {name} is required.")
    return value


def realtime_url(endpoint: str) -> str:
    """Build the GA transcription WebSocket URL."""
    normalized = endpoint.strip().rstrip("/")
    if normalized.lower().startswith("https://"):
        normalized = "wss://" + normalized[8:]
    elif not normalized.lower().startswith("wss://"):
        raise ValueError("AZURE_OPENAI_ENDPOINT must start with https:// or wss://.")
    return f"{normalized}/openai/v1/realtime?intent=transcription"


def session_update_message(
    deployment_name: str,
    language: str = "",
    delay: str = "medium",
) -> str:
    """Create the GA transcription session configuration."""
    transcription: dict[str, str] = {"model": deployment_name}
    if language:
        transcription["language"] = language
    if delay:
        transcription["delay"] = delay

    return json.dumps(
        {
            "type": "session.update",
            "session": {
                "type": "transcription",
                "audio": {
                    "input": {
                        "format": {"type": "audio/pcm", "rate": SAMPLE_RATE},
                        "turn_detection": None,
                        "transcription": transcription,
                    }
                },
            },
        }
    )


def authentication_headers() -> tuple[Mapping[str, str], DefaultAzureCredential | None]:
    """Prefer Entra ID and fall back to a resource key when explicitly provided."""
    api_key = os.getenv("AZURE_OPENAI_API_KEY", "").strip()
    if api_key:
        return {"api-key": api_key}, None

    credential = DefaultAzureCredential()
    token = credential.get_token(AZURE_OPENAI_SCOPE)
    return {"Authorization": f"Bearer {token.token}"}, credential


async def send_microphone_audio(connection: Any, stop: asyncio.Event) -> None:
    """Capture PCM16 microphone blocks and append them to the input buffer."""
    loop = asyncio.get_running_loop()
    queue: asyncio.Queue[bytes] = asyncio.Queue(maxsize=20)

    def enqueue_audio(audio: bytes) -> None:
        try:
            queue.put_nowait(audio)
        except asyncio.QueueFull:
            pass

    def on_audio(indata: Any, frames: int, time_info: Any, status: Any) -> None:
        del frames, time_info
        if status:
            print(f"Microphone warning: {status}")
        loop.call_soon_threadsafe(enqueue_audio, bytes(indata))

    block_size = int(SAMPLE_RATE * BLOCK_MILLISECONDS / 1_000)
    chunks_per_commit = max(1, int(COMMIT_SECONDS * 1_000 / BLOCK_MILLISECONDS))

    with sd.RawInputStream(
        samplerate=SAMPLE_RATE,
        blocksize=block_size,
        channels=CHANNELS,
        dtype=DTYPE,
        callback=on_audio,
    ):
        append_count = 0
        chunks_since_commit = 0
        print("Listening. Press Ctrl+C to stop.\n")

        while not stop.is_set():
            audio = await queue.get()
            append_count += 1
            await connection.send(
                json.dumps(
                    {
                        "type": "input_audio_buffer.append",
                        "event_id": f"append_{append_count}",
                        "audio": base64.b64encode(audio).decode("ascii"),
                    }
                )
            )

            chunks_since_commit += 1
            if chunks_since_commit >= chunks_per_commit:
                await connection.send(
                    json.dumps(
                        {
                            "type": "input_audio_buffer.commit",
                            "event_id": f"commit_{append_count}",
                        }
                    )
                )
                chunks_since_commit = 0


async def receive_transcripts(connection: Any, stop: asyncio.Event) -> None:
    """Print incremental and completed transcription events."""
    async for raw_message in connection:
        if stop.is_set():
            return

        event = json.loads(raw_message)
        event_type = event.get("type")
        if event_type == "conversation.item.input_audio_transcription.delta":
            print(event.get("delta", ""), end="", flush=True)
        elif event_type in {
            "conversation.item.input_audio_transcription.completed",
            "response.text.done",
        }:
            text = event.get("text") or event.get("transcript")
            if text:
                print(f"\n{text}\n", flush=True)
        elif event_type in {
            "conversation.item.input_audio_transcription.failed",
            "error",
        }:
            raise RuntimeError(f"Realtime transcription failed: {event}")


async def transcribe() -> None:
    endpoint = required_setting("AZURE_OPENAI_ENDPOINT")
    deployment_name = required_setting("AZURE_OPENAI_DEPLOYMENT_NAME")
    language = os.getenv("TRANSCRIPTION_LANGUAGE", "").strip()
    delay = os.getenv("TRANSCRIPTION_DELAY", "medium").strip()
    headers, credential = authentication_headers()
    stop = asyncio.Event()

    try:
        async with websockets.connect(
            realtime_url(endpoint),
            additional_headers=headers,
            max_size=None,
        ) as connection:
            await connection.send(
                session_update_message(deployment_name, language, delay)
            )

            async for raw_message in connection:
                event = json.loads(raw_message)
                if event.get("type") == "session.updated":
                    print("Transcription session configured.")
                    break
                if event.get("type") == "error":
                    raise RuntimeError(f"Session configuration failed: {event}")

            sender = asyncio.create_task(send_microphone_audio(connection, stop))
            receiver = asyncio.create_task(receive_transcripts(connection, stop))
            try:
                await asyncio.gather(sender, receiver)
            finally:
                stop.set()
                sender.cancel()
                receiver.cancel()
                await asyncio.gather(sender, receiver, return_exceptions=True)
    finally:
        if credential:
            credential.close()


def main() -> None:
    load_dotenv()
    try:
        asyncio.run(transcribe())
    except KeyboardInterrupt:
        print("\nTranscription stopped.")


if __name__ == "__main__":
    main()