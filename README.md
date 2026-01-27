# Meeting Recorder

A macOS menubar application that records system audio and microphone input during meetings, then transcribes the conversation with speaker diarization into a readable markdown document.

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- whisper.cpp CLI tool for transcription

## Installation

### Install whisper.cpp

```bash
brew install whisper-cpp
```

### Build the App

#### Option 1: Using Swift Package Manager

```bash
cd MeetingRecorder
swift build -c release
```

#### Option 2: Using Xcode (via xcodegen)

```bash
# Install xcodegen if not already installed
brew install xcodegen

# Generate Xcode project
cd MeetingRecorder
xcodegen generate

# Open in Xcode
open MeetingRecorder.xcodeproj
```

### Install the App

After building, the app bundle is at:

```
build/Meeting Recorder.app
```

To install:

```bash
cp -r "build/Meeting Recorder.app" /Applications/
```

Or drag it to Applications in Finder.

The app is a proper macOS menubar app that:
- Shows in the menubar (not the dock)
- Has "Launch at Login" option in Settings
- Can be installed in /Applications

## Usage

1. Launch the app - it will appear as an icon in your menubar
2. Click the menubar icon to see the dropdown menu
3. Click "Start Recording" to begin capturing audio
4. Conduct your meeting
5. Click "Stop Recording" when finished
6. The app will automatically transcribe the audio and save a markdown file

## Features

- **Dual Audio Capture**: Records both microphone (your voice) and system audio (remote participants)
- **Local Transcription**: Uses Whisper for privacy-focused, offline transcription
- **Markdown Output**: Clean, readable transcripts with speaker labels and timestamps
- **Menubar App**: Unobtrusive, always accessible from the menubar

## Permissions

The app requires:

- **Microphone Access**: To record your voice
- **Screen Recording**: Required by ScreenCaptureKit to capture system audio

Grant these permissions when prompted, or enable them in System Settings > Privacy & Security.

## Configuration

Click "Settings..." in the menubar menu to configure:

- **Launch at Login**: Start the app automatically when you log in
- **Save Location**: Where transcripts are saved (default: ~/Documents/Transcripts)
- **Whisper Model**: tiny (fastest), base (balanced), or small (most accurate)
- **Speaker Labels**: Customize "Person 1" and "Person 2" labels
- **Auto-open**: Automatically open transcript after processing
- **Delete Audio**: Remove audio files after successful transcription

## Output Format

Transcripts are saved as markdown files:

```markdown
# Meeting Transcript

**Date:** January 26, 2025 at 2:30 PM
**Duration:** 45:23

---

[00:00:05] **Person 1:** Let's discuss the project timeline.

[00:00:12] **Person 2:** I think we should start with...
```

## Troubleshooting

### "Whisper not found" error

Install whisper.cpp:

```bash
brew install whisper-cpp
```

### No system audio captured

1. Go to System Settings > Privacy & Security > Screen Recording
2. Enable Meeting Recorder
3. Restart the app

### Transcription is slow

- Use the "tiny" model for faster transcription
- The first run downloads the Whisper model, which takes time

## Architecture

```bash
MeetingRecorder/
├── Sources/
│   ├── App/
│   │   └── MeetingRecorderApp.swift    # App entry point
│   ├── Models/
│   │   ├── AppState.swift              # Global app state
│   │   └── AppConfig.swift             # Configuration management
│   ├── Services/
│   │   ├── AudioRecordingManager.swift # Recording orchestration
│   │   ├── MicrophoneRecorder.swift    # Microphone capture
│   │   ├── SystemAudioRecorder.swift   # ScreenCaptureKit audio
│   │   ├── TranscriptionService.swift  # Whisper integration
│   │   └── MarkdownGenerator.swift     # Transcript generation
│   └── Views/
│       ├── MenuBarView.swift           # Menubar UI
│       └── SettingsView.swift          # Settings window
├── Info.plist
├── MeetingRecorder.entitlements
├── Package.swift
└── project.yml                         # Xcodegen config
```

## License

MIT License
