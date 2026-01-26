import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  root: resolve(__dirname, 'src/renderer'),
  build: {
    rollupOptions: {
      input: {
        progress: resolve(__dirname, 'src/renderer/progress/index.html'),
        'mic-recorder': resolve(__dirname, 'src/renderer/mic-recorder/index.html'),
      },
    },
  },
});
