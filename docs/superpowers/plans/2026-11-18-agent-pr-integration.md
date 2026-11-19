# Agent PR integration implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Carry the three merged agent PRs onto the tablet's flo-shell branch without losing existing fixes.

**Architecture:** Keep the tested tablet branch as the base. Apply each PR diff in order and reconcile shared QML, Makefile and documentation. Agent settings and launch remain delegated to the optional companion CLI.

**Tech Stack:** Quickshell QML, POSIX shell, Python checks, Git.

**Spec:** `docs/AGENT-PR-INTEGRATION.md`.

## Global constraints

- Preserve the existing Lua/classic Hyprland launch selection and PIN/lock behavior.
- Keep agent controls absent if `flo-agents` is missing.
- Never put configuration values into shell command strings or API keys into argv.
- Do not change the installed tablet package until source and staging checks pass.

## Review focus

- Launcher agent rows must coexist with the tablet launcher and home behavior.
- Opening settings must coexist with dismissal of the quick controls overlay.
- Install and uninstall must include both the new scripts and existing `flo-hyprland`.
- Existing backlight and lock tests must continue to pass.
- Documentation must distinguish source integration from native agent verification.

### Task 1: Integrate PR diffs

- [x] Apply PR #1, #2, #3 onto the tablet branch in order.
- [x] Resolve conflicts by retaining tablet fixes and the PR feature behavior.
- [x] Run the PR tests and all existing tests; fix failures.
- [x] Commit the integrated source.

### Task 2: Stage and review package

- [x] Run `make install` into a temporary directory and inspect scripts, QML and both Hyprland formats.
- [x] Compare the resulting tree with the currently installed package before any device change.
- [x] Document remaining CLI and native tablet test dependencies.
- [x] Publish an integration branch for review.
