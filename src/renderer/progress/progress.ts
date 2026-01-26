import type { ProcessingProgress, ElectronAPI } from '../../shared/types.js';

declare global {
  interface Window {
    electronAPI: ElectronAPI;
  }
}

function updateProgressBar(percentage: number): void {
  const fill = document.getElementById('progressFill');
  if (fill) {
    fill.style.width = `${percentage}%`;
  }
}

function updateStatusMessage(message: string): void {
  const status = document.getElementById('statusMessage');
  if (status) {
    status.textContent = message;
  }
}

window.electronAPI.onProcessingProgress((progress: ProcessingProgress) => {
  updateProgressBar(progress.percentage);
  updateStatusMessage(progress.message);
});
