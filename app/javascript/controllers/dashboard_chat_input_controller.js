// app/javascript/controllers/dashboard_chat_input_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "sendButton", "charCount"]
  static values = {
    context: Object
  }

  connect() {
    console.log("Dashboard chat input connected")
    this.maxLength = 2000
    this.adjustTextareaHeight()
    this.loadChatHistory()
  }

  async loadChatHistory() {
    console.log("Loading dashboard chat history...")
    try {
      const response = await fetch('/chat/dashboard_history', {
        headers: {
          'Accept': 'text/vnd.turbo-stream.html',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      if (response.ok) {
        const html = await response.text()
        console.log("Dashboard chat history received, length:", html.length)
        
        // CRITICAL: Manually render the Turbo Stream
        if (typeof Turbo !== 'undefined' && Turbo.renderStreamMessage) {
          console.log("Rendering Turbo Stream manually...")
          Turbo.renderStreamMessage(html)
          console.log("✅ Turbo Stream rendered")
        } else {
          console.error("❌ Turbo.renderStreamMessage not available!")
        }
      } else {
        console.error("Failed to load dashboard chat history:", response.status)
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
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault()
      this.sendMessage()
    }
  }

  useSuggestion(event) {
    const suggestion = event.currentTarget.dataset.suggestion
    console.log("Using suggestion:", suggestion)
    this.inputTarget.value = suggestion
    this.handleInput()
    this.inputTarget.focus()
  }

  async sendMessage() {
    const message = this.inputTarget.value.trim()
    if (!message || message.length > this.maxLength) return

    console.log("Sending dashboard message:", message)

    this.inputTarget.disabled = true
    this.sendButtonTarget.disabled = true
    this.showTypingIndicator()

    const userMessage = message
    this.inputTarget.value = ''
    this.handleInput()

    try {
      const formData = new FormData()
      formData.append('message', userMessage)
      formData.append('current_page', 'dashboard#index')
      
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

      // CRITICAL: Manually render the Turbo Stream response
      const html = await response.text()
      console.log("Message response received, rendering Turbo Stream...")
      
      if (typeof Turbo !== 'undefined' && Turbo.renderStreamMessage) {
        Turbo.renderStreamMessage(html)
        console.log("✅ Message Turbo Stream rendered")
      } else {
        console.error("❌ Turbo.renderStreamMessage not available!")
      }
      
    } catch (error) {
      console.error('Error sending message:', error)
      this.showError('Failed to send message. Please try again.')
      this.inputTarget.value = userMessage
      this.handleInput()
    } finally {
      this.hideTypingIndicator()
      this.inputTarget.disabled = false
      this.inputTarget.focus()
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
    if (indicator) {
      indicator.classList.remove('hidden')
      console.log("Showing typing indicator")
    }
  }

  hideTypingIndicator() {
    const indicator = document.getElementById('dashboard-typing-indicator')
    if (indicator) {
      indicator.classList.add('hidden')
      console.log("Hiding typing indicator")
    }
  }

  showError(message) {
    console.error(message)
    alert(message)
  }
}