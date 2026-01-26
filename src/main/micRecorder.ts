import { BrowserWindow, ipcMain, systemPreferences } from 'electron';
import * as path from 'node:path';
import * as fs from 'node:fs';

declare const MIC_RECORDER_VITE_DEV_SERVER_URL: string | undefined;
declare const MIC_RECORDER_VITE_NAME: string;

export class MicRecorder {
  private hiddenWindow: BrowserWindow | null = null;
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

    this.hiddenWindow = new BrowserWindow({
      show: false,
      webPreferences: {
        preload: path.join(__dirname, 'mic.js'),
        contextIsolation: true,
        nodeIntegration: false,
      },
    });

    return new Promise((resolve, reject) => {
      const onReady = (): void => {
        ipcMain.removeListener('mic-recorder-error', onError);
        this.status = 'recording';
        resolve();
      };

      const onError = (_event: Electron.IpcMainEvent, error: string): void => {
        ipcMain.removeListener('mic-recorder-ready', onReady);
        this.cleanup();
        reject(new Error(error));
      };

      ipcMain.once('mic-recorder-ready', onReady);
      ipcMain.once('mic-recorder-error', onError);

      if (MIC_RECORDER_VITE_DEV_SERVER_URL) {
        this.hiddenWindow?.loadURL(`${MIC_RECORDER_VITE_DEV_SERVER_URL}/mic-recorder/index.html`);
      } else {
        this.hiddenWindow?.loadFile(
          path.join(__dirname, `../renderer/${MIC_RECORDER_VITE_NAME}/mic-recorder/index.html`)
        );
      }
    });
  }

  async stop(): Promise<void> {
    if (!this.hiddenWindow || this.status !== 'recording') {
      return;
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        ipcMain.removeListener('mic-recording-data', onData);
        this.cleanup();
        reject(new Error('Timeout waiting for recording data'));
      }, 10000);

      const onData = (_event: Electron.IpcMainEvent, audioData: ArrayBuffer): void => {
        clearTimeout(timeout);
        try {
          const buffer = Buffer.from(audioData);
          fs.writeFileSync(this.outputPath, buffer);
          this.cleanup();
          resolve();
        } catch (error) {
          this.cleanup();
          reject(error);
        }
      };

      ipcMain.once('mic-recording-data', onData);
      this.hiddenWindow?.webContents.send('stop-mic-recording');
    });
  }

  private cleanup(): void {
    this.hiddenWindow?.close();
    this.hiddenWindow = null;
    this.status = 'idle';
  }

  getStatus(): 'idle' | 'recording' {
    return this.status;
  }
}
