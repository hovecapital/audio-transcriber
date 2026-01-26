import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  root: resolve(__dirname, 'src/renderer'),
  build: {
    rollupOptions: {
      input: {
        progress: resolve(__dirname, 'src/renderer/progress/index.html'),
      },
    },
  },
});
