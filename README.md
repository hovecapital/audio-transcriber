# Meeting Recorder

A macOS menu bar app that records meeting audio, transcribes it with Whisper, and optionally analyzes transcripts with LLMs for summaries, action items, and engineering specs. Also features voice dictation, automatic meeting detection, and system-wide autocorrect.

## Features

- Records microphone and system audio simultaneously
- Transcribes audio using whisper.cpp with configurable model sizes
- **Real-time transcription** - live transcript segments during recording
- **LLM analysis** - extracts summaries, action items, clarification questions, and engineering specs (Anthropic Claude / OpenAI GPT)
- **Autocorrect** - system-wide spell/grammar correction using local LLMs (Ollama or llama.cpp)
- **Voice dictation** - push-to-talk speech-to-text that inserts transcribed text at cursor position
- **Automatic meeting detection** - monitors browsers for Google Meet, Teams, and Slack Huddles; auto-starts/stops recording
- **Audio backup** - automatic backup of recordings to a configurable directory before processing
- **Recording health monitoring** - real-time monitoring of audio buffer flow with warnings if audio stops
- **Disk space monitoring** - warns below 500MB, blocks recording below 100MB
- **Customizable hotkeys** - configure shortcuts for autocorrect and dictation via a hotkey recorder UI
- Timestamped markdown transcripts with speaker labels
- Menu bar interface with no dock icon
- Graceful shutdown with recovery options for interrupted recordings
- Launch at login support
- Built-in log viewer for debugging

## Requirements

- macOS 13.0 or later
- whisper.cpp CLI installed (models download automatically)
- Microphone permission
- Screen Recording permission (for system audio capture)
- Accessibility permission (for autocorrect and voice dictation)

## Installation

### Build the App

```bash
swift build -c release

mkdir -p "build/Meeting Recorder.app/Contents/MacOS"
mkdir -p "build/Meeting Recorder.app/Contents/Resources"

cp .build/release/MeetingRecorder "build/Meeting Recorder.app/Contents/MacOS/"
cp Info.plist "build/Meeting Recorder.app/Contents/"
cp AppIcon.icns "build/Meeting Recorder.app/Contents/Resources/"
echo "APPL????" > "build/Meeting Recorder.app/Contents/PkgInfo"

codesign --force --sign - --options runtime \
  --entitlements MeetingRecorder.entitlements \
  "build/Meeting Recorder.app"
```

### Install

Drag `build/Meeting Recorder.app` to your Applications folder, or:

```bash
cp -r "build/Meeting Recorder.app" /Applications/
```

### Launch

Open from Applications or Launchpad. The app runs in the menu bar -- look for the microphone icon.

### Development

```bash
swift run
```

## Usage

### Recording

1. Click the menu bar icon
2. Click "Start Recording"
3. Conduct your meeting
4. Click "Stop Recording"
5. Wait for transcription to complete
6. Transcript opens automatically (if enabled)

### Real-Time Transcription

Enable in Settings to get live transcript segments during recording. Audio is transcribed in chunks (configurable 10-60s intervals) and displayed as it arrives.

When combined with an LLM provider, analysis runs periodically during the meeting to extract summaries, questions, tasks, and specs.

### Quit During Recording

If you quit while recording:

- **Process Now** - Stops recording, transcribes, then quits
- **Save for Later** - Saves session for later processing
- **Discard** - Deletes the recording

Saved recordings can be processed later via the menu bar.

### Voice Dictation

Press the dictation hotkey (default: Ctrl+Cmd+D) to start listening. Speak, then release to transcribe and insert text at the current cursor position via the Accessibility API. The menu bar icon shows the current state: idle, listening, or transcribing.

