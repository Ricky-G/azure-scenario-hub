#!/usr/bin/env python3
"""Generate consistent Azure Speech audio with an SSML voice profile."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
from xml.etree import ElementTree

import azure.cognitiveservices.speech as speechsdk
from dotenv import load_dotenv

SSML_NAMESPACE = "http://www.w3.org/2001/10/synthesis"
XML_NAMESPACE = "http://www.w3.org/XML/1998/namespace"


def required_setting(name: str) -> str:
    """Return a required environment setting or fail with a useful message."""
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Environment variable {name} is required.")
    return value


class SsmlVoiceProfile:
    """Apply one reusable voice and prosody profile to every synthesis call."""

    def __init__(
        self,
        voice_name: str = "en-US-AvaMultilingualNeural",
        speaking_rate: str = "0.9",
        pitch: str = "+5%",
        volume: str = "soft",
    ) -> None:
        speech_config = speechsdk.SpeechConfig(
            subscription=required_setting("AZURE_SPEECH_KEY"),
            region=required_setting("AZURE_SPEECH_REGION"),
        )
        speech_config.speech_synthesis_voice_name = voice_name

        self.speech_config = speech_config
        self.voice_name = voice_name
        self.speaking_rate = speaking_rate
        self.pitch = pitch
        self.volume = volume

    def create_ssml(self, text: str) -> str:
        """Build an escaped SSML document for untrusted plain-text input."""
        ElementTree.register_namespace("", SSML_NAMESPACE)
        speak = ElementTree.Element(
            f"{{{SSML_NAMESPACE}}}speak",
            {
                "version": "1.0",
                f"{{{XML_NAMESPACE}}}lang": "en-US",
            },
        )
        voice = ElementTree.SubElement(speak, "voice", {"name": self.voice_name})
        prosody = ElementTree.SubElement(
            voice,
            "prosody",
            {
                "rate": self.speaking_rate,
                "pitch": self.pitch,
                "volume": self.volume,
            },
        )
        prosody.text = text
        return ElementTree.tostring(speak, encoding="unicode")

    def synthesize_to_wav(self, text: str, output_path: Path) -> Path:
        """Synthesize text with the profile and write a WAV file."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        audio_config = speechsdk.audio.AudioOutputConfig(filename=str(output_path))
        synthesizer = speechsdk.SpeechSynthesizer(
            speech_config=self.speech_config,
            audio_config=audio_config,
        )
        result = synthesizer.speak_ssml_async(self.create_ssml(text)).get()

        if result.reason == speechsdk.ResultReason.SynthesizingAudioCompleted:
            return output_path

        if result.reason == speechsdk.ResultReason.Canceled:
            details = speechsdk.SpeechSynthesisCancellationDetails(result)
            message = f"Speech synthesis canceled: {details.reason}"
            if details.error_details:
                message += f". {details.error_details}"
            raise RuntimeError(message)

        raise RuntimeError(f"Speech synthesis failed: {result.reason}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a WAV file with a consistent Azure Speech SSML profile."
    )
    parser.add_argument(
        "text",
        nargs="?",
        default="Hello. This sample keeps the same voice profile on every request.",
        help="Plain text to synthesize.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("voice-response.wav"),
        help="Destination WAV file.",
    )
    return parser.parse_args()


def main() -> None:
    load_dotenv()
    args = parse_args()
    profile = SsmlVoiceProfile()
    output_path = profile.synthesize_to_wav(args.text, args.output)
    print(f"Audio written to {output_path.resolve()}")


if __name__ == "__main__":
    main()