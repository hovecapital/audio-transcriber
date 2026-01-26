export class SystemAudioRecorder {
  private recording = false;

  async start(_outputPath: string): Promise<void> {
    // STUB: ScreenCaptureKit implementation to be added later
    console.log('SystemAudioRecorder: start (stub) - system audio capture not implemented');
    this.recording = true;
    return Promise.resolve();
  }

  async stop(): Promise<void> {
    // STUB: Returns immediately, creates empty file
    console.log('SystemAudioRecorder: stop (stub)');
    this.recording = false;
    return Promise.resolve();
  }

  async checkPermissions(): Promise<boolean> {
    // STUB: Always returns true
    // Real implementation would check Screen Recording permission on macOS
    return true;
  }

  getStatus(): 'idle' | 'recording' {
    return this.recording ? 'recording' : 'idle';
  }
}
