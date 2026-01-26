import { app, BrowserWindow, ipcMain, shell, dialog } from 'electron';
import * as path from 'node:path';
import started from 'electron-squirrel-startup';
import { createMenuBar, updateMenuBarIcon } from './menuBar.js';
import { startRecording, stopRecording } from './audioRecorder.js';
import { loadConfig, saveConfig } from './configManager.js';
import type { AppConfig, ProcessingProgress } from '../shared/types.js';

declare const PROGRESS_WINDOW_VITE_DEV_SERVER_URL: string | undefined;
declare const PROGRESS_WINDOW_VITE_NAME: string;

if (started) {
  app.quit();
}

let progressWindow: BrowserWindow | null = null;

function createProgressWindow(): BrowserWindow {
  const win = new BrowserWindow({
    width: 300,
    height: 120,
    resizable: false,
    frame: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  if (PROGRESS_WINDOW_VITE_DEV_SERVER_URL) {
    win.loadURL(`${PROGRESS_WINDOW_VITE_DEV_SERVER_URL}/progress/index.html`);
  } else {
    win.loadFile(path.join(__dirname, `../renderer/${PROGRESS_WINDOW_VITE_NAME}/progress/index.html`));
  }

  return win;
}

function sendProgressUpdate(progress: ProcessingProgress): void {
  progressWindow?.webContents.send('processing-progress', progress);
}

async function handleStartRecording(): Promise<void> {
  try {
    const session = await startRecording();
    updateMenuBarIcon('recording');
    console.log('Recording started:', session.id);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    dialog.showErrorBox('Recording Error', message);
  }
}

async function handleStopRecording(): Promise<void> {
  try {
    updateMenuBarIcon('processing');
    progressWindow = createProgressWindow();

    await stopRecording(sendProgressUpdate);

    progressWindow?.close();
    progressWindow = null;
    updateMenuBarIcon('idle');
  } catch (error) {
    progressWindow?.close();
    progressWindow = null;
    updateMenuBarIcon('idle');

    const message = error instanceof Error ? error.message : 'Unknown error';
    dialog.showErrorBox('Processing Error', message);
  }
}

function setupIPCHandlers(): void {
  ipcMain.handle('start-recording', async () => {
    try {
      const session = await startRecording();
      updateMenuBarIcon('recording');
      return { sessionId: session.id };
    } catch (error) {
      return { error: error instanceof Error ? error.message : 'Unknown error' };
    }
  });

  ipcMain.handle('stop-recording', async () => {
    try {
      updateMenuBarIcon('processing');
      progressWindow = createProgressWindow();

      await stopRecording(sendProgressUpdate);

      progressWindow?.close();
      progressWindow = null;
      updateMenuBarIcon('idle');
      return { success: true as const };
    } catch (error) {
      progressWindow?.close();
      progressWindow = null;
      updateMenuBarIcon('idle');
      return { error: error instanceof Error ? error.message : 'Unknown error' };
    }
  });

  ipcMain.handle('get-config', () => {
    return loadConfig();
  });

  ipcMain.handle('save-config', (_event, config: Partial<AppConfig>) => {
    saveConfig(config);
  });

  ipcMain.handle('open-folder', async (_event, folderPath: string) => {
    await shell.openPath(folderPath);
  });
}

app.whenReady().then(() => {
  if (process.platform === 'darwin') {
    app.dock.hide();
  }

  createMenuBar({
    onStartRecording: handleStartRecording,
    onStopRecording: handleStopRecording,
    onOpenSettings: () => {
      const config = loadConfig();
      dialog.showMessageBox({
        type: 'info',
        title: 'Settings',
        message: 'Edit config.json manually',
        detail: `Config location: ${app.getPath('userData')}/config.json\n\nRunpod Endpoint: ${config.runpodEndpoint}\nOutput Directory: ${config.outputDirectory}`,
      });
    },
  });

  setupIPCHandlers();
  loadConfig();

  console.log('Meeting Recorder ready');
});

app.on('window-all-closed', () => {
  // Menu bar app - do not quit when windows close
});
