// app/javascript/controllers/floating_chat_controller.js
// Stimulus controller for floating chat widget interactions
// Handles toggling between collapsed (button only) and expanded (chat window) states

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggleButton", "chatContainer", "closeButton"]
  static values = { isOpen: { type: Boolean, default: false } }

  connect() {
    console.log("Floating chat controller connected")

    // Restore state from localStorage (remember if user had chat open)
    const wasOpen = localStorage.getItem("floating-chat-open") === "true"
    if (wasOpen) {
      this.expand()
    } else {
      this.collapse()
    }

    // Prevent body scroll when chat is open on mobile
    this.setupScrollLock()
  }

  disconnect() {
    this.removeScrollLock()
  }

  // Toggle between collapsed and expanded states
  toggle() {
    if (this.isOpenValue) {
      this.collapse()
    } else {
      this.expand()
    }
  }

  // Expand the chat window
  expand() {
    this.isOpenValue = true
    localStorage.setItem("floating-chat-open", "true")

    // Hide toggle button
    this.toggleButtonTarget.classList.add("hidden")

    // Show chat container
    this.chatContainerTarget.classList.remove("hidden")

    // Focus input field
    setTimeout(() => {
      const input = this.element.querySelector('input[data-unified-chat-target="messageInput"]')
      if (input) {
        input.focus()
      }
    }, 100)

    // Announce to screen readers
    this.chatContainerTarget.setAttribute("aria-hidden", "false")
    this.toggleButtonTarget.setAttribute("aria-hidden", "true")
  }

  // Collapse the chat window back to button
  collapse() {
    this.isOpenValue = false
    localStorage.setItem("floating-chat-open", "false")

    // Show toggle button
    this.toggleButtonTarget.classList.remove("hidden")

    // Hide chat container
    this.chatContainerTarget.classList.add("hidden")

    // Announce to screen readers
    this.chatContainerTarget.setAttribute("aria-hidden", "true")
    this.toggleButtonTarget.setAttribute("aria-hidden", "false")
  }

  // Close on escape key
  keydown(event) {
    if (event.key === "Escape" && this.isOpenValue) {
      this.collapse()
      this.toggleButtonTarget.focus()
    }
  }

  // Setup scroll lock for mobile
  setupScrollLock() {
    this.element.addEventListener("keydown", this.keydown.bind(this))
  }

  // Remove scroll lock listener
  removeScrollLock() {
    this.element.removeEventListener("keydown", this.keydown.bind(this))
  }

  // Handle auto-scroll to latest message
  scrollToBottom() {
    setTimeout(() => {
      const container = this.element.querySelector('[data-unified-chat-target="messagesContainer"]')
      if (container) {
        container.scrollTop = container.scrollHeight
      }
    }, 100)
  }
}