If direct text insertion fails (e.g. the target app doesn't support Accessibility), the transcribed text is copied to the clipboard as a fallback.

### Automatic Meeting Detection

When enabled, the app monitors browser windows for supported meeting platforms and automatically starts/stops recording when a meeting is detected. Toggle auto-detection from the menu bar.

Supported browsers: Chrome, Safari, Edge, Firefox, Brave, Arc.

Supported platforms: Google Meet, Microsoft Teams, Slack Huddles.

## Configuration

Access settings via the menu bar icon > Settings.

### General

| Setting | Description | Default |
|---------|-------------|---------|
| Output Directory | Where transcripts are saved | `~/Documents/Transcripts` |
| Whisper Model | Transcription model (tiny/base/small) | Base |
| Person 1 Label | Label for microphone audio | Person 1 |
| Person 2 Label | Label for system audio | Person 2 |
| Auto-open Transcript | Open transcript after processing | Yes |
| Delete Audio After | Remove WAV files after transcription | Yes |
| Launch at Login | Start app on login | No |

### Real-Time Transcription & LLM Analysis

| Setting | Description | Default |
|---------|-------------|---------|
| Enable Real-Time Transcription | Live transcription during recording | No |
| Chunk Interval | Seconds between transcription runs | 15s |
| LLM Provider | Anthropic or OpenAI | -- |
| LLM Model | Model identifier | claude-sonnet-4-20250514 / gpt-4o |
| Analysis Interval | Seconds between LLM analysis runs | 120s |

API keys are stored in macOS Keychain and can be entered in Settings.

### Voice Dictation

| Setting | Description | Default |
|---------|-------------|---------|
| Enable Dictation | Enable push-to-talk voice dictation | No |
| Dictation Hotkey | Keyboard shortcut to activate dictation | Ctrl+Cmd+D |

Requires Accessibility permission (Settings > Privacy & Security > Accessibility).

### Meeting Detection

| Setting | Description | Default |
|---------|-------------|---------|
| Enable Meeting Detection | Auto-detect and record meetings | No |

Supported browsers: Chrome, Safari, Edge, Firefox, Brave, Arc. Supported platforms: Google Meet, Microsoft Teams, Slack Huddles.

### Audio Backup

| Setting | Description | Default |
|---------|-------------|---------|
| Backup Directory | Directory for automatic audio backups | -- |

When configured, recordings are automatically backed up to this directory before processing.

### Autocorrect

| Setting | Description | Default |
|---------|-------------|---------|
| Enable Autocorrect | System-wide spell/grammar correction | No |
| Autocorrect Hotkey | Keyboard shortcut for autocorrect | Configurable |
| Backend | Ollama or llama.cpp | Ollama |
| Server URL | Local LLM server address | http://localhost:11434 |
| Model | Model name | -- |
| Timeout | Request timeout | 3s |
| Auto-start Server | Automatically start llama.cpp server | No |

**Ollama setup:**

```bash
ollama serve
ollama pull llama3.2:3b
```

**llama.cpp setup:**

```bash
llama-server -m /path/to/model.gguf --port 8080
```

When using the llama.cpp backend with "Auto-start Server" enabled, the app manages the llama.cpp server process automatically -- no need to start it manually.

Requires Accessibility permission (Settings > Privacy & Security > Accessibility).

## Output Format

Transcripts are saved as markdown. With LLM analysis enabled, the output includes structured sections:

```markdown
# Meeting Transcript

**Date:** January 26, 2025 at 2:30 PM
**Duration:** 45:23

---

## Summary

Brief overview of the meeting discussion.

## Clarification Questions

- [HIGH] What is the deadline for the API migration?
- [MEDIUM] Who owns the database schema changes?

## Goals and Tasks

- Finalize API contract (assigned: Alice)
- Write migration script (assigned: Bob)

## Transcript

[00:00:05] **Person 1:** Let's discuss the project timeline.

[00:00:12] **Person 2:** I think we should aim for Q2 delivery.
```

Without LLM analysis, the output contains the transcript section only.

## File Structure

```
~/Documents/Transcripts/
├── session_2025-01-26_143022/     # Session directory (temporary)
│   ├── microphone.wav             # Your audio
│   ├── system_audio.wav           # Remote audio
│   └── unprocessed.json           # Metadata (if saved for later)
└── meeting_2025-01-26_14-30.md    # Final transcript
```

Configuration: `~/Library/Application Support/MeetingRecorder/config.json`
Models: `~/Library/Application Support/MeetingRecorder/models/`

## Permissions

On first run, macOS will prompt for:

1. **Microphone Access** - Record your voice
2. **Screen Recording** - Capture system audio via ScreenCaptureKit
3. **Accessibility** - Required for autocorrect and voice dictation

Grant these in System Settings > Privacy & Security.

## Troubleshooting

### No system audio captured

- Ensure Screen Recording permission is granted
- Restart the app after granting permission

### Transcription fails

- Check that whisper.cpp is installed and accessible
- Models are downloaded to `~/Library/Application Support/MeetingRecorder/models/`
- Try a smaller model if out of memory

### App doesn't appear in menu bar

- Check if already running in Activity Monitor
- Ensure macOS 13.0 or later

### LLM analysis not working

- Verify API key is entered in Settings
- Check that real-time transcription is enabled
- Confirm the selected provider/model is valid

### Autocorrect not working

- Verify Accessibility permission is granted
- Check local LLM server is running ("Test Connection" in Settings)
- Ensure a model is available on the server

### Dictation not inserting text

- Verify Accessibility permission is granted
- Some apps don't support Accessibility text insertion -- the transcribed text will be copied to your clipboard as a fallback
- Check that dictation is enabled in Settings

### Meeting detection not working

- Ensure meeting detection is enabled in Settings
- Verify a supported browser is in use (Chrome, Safari, Edge, Firefox, Brave, Arc)
- The meeting must be on a supported platform (Google Meet, Microsoft Teams, Slack Huddles)
- Try restarting the app after granting Screen Recording permission

## License

[MIT](LICENSE)
