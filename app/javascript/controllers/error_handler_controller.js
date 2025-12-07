// app/javascript/controllers/error_handler_controller.js
// Simplified version focused on basic chat and form error handling
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["notification"]
  static values = { 
    autoRetry: { type: Boolean, default: false },
    maxRetries: { type: Number, default: 2 },
    retryDelay: { type: Number, default: 2000 },
    autoHide: { type: Boolean, default: true },
    autoHideDelay: { type: Number, default: 5000 }
  }

  connect() {
    this.retryCount = 0
    this.lastError = null
    this.setupErrorListeners()
  }

  setupErrorListeners() {
    // Listen for connection status changes
    document.addEventListener('connection:status-changed', this.handleConnectionChange.bind(this))
    
    // Listen for chat-specific errors
    document.addEventListener('chat:error', this.handleChatError.bind(this))
    
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
        actions: ['dismiss'],
        severity: 'warning'
      })
    } else if (status === 'online' && this.lastError?.type === 'connection') {
      this.showSuccess({
        title: 'Connection Restored',
        message: 'You\'re back online!',
        autoHide: true
      })
      this.clearError()
    }
  }

  handleChatError(event) {
    const { error, retryable } = event.detail
    
    const errorConfig = {
      type: 'chat',
      title: 'Chat Error',
      message: this.getErrorMessage(error),
      actions: retryable ? ['retry', 'dismiss'] : ['dismiss'],
      severity: 'error'
    }
    
    this.showError(errorConfig)
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
    
    // Auto-hide if configured
    if (config.autoHide || this.autoHideValue) {
      this.scheduleAutoHide(config.autoHideDelay || this.autoHideDelayValue)
    }
  }

  showSuccess(config) {
    this.updateNotificationUI({
      ...config,
      severity: 'success'
    })
    
    if (config.autoHide !== false) {
      this.scheduleAutoHide(config.autoHideDelay || 3000)
    }
  }

  updateNotificationUI(config) {
    if (!this.hasNotificationTarget) {
      // Create notification if it doesn't exist
      this.createNotificationElement()
    }
    
    const { title, message, actions, severity } = config
    const severityClasses = {
      error: 'bg-red-600 border-red-500',
      warning: 'bg-yellow-600 border-yellow-500', 
      success: 'bg-green-600 border-green-500',
      info: 'bg-blue-600 border-blue-500'
    }
    
    const baseClasses = 'fixed top-4 right-4 z-50 max-w-sm p-4 rounded-lg shadow-lg text-white border-l-4 transition-all duration-300'
    const severityClass = severityClasses[severity] || severityClasses.error
    
    this.notificationTarget.className = `${baseClasses} ${severityClass}`
    this.notificationTarget.innerHTML = `
      <div class="flex items-start">
        <div class="flex-shrink-0">
          ${this.getIconForSeverity(severity)}
        </div>
        <div class="ml-3 flex-1">
          <h3 class="text-sm font-medium">${title}</h3>
          <p class="mt-1 text-sm opacity-90">${message}</p>
          ${this.renderActions(actions)}
        </div>
        <div class="ml-4 flex-shrink-0">
          <button data-action="click->error-handler#dismiss" 
                  class="inline-flex text-white hover:text-gray-200 focus:outline-none">
            <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"></path>
            </svg>
          </button>
        </div>
      </div>
    `
    
    // Show the notification
    this.notificationTarget.classList.remove('hidden')
  }

  createNotificationElement() {
    const notification = document.createElement('div')
    notification.setAttribute('data-error-handler-target', 'notification')
    notification.className = 'hidden'
    document.body.appendChild(notification)
  }

  renderActions(actions) {
    if (!actions || actions.length === 0) return ''
    
    const actionButtons = actions.map(action => {
      const buttonText = {
        retry: 'Try Again',
        dismiss: 'Dismiss', 
        reload: 'Reload Page'
      }
      
      return `
        <button data-action="click->error-handler#${action}"
                class="inline-flex items-center px-2 py-1 mt-2 mr-2 text-xs font-medium bg-white bg-opacity-90 hover:bg-opacity-100 text-gray-900 rounded border border-white transition-colors duration-200">
          ${buttonText[action] || action}
        </button>
      `
    }).join('')
    
    return `<div class="mt-2">${actionButtons}</div>`
  }

  getIconForSeverity(severity) {
    const icons = {
      error: `<svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"></path>
      </svg>`,
      warning: `<svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path>
      </svg>`,
      success: `<svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"></path>
      </svg>`,
      info: `<svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
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
      'TimeoutError': 'Request timed out. Please try again.',
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
    
    // Simple retry - just reload the page or dispatch a retry event
    if (this.lastError?.type === 'chat') {
      // Let the chat controller handle the retry
      document.dispatchEvent(new CustomEvent('chat:retry-requested', {
        detail: { error: this.lastError }
      }))
    } else {
      // For other errors, just reload
      window.location.reload()
    }
    
    this.clearError()
  }

  dismiss() {
    this.clearError()
  }

  reload() {
    window.location.reload()
  }

  // Utility methods
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

  // Public API for other controllers to use
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