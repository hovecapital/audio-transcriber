**Updated App Specification: Meeting Recorder**

---

## Overview

macOS menu bar application for recording internal meetings from Slack huddles and browser-based Teams meetings. Records microphone and system audio separately, transcribes via Runpod-hosted Whisper, outputs markdown transcript.

---

## Technical Stack

- **Framework**: Electron + Electron Forge
- **Build Tool**: Vite
- **Language**: TypeScript
- **Audio Capture**:
  - System audio: ScreenCaptureKit (macOS native API, requires Swift/Objective-C bridge)
  - Microphone: Web Audio API via MediaDevices
- **Transcription**: Whisper (base model) hosted on Runpod
- **Storage**: Local filesystem

---

## Project Structure (Electron Forge + Vite + TS)

```
audio-transcriber/
├── node_modules/
├── src/
│   ├── main/
│   │   ├── index.ts                      # Main process entry
│   │   ├── menuBar.ts                    # System tray/menu bar
│   │   ├── audioRecorder.ts              # Dual-track recording orchestrator
│   │   ├── micRecorder.ts                # Microphone recording
│   │   ├── systemAudioRecorder.ts        # ScreenCaptureKit bridge
│   │   ├── transcriptionService.ts       # Runpod API client
│   │   ├── markdownGenerator.ts          # Transcript merger
│   │   ├── configManager.ts              # Settings/config management
│   │   └── types.ts                      # Shared TypeScript types
│   ├── renderer/
│   │   ├── progress/
│   │   │   ├── index.html                # Progress window
│   │   │   ├── progress.ts               # Progress window logic
│   │   │   └── progress.css              # Styles
│   │   └── settings/
│   │       ├── index.html                # Settings window
│   │       ├── settings.ts               # Settings logic
│   │       └── settings.css              # Styles
│   ├── preload/
│   │   └── index.ts                      # Preload script for IPC
│   └── native/
│       └── ScreenCaptureModule/          # Swift module
│           ├── ScreenCapture.swift
│           ├── module.swift
│           └── binding.gyp               # Native addon build config
├── assets/
│   ├── icon.png                          # Menu bar icon (idle)
│   ├── icon-recording.png                # Menu bar icon (recording)
│   └── icon-processing.png               # Menu bar icon (processing)
├── forge.config.ts                       # Electron Forge config (existing)
├── vite.main.config.ts                   # Vite config for main process (existing)
├── vite.preload.config.ts                # Vite config for preload (existing)
├── vite.renderer.config.ts               # Vite config for renderer (existing)
├── tsconfig.json                         # TypeScript config (existing)
├── package.json                          # Dependencies (existing)
└── .gitignore                            # Git ignore (existing)
```

---

## TypeScript Types

**File:** `src/main/types.ts`

```typescript
export interface RecordingSession {
  id: string;
  startTime: Date;
  endTime?: Date;
  micFilePath: string;
  systemFilePath: string;
  transcriptPath?: string;
  status: 'recording' | 'processing' | 'completed' | 'error';
}

export interface TranscriptSegment {
  start: number;
  end: number;
  text: string;
  speaker: 'You' | 'Other Speaker';
}

export interface RunpodRequest {
  input: {
    audio_base64: string;
    model: string;
  };
}

export interface RunpodResponse {
  transcript: Array<{
    start: number;
    end: number;
    text: string;
  }>;
}

export interface AppConfig {
  runpodEndpoint: string;
  runpodApiKey: string;
  outputDirectory: string;
  autoOpenTranscript: boolean;
  whisperModel: 'base';
}

export interface ProcessingProgress {
  stage: 'uploading_mic' | 'uploading_system' | 'transcribing' | 'generating' | 'complete';
  percentage: number;
  message: string;
}
```

---

## Main Process Modules

### 1. `src/main/index.ts`

**Responsibilities:**

- Initialize Electron app
- Create menu bar (no main window)
- Setup IPC handlers
- Manage app lifecycle

**Key functions:**

```typescript
app.whenReady().then(() => {
  initializeMenuBar();
  setupIPCHandlers();
  loadConfig();
});
```

### 2. `src/main/menuBar.ts`

**Responsibilities:**

- Create system tray icon
- Show/hide based on recording state
- Handle start/stop recording clicks

**Key exports:**

