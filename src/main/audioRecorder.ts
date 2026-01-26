import { v4 as uuidv4 } from 'uuid';
import * as path from 'node:path';
import * as fs from 'node:fs';
import { shell } from 'electron';
import { MicRecorder } from './micRecorder.js';
import { SystemAudioRecorder } from './systemAudioRecorder.js';
import { transcribeAudio } from './transcriptionService.js';
import { generateMarkdown, saveMarkdown } from './markdownGenerator.js';
import { ensureOutputDirectory, loadConfig } from './configManager.js';
import type {
  RecordingSession,
  RecordingStatus,
  ProcessingProgress,
  TranscriptSegment,
} from '../shared/types.js';

let currentSession: RecordingSession | null = null;
let micRecorder: MicRecorder | null = null;
let systemRecorder: SystemAudioRecorder | null = null;
let status: RecordingStatus = 'idle';

function formatTimestamp(date: Date): string {
  return date
    .toISOString()
    .replace(/[:.]/g, '-')
    .slice(0, 19)
    .replace('T', '_');
}

export function getRecordingStatus(): RecordingStatus {
  return status;
}

export async function startRecording(): Promise<RecordingSession> {
  if (status !== 'idle') {
    throw new Error('Recording already in progress');
  }

  const sessionId = uuidv4();
  const timestamp = formatTimestamp(new Date());
  const outputDir = ensureOutputDirectory();
  const sessionDir = path.join(outputDir, timestamp);

  fs.mkdirSync(sessionDir, { recursive: true });

  const session: RecordingSession = {
    id: sessionId,
    startTime: new Date(),
    micFilePath: path.join(sessionDir, 'recording-mic.webm'),
    systemFilePath: path.join(sessionDir, 'recording-system.webm'),
    status: 'recording',
  };

  micRecorder = new MicRecorder();
  systemRecorder = new SystemAudioRecorder();

  try {
    await micRecorder.start(session.micFilePath);
    await systemRecorder.start(session.systemFilePath);
  } catch (error) {
    await micRecorder?.stop().catch(() => {});
    await systemRecorder?.stop().catch(() => {});
    micRecorder = null;
    systemRecorder = null;
    throw error;
  }

  currentSession = session;
  status = 'recording';

  return session;
}

export async function stopRecording(
  progressCallback: (progress: ProcessingProgress) => void
): Promise<void> {
  if (!currentSession || status !== 'recording') {
    throw new Error('No recording in progress');
  }

  status = 'processing';
  currentSession.endTime = new Date();
  currentSession.status = 'processing';

  await micRecorder?.stop();
  await systemRecorder?.stop();

  progressCallback({
    stage: 'uploading_mic',
    percentage: 10,
    message: 'Uploading microphone audio...',
  });

  const config = loadConfig();
  let micTranscript: TranscriptSegment[] = [];

  if (fs.existsSync(currentSession.micFilePath)) {
    try {
      const rawMicTranscript = await transcribeAudio(
        currentSession.micFilePath,
        config,
        (pct) => {
          progressCallback({
            stage: 'transcribing',
            percentage: 20 + pct * 50,
            message: 'Transcribing microphone...',
          });
        }
      );

      micTranscript = rawMicTranscript.map((seg) => ({
        ...seg,
        speaker: 'You' as const,
      }));
    } catch (error) {
      console.error('Mic transcription failed:', error);
    }
  }

  progressCallback({
    stage: 'uploading_system',
    percentage: 75,
    message: 'System audio (stub - skipped)...',
  });

  const systemTranscript: TranscriptSegment[] = [];

  progressCallback({
    stage: 'generating',
    percentage: 90,
    message: 'Generating transcript...',
  });

  const markdown = generateMarkdown(micTranscript, systemTranscript, currentSession);
  const sessionDir = path.dirname(currentSession.micFilePath);
  const transcriptPath = path.join(sessionDir, 'transcript.md');

  await saveMarkdown(markdown, transcriptPath);

  currentSession.transcriptPath = transcriptPath;
  currentSession.status = 'completed';

  progressCallback({
    stage: 'complete',
    percentage: 100,
    message: 'Complete!',
  });

  if (config.autoOpenTranscript) {
    shell.openPath(transcriptPath);
  }

  currentSession = null;
  micRecorder = null;
  systemRecorder = null;
  status = 'idle';
}

export function getCurrentSession(): RecordingSession | null {
  return currentSession;
}
