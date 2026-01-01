// app/javascript/controllers/floating_chat_controller.js
// Stimulus controller for floating chat widget interactions
// Handles toggling between collapsed (button only) and expanded (chat window) states

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggleButton", "chatContainer", "closeButton"]
  static values = { isOpen: { type: Boolean, default: false } }

  connect() {
    console.log("Floating chat controller connected")
    console.log("Toggle button element:", this.toggleButtonTarget)
    console.log("Chat container element:", this.chatContainerTarget)

    // Restore state from localStorage (remember if user had chat open)
    const wasOpen = localStorage.getItem("floating-chat-open") === "true"
    console.log("Was chat open before?", wasOpen)

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
    this.chatContainerTarget.setAttribute("aria-hidden", "false")

    // Focus input field
    setTimeout(() => {
      const input = this.element.querySelector('input[data-unified-chat-target="messageInput"]')
      if (input) {
        input.focus()
      }
    }, 100)
  }

  // Collapse the chat window back to button
  collapse() {
    this.isOpenValue = false
    localStorage.setItem("floating-chat-open", "false")

    // Show toggle button
    this.toggleButtonTarget.classList.remove("hidden")

    // Hide chat container
    this.chatContainerTarget.classList.add("hidden")
    this.chatContainerTarget.setAttribute("aria-hidden", "true")

    // Return focus to toggle button
    this.toggleButtonTarget.focus()
  }

  // Close on escape key
  handleEscape(event) {
    if (event.key === "Escape" && this.isOpenValue) {
      event.preventDefault()
      this.collapse()
      this.toggleButtonTarget.focus()
    }
  }

  // Setup event listeners
  setupScrollLock() {
    // Bind the handler to maintain proper 'this' context
    this.boundEscapeHandler = this.handleEscape.bind(this)
    document.addEventListener("keydown", this.boundEscapeHandler)
  }

  // Remove event listeners
  removeScrollLock() {
    if (this.boundEscapeHandler) {
      document.removeEventListener("keydown", this.boundEscapeHandler)
    }
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