```typescript
export function createMenuBar(): void;
export function updateMenuBarIcon(state: 'idle' | 'recording' | 'processing'): void;
export function showMenu(): void;
```

### 3. `src/main/audioRecorder.ts`

**Responsibilities:**

- Orchestrate dual-track recording
- Coordinate mic + system audio recorders
- Generate unique session IDs
- Save files to output directory

**Key exports:**

```typescript
export async function startRecording(): Promise<RecordingSession>;
export async function stopRecording(sessionId: string): Promise<void>;
export function getRecordingStatus(): 'idle' | 'recording' | 'processing';
```

### 4. `src/main/micRecorder.ts`

**Responsibilities:**

- Capture microphone audio via Web Audio API
- Save as WAV file

**Key exports:**

```typescript
export class MicRecorder {
  async start(outputPath: string): Promise<void>;
  async stop(): Promise<void>;
  getStatus(): 'idle' | 'recording';
}
```

### 5. `src/main/systemAudioRecorder.ts`

**Responsibilities:**

- Bridge to native Swift module
- Control ScreenCaptureKit recording
- Save system audio as WAV

**Key exports:**

```typescript
export class SystemAudioRecorder {
  async start(outputPath: string): Promise<void>;
  async stop(): Promise<void>;
  async checkPermissions(): Promise<boolean>;
}
```

### 6. `src/main/transcriptionService.ts`

**Responsibilities:**

- Upload audio to Runpod
- Poll for results
- Handle retries and errors

**Key exports:**

```typescript
export async function transcribeAudio(
  audioFilePath: string,
  progressCallback: (progress: number) => void
): Promise<TranscriptSegment[]>;
```

### 7. `src/main/markdownGenerator.ts`

**Responsibilities:**

- Merge two transcript arrays
- Sort by timestamp
- Generate formatted markdown

**Key exports:**

```typescript
export function generateMarkdown(
  micTranscript: TranscriptSegment[],
  systemTranscript: TranscriptSegment[],
  session: RecordingSession
): string;

export async function saveMarkdown(
  content: string,
  outputPath: string
): Promise<void>;
```

### 8. `src/main/configManager.ts`

**Responsibilities:**

- Load/save app configuration
- Validate Runpod credentials
- Manage output directory

**Key exports:**

```typescript
export function loadConfig(): AppConfig;
export function saveConfig(config: Partial<AppConfig>): void;
export function getDefaultConfig(): AppConfig;
```

---

## Renderer Process (Progress Window)

### `src/renderer/progress/index.html`

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Processing Recording</title>
  <link rel="stylesheet" href="./progress.css">
</head>
<body>
  <div class="container">
    <h2>Processing Recording</h2>
    <div class="progress-bar">
      <div class="progress-fill" id="progressFill"></div>
    </div>
    <p id="statusMessage">Preparing...</p>
  </div>
  <script type="module" src="./progress.ts"></script>
</body>
</html>
```

### `src/renderer/progress/progress.ts`

```typescript
// Listen for progress updates from main process
window.electronAPI.onProcessingProgress((progress: ProcessingProgress) => {
  updateProgressBar(progress.percentage);
  updateStatusMessage(progress.message);
});

function updateProgressBar(percentage: number): void {
  const fill = document.getElementById('progressFill');
  fill.style.width = `${percentage}%`;
}

