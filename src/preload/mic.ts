import { contextBridge, ipcRenderer } from 'electron';

type MicRecorderAPI = {
  sendReady: () => void;
  sendError: (error: string) => void;
  sendData: (data: ArrayBuffer) => void;
  onStopRecording: (callback: () => void) => void;
};

const micRecorderAPI: MicRecorderAPI = {
  sendReady: (): void => {
    ipcRenderer.send('mic-recorder-ready');
  },

  sendError: (error: string): void => {
    ipcRenderer.send('mic-recorder-error', error);
  },

  sendData: (data: ArrayBuffer): void => {
    ipcRenderer.send('mic-recording-data', data);
  },

  onStopRecording: (callback: () => void): void => {
    ipcRenderer.on('stop-mic-recording', () => {
      callback();
    });
  },
};

contextBridge.exposeInMainWorld('micRecorderAPI', micRecorderAPI);
