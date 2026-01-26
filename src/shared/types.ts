export type RecordingStatus = 'idle' | 'recording' | 'processing';

export type RecordingSession = {
  id: string;
  startTime: Date;
  endTime?: Date;
  micFilePath: string;
  systemFilePath: string;
  transcriptPath?: string;
  status: RecordingStatus | 'completed' | 'error';
};

export type TranscriptSegment = {
  start: number;
  end: number;
  text: string;
  speaker: 'You' | 'Other Speaker';
};

export type RawTranscriptSegment = {
  start: number;
  end: number;
  text: string;
};

export type RunpodRequest = {
  input: {
    audio_base64: string;
    model: string;
  };
};

export type RunpodSubmitResponse = {
  id: string;
  status: string;
};

export type RunpodStatusResponse = {
  id: string;
  status: 'IN_QUEUE' | 'IN_PROGRESS' | 'COMPLETED' | 'FAILED';
  output?: {
    transcript: RawTranscriptSegment[];
  };
  error?: string;
};

export type AppConfig = {
  runpodEndpoint: string;
  runpodApiKey: string;
  outputDirectory: string;
  autoOpenTranscript: boolean;
  whisperModel: 'base';
};

export type ProcessingStage =
  | 'uploading_mic'
  | 'uploading_system'
  | 'transcribing'
  | 'generating'
  | 'complete';

export type ProcessingProgress = {
  stage: ProcessingStage;
  percentage: number;
  message: string;
};

export type StartRecordingResult =
  | { sessionId: string; error?: never }
  | { error: string; sessionId?: never };

export type StopRecordingResult =
  | { success: true; error?: never }
  | { error: string; success?: never };

export type ElectronAPI = {
  startRecording: () => Promise<StartRecordingResult>;
  stopRecording: () => Promise<StopRecordingResult>;
  onProcessingProgress: (callback: (progress: ProcessingProgress) => void) => void;
  getConfig: () => Promise<AppConfig>;
  saveConfig: (config: Partial<AppConfig>) => Promise<void>;
  openFolder: (path: string) => Promise<void>;
};
