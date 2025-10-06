// app/javascript/controllers/dashboard_chat_controller.js
import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="dashboard-chat"
export default class extends Controller {
  static targets = ["messageInput", "sendButton", "messagesContainer", "typingIndicator"]
  static values = {
    context: Object
  }

  connect() {
    console.log("Dashboard chat controller connected")
    this.loadChatHistory()
  }

  async loadChatHistory() {
    try {
      const response = await fetch('/chat/load_history', {
        headers: {
          'Accept': 'text/vnd.turbo-stream.html'
        }
      })
      
      if (response.ok) {
        const html = await response.text()
        // Turbo will handle the stream response automatically
      }
    } catch (error) {
      console.error("Error loading chat history:", error)
    }
  }

  async sendMessage(event) {
    event?.preventDefault()
    
    const message = this.messageInputTarget.value.trim()
    if (!message) return

    // Disable input while processing
    this.setInputState(false)
    this.showTypingIndicator()

    // Clear input immediately for better UX
    this.messageInputTarget.value = ''
    
    // Dispatch event to update character counter
    this.messageInputTarget.dispatchEvent(new Event('input'))

    try {
      const formData = new FormData()
      formData.append('message', message)
      formData.append('current_page', 'dashboard#index')
      
      // Merge context from the view with current state
      const context = {
        ...this.contextValue,
        timestamp: new Date().toISOString()
      }
      formData.append('context', JSON.stringify(context))

      const response = await fetch('/chat/create_message', {
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

      // Turbo Streams will handle appending the messages
      this.hideTypingIndicator()
      this.scrollToBottom()
      
    } catch (error) {
      console.error('Error sending message:', error)
      this.appendErrorMessage('Failed to send message. Please try again.')
    } finally {
      this.setInputState(true)
      this.hideTypingIndicator()
      this.messageInputTarget.focus()
    }
  }

  showTypingIndicator() {
    if (this.hasTypingIndicatorTarget) {
      this.typingIndicatorTarget.classList.remove('hidden')
      this.scrollToBottom()
    }
  }

  hideTypingIndicator() {
    if (this.hasTypingIndicatorTarget) {
      this.typingIndicatorTarget.classList.add('hidden')
    }
  }

  setInputState(enabled) {
    if (!this.hasMessageInputTarget || !this.hasSendButtonTarget) return
    
    this.messageInputTarget.disabled = !enabled
    this.sendButtonTarget.disabled = !enabled
    
    if (enabled) {
      this.sendButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
      this.messageInputTarget.classList.remove('opacity-50')
    } else {
      this.sendButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
      this.messageInputTarget.classList.add('opacity-50')
    }
  }

  scrollToBottom() {
    if (this.hasMessagesContainerTarget) {
      this.messagesContainerTarget.scrollTop = this.messagesContainerTarget.scrollHeight
    }
  }

  appendErrorMessage(message) {
    if (!this.hasMessagesContainerTarget) return

    const errorDiv = document.createElement('div')
    errorDiv.className = 'flex items-start space-x-3 mb-4'
    errorDiv.innerHTML = `
      <div class="flex-shrink-0 w-8 h-8 bg-red-500 rounded-full flex items-center justify-center">
        <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
      </div>
      <div class="bg-red-50 border border-red-200 rounded-lg px-4 py-2.5 max-w-[75%]">
        <p class="text-sm text-red-700 leading-relaxed">${message}</p>
      </div>
    `
    
    this.messagesContainerTarget.appendChild(errorDiv)
    this.scrollToBottom()
  }
}