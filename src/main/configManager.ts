import { app } from 'electron';
import * as fs from 'node:fs';
import * as path from 'node:path';
import type { AppConfig } from '../shared/types.js';

const CONFIG_FILE_NAME = 'config.json';

function getConfigPath(): string {
  return path.join(app.getPath('userData'), CONFIG_FILE_NAME);
}

function getDefaultConfig(): AppConfig {
  return {
    runpodEndpoint: 'https://api.runpod.ai/v2/YOUR_ENDPOINT_ID/run',
    runpodApiKey: '',
    outputDirectory: path.join(app.getPath('documents'), 'MeetingRecordings'),
    autoOpenTranscript: true,
    whisperModel: 'base',
  };
}

export function loadConfig(): AppConfig {
  const configPath = getConfigPath();

  if (!fs.existsSync(configPath)) {
    const defaultConfig = getDefaultConfig();
    saveConfigToFile(defaultConfig);
    return defaultConfig;
  }

  try {
    const raw = fs.readFileSync(configPath, 'utf-8');
    const parsed = JSON.parse(raw) as Partial<AppConfig>;
    return { ...getDefaultConfig(), ...parsed };
  } catch {
    return getDefaultConfig();
  }
}

function saveConfigToFile(config: AppConfig): void {
  const configPath = getConfigPath();
  const dir = path.dirname(configPath);

  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
}

export function saveConfig(partial: Partial<AppConfig>): void {
  const current = loadConfig();
  const updated = { ...current, ...partial };
  saveConfigToFile(updated);
}

export function ensureOutputDirectory(): string {
  const config = loadConfig();
  const outputDir = config.outputDirectory.startsWith('~')
    ? config.outputDirectory.replace('~', app.getPath('home'))
    : config.outputDirectory;

  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  return outputDir;
}
