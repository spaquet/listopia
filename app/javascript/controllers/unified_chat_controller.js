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
    // Auto-focus input on connect
    setTimeout(() => this.messageInputTarget.focus(), 100)

    // Set up input listeners
    this.messageInputTarget.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault()
        this.submitMessage(e)
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
   * Handle message submission
   */
  async submitMessage(event) {
    event.preventDefault()

    const content = this.messageInputTarget.value.trim()
    if (!content) return

    // Clear input immediately
    this.messageInputTarget.value = ""
    this.messageInputTarget.focus()

    // All messages (including commands) go to server
    try {
      await this.submitMessageToServer(content)
    } catch (error) {
      console.error("Error submitting message:", error)
    }
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
   * Submit message to server using form submission
   */
  async submitMessageToServer(content) {
    // Create a form submission using the message form
    const formData = new FormData(this.messageFormTarget)

    // Override the content field
    formData.set("message[content]", content)

    const response = await fetch(this.messageFormTarget.action, {
      method: "POST",
      headers: {
        "X-CSRF-Token": this.getCsrfToken(),
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: formData
    })

    if (!response.ok) {
      throw new Error(`Failed to submit message: ${response.statusText}`)
    }

    // Get the response text and process it as a Turbo Stream
    const responseText = await response.text()

    // Parse the response and manually process turbo-stream elements
    const parser = new DOMParser()
    const doc = parser.parseFromString(responseText, 'text/html')
    const streams = doc.querySelectorAll('turbo-stream')

    // Append each stream element to the document for Turbo to process
    streams.forEach((stream) => {
      document.body.appendChild(stream)
    })
  }

  /**
   * Add user message to display
   */
  addUserMessage(content) {
    const messageEl = document.createElement("div")
    messageEl.className = "flex justify-end"
    messageEl.innerHTML = `
      <div class="max-w-xs lg:max-w-md bg-blue-600 text-white rounded-lg px-4 py-2">
        <p class="text-sm">${this.escapeHtml(content)}</p>
      </div>
    `
    this.messagesContainerTarget.appendChild(messageEl)
    this.autoScrollToBottom()
  }

  /**
   * Add assistant message to display
   */
  addAssistantMessage(content) {
    const messageEl = document.createElement("div")
    messageEl.className = "flex justify-start"
    messageEl.innerHTML = `
      <div class="max-w-xs lg:max-w-md bg-gray-100 text-gray-900 rounded-lg px-4 py-2">
        <p class="text-sm">${this.escapeHtml(content)}</p>
      </div>
    `
    this.messagesContainerTarget.appendChild(messageEl)
    this.autoScrollToBottom()
  }

  /**
   * Add system message
   */
  addSystemMessage(content) {
    const messageEl = document.createElement("div")
    messageEl.className = "flex justify-center"
    messageEl.innerHTML = `
      <div class="max-w-xs text-center text-gray-600 text-sm px-3 py-2">
        <p>${this.escapeHtml(content)}</p>
      </div>
    `
    this.messagesContainerTarget.appendChild(messageEl)
    this.autoScrollToBottom()
  }

  /**
   * Add search results message
   */
  addSearchResultsMessage(results) {
    if (results.length === 0) {
      this.addSystemMessage("No results found")
      return
    }

    const messageEl = document.createElement("div")
    messageEl.className = "flex justify-start"
    messageEl.innerHTML = `
      <div class="max-w-2xl bg-gray-100 rounded-lg p-4 space-y-2">
        <p class="font-semibold text-gray-900">Search Results:</p>
        ${results.map(result => `
          <a href="${this.escapeHtml(result.url)}" class="block hover:bg-gray-200 rounded p-2 transition-colors">
            <p class="font-medium text-blue-600">${this.escapeHtml(result.title)}</p>
            <p class="text-sm text-gray-600">${this.escapeHtml(result.description || "")}</p>
          </a>
        `).join("")}
      </div>
    `
    this.messagesContainerTarget.appendChild(messageEl)
    this.autoScrollToBottom()
  }

  /**
   * Show error notification
   */
  showErrorNotification(message) {
    const notification = document.createElement("div")
    notification.className = "fixed bottom-4 right-4 bg-red-500 text-white rounded-lg px-4 py-2 shadow-lg"
    notification.textContent = message
    document.body.appendChild(notification)

    setTimeout(() => {
      notification.remove()
    }, 4000)
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
