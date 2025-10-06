// app/javascript/controllers/chat_scroll_controller.js

// NOTE: This stimulus controller automatically scrolls a chat messages container to the bottom
// It is used by the chat in the dashboard index.html.erb view and not by the free floating chat widget
import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="chat-scroll"
export default class extends Controller {
  static targets = ["messagesContainer"]

  connect() {
    // Scroll to bottom when controller connects
    this.scrollToBottom()
    
    // Setup mutation observer to auto-scroll when new messages arrive
    this.setupObserver()
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  setupObserver() {
    if (!this.hasMessagesContainerTarget) return

    this.observer = new MutationObserver(() => {
      this.scrollToBottom()
    })

    this.observer.observe(this.messagesContainerTarget, {
      childList: true,
      subtree: true
    })
  }

  scrollToBottom() {
    if (this.hasMessagesContainerTarget) {
      requestAnimationFrame(() => {
        this.messagesContainerTarget.scrollTop = this.messagesContainerTarget.scrollHeight
      })
    }
  }
}