function updateStatusMessage(message: string): void {
  const status = document.getElementById('statusMessage');
  status.textContent = message;
}
```

---

## IPC Communication

### `src/preload/index.ts`

```typescript
import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('electronAPI', {
  // Recording controls
  startRecording: () => ipcRenderer.invoke('start-recording'),
  stopRecording: () => ipcRenderer.invoke('stop-recording'),
  
  // Progress updates
  onProcessingProgress: (callback: (progress: ProcessingProgress) => void) => {
    ipcRenderer.on('processing-progress', (_event, progress) => callback(progress));
  },
  
  // Config
  getConfig: () => ipcRenderer.invoke('get-config'),
  saveConfig: (config: Partial<AppConfig>) => ipcRenderer.invoke('save-config', config),
  
  // Utility
  openFolder: (path: string) => ipcRenderer.invoke('open-folder', path),
});
```

**IPC Channels:**

- `start-recording` → Returns session ID
- `stop-recording` → Triggers processing flow
- `processing-progress` → Emits progress updates to renderer
- `get-config` → Returns current config
- `save-config` → Updates config
- `open-folder` → Opens finder to output directory

---

## Native Module (Swift)

### `src/native/ScreenCaptureModule/ScreenCapture.swift`

**Responsibilities:**

- Request screen recording permission
- Use ScreenCaptureKit to capture audio
- Stream audio data to file
- Convert to WAV format

**Key functions:**

```swift
@objc class ScreenCaptureRecorder: NSObject {
  @objc func startRecording(outputPath: String) -> Bool
  @objc func stopRecording() -> Bool
  @objc func checkPermissions() -> Bool
}
```

**Integration with Node:**

- Use `node-gyp` or `cmake-js` to build native addon
- Expose Swift class to JavaScript via Objective-C bridge
- Called from `systemAudioRecorder.ts`

---

## Recording Flow (Detailed)

### Phase 1: Start Recording

```typescript
// User clicks "Start Recording" in menu bar
1. menuBar.ts emits 'start-recording' event
2. audioRecorder.ts:
   - Creates new RecordingSession with unique ID
   - Creates output directory: ~/Documents/MeetingRecordings/[timestamp]/
   - Starts micRecorder → recording-mic.wav
   - Starts systemAudioRecorder → recording-system.wav
   - Updates menu bar icon to "recording"
3. Returns success/error to user
```

### Phase 2: Stop Recording

```typescript
// User clicks "Stop Recording"
1. menuBar.ts emits 'stop-recording' event
2. audioRecorder.ts:
   - Stops both recorders
   - Finalizes WAV files
   - Updates session endTime
   - Opens progress window
   - Triggers processing
```

### Phase 3: Processing

```typescript
3. transcriptionService.ts:
   - Emits progress: { stage: 'uploading_mic', percentage: 10, message: 'Uploading microphone audio...' }
   - Converts recording-mic.wav to base64
   - Uploads to Runpod endpoint
   - Emits progress: { stage: 'uploading_system', percentage: 40, message: 'Uploading system audio...' }
   - Converts recording-system.wav to base64
   - Uploads to Runpod endpoint
   - Emits progress: { stage: 'transcribing', percentage: 70, message: 'Transcribing audio...' }
   - Waits for both Runpod responses
   - Returns two transcript arrays

4. markdownGenerator.ts:
   - Emits progress: { stage: 'generating', percentage: 90, message: 'Generating transcript...' }
   - Labels mic transcript as "You"
   - Labels system transcript as "Other Speaker"
   - Merges and sorts by timestamp
   - Generates markdown string
   - Saves to transcript-[timestamp].md
   - Emits progress: { stage: 'complete', percentage: 100, message: 'Complete!' }

5. Final actions:
   - Close progress window
   - Show notification: "Transcript ready"
   - Auto-open markdown file (if enabled in config)
   - Update menu bar icon to "idle"
```

---

## Dependencies (package.json additions)

```json
{
  "dependencies": {
    "node-wav": "^0.0.2",           // WAV file manipulation
    "axios": "^1.6.0",              // HTTP client for Runpod
    "uuid": "^9.0.0"                // Session ID generation
  },
  "devDependencies": {
    "node-gyp": "^10.0.0",          // Native module compilation
    "@types/uuid": "^9.0.0"
  }
}
```

---

## Forge Configuration Updates

### `forge.config.ts`

```typescript
export default {
  // ... existing config
  makers: [
    {
      name: '@electron-forge/maker-dmg',
      config: {
        background: './assets/dmg-background.png',
        icon: './assets/icon.icns',
      },
    },
  ],
  plugins: [
    {
      name: '@electron-forge/plugin-vite',
      config: {
        // Existing vite configs...
      },
    },
  ],
  rebuildConfig: {
    // For native module compilation
    force: true,
  },
};
```

---

## Markdown Output Format

**File:** `~/Documents/MeetingRecordings/2025-01-26_143215/transcript-2025-01-26_143215.md`

```markdown
# Meeting Recording
**Date:** January 26, 2025 at 2:32:15 PM  
**Duration:** 45:23  
**Location:** ~/Documents/MeetingRecordings/2025-01-26_143215

---

[00:00:05] **You:** Let's discuss the Q1 roadmap for the project

[00:00:12] **Other Speaker:** I think we should prioritize the API integration first

[00:00:28] **You:** Agreed, what's the timeline looking like?

