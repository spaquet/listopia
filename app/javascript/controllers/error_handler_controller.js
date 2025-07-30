// app/javascript/controllers/error_handler_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["notification", "retryButton", "contextInfo"]
  static values = { 
    autoRetry: { type: Boolean, default: true },
    maxRetries: { type: Number, default: 3 },
    retryDelay: { type: Number, default: 2000 },
    autoHide: { type: Boolean, default: false },
    autoHideDelay: { type: Number, default: 5000 },
    persistContext: { type: Boolean, default: true }
  }

  connect() {
    this.retryCount = 0
    this.lastError = null
    this.contextData = {}
    this.setupErrorListeners()
    this.loadPersistedContext()
  }

  setupErrorListeners() {
    // Listen for connection status changes
    document.addEventListener('connection:status-changed', this.handleConnectionChange.bind(this))
    
    // Listen for chat-specific errors
    document.addEventListener('chat:error', this.handleChatError.bind(this))
    document.addEventListener('chat:retry', this.handleRetryRequest.bind(this))
    
    // Listen for form errors
    document.addEventListener('turbo:submit-end', this.handleFormError.bind(this))
    
    // Listen for fetch errors
    document.addEventListener('turbo:fetch-request-error', this.handleFetchError.bind(this))
  }

  handleConnectionChange(event) {
    const { status, isOnline } = event.detail
    
    if (!isOnline) {
      this.showError({
        type: 'connection',
        title: 'Connection Lost',
        message: 'You\'re currently offline. Changes may not be saved.',
        actions: ['retry'],
        persistent: true,
        severity: 'warning'
      })
    } else if (status === 'online' && this.lastError?.type === 'connection') {
      this.showSuccess({
        title: 'Connection Restored',
        message: 'You\'re back online! Attempting to sync changes...',
        autoHide: true
      })
      this.clearError()
      this.syncPendingActions()
    } else if (status === 'degraded') {
      this.showError({
        type: 'connection',
        title: 'Poor Connection',
        message: 'Connection is unstable. Some features may be slow.',
        actions: ['retry'],
        severity: 'warning',
        autoHide: true
      })
    }
  }

  handleChatError(event) {
    const { error, context, retryable } = event.detail
    
    this.storeContext(context)
    
    const errorConfig = {
      type: 'chat',
      title: 'Chat Error',
      message: this.getErrorMessage(error),
      actions: retryable ? ['retry', 'dismiss'] : ['dismiss'],
      severity: 'error',
      context: context
    }
    
    this.showError(errorConfig)
  }

  handleRetryRequest(event) {
    const { originalMessage, context } = event.detail
    this.retryWithContext(originalMessage, context)
  }

  handleFormError(event) {
    if (event.detail.success === false) {
      const response = event.detail.fetchResponse?.response
      if (response && !response.ok) {
        this.showError({
          type: 'form',
          title: 'Form Error',
          message: `Failed to submit form (${response.status})`,
          actions: ['retry', 'dismiss'],
          severity: 'error'
        })
      }
    }
  }

  handleFetchError(event) {
    const { error } = event.detail
    this.showError({
      type: 'fetch',
      title: 'Request Failed',
      message: this.getErrorMessage(error),
      actions: ['retry', 'dismiss'],
      severity: 'error'
    })
  }

  showError(config) {
    this.lastError = config
    this.updateNotificationUI(config)
    
    // Auto-retry if enabled and retryable
    if (this.autoRetryValue && config.actions?.includes('retry') && this.retryCount < this.maxRetriesValue) {
      this.scheduleAutoRetry(config)
    }
    
    // Auto-hide if configured
    if (config.autoHide || (this.autoHideValue && !config.persistent)) {
      this.scheduleAutoHide(config.autoHideDelay || this.autoHideDelayValue)
    }
  }

  showSuccess(config) {
    const successConfig = {
      ...config,
      severity: 'success',
      actions: config.actions || []
    }
    this.updateNotificationUI(successConfig)
    
    if (config.autoHide !== false) {
      this.scheduleAutoHide(config.autoHideDelay || 3000)
    }
  }

  updateNotificationUI(config) {
    if (!this.hasNotificationTarget) return

    const severityClasses = {
      error: 'bg-red-50 border-red-200 text-red-800',
      warning: 'bg-yellow-50 border-yellow-200 text-yellow-800',
      success: 'bg-green-50 border-green-200 text-green-800',
      info: 'bg-blue-50 border-blue-200 text-blue-800'
    }

    const iconSvg = this.getIconForSeverity(config.severity)
    
    this.notificationTarget.innerHTML = `
      <div class="rounded-md border p-4 ${severityClasses[config.severity] || severityClasses.error}">
        <div class="flex">
          <div class="flex-shrink-0">
            ${iconSvg}
          </div>
          <div class="ml-3 flex-1">
            <h3 class="text-sm font-medium">${config.title}</h3>
            <div class="mt-2 text-sm">
              <p>${config.message}</p>
              ${this.renderContextInfo(config.context)}
            </div>
            ${this.renderActions(config.actions)}
          </div>
          <div class="ml-auto pl-3">
            <div class="-mx-1.5 -my-1.5">
              <button data-action="click->error-handler#dismiss" 
                      class="inline-flex rounded-md p-1.5 hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-red-50 focus:ring-red-600">
                <svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"></path>
                </svg>
              </button>
            </div>
          </div>
        </div>
      </div>
    `

    this.notificationTarget.classList.remove('hidden')
  }

  renderContextInfo(context) {
    if (!context || !this.hasContextInfoTarget) return ''
    
    const contextItems = Object.entries(context).map(([key, value]) => 
      `<span class="inline-flex items-center px-2 py-1 rounded text-xs bg-white bg-opacity-50 mr-2 mb-1">
        <strong>${key}:</strong>&nbsp;${value}
      </span>`
    ).join('')
    
    return contextItems ? `<div class="mt-2">${contextItems}</div>` : ''
  }

  renderActions(actions) {
    if (!actions || actions.length === 0) return ''
    
    const actionButtons = actions.map(action => {
      const buttonClasses = {
        retry: 'bg-white bg-opacity-20 hover:bg-opacity-30 text-current border border-current',
        dismiss: 'bg-transparent hover:bg-white hover:bg-opacity-10 text-current',
        reload: 'bg-current text-white hover:opacity-90'
      }
      
      const buttonText = {
        retry: 'Try Again',
        dismiss: 'Dismiss', 
        reload: 'Reload Page'
      }
      
      return `
        <button data-action="click->error-handler#${action}" 
                class="inline-flex items-center px-3 py-1.5 rounded text-xs font-medium transition-colors duration-200 mr-2 ${buttonClasses[action] || buttonClasses.dismiss}">
          ${buttonText[action] || action}
        </button>
      `
    }).join('')
    
    return `<div class="mt-3">${actionButtons}</div>`
  }

  getIconForSeverity(severity) {
    const icons = {
      error: `<svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"></path>
      </svg>`,
      warning: `<svg class="h-5 w-5 text-yellow-400" viewBox="0 0 20 20" fill="currentColor">
        <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path>
      </svg>`,
      success: `<svg class="h-5 w-5 text-green-400" viewBox="0 0 20 20" fill="currentColor">
        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"></path>
      </svg>`,
      info: `<svg class="h-5 w-5 text-blue-400" viewBox="0 0 20 20" fill="currentColor">
        <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"></path>
      </svg>`
    }
    return icons[severity] || icons.error
  }

  getErrorMessage(error) {
    const errorMessages = {
      'TypeError': 'A technical error occurred. Please try again.',
      'NetworkError': 'Network connection failed. Check your internet connection.',
      'AbortError': 'Request was cancelled or timed out.',
      'TimeoutError': 'Request timed out. The server may be busy.',
      'AuthenticationError': 'Authentication failed. Please sign in again.',
      'AuthorizationError': 'You don\'t have permission to perform this action.',
      'ValidationError': 'Please check your input and try again.',
      'ServerError': 'Server error occurred. Please try again later.',
      'ServiceUnavailable': 'Service is temporarily unavailable.'
    }
    
    if (typeof error === 'string') return error
    if (error?.message) return errorMessages[error.constructor.name] || error.message
    return 'An unexpected error occurred. Please try again.'
  }

  // Action handlers
  retry() {
    this.retryCount++
    
    if (this.lastError?.context) {
      this.retryWithContext(this.lastError.context.originalMessage, this.lastError.context)
    } else {
      // Generic retry - reload the page or retry last action
      window.location.reload()
    }
  }

  dismiss() {
    this.clearError()
  }

  reload() {
    window.location.reload()
  }

  // Utility methods
  scheduleAutoRetry(config) {
    const delay = this.retryDelayValue * Math.pow(1.5, this.retryCount)
    
    setTimeout(() => {
      if (this.lastError === config) { // Only retry if this is still the current error
        this.retry()
      }
    }, delay)
  }

  scheduleAutoHide(delay) {
    setTimeout(() => {
      this.clearError()
    }, delay)
  }

  clearError() {
    this.lastError = null
    this.retryCount = 0
    if (this.hasNotificationTarget) {
      this.notificationTarget.classList.add('hidden')
    }
  }

  storeContext(context) {
    if (this.persistContextValue && context) {
      this.contextData = { ...this.contextData, ...context }
      localStorage.setItem('listopia_error_context', JSON.stringify(this.contextData))
    }
  }

  loadPersistedContext() {
    if (this.persistContextValue) {
      try {
        const stored = localStorage.getItem('listopia_error_context')
        if (stored) {
          this.contextData = JSON.parse(stored)
        }
      } catch (error) {
        console.warn('Failed to load persisted context:', error)
      }
    }
  }

  retryWithContext(originalMessage, context) {
    // Dispatch retry event for chat or other components to handle
    const event = new CustomEvent('error-handler:retry', {
      detail: {
        originalMessage,
        context: { ...this.contextData, ...context },
        retryCount: this.retryCount
      },
      bubbles: true
    })
    this.element.dispatchEvent(event)
  }

  syncPendingActions() {
    // Attempt to sync any pending actions when connection is restored
    const event = new CustomEvent('error-handler:sync-pending', {
      detail: { context: this.contextData },
      bubbles: true
    })
    this.element.dispatchEvent(event)
  }

  // Public API
  triggerError(config) {
    this.showError(config)
  }

  triggerSuccess(config) {
    this.showSuccess(config)
  }

  get hasActiveError() {
    return this.lastError !== null
  }
}