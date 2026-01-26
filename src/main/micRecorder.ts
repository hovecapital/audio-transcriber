import { systemPreferences } from 'electron';
import { spawn, type ChildProcess } from 'node:child_process';
import * as fs from 'node:fs';

export class MicRecorder {
  private process: ChildProcess | null = null;
  private outputPath: string = '';
  private status: 'idle' | 'recording' = 'idle';

  async checkPermissions(): Promise<boolean> {
    if (process.platform === 'darwin') {
      const status = systemPreferences.getMediaAccessStatus('microphone');
      if (status === 'not-determined') {
        const granted = await systemPreferences.askForMediaAccess('microphone');
        return granted;
      }
      return status === 'granted';
    }
    return true;
  }

  async start(outputPath: string): Promise<void> {
    const hasPermission = await this.checkPermissions();
    if (!hasPermission) {
      throw new Error('Microphone permission denied');
    }

    this.outputPath = outputPath;

    // Use macOS native sox/rec command for audio recording
    // Falls back to afrecord if available
    try {
      // Try using sox (commonly available via homebrew)
      this.process = spawn('rec', [
        '-q',           // quiet
        '-r', '16000',  // sample rate
        '-c', '1',      // mono
        '-b', '16',     // 16-bit
        outputPath,
      ]);

      this.process.on('error', (err) => {
        console.error('rec command failed, trying ffmpeg:', err.message);
        this.startWithFFmpeg(outputPath);
      });

      this.status = 'recording';
    } catch {
      await this.startWithFFmpeg(outputPath);
    }
  }

  private async startWithFFmpeg(outputPath: string): Promise<void> {
    // Use ffmpeg with avfoundation (macOS built-in)
    this.process = spawn('ffmpeg', [
      '-f', 'avfoundation',
      '-i', ':0',  // default audio input
      '-ar', '16000',
      '-ac', '1',
      '-y',  // overwrite
      outputPath,
    ]);

    this.process.on('error', (err) => {
      console.error('ffmpeg failed:', err.message);
      // Create empty file as fallback
      fs.writeFileSync(outputPath, Buffer.alloc(0));
    });

    this.status = 'recording';
  }

  async stop(): Promise<void> {
    if (this.process) {
      // Send SIGINT to gracefully stop recording
      this.process.kill('SIGINT');

      // Wait for process to finish
      await new Promise<void>((resolve) => {
        if (this.process) {
          this.process.on('close', () => resolve());
          // Timeout fallback
          setTimeout(() => {
            this.process?.kill('SIGKILL');
            resolve();
          }, 3000);
        } else {
          resolve();
        }
      });

      this.process = null;
    }
    this.status = 'idle';
  }

  getStatus(): 'idle' | 'recording' {
    return this.status;
  }
}
