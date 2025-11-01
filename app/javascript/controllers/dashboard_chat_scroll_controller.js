// app/javascript/controllers/dashboard_chat_scroll_controller.js
import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="dashboard-chat-scroll"
export default class extends Controller {
  static targets = ["container"]

  connect() {
    this.scrollToBottom()
    this.observeChanges()
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  observeChanges() {
    this.observer = new MutationObserver(() => {
      this.scrollToBottom()
    })

    this.observer.observe(this.containerTarget, {
      childList: true,
      subtree: true
    })
  }

  scrollToBottom() {
    requestAnimationFrame(() => {
      this.containerTarget.scrollTop = this.containerTarget.scrollHeight
    })
  }
}