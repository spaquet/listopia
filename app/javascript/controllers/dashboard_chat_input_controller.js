// app/javascript/controllers/dashboard_chat_input_controller.js
import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="dashboard-chat-input"
export default class extends Controller {
  static targets = ["input", "sendButton", "charCount"]
  static values = {
    context: Object
  }

  connect() {
    this.maxLength = 2000
    this.adjustTextareaHeight()
    this.loadChatHistory()
  }

  async loadChatHistory() {
    try {
      const response = await fetch('/chat/dashboard_history', {
        headers: {
          'Accept': 'text/vnd.turbo-stream.html',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      if (response.ok) {
        // Turbo will handle the stream response automatically
      }
    } catch (error) {
      console.error("Error loading chat history:", error)
    }
  }

  handleInput(event) {
    this.adjustTextareaHeight()
    this.updateCharCount()
    this.updateSendButton()
  }

  handleKeydown(event) {
    // Send on Enter (without Shift)
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault()
      this.sendMessage()
    }
  }

  useSuggestion(event) {
    const suggestion = event.currentTarget.dataset.suggestion
    this.inputTarget.value = suggestion
    this.handleInput()
    this.inputTarget.focus()
  }

  async sendMessage() {
    const message = this.inputTarget.value.trim()
    if (!message || message.length > this.maxLength) return

    // Disable input while processing
    this.inputTarget.disabled = true
    this.sendButtonTarget.disabled = true
    
    // Hide welcome message and show compact suggestions
    this.transitionToCompactMode()

    // Show typing indicator
    this.showTypingIndicator()

    // Clear input
    const userMessage = message
    this.inputTarget.value = ''
    this.handleInput()

    try {
      const formData = new FormData()
      formData.append('message', userMessage)
      formData.append('current_page', 'dashboard#index')
      
      // Add context
      if (this.contextValue) {
        Object.keys(this.contextValue).forEach(key => {
          if (typeof this.contextValue[key] === 'object') {
            formData.append(`context[${key}]`, JSON.stringify(this.contextValue[key]))
          } else {
            formData.append(`context[${key}]`, this.contextValue[key])
          }
        })
      }

      const response = await fetch('/chat/messages', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Accept': 'text/vnd.turbo-stream.html'
        },
        body: formData
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      // Turbo Streams will handle the response
      
    } catch (error) {
      console.error('Error sending message:', error)
      this.showError('Failed to send message. Please try again.')
    } finally {
      this.hideTypingIndicator()
      this.inputTarget.disabled = false
      this.inputTarget.focus()
    }
  }

  transitionToCompactMode() {
    // Remove welcome message if it exists
    const welcome = document.querySelector('[data-dashboard-chat-welcome]')
    if (welcome) {
      welcome.remove()
    }
    
    // Show compact suggestions bar
    const suggestionsBar = document.getElementById('dashboard-suggestions-compact')
    if (suggestionsBar) {
      suggestionsBar.classList.remove('hidden')
    }
  }

  adjustTextareaHeight() {
    const textarea = this.inputTarget
    textarea.style.height = 'auto'
    const newHeight = Math.min(textarea.scrollHeight, 200)
    textarea.style.height = newHeight + 'px'
  }

  updateCharCount() {
    if (!this.hasCharCountTarget) return
    const length = this.inputTarget.value.length
    this.charCountTarget.textContent = `${length} / ${this.maxLength}`
    
    if (length > this.maxLength) {
      this.charCountTarget.classList.add('text-red-500')
    } else {
      this.charCountTarget.classList.remove('text-red-500')
    }
  }

  updateSendButton() {
    const hasText = this.inputTarget.value.trim().length > 0
    const withinLimit = this.inputTarget.value.length <= this.maxLength
    this.sendButtonTarget.disabled = !hasText || !withinLimit
  }

  showTypingIndicator() {
    const indicator = document.getElementById('dashboard-typing-indicator')
    if (indicator) indicator.classList.remove('hidden')
  }

  hideTypingIndicator() {
    const indicator = document.getElementById('dashboard-typing-indicator')
    if (indicator) indicator.classList.add('hidden')
  }

  showError(message) {
    console.error(message)
    alert(message) // Replace with a nicer toast notification later
  }
}