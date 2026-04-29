import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    theme: String
  }

  connect() {
    this.initializeTheme()
  }

  initializeTheme() {
    const savedTheme = this.getSavedTheme()
    const preferredTheme = this.getSystemPreference()
    const theme = savedTheme || preferredTheme || "editorial"

    this.setTheme(theme)
  }

  toggle() {
    const current = document.documentElement.getAttribute("data-theme")
    const newTheme = current === "editorial" ? "console" : "editorial"
    this.setTheme(newTheme)
  }

  setTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme)
    localStorage.setItem("theme-preference", theme)

    // Dispatch event for any listeners
    window.dispatchEvent(new CustomEvent("theme-changed", { detail: { theme } }))
  }

  getSavedTheme() {
    return localStorage.getItem("theme-preference")
  }

  getSystemPreference() {
    if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
      return "console"
    }
    return "editorial"
  }
}
