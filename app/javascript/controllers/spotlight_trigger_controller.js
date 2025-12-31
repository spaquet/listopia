import { Controller } from "@hotwire/stimulus"

export default class extends Controller {
  connect() {
    // Listen for custom spotlight:open event from keyboard shortcuts
    this.boundOpen = this.open.bind(this)
    document.addEventListener("spotlight:open", this.boundOpen)
  }

  disconnect() {
    document.removeEventListener("spotlight:open", this.boundOpen)
  }

  open(event) {
    if (event && event.preventDefault) {
      event.preventDefault()
    }

    // Get or create turbo frame
    const frame = document.getElementById("spotlight_modal")
    if (!frame) {
      console.error("Spotlight modal frame not found")
      return
    }

    // Fetch and inject modal HTML into the frame
    this.loadModal(frame)
  }

  async loadModal(frame) {
    try {
      const response = await fetch("/search/spotlight_modal", {
        headers: { "Accept": "text/html" }
      })

      if (!response.ok) {
        console.error("Failed to load spotlight modal")
        return
      }

      const html = await response.text()
      frame.innerHTML = html
    } catch (error) {
      console.error("Error loading spotlight modal:", error)
    }
  }
}
