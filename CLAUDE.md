# Meeting Recorder — contributor notes

A macOS menu bar app written in Swift 5.9 targeting macOS 13+. Records meeting
audio, transcribes via whisper.cpp, and optionally analyzes transcripts with
remote LLMs (Anthropic / OpenAI) or local LLMs (Ollama / llama.cpp).

See `README.md` for end-user setup. This file captures conventions for anyone
(human or AI) editing the codebase.

## Build, run, test

The app must be built as a `.app` bundle for permission prompts (microphone,
screen recording, accessibility) to work correctly. The bundle steps in
`README.md` under "Build the App" are the canonical recipe.

- `swift build -c release` — release build
- `swift run` — fast dev run (some macOS permission flows may not trigger)
- `swift test` — run the test suite in `Tests/`
- Full `.app` build: see README

When iterating on permission-sensitive code (recording, accessibility, screen
capture), always rebuild the `.app` and launch from Finder/Applications.

## Project layout

- `Sources/AppEntry/` — `@main` entry point and app lifecycle
- `Sources/Models/` — value types and observable state
- `Sources/Services/` — recording, transcription, LLM, dictation, autocorrect
- `Sources/Utils/` — Keychain, logging, Whisper output parsing, version info
- `Sources/Views/` — SwiftUI views for menu bar, settings, transcript, hotkeys
- `Tests/` — XCTest suites

`MeetingRecorderCore` (library) holds everything in `Sources/` except
`AppEntry/`; the executable target depends on it. Keep new logic in
`MeetingRecorderCore` so it stays testable.

## Coding conventions

- Less code is better. Prefer deletion over abstraction; avoid speculative
  generality.
- Self-documenting names over comments. Add a comment only when *why* is
  non-obvious (a workaround, a subtle invariant, a permission quirk).
- Single-responsibility functions, short bodies, fail-early on bad input.
- Explicit types on public APIs and non-trivial locals.
- No force-unwraps (`!`) on values that can legitimately be nil; use `guard`
  with a clear error path.
- Use `Result` or thrown typed errors for failure modes, not silent `nil`.
- Don't hand-roll persistence for things `UserDefaults` or
  `~/Library/Application Support/MeetingRecorder/` already covers.

## Secrets

API keys (Anthropic, OpenAI, etc.) live in macOS Keychain via
`Sources/Utils/KeychainHelper.swift`. Never read or write keys to source,
plist, `UserDefaults`, or log output.

## Working with Claude Code

- The user runs all build/test commands; propose the command and wait for the
  result rather than executing long-running builds yourself.
- Don't `git add`, `git commit`, or `git push` unless explicitly asked.
- When facing an unfamiliar error, search the web first — Swift/AVFoundation
  /ScreenCaptureKit error messages are usually well-documented externally.
