import { contextBridge, ipcRenderer } from 'electron';
import type {
  ProcessingProgress,
  AppConfig,
  ElectronAPI,
  StartRecordingResult,
  StopRecordingResult,
} from '../shared/types.js';

const electronAPI: ElectronAPI = {
  startRecording: (): Promise<StartRecordingResult> => {
    return ipcRenderer.invoke('start-recording');
  },

  stopRecording: (): Promise<StopRecordingResult> => {
    return ipcRenderer.invoke('stop-recording');
  },

  onProcessingProgress: (callback: (progress: ProcessingProgress) => void): void => {
    ipcRenderer.on('processing-progress', (_event, progress: ProcessingProgress) => {
      callback(progress);
    });
  },

  getConfig: (): Promise<AppConfig> => {
    return ipcRenderer.invoke('get-config');
  },

  saveConfig: (config: Partial<AppConfig>): Promise<void> => {
    return ipcRenderer.invoke('save-config', config);
  },

  openFolder: (folderPath: string): Promise<void> => {
    return ipcRenderer.invoke('open-folder', folderPath);
  },
};

contextBridge.exposeInMainWorld('electronAPI', electronAPI);
