import * as fs from 'node:fs/promises';
import type { RecordingSession, TranscriptSegment } from '../shared/types.js';

function formatTimestamp(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
}

function formatDuration(startTime: Date, endTime: Date): string {
  const diffMs = endTime.getTime() - startTime.getTime();
  const totalSeconds = Math.floor(diffMs / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  if (hours > 0) {
    return `${hours}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  }
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}

function formatDate(date: Date): string {
  const dateStr = date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
  const timeStr = date.toLocaleTimeString('en-US', {
    hour: 'numeric',
    minute: '2-digit',
  });
  return `${dateStr} at ${timeStr}`;
}

export function generateMarkdown(
  micTranscript: TranscriptSegment[],
  systemTranscript: TranscriptSegment[],
  session: RecordingSession
): string {
  const allSegments = [...micTranscript, ...systemTranscript].sort(
    (a, b) => a.start - b.start
  );

  const duration = session.endTime
    ? formatDuration(session.startTime, session.endTime)
    : 'Unknown';

  const lines: string[] = [
    '# Meeting Recording',
    '',
    `**Date:** ${formatDate(session.startTime)}`,
    `**Duration:** ${duration}`,
    '',
    '---',
    '',
  ];

  for (const segment of allSegments) {
    const timestamp = formatTimestamp(segment.start);
    lines.push(`[${timestamp}] **${segment.speaker}:** ${segment.text}`);
    lines.push('');
  }

  if (allSegments.length === 0) {
    lines.push('*No speech detected in this recording.*');
    lines.push('');
  }

  return lines.join('\n');
}

export async function saveMarkdown(content: string, outputPath: string): Promise<void> {
  await fs.writeFile(outputPath, content, 'utf-8');
}
