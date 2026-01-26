import axios from 'axios';
import * as fs from 'node:fs';
import type { AppConfig, RawTranscriptSegment, RunpodStatusResponse } from '../shared/types.js';

const POLL_INTERVAL_MS = 2000;
const MAX_POLL_ATTEMPTS = 150;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function transcribeAudio(
  audioFilePath: string,
  config: AppConfig,
  progressCallback: (percentage: number) => void
): Promise<RawTranscriptSegment[]> {
  if (!config.runpodApiKey || !config.runpodEndpoint) {
    throw new Error('Runpod API key and endpoint must be configured');
  }

  if (!fs.existsSync(audioFilePath)) {
    throw new Error(`Audio file not found: ${audioFilePath}`);
  }

  const audioBuffer = fs.readFileSync(audioFilePath);
  const audioBase64 = audioBuffer.toString('base64');

  progressCallback(0.1);

  const submitResponse = await axios.post<{ id: string }>(
    config.runpodEndpoint,
    {
      input: {
        audio_base64: audioBase64,
        model: config.whisperModel,
      },
    },
    {
      headers: {
        Authorization: `Bearer ${config.runpodApiKey}`,
        'Content-Type': 'application/json',
      },
      timeout: 60000,
    }
  );

  const jobId = submitResponse.data.id;
  progressCallback(0.2);

  const statusEndpoint = config.runpodEndpoint.replace('/run', `/status/${jobId}`);

  for (let attempt = 0; attempt < MAX_POLL_ATTEMPTS; attempt++) {
    await sleep(POLL_INTERVAL_MS);

    const statusResponse = await axios.get<RunpodStatusResponse>(statusEndpoint, {
      headers: {
        Authorization: `Bearer ${config.runpodApiKey}`,
      },
      timeout: 30000,
    });

    const { status, output, error } = statusResponse.data;

    if (status === 'COMPLETED' && output?.transcript) {
      progressCallback(1.0);
      return output.transcript;
    }

    if (status === 'FAILED') {
      throw new Error(`Transcription failed: ${error ?? 'Unknown error'}`);
    }

    const progress = 0.2 + (attempt / MAX_POLL_ATTEMPTS) * 0.8;
    progressCallback(Math.min(progress, 0.95));
  }

  throw new Error('Transcription timed out');
}
