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
    console.log('Chat controller connected');
    console.log('MessagesContainer target exists:', this.hasMessagesContainerTarget);
    console.log('Element with ID chat-messages:', document.getElementById('chat-messages'));
    this.restoreState();
    this.initializeWithRetry();
    this.logContextInfo();
    this.setupErrorHandling();
  }

  initializeWithRetry() {
    const attemptSetup = (attempts = 3, delay = 100) => {
      if (this.hasMessagesContainerTarget) {
        this.setupMessageContainer();
        this.loadChatHistory();
        if (this.expandedValue) {
          this.focusInput();
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
      });
      
      if (response.ok) {
        const responseText = await response.text();
        if (responseText.trim()) {
          Turbo.renderStreamMessage(responseText);
          this.scrollToBottom();
        }
      }
    } catch (error) {
      console.warn('Could not load chat history:', error);
    }
  }

  toggle() {
    this.expandedValue = !this.expandedValue;
    this.updateDisplay();
    this.saveState();
    
    if (this.expandedValue) {
      this.focusInput();
      this.scrollToBottom();
      this.hideNotificationDot();
    }
  }

  minimize() {
    this.expandedValue = false
    this.updateDisplay()
    this.saveState()
  }

  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      this.sendMessage(event);
    }
  }

  // Method to force UI refresh after AI creates lists
  notifyListCreated(listId) {
    // Dispatch custom event to notify other controllers
    document.dispatchEvent(new CustomEvent('listopia:list-created', {
      detail: { listId: listId }
    }));
    
    // Force refresh of lists if user is on lists page
    if (this.currentPageValue === 'lists#index') {
      this.refreshListsPage();
    }
  }

  async refreshListsPage() {
    try {
      const response = await fetch(window.location.pathname, {
        headers: { 'Accept': 'text/html' }
      });
      
      if (response.ok) {
        const html = await response.text();
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        const newContainer = doc.getElementById('lists-container');
        
        if (newContainer) {
          const currentContainer = document.getElementById('lists-container');
          if (currentContainer) {
            currentContainer.innerHTML = newContainer.innerHTML;
          }
        }
      }
    } catch (error) {
      console.error('Failed to refresh lists:', error);
    }
  }

  async sendMessage(event) {
    event?.preventDefault()
    
    // Get message from either the event detail (keyboard shortcut) or the textarea directly
    const message = event?.detail?.message || this.messageInputTarget.value.trim()
    if (!message) return

    await this.sendMessageWithText(message)
    
    // Clear the textarea and trigger events for other controllers
    this.messageInputTarget.value = ""
    this.messageInputTarget.dispatchEvent(new Event('input', { bubbles: true }))
  }

  // New method to handle sending with specific text
  async sendMessageWithText(message) {
    if (!message || !this.hasMessagesContainerTarget) return

    this.setInputState(false)
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
        // Handle HTTP errors
        const error = new Error(`HTTP ${response.status}: ${response.statusText}`)
        this.handleError(error, { message, type: 'http_error' })
      }
    } catch (error) {
      console.error('Chat error:', error)
      // Handle network/fetch errors  
      this.handleError(error, { message, type: 'network_error' })
    } finally {
      this.hideTypingIndicator()
      this.setInputState(true)
      this.focusInput()
    }
  }

  addUserMessage(message) {
    if (!this.hasMessagesContainerTarget) {
      console.warn("Cannot add user message: messagesContainer target missing")
      return
    }
    
    const messageElement = this.createMessageElement(message, 'user')
    
    // Add timestamp data for threading
    messageElement.dataset.timestamp = new Date().toISOString()
    messageElement.dataset.messageType = 'user'
    
    this.messagesContainerTarget.appendChild(messageElement)
    this.scrollToBottom()
  }

  addAssistantMessage(message) {
    if (!this.hasMessagesContainerTarget) {
      console.warn("Cannot add assistant message: messagesContainer target missing")
      return
    }
    
    const messageElement = this.createMessageElement(message, 'assistant')
    
    // Add timestamp data for threading
    messageElement.dataset.timestamp = new Date().toISOString()
    messageElement.dataset.messageType = 'assistant'
    
    this.messagesContainerTarget.appendChild(messageElement)
    this.scrollToBottom()
  }

  addErrorMessage(message) {
    if (!this.hasMessagesContainerTarget) {
      console.warn("Cannot add error message: messagesContainer target missing");
      return;
    }
    const messageElement = this.createMessageElement(message, 'error');
    this.messagesContainerTarget.appendChild(messageElement);
    this.scrollToBottom();
  }

  addSuccessMessage(message) {
    if (!this.hasMessagesContainerTarget) {
      console.warn("Cannot add success message: messagesContainer target missing");
      return;
    }
    const messageElement = this.createMessageElement(message, 'success');
    this.messagesContainerTarget.appendChild(messageElement);
    this.scrollToBottom();
  }

  createMessageElement(message, type) {
    const messageDiv = document.createElement('div');
    messageDiv.className = 'flex items-start space-x-3 mb-4';
    
    const isUser = type === 'user';
    const isError = type === 'error';
    const isSuccess = type === 'success';  // NEW
    
    if (isUser) {
      messageDiv.classList.add('justify-end');
    }

    const avatarDiv = document.createElement('div');
    // Updated to handle success type
    avatarDiv.className = `flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center ${
      isUser ? 'bg-blue-600' : 
      isError ? 'bg-red-500' : 
      isSuccess ? 'bg-green-500' :  // NEW
      'bg-gray-400'
    }`;

    // Icon for success
    if (isSuccess) {
      avatarDiv.innerHTML = `
        <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
        </svg>
      `;
    } else if (isUser) {
      // existing user icon
      avatarDiv.innerHTML = `...`;
    } else if (isError) {
      // existing error icon
      avatarDiv.innerHTML = `...`;
    } else {
      // existing AI icon
      avatarDiv.innerHTML = `...`;
    }

    const messageContentDiv = document.createElement('div');
    messageContentDiv.className = `rounded-lg px-4 py-2 max-w-[80%] ${
      isUser ? 'bg-blue-600 text-white order-1' : 
      isError ? 'bg-red-100 border border-red-200 text-red-700' : 
      isSuccess ? 'bg-green-50 border border-green-200 text-green-900' :  // NEW
      'bg-gray-50 border text-gray-700'
    }`;

    const messageText = document.createElement('p');
    messageText.className = `text-sm leading-relaxed ${
      isUser ? 'text-white' : 
      isError ? 'text-red-700' : 
      isSuccess ? 'text-green-900' :  // NEW
      'text-gray-700'
    }`;
    messageText.textContent = message;

    messageContentDiv.appendChild(messageText);
    messageDiv.appendChild(avatarDiv);
    messageDiv.appendChild(messageContentDiv);

    return messageDiv;
  }

  showTypingIndicator() {
    if (this.hasTypingIndicatorTarget) {
      this.typingIndicatorTarget.classList.remove('hidden');
      this.scrollToBottom();
    }
  }

  hideTypingIndicator() {
    if (this.hasTypingIndicatorTarget) {
      this.typingIndicatorTarget.classList.add('hidden');
    }
  }

  showNotificationDot() {
    if (!this.expandedValue && this.hasNotificationDotTarget) {
      this.notificationDotTarget.classList.remove('hidden');
    }
  }

  hideNotificationDot() {
    if (this.hasNotificationDotTarget) {
      this.notificationDotTarget.classList.add('hidden');
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

  updateDisplay() {
    if (this.hasToggleButtonTarget && this.hasChatWindowTarget) {
      if (this.expandedValue) {
        this.toggleButtonTarget.style.display = 'none';
        this.chatWindowTarget.style.display = 'flex';
      } else {
        this.toggleButtonTarget.style.display = 'block';
        this.chatWindowTarget.style.display = 'none';
      }
    }
  }

  setupMessageContainer() {
    if (!this.hasMessagesContainerTarget) {
      console.warn("Cannot setup message container: messagesContainer target missing");
      return;
    }
    
    if (this.messageObserver) {
      this.messageObserver.disconnect();
    }
    
    this.messageObserver = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
          this.scrollToBottom();
        }
      });
    });
    
    this.messageObserver.observe(this.messagesContainerTarget, {
      childList: true,
      subtree: true
    });
  }

  scrollToBottom() {
    const scrollController = this.application.getControllerForElementAndIdentifier(
      this.element.querySelector('[data-controller*="chat-scroll"]'),
      'chat-scroll'
    )
    
    if (scrollController) {
      scrollController.autoScrollToBottom()
    } else {
      // Fallback to original implementation
      if (!this.hasMessagesContainerTarget) return
      setTimeout(() => {
        this.messagesContainerTarget.scrollTop = this.messagesContainerTarget.scrollHeight
      }, 50)
    }
  }

  // Handle scroll events from scroll controller
  handleScroll(event) {
    const { isNearBottom, direction } = event.detail
    
    // Show/hide notification dot based on scroll position
    if (!this.expandedValue && direction === 'up' && !isNearBottom) {
      // User scrolled up and away from bottom - they might have missed messages
      this.showNotificationDot()
    }
  }

  focusInput() {
    if (this.expandedValue && this.hasMessageInputTarget) {
      setTimeout(() => {
        this.messageInputTarget.focus();
      }, 100);
    }
  }

  saveState() {
    localStorage.setItem('listopia_chat_expanded', this.expandedValue);
  }

  restoreState() {
    const saved = localStorage.getItem('listopia_chat_expanded');
    if (saved !== null) {
      this.expandedValue = saved === 'true';
      this.updateDisplay();
    }
  }

  handleNewMessage(message, type = 'assistant') {
    if (type === 'assistant') {
      this.addAssistantMessage(message);
    }
    
    if (!this.expandedValue) {
      this.showNotificationDot();
    }
  }

  disconnect() {
    this.saveState();
    
    if (this.messageObserver) {
      this.messageObserver.disconnect();
    }
  }

  logContextInfo() {
    if (this.hasContextValue) {
      console.log('Chat Context:', {
        page: this.currentPageValue,
        context: this.contextValue,
        userId: this.userIdValue
      });
    }
  }

  getCurrentContext() {
    return {
      page: this.currentPageValue,
      context: this.contextValue,
      userId: this.userIdValue,
      timestamp: new Date().toISOString()
    };
  }

  showContextSuggestions() {
    if (this.hasContextValue && this.contextValue.suggestions) {
      return this.contextValue.suggestions;
    }
    return [];
  }

  setupErrorHandling() {
  document.addEventListener('error-handler:retry', this.handleRetryRequest.bind(this))
  document.addEventListener('connection:status-changed', this.handleConnectionChange.bind(this))
}

  handleError(error, context = {}) {
    const errorEvent = new CustomEvent('chat:error', {
      detail: {
        error,
        context: {
          ...context,
          chatId: this.userIdValue,
          currentPage: this.currentPageValue,
          timestamp: new Date().toISOString(),
          originalMessage: context.message || context.originalMessage
        },
        retryable: this.isRetryableError(error)
      },
      bubbles: true
    })
    document.dispatchEvent(errorEvent)
  }

  isRetryableError(error) {
    const retryableErrors = [
      'NetworkError',
      'AbortError', 
      'TimeoutError',
      'TypeError'
    ]
    
    if (typeof error === 'string') {
      return retryableErrors.some(type => error.includes(type))
    }
    
    return retryableErrors.includes(error?.constructor?.name)
  }

  handleRetryRequest(event) {
    const { originalMessage, context } = event.detail
    
    if (context.chatId === this.userIdValue && originalMessage) {
      console.log('Retrying chat message:', originalMessage)
      this.sendMessageWithText(originalMessage)
    }
  }

  handleConnectionChange(event) {
    const { status, isOnline } = event.detail
    
    // Update send button state based on connection
    if (this.hasSendButtonTarget) {
      if (!isOnline) {
        this.sendButtonTarget.disabled = true
        this.sendButtonTarget.title = 'Offline - Cannot send messages'
      } else {
        this.sendButtonTarget.disabled = false
        this.sendButtonTarget.title = 'Send message'
      }
    }
  }
}