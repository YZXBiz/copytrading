import { resolve } from "node:path"
import { defineConfig } from "vitest/config"

export default defineConfig({
  resolve: { alias: { "@": resolve("src") } },
  test: { include: ["tests/**/*.test.ts", "src/**/*.test.ts"] },
})
