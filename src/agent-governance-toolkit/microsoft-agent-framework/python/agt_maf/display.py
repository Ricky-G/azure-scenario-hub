"""Small ANSI-colour helpers for a clean, readable demo trace.

These helpers render nicely both in a terminal and in Jupyter (which prints ANSI
escape codes in cell output). Colour can be disabled with ``AGT_MAF_NO_COLOR=1``.

Importing this module also best-effort switches stdout to UTF-8 so the emoji and
box-drawing characters in the demo trace render correctly on Windows consoles
(whose default code page is cp1252).
"""

from __future__ import annotations

import os
import sys

# Make the colourful trace safe on Windows terminals, whose default code page
# (cp1252) cannot encode the emoji / box-drawing glyphs. macOS and Linux default
# to UTF-8, so we only touch the streams on Windows. Guarded because some hosts
# (Jupyter, pytest capture) replace stdout with a stream that has no ``reconfigure``.
if sys.platform == "win32":
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
        except (AttributeError, ValueError, OSError):
            pass

_NO_COLOR = os.getenv("AGT_MAF_NO_COLOR", "").strip() not in ("", "0", "false", "False")

# Core palette ------------------------------------------------------------
RESET = "" if _NO_COLOR else "\033[0m"
BOLD = "" if _NO_COLOR else "\033[1m"
DIM = "" if _NO_COLOR else "\033[2m"
RED = "" if _NO_COLOR else "\033[31m"
GREEN = "" if _NO_COLOR else "\033[32m"
YELLOW = "" if _NO_COLOR else "\033[33m"
BLUE = "" if _NO_COLOR else "\033[34m"
MAGENTA = "" if _NO_COLOR else "\033[35m"
CYAN = "" if _NO_COLOR else "\033[36m"
GREY = "" if _NO_COLOR else "\033[90m"

_WIDTH = 78


def banner(title: str, subtitle: str | None = None) -> None:
    """Print a top-level banner for a demo."""
    print(f"\n{BOLD}{BLUE}{'═' * _WIDTH}{RESET}")
    print(f"{BOLD}{BLUE}  {title}{RESET}")
    if subtitle:
        print(f"{GREY}  {subtitle}{RESET}")
    print(f"{BOLD}{BLUE}{'═' * _WIDTH}{RESET}")


def section(title: str) -> None:
    """Print a section divider."""
    pad = max(0, _WIDTH - len(title) - 4)
    print(f"\n{BOLD}{CYAN}── {title} {'─' * pad}{RESET}")


def user(text: str) -> None:
    print(f"{BOLD}👤 user:{RESET} {text}")


def intercept(layer: str, target: str) -> None:
    """Show that AGT intercepted an outbound action inside the MAF pipeline."""
    print(f"{MAGENTA}🛡  AGT intercept{RESET} {DIM}[{layer}]{RESET} → {BOLD}{target}{RESET}")


def allowed(reason: str) -> None:
    print(f"{GREEN}   ✅ ALLOW{RESET} {GREY}{reason}{RESET}")


def denied(reason: str) -> None:
    print(f"{RED}   ⛔ DENY{RESET}  {reason}")


def escalate(reason: str) -> None:
    print(f"{YELLOW}   ⚠️  ESCALATE{RESET} {reason}")


def info(label: str, value: str) -> None:
    print(f"{GREY}   {label}:{RESET} {value}")


def agent_says(text: str) -> None:
    print(f"{BOLD}{GREEN}🤖 agent:{RESET} {text}")


def note(text: str) -> None:
    print(f"{GREY}   {text}{RESET}")
