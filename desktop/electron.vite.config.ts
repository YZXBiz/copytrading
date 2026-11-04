import { resolve } from "node:path"
import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import { defineConfig } from "electron-vite"
import type { Plugin } from "vite"

// Vite's dev server needs an inline preamble and a websocket; the built app keeps the strict policy.
const devCsp: Plugin = {
  name: "dev-csp",
  apply: "serve",
  transformIndexHtml: (html) =>
    html.replace(/content="default-src[^"]*"/, `content="default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self' ws:"`),
}

export default defineConfig({
  main: { build: { outDir: "dist/main", lib: { entry: "electron/main/index.ts" } } },
  preload: { build: { outDir: "dist/preload", lib: { entry: "electron/preload/index.ts" } } },
  renderer: {
    root: ".",
    build: { outDir: "dist/renderer", rollupOptions: { input: resolve("index.html") } },
    resolve: { alias: { "@": resolve("src") } },
    plugins: [react(), tailwindcss(), devCsp],
  },
})