[00:00:35] **Other Speaker:** We can probably have it done in two weeks if we focus

[00:01:02] **You:** That works, let me check with the backend team

...
```

---

## Configuration File

**Location:** `~/Library/Application Support/audio-transcriber/config.json`

```json
{
  "runpodEndpoint": "https://api.runpod.ai/v2/[endpoint-id]/run",
  "runpodApiKey": "",
  "outputDirectory": "~/Documents/MeetingRecordings",
  "autoOpenTranscript": true,
  "whisperModel": "base"
}
```

---

## Error Handling Strategy

```typescript
// All async operations wrapped in try-catch
// Errors shown to user via dialog

try {
  await startRecording();
} catch (error) {
  if (error.code === 'PERMISSION_DENIED') {
    showPermissionDialog();
  } else if (error.code === 'NO_MICROPHONE') {
    dialog.showErrorBox('No Microphone', 'Please connect a microphone');
  } else {
    dialog.showErrorBox('Recording Error', error.message);
  }
}
```

**Error Types:**

- `PERMISSION_DENIED` - Screen recording permission not granted
- `NO_MICROPHONE` - No mic detected
- `RUNPOD_TIMEOUT` - API timeout (retry logic)
- `RUNPOD_AUTH_ERROR` - Invalid API key
- `DISK_FULL` - Insufficient storage
- `NETWORK_ERROR` - No internet connection

---

## Runpod Implementation Details

### Serverless Handler (Python)

**File:** `handler.py` (deployed to Runpod)

```python
import whisper
import base64
import tempfile
import os
import json

model = whisper.load_model("base")

def handler(event):
    audio_base64 = event['input']['audio_base64']
    
    # Decode base64 to audio file
    audio_data = base64.b64decode(audio_base64)
    
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
        tmp.write(audio_data)
        tmp_path = tmp.name
    
    # Transcribe
    result = model.transcribe(tmp_path, word_timestamps=True)
    
    # Clean up
    os.unlink(tmp_path)
    
    # Format output
    transcript = []
    for segment in result['segments']:
        transcript.append({
            'start': segment['start'],
            'end': segment['end'],
            'text': segment['text'].strip()
        })
    
    return {'transcript': transcript}
```

### Runpod Deployment Steps

1. Create Runpod account at runpod.io
2. Navigate to Serverless → Endpoints
3. Click "New Endpoint"
4. Select template: "Custom Docker Image"
5. Docker image: `runpod/pytorch:2.1.0-py3.10-cuda11.8.0-devel`
6. Add startup command:

   ```bash
   pip install openai-whisper && python handler.py
   ```

7. Upload `handler.py` via their web interface
8. Select GPU tier: RTX 3070 (~$0.20/hr)
9. Set timeout: 300 seconds (5 min)
10. Deploy endpoint
11. Copy endpoint URL and API key to app config

---

## Build & Distribution

### Development

```bash
npm run start
```

### Production Build

```bash
npm run make
```

**Output:** DMG installer in `out/make/`

### Code Signing (macOS)

- Required for distribution outside App Store
- Notarization needed for Gatekeeper
- Update `forge.config.ts` with signing identity

---

## First-Time User Setup Flow

1. **Launch app** → Menu bar icon appears
2. **Click "Start Recording"** → Permission prompts:
   - Microphone access (automatic dialog)
   - Screen Recording (redirect to System Preferences)
3. **After permissions granted** → Settings dialog appears:
   - "Enter your Runpod API key"
   - "Enter Runpod endpoint URL"
   - "Choose output directory"
4. **Save settings** → Ready to record

---

## Testing Strategy

### Unit Tests

- `audioRecorder.ts` - Mock file system operations
- `transcriptionService.ts` - Mock Runpod API responses
- `markdownGenerator.ts` - Test timestamp merging logic

### Integration Tests

- Full recording → processing → output flow
- Error handling (no internet, invalid API key)
- Permission flows

### Manual Testing Checklist

- [ ] Record 1 min meeting, verify transcript accuracy
- [ ] Test with 3 hour meeting (max duration)
- [ ] Test Runpod retry logic (disconnect during upload)
- [ ] Test with no microphone connected
- [ ] Test without screen recording permission
- [ ] Verify markdown format is correct
- [ ] Test auto-open transcript feature

---

End of updated specification for Electron Forge + Vite + TypeScript implementation.
