import { Tray, Menu, nativeImage, app } from 'electron';
import * as path from 'node:path';

let tray: Tray | null = null;

export type MenuBarState = 'idle' | 'recording' | 'processing';

let currentState: MenuBarState = 'idle';
let onStartRecording: (() => void) | null = null;
let onStopRecording: (() => void) | null = null;
let onOpenSettings: (() => void) | null = null;

function getIconPath(state: MenuBarState): string {
  const iconName =
    state === 'idle'
      ? 'icon.png'
      : state === 'recording'
        ? 'icon-recording.png'
        : 'icon-processing.png';

  if (app.isPackaged) {
    return path.join(process.resourcesPath, 'assets', iconName);
  }
  return path.join(__dirname, '../../assets', iconName);
}

function buildContextMenu(): Menu {
  const isRecording = currentState === 'recording';
  const isProcessing = currentState === 'processing';

  return Menu.buildFromTemplate([
    {
      label: isRecording ? 'Stop Recording' : 'Start Recording',
      enabled: !isProcessing,
      click: () => {
        if (isRecording) {
          onStopRecording?.();
        } else {
          onStartRecording?.();
        }
      },
    },
    { type: 'separator' },
    {
      label: 'Settings...',
      enabled: !isRecording && !isProcessing,
      click: () => {
        onOpenSettings?.();
      },
    },
    { type: 'separator' },
    {
      label: 'Quit',
      click: () => {
        app.quit();
      },
    },
  ]);
}

export type MenuBarCallbacks = {
  onStartRecording: () => void;
  onStopRecording: () => void;
  onOpenSettings?: () => void;
};

export function createMenuBar(callbacks: MenuBarCallbacks): void {
  onStartRecording = callbacks.onStartRecording;
  onStopRecording = callbacks.onStopRecording;
  onOpenSettings = callbacks.onOpenSettings ?? null;

  const iconPath = getIconPath('idle');
  const icon = nativeImage.createFromPath(iconPath);
  icon.setTemplateImage(true);

  tray = new Tray(icon);
  tray.setToolTip('Meeting Recorder');
  tray.setContextMenu(buildContextMenu());
}

export function updateMenuBarIcon(state: MenuBarState): void {
  if (!tray) {
    return;
  }

  currentState = state;
  const iconPath = getIconPath(state);
  const icon = nativeImage.createFromPath(iconPath);
  icon.setTemplateImage(true);
  tray.setImage(icon);
  tray.setContextMenu(buildContextMenu());
}

export function getMenuBarState(): MenuBarState {
  return currentState;
}

export function getTray(): Tray | null {
  return tray;
}
