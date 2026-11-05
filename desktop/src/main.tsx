import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import App from "./App"
import "./index.css"

// The window follows the system appearance (main sets it from Settings, dark by default); the `dark` class and `data-theme` carry it to the old tokens and the new ones.
const dark = window.matchMedia("(prefers-color-scheme: dark)")
const applyTheme = () => {
  document.documentElement.classList.toggle("dark", dark.matches)
  document.documentElement.dataset.theme = dark.matches ? "dark" : "light"
}
applyTheme()
dark.addEventListener("change", applyTheme)

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
