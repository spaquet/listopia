// app/javascript/controllers/chat_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    userId: String, 
    expanded: Boolean 
  }
  
  static targets = [
    "toggleButton",
    "chatWindow", 
    "messagesContainer",
    "messageInput",
    "messageForm",
    "sendButton",
    "typingIndicator",
    "notificationDot"
  ]

  connect() {
    this.restoreState()
    this.setupMessageContainer()
    // Focus input when window is expanded
    if (this.expandedValue) {
      this.focusInput()
    }
  }

  toggle() {
    this.expandedValue = !this.expandedValue
    this.updateDisplay()
    this.saveState()
    
    if (this.expandedValue) {
      this.focusInput()
      this.scrollToBottom()
      this.hideNotificationDot()
    }
  }

  minimize() {
    this.expandedValue = false
    this.updateDisplay()
    this.saveState()
  }

  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.sendMessage(event)
    }
  }

  async sendMessage(event) {
    event.preventDefault()
    
    const message = this.messageInputTarget.value.trim()
    if (!message) return

    // Disable input and button while sending
    this.setInputState(false)
    
    // Add user message to chat immediately
    this.addUserMessage(message)
    
    // Clear input
    this.messageInputTarget.value = ""
    
    // Show typing indicator
    this.showTypingIndicator()

    try {
      // Send message to backend
      const response = await fetch('/chat/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ message: message })
      })

      if (response.ok) {
        // Response will be handled via Turbo Stream
        // The server will send back a turbo stream to add assistant message
      } else {
        this.addErrorMessage("Sorry, I couldn't process your message. Please try again.")
      }
    } catch (error) {
      console.error('Chat error:', error)
      this.addErrorMessage("Connection error. Please check your internet and try again.")
    } finally {
      this.hideTypingIndicator()
      this.setInputState(true)
      this.focusInput()
    }
  }

  addUserMessage(message) {
    const messageElement = this.createMessageElement(message, 'user')
    this.messagesContainerTarget.appendChild(messageElement)
    this.scrollToBottom()
  }

  addAssistantMessage(message) {
    const messageElement = this.createMessageElement(message, 'assistant')
    this.messagesContainerTarget.appendChild(messageElement)
    this.scrollToBottom()
  }

  addErrorMessage(message) {
    const messageElement = this.createMessageElement(message, 'error')
    this.messagesContainerTarget.appendChild(messageElement)
    this.scrollToBottom()
  }

  createMessageElement(message, type) {
    const messageDiv = document.createElement('div')
    messageDiv.className = 'flex items-start space-x-2'
    
    const isUser = type === 'user'
    const isError = type === 'error'
    
    if (isUser) {
      messageDiv.classList.add('justify-end')
    }

    const avatarDiv = document.createElement('div')
    avatarDiv.className = `flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center ${isUser ? 'order-2' : ''}`
    
    if (isUser) {
      avatarDiv.className += ' bg-blue-600'
      avatarDiv.innerHTML = `
        <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"></path>
        </svg>
      `
    } else if (isError) {
      avatarDiv.className += ' bg-red-500'
      avatarDiv.innerHTML = `
        <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"></path>
        </svg>
      `
    } else {
      avatarDiv.className += ' bg-gradient-to-r from-purple-500 to-pink-500'
      avatarDiv.innerHTML = `
        <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"></path>
        </svg>
      `
    }

    const messageContentDiv = document.createElement('div')
    messageContentDiv.className = `rounded-lg px-3 py-2 max-w-xs shadow-sm ${isUser ? 'order-1' : ''}`
    
    if (isUser) {
      messageContentDiv.className += ' bg-blue-600 text-white'
    } else if (isError) {
      messageContentDiv.className += ' bg-red-100 border border-red-200'
    } else {
      messageContentDiv.className += ' bg-white border'
    }

    const messageText = document.createElement('p')
    messageText.className = `text-sm ${isUser ? 'text-white' : isError ? 'text-red-700' : 'text-gray-700'}`
    messageText.textContent = message

    messageContentDiv.appendChild(messageText)
    messageDiv.appendChild(avatarDiv)
    messageDiv.appendChild(messageContentDiv)

    return messageDiv
  }

  showTypingIndicator() {
    this.typingIndicatorTarget.classList.remove('hidden')
    this.scrollToBottom()
  }

  hideTypingIndicator() {
    this.typingIndicatorTarget.classList.add('hidden')
  }

  showNotificationDot() {
    if (!this.expandedValue) {
      this.notificationDotTarget.classList.remove('hidden')
    }
  }

  hideNotificationDot() {
    this.notificationDotTarget.classList.add('hidden')
  }

  setInputState(enabled) {
    this.messageInputTarget.disabled = !enabled
    this.sendButtonTarget.disabled = !enabled
    
    if (enabled) {
      this.sendButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
    } else {
      this.sendButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
    }
  }

  updateDisplay() {
    if (this.expandedValue) {
      this.toggleButtonTarget.classList.add('hidden')
      this.chatWindowTarget.classList.remove('hidden')
    } else {
      this.toggleButtonTarget.classList.remove('hidden')
      this.chatWindowTarget.classList.add('hidden')
    }
  }

  setupMessageContainer() {
    // Auto-scroll behavior for messages container
    this.messagesContainerTarget.addEventListener('DOMNodeInserted', () => {
      this.scrollToBottom()
    })
  }

  scrollToBottom() {
    // Small delay to ensure DOM has updated
    setTimeout(() => {
      this.messagesContainerTarget.scrollTop = this.messagesContainerTarget.scrollHeight
    }, 50)
  }

  focusInput() {
    if (this.expandedValue && this.hasMessageInputTarget) {
      setTimeout(() => {
        this.messageInputTarget.focus()
      }, 100)
    }
  }

  saveState() {
    localStorage.setItem('listopia_chat_expanded', this.expandedValue)
  }

  restoreState() {
    const saved = localStorage.getItem('listopia_chat_expanded')
    if (saved !== null) {
      this.expandedValue = saved === 'true'
      this.updateDisplay()
    }
  }

  // Method to be called when new messages arrive via Turbo Stream
  handleNewMessage(message, type = 'assistant') {
    if (type === 'assistant') {
      this.addAssistantMessage(message)
    }
    
    // Show notification if chat is closed
    if (!this.expandedValue) {
      this.showNotificationDot()
    }
  }

  // Cleanup when controller disconnects
  disconnect() {
    this.saveState()
  }
}