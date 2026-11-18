#!/usr/bin/env python3
"""Lightweight QML lint for flo-shell.

Quickshell modules are not installed in CI, so qt6's qmllint cannot
resolve imports. This checker walks shell/ and greeter/ and reports:
  - unbalanced braces / brackets / parens (strings and comments skipped)
  - console.error / console.warn (the shell log must stay quiet)
Exit 0 when clean. No network, no extra packages.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", "build", "sessiond"}
PAIRS = {"{": "}", "[": "]", "(": ")"}
OPENERS = set(PAIRS)
CLOSERS = {v: k for k, v in PAIRS.items()}


def iter_qml(root: Path):
    for path in sorted(root.rglob("*.qml")):
        if any(part in SKIP_DIRS for part in path.relative_to(root).parts):
            continue
        yield path


def scan(text: str, path: Path) -> list[str]:
    errors: list[str] = []
    stack: list[tuple[str, int, int]] = []
    i = 0
    n = len(text)
    line = 1
    col = 1
    in_line = False
    in_block = False
    in_str = False
    quote = ""
    escape = False

    def at() -> tuple[int, int]:
        return line, col

    def bump(ch: str) -> None:
        nonlocal line, col
        if ch == "\n":
            line += 1
            col = 1
        else:
            col += 1

    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        if in_line:
            if ch == "\n":
                in_line = False
            bump(ch)
            i += 1
            continue
        if in_block:
            if ch == "*" and nxt == "/":
                in_block = False
                bump(ch)
                bump(nxt)
                i += 2
                continue
            bump(ch)
            i += 1
            continue
        if in_str:
            if escape:
                escape = False
                bump(ch)
                i += 1
                continue
            if ch == "\\":
                escape = True
                bump(ch)
                i += 1
                continue
            if ch == quote:
                in_str = False
            bump(ch)
            i += 1
            continue

        if ch == "/" and nxt == "/":
            in_line = True
            bump(ch)
            bump(nxt)
            i += 2
            continue
        if ch == "/" and nxt == "*":
            in_block = True
            bump(ch)
            bump(nxt)
            i += 2
            continue
        if ch in ("'", '"'):
            in_str = True
            quote = ch
            bump(ch)
            i += 1
            continue

        if ch in OPENERS:
            stack.append((ch, line, col))
        elif ch in CLOSERS:
            if not stack or stack[-1][0] != CLOSERS[ch]:
                want = PAIRS[stack[-1][0]] if stack else "nothing"
                errors.append(
                    f"{path}:{line}:{col}: unexpected {ch!r} (expected {want})"
                )
            else:
                stack.pop()

        bump(ch)
        i += 1

    if in_str:
        errors.append(f"{path}:{line}:{col}: unterminated string")
    if in_block:
        errors.append(f"{path}:{line}:{col}: unterminated block comment")
    for opener, ol, oc in stack:
        errors.append(f"{path}:{ol}:{oc}: unclosed {opener!r}")

    lower = path.name.lower()
    # Agent integration must not write errors when flo-agents is absent.
    if "agent" in lower:
        for lineno, raw in enumerate(text.splitlines(), 1):
            stripped = raw.lstrip()
            if stripped.startswith("//"):
                continue
            if "console.error" in raw or "console.warn" in raw:
                errors.append(
                    f"{path}:{lineno}: console.error/warn is not allowed here"
                )
    return errors


def main() -> int:
    errors: list[str] = []
    files = list(iter_qml(ROOT))
    if not files:
        print("qml_lint: no QML files found", file=sys.stderr)
        return 1
    seen: set[Path] = set()
    for path in files:
        real = path.resolve()
        if real in seen:
            continue
        seen.add(real)
        errors.extend(scan(path.read_text(encoding="utf-8"), path.relative_to(ROOT)))
    if errors:
        print("\n".join(errors), file=sys.stderr)
        print(f"qml_lint: {len(errors)} issue(s) in {len(seen)} files", file=sys.stderr)
        return 1
    print(f"qml_lint: {len(seen)} files ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
