import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

// The shell loads the client from disk, not from a server, so every asset
// reference has to be relative. See Paths::webClientPath() in src/shared/Paths.cpp.
export default defineConfig({
  plugins: [svelte()],
  base: './',
  build: {
    outDir: 'dist',
    target: 'chrome108', // QtWebEngine 6.x is Chromium 108-ish; do not out-run it
    assetsInlineLimit: 0
  },
  server: {
    port: 5180
  }
});
