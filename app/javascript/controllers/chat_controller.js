// app/javascript/controllers/chat_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    userId: String, 
    expanded: Boolean,
    context: Object,
    currentPage: String
  }
  
  static targets = [
    "toggleButton",
    "chatWindow", 
    "messagesContainer",
    "messageInput",
    "sendButton",
    "typingIndicator",
    "notificationDot"
  ]

  connect() {
    this.restoreState()
    this.initializeWithRetry()
    this.logContextInfo() // Debug context information
  }

  initializeWithRetry() {
    // Attempt to set up message container with retry mechanism
    const attemptSetup = (attempts = 3, delay = 100) => {
      if (this.hasMessagesContainerTarget) {
        this.setupMessageContainer()
        this.loadChatHistory()
        if (this.expandedValue) {
          this.focusInput()
        }
      } else if (attempts > 0) {
        console.warn(`MessagesContainer target not found, retrying... (${attempts} attempts left)`);
        setTimeout(() => attemptSetup(attempts - 1, delay * 2), delay);
      } else {
        console.error("Failed to find messagesContainer target after retries");
      }
    };
    
    attemptSetup();
  }

  async loadChatHistory() {
    if (!this.hasMessagesContainerTarget) {
      console.warn("Cannot load chat history: messagesContainer target missing");
      return;
    }
    
    try {
      const response = await fetch('/chat/history', {
        method: 'GET',
        headers: {
          'Accept': 'text/vnd.turbo-stream.html',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })
      
      if (response.ok) {
        const responseText = await response.text()
        if (responseText.trim()) {
          Turbo.renderStreamMessage(responseText)
          this.scrollToBottom()
        }
      }
    } catch (error) {
      console.warn('Could not load chat history:', error)
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
    event?.preventDefault()
    
    const message = this.messageInputTarget.value.trim()
    if (!message) return

    if (!this.hasMessagesContainerTarget) {
      console.warn("Cannot send message: messagesContainer target missing");
      return;
    }

    this.setInputState(false)
    this.addUserMessage(message)
    this.messageInputTarget.value = ""
    this.showTypingIndicator()

    try {
      const formData = new FormData()
      formData.append('message', message)
      formData.append('current_page', this.currentPageValue)
      
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
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'text/vnd.turbo-stream.html'
        },
        body: formData
      })

      if (response.ok) {
        const responseText = await response.text()
        if (responseText.trim()) {
          Turbo.renderStreamMessage(responseText)
        }
      } else {
        console.error('Response not ok:', response.status)
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
    if (!this.hasMessagesContainerTarget) {
      console.warn("Cannot add user message: messagesContainer target missing");
      return;
    }
    const messageElement = this.createMessageElement(message, 'user')
    this.messagesContainerTarget.appendChild(messageElement)
    this.scrollToBottom()
  }

  addAssistantMessage(message) {
    if (!this.hasMessagesContainerTarget) {
      console.warn("Cannot add assistant message: messagesContainer target missing");
      return;
    }
    const messageElement = this.createMessageElement(message, 'assistant')
    this.messagesContainerTarget.appendChild(messageElement)
    this.scrollToBottom()
  }

  addErrorMessage(message) {
    if (!this.hasMessagesContainerTarget) {
      console.warn("Cannot add error message: messagesContainer target missing");
      return;
    }
    const messageElement = this.createMessageElement(message, 'error')
    this.messagesContainerTarget.appendChild(messageElement)
    this.scrollToBottom()
  }

  createMessageElement(message, type) {
    const messageDiv = document.createElement('div')
    messageDiv.className = 'flex items-start space-x-3 mb-4'
    
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
    messageContentDiv.className = `rounded-lg px-4 py-2.5 max-w-[75%] shadow-sm ${isUser ? 
      'bg-blue-600 text-white order-1' : 
      isError ? 'bg-red-100 border border-red-200' : 'bg-gray-50 border'}`

    const messageText = document.createElement('p')
    messageText.className = `text-sm leading-relaxed ${isUser ? 'text-white' : isError ? 'text-red-700' : 'text-gray-700'}`
    messageText.textContent = message

    messageContentDiv.appendChild(messageText)
    messageDiv.appendChild(avatarDiv)
    messageDiv.appendChild(messageContentDiv)

    return messageDiv
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

  showNotificationDot() {
    if (!this.expandedValue && this.hasNotificationDotTarget) {
      this.notificationDotTarget.classList.remove('hidden')
    }
  }

  hideNotificationDot() {
    if (this.hasNotificationDotTarget) {
      this.notificationDotTarget.classList.add('hidden')
    }
  }

  setInputState(enabled) {
    if (!this.hasMessageInputTarget || !this.hasSendButtonTarget) return;
    
    this.messageInputTarget.disabled = !enabled
    this.sendButtonTarget.disabled = !enabled
    
    if (enabled) {
      this.sendButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
    } else {
      this.sendButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
    }
  }

  updateDisplay() {
    if (this.hasToggleButtonTarget && this.hasChatWindowTarget) {
      if (this.expandedValue) {
        this.toggleButtonTarget.style.display = 'none'
        this.chatWindowTarget.style.display = 'flex'
      } else {
        this.toggleButtonTarget.style.display = 'block'
        this.chatWindowTarget.style.display = 'none'
      }
    }
  }

  setupMessageContainer() {
    if (!this.hasMessagesContainerTarget) {
      console.warn("Cannot setup message container: messagesContainer target missing");
      return;
    }
    
    if (this.messageObserver) {
      this.messageObserver.disconnect()
    }
    
    this.messageObserver = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
          this.scrollToBottom()
        }
      })
    })
    
    this.messageObserver.observe(this.messagesContainerTarget, {
      childList: true,
      subtree: true
    })
  }

  scrollToBottom() {
    if (!this.hasMessagesContainerTarget) return;
    
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

  handleNewMessage(message, type = 'assistant') {
    if (type === 'assistant') {
      this.addAssistantMessage(message)
    }
    
    if (!this.expandedValue) {
      this.showNotificationDot()
    }
  }

  disconnect() {
    this.saveState()
    
    if (this.messageObserver) {
      this.messageObserver.disconnect()
    }
  }

  logContextInfo() {
    if (this.hasContextValue) {
      console.log('Chat Context:', {
        page: this.currentPageValue,
        context: this.contextValue,
        userId: this.userIdValue
      })
    }
  }

  getCurrentContext() {
    return {
      page: this.currentPageValue,
      context: this.contextValue,
      userId: this.userIdValue,
      timestamp: new Date().toISOString()
    }
  }

  showContextSuggestions() {
    if (this.hasContextValue && this.contextValue.suggestions) {
      return this.contextValue.suggestions
    }
    return []
  }
}