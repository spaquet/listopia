// app/javascript/controllers/unified_chat_controller.js
// Handles unified chat interactions across all contexts (dashboard, floating, etc.)

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "messagesContainer",
    "messageForm",
    "messageInput",
    "submitButton",
    "commandPalette"
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

    // Disable submit button during request
    this.submitButtonTarget.disabled = true

    try {
      // Check if this is a command
      if (content.startsWith("/")) {
        await this.handleCommand(content)
      } else {
        await this.submitMessageToServer(content)
      }
    } catch (error) {
      console.error("Error submitting message:", error)
      this.showErrorNotification("Failed to send message")
    } finally {
      this.submitButtonTarget.disabled = false
      this.messageInputTarget.value = ""
      this.messageInputTarget.focus()
    }
  }

  /**
   * Insert command into input when suggestion is clicked
   */
  insertCommand(event) {
    const command = event.target.dataset.command
    this.messageInputTarget.value = command + " "
    this.messageInputTarget.focus()
  }

  /**
   * Handle command parsing and execution
   */
  async handleCommand(input) {
    const [command, ...args] = input.split(" ")

    switch (command) {
      case "/search":
        await this.handleSearchCommand(args.join(" "))
        break
      case "/help":
        this.showHelpCommand()
        break
      case "/clear":
        this.clearChat()
        break
      case "/new":
        this.createNewChat()
        break
      default:
        this.showErrorNotification(`Unknown command: ${command}`)
    }
  }

  /**
   * Handle /search command
   */
  async handleSearchCommand(query) {
    if (!query.trim()) {
      this.showErrorNotification("Please provide a search query")
      return
    }

    // Show loading state
    this.addSystemMessage("Searching for '" + query + "'...")

    try {
      const response = await fetch("/search", {
        method: "GET",
        headers: {
          "X-Requested-With": "XMLHttpRequest",
          "Accept": "application/json"
        },
        body: new URLSearchParams({
          q: query,
          chat_id: this.chatIdValue
        })
      })

      if (!response.ok) {
        throw new Error("Search failed")
      }

      const data = await response.json()
      this.addSearchResultsMessage(data.results || [])
    } catch (error) {
      this.showErrorNotification("Search failed: " + error.message)
    }
  }

  /**
   * Show help command output
   */
  showHelpCommand() {
    const helpContent = `
Available Commands:
• /search <query> - Find your lists and items
• /browse - Browse all available lists
• /help - Show this help message
• /clear - Clear chat history
• /new - Start a new conversation

Tips:
• Start a normal message to chat with the assistant
• Use markdown for formatting
• All responses can be rated for quality
    `.trim()

    this.addSystemMessage(helpContent)
  }

  /**
   * Clear chat history
   */
  clearChat() {
    if (confirm("Clear chat history? This cannot be undone.")) {
      this.messagesContainerTarget.innerHTML = ""
      this.addSystemMessage("Chat history cleared.")
    }
  }

  /**
   * Create new chat
   */
  createNewChat() {
    const form = document.createElement("form")
    form.method = "POST"
    form.action = "/chats"
    form.style.display = "none"
    document.body.appendChild(form)
    form.submit()
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
    // Create palette if it doesn't exist
    if (!this.hasPaletteTarget) {
      const palette = document.createElement("div")
      palette.dataset.unifiedChatTarget = "commandPalette"
      palette.className = "absolute bottom-20 left-0 right-0 bg-white border border-gray-300 rounded-lg shadow-lg max-h-48 overflow-y-auto"
      this.messageFormTarget.appendChild(palette)
    }

    const palette = this.commandPaletteTarget
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
    if (this.hasPaletteTarget) {
      this.commandPaletteTarget.style.display = "none"
    }
  }

  /**
   * Submit regular message to server
   */
  async submitMessageToServer(content) {
    const response = await fetch(`/chats/${this.chatIdValue}/messages`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.getCsrfToken()
      },
      body: JSON.stringify({
        message: { content: content }
      })
    })

    if (!response.ok) {
      throw new Error("Failed to submit message")
    }

    // Response should be a Turbo Stream
    const text = await response.text()
    // Turbo will automatically process the stream
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

  /**
   * Check if command palette target exists
   */
  hasPaletteTarget() {
    try {
      return this.commandPaletteTarget !== undefined
    } catch {
      return false
    }
  }
}
