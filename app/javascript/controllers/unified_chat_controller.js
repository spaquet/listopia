// app/javascript/controllers/unified_chat_controller.js
// Handles unified chat interactions across all contexts (dashboard, floating, etc.)

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "messagesContainer",
    "messageForm",
    "messageInput",
    "submitButton"
  ]

  static values = {
    chatId: String,
    location: String
  }

  connect() {
    // Scroll to bottom immediately on connect
    this.autoScrollToBottom()

    // Auto-focus input on connect
    setTimeout(() => this.messageInputTarget.focus(), 100)

    // Set up input listeners for Enter key
    this.messageInputTarget.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault()
        this.messageFormTarget.requestSubmit()
      }
    })

    // Show command palette when "/" is typed
    this.messageInputTarget.addEventListener("input", (e) => {
      this.handleCommandInput(e)
    })

    // Auto-scroll to bottom when new messages arrive
    this.setupAutoScroll()
  }


  disconnect() {
    // Clean up listeners if needed
  }

  /**
   * Clear the input field and focus it
   * Called from server after message is processed
   */
  clearInput() {
    this.messageInputTarget.value = ''
    this.messageInputTarget.focus()
  }

  /**
   * Insert command into input when suggestion is clicked
   */
  insertCommand(event) {
    event.preventDefault()
    const button = event.target.closest("button")
    if (!button) return

    const command = button.dataset.command
    this.messageInputTarget.value = command
    this.hideCommandPalette()

    // Commands that auto-submit (don't require parameters)
    const autoSubmitCommands = ['/help', '/clear', '/new']

    // Auto-submit only for commands that don't need parameters
    if (autoSubmitCommands.includes(command)) {
      setTimeout(() => {
        this.messageFormTarget.requestSubmit()
      }, 50)
    } else {
      // For /search and /browse, focus input and let user add parameters
      this.messageInputTarget.focus()
    }
  }


  /**
   * Handle command input for showing command palette
   */
  handleCommandInput(event) {
    const value = event.target.value
    const caretPos = event.target.selectionStart

    // Only show palette at start of input
    if (value.length === 0 || caretPos === 0) {
      this.hideCommandPalette()
      return
    }

    // Check if "/" appears at the beginning of a word
    const lastChar = value[caretPos - 1]
    const beforeCaret = value.substring(0, caretPos)

    if (beforeCaret.endsWith("/")) {
      this.showCommandPalette(beforeCaret)
    } else {
      this.hideCommandPalette()
    }
  }

  /**
   * Show command palette
   */
  showCommandPalette(beforeCaret) {
    // Get or create palette element
    let palette = document.querySelector("[data-unified-chat-target='commandPalette']")

    if (!palette) {
      palette = document.createElement("div")
      palette.dataset.unifiedChatTarget = "commandPalette"
      palette.className = "absolute bottom-20 left-0 right-0 bg-white border border-gray-300 rounded-lg shadow-lg max-h-48 overflow-y-auto z-50"
      this.messageFormTarget.appendChild(palette)
    }

    palette.innerHTML = `
      <div class="p-2">
        <button class="block w-full text-left px-3 py-2 hover:bg-blue-50 rounded text-sm" data-action="click->unified-chat#insertCommand" data-command="/search">
          <span class="font-mono text-blue-600">/search</span> - Search lists
        </button>
        <button class="block w-full text-left px-3 py-2 hover:bg-blue-50 rounded text-sm" data-action="click->unified-chat#insertCommand" data-command="/browse">
          <span class="font-mono text-blue-600">/browse</span> - Browse lists
        </button>
        <button class="block w-full text-left px-3 py-2 hover:bg-blue-50 rounded text-sm" data-action="click->unified-chat#insertCommand" data-command="/help">
          <span class="font-mono text-blue-600">/help</span> - Show help
        </button>
      </div>
    `
    palette.style.display = "block"
  }

  /**
   * Hide command palette
   */
  hideCommandPalette() {
    const palette = document.querySelector("[data-unified-chat-target='commandPalette']")
    if (palette) {
      palette.style.display = "none"
    }
  }



  /**
   * Auto-scroll messages container to bottom
   */
  autoScrollToBottom() {
    this.messagesContainerTarget.scrollTop = this.messagesContainerTarget.scrollHeight
  }

  /**
   * Setup auto-scroll when new messages arrive
   */
  setupAutoScroll() {
    const observer = new MutationObserver(() => {
      this.autoScrollToBottom()
    })

    observer.observe(this.messagesContainerTarget, {
      childList: true,
      subtree: true
    })
  }

  /**
   * Get CSRF token from page
   */
  getCsrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  /**
   * Escape HTML to prevent XSS
   */
  escapeHtml(text) {
    const map = {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#039;"
    }
    return text.replace(/[&<>"']/g, m => map[m])
  }

}
