# Meeting Recorder

A macOS menu bar app that records meeting audio from your microphone and system audio, then transcribes it to markdown using Whisper.

## Features

- Records microphone audio (your voice) and system audio (remote participants) simultaneously
- Transcribes both audio streams using whisper.cpp
- Generates timestamped markdown transcripts with speaker labels
- Menu bar interface for quick access
- Configurable Whisper model size (tiny/base/small)
- Custom speaker labels
- Auto-open transcripts after processing
- Graceful shutdown handling with recovery options
- Process old/interrupted recordings later

## Requirements

- macOS 13.0 or later
- Microphone permission
- Screen recording permission (for system audio capture)
- whisper.cpp CLI installed (models downloaded automatically)

## Installation

### Build the App

```bash
# Build release binary
swift build -c release

# Create app bundle
mkdir -p "build/Meeting Recorder.app/Contents/MacOS"
mkdir -p "build/Meeting Recorder.app/Contents/Resources"

# Copy files into bundle
cp .build/release/MeetingRecorder "build/Meeting Recorder.app/Contents/MacOS/"
cp Info.plist "build/Meeting Recorder.app/Contents/"
cp AppIcon.icns "build/Meeting Recorder.app/Contents/Resources/"
echo "APPL????" > "build/Meeting Recorder.app/Contents/PkgInfo"
```

### Install

Drag `build/Meeting Recorder.app` to your Applications folder:

```bash
cp -r "build/Meeting Recorder.app" /Applications/
```

Or copy it manually in Finder.

### Launch

- Open from Applications or Launchpad
- The app runs in the menu bar (no dock icon)
- Look for the microphone icon in your menu bar

### Quick Development Run

For development without building the full app:

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

### Quit During Recording

If you quit while recording, you'll see a dialog with options:

- **Process Now** - Stops recording, transcribes, then quits
- **Save for Later** - Saves session for later processing, quits immediately
- **Discard** - Deletes the recording, quits immediately

### Process Old Recordings

If you have saved recordings from interrupted sessions:

1. Click the menu bar icon
2. Click "Process Old Recordings"
3. Select a session from the list to process it

## Configuration

Access settings via the menu bar icon > Settings.

| Setting | Description | Default |
|---------|-------------|---------|
| Output Directory | Where transcripts are saved | `~/Documents/Transcripts` |
| Whisper Model | Transcription model (tiny/base/small) | Base |
| Person 1 Label | Label for microphone audio | Person 1 |
| Person 2 Label | Label for system audio | Person 2 |
| Auto-open Transcript | Open transcript after processing | Yes |
| Delete Audio After | Remove WAV files after transcription | Yes |

Configuration is stored at `~/Library/Application Support/MeetingRecorder/config.json`.

## Output Format

Transcripts are saved as markdown files:

```markdown
# Meeting Transcript

**Date:** January 26, 2025 at 2:30 PM
**Duration:** 45:23

---

[00:00:05] **Person 1:** Let's discuss the project timeline.

[00:00:12] **Person 2:** I think we should aim for Q2 delivery.
```

## File Structure

```
~/Documents/Transcripts/           # Default output directory
├── session_2025-01-26_143022/     # Session directory (temporary)
│   ├── microphone.wav             # Your audio
│   ├── system_audio.wav           # Remote audio
│   └── unprocessed.json           # Metadata (if saved for later)
└── meeting_2025-01-26_14-30.md    # Final transcript
```

## Permissions

On first run, macOS will prompt for:

1. **Microphone Access** - Required to record your voice
2. **Screen Recording** - Required to capture system audio via ScreenCaptureKit

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

## License

MIT
