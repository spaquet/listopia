// app/javascript/controllers/connection_status_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["indicator", "status", "message"]
  static values = { 
    checkInterval: { type: Number, default: 30000 }, // 30 seconds
    timeoutDuration: { type: Number, default: 10000 }, // 10 seconds
    retryAttempts: { type: Number, default: 3 },
    retryDelay: { type: Number, default: 1000 } // 1 second base delay
  }

  connect() {
    this.isOnline = navigator.onLine
    this.connectionState = 'unknown'
    this.retryCount = 0
    this.setupEventListeners()
    this.startPeriodicCheck()
    this.checkConnection()
  }

  disconnect() {
    this.cleanup()
  }

  setupEventListeners() {
    // Browser online/offline events
    window.addEventListener('online', this.handleOnline.bind(this))
    window.addEventListener('offline', this.handleOffline.bind(this))
    
    // ActionCable connection events (if available)
    if (window.consumer) {
      window.consumer.subscriptions.subscriptions.forEach(subscription => {
        if (subscription.consumer) {
          subscription.consumer.connection.monitor.addEventListener('connected', this.handleCableConnected.bind(this))
          subscription.consumer.connection.monitor.addEventListener('disconnected', this.handleCableDisconnected.bind(this))
          subscription.consumer.connection.monitor.addEventListener('rejected', this.handleCableRejected.bind(this))
        }
      })
    }

    // Turbo events for failed requests
    document.addEventListener('turbo:fetch-request-error', this.handleTurboError.bind(this))
    document.addEventListener('turbo:frame-missing', this.handleTurboError.bind(this))
  }

  startPeriodicCheck() {
    this.checkTimer = setInterval(() => {
      this.checkConnection()
    }, this.checkIntervalValue)
  }

  async checkConnection() {
    if (!navigator.onLine) {
      this.updateConnectionState('offline')
      return
    }

    try {
      // Use Rails 8's built-in health check endpoint
      const controller = new AbortController()
      const timeoutId = setTimeout(() => controller.abort(), this.timeoutDurationValue)

      const response = await fetch('/up', {
        method: 'HEAD',
        signal: controller.signal,
        cache: 'no-cache',
        headers: {
          'X-Connection-Check': 'true'
        }
      })

      clearTimeout(timeoutId)

      if (response.ok) {
        this.updateConnectionState('online')
        this.retryCount = 0
      } else {
        this.updateConnectionState('degraded')
      }
    } catch (error) {
      console.warn('Connection check failed:', error.name)
      
      if (error.name === 'AbortError') {
        this.updateConnectionState('slow')
      } else {
        this.updateConnectionState('offline')
      }
      
      this.scheduleRetry()
    }
  }

  scheduleRetry() {
    if (this.retryCount < this.retryAttemptsValue) {
      this.retryCount++
      const delay = this.retryDelayValue * Math.pow(2, this.retryCount - 1) // Exponential backoff
      
      setTimeout(() => {
        this.checkConnection()
      }, delay)
    }
  }

  updateConnectionState(newState) {
    if (this.connectionState === newState) return

    const previousState = this.connectionState
    this.connectionState = newState
    
    this.updateUI()
    this.dispatchConnectionEvent(newState, previousState)
  }

  updateUI() {
    const states = {
      online: {
        class: 'bg-green-500',
        status: 'Online',
        message: 'Connected to server',
        icon: this.getOnlineIcon()
      },
      offline: {
        class: 'bg-red-500',
        status: 'Offline',
        message: 'No internet connection',
        icon: this.getOfflineIcon()
      },
      degraded: {
        class: 'bg-yellow-500',
        status: 'Degraded', 
        message: 'Connection issues detected',
        icon: this.getWarningIcon()
      },
      slow: {
        class: 'bg-orange-500',
        status: 'Slow',
        message: 'Slow connection detected',
        icon: this.getSlowIcon()
      },
      unknown: {
        class: 'bg-gray-500',
        status: 'Unknown',
        message: 'Checking connection...',
        icon: this.getUnknownIcon()
      }
    }

    const state = states[this.connectionState] || states.unknown

    // Update indicator
    if (this.hasIndicatorTarget) {
      this.indicatorTarget.className = `w-2 h-2 rounded-full transition-colors duration-200 ${state.class}`
    }

    // Update status text
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = state.status
      this.statusTarget.className = `text-xs font-medium ${this.getStatusTextColor()}`
    }

    // Update message
    if (this.hasMessageTarget) {
      this.messageTarget.innerHTML = `${state.icon} ${state.message}`
    }
  }

  getStatusTextColor() {
    const colors = {
      online: 'text-green-700',
      offline: 'text-red-700', 
      degraded: 'text-yellow-700',
      slow: 'text-orange-700',
      unknown: 'text-gray-700'
    }
    return colors[this.connectionState] || colors.unknown
  }

  dispatchConnectionEvent(newState, previousState) {
    const event = new CustomEvent('connection:status-changed', {
      detail: {
        status: newState,
        previousStatus: previousState,
        isOnline: newState === 'online',
        timestamp: new Date().toISOString()
      },
      bubbles: true
    })
    this.element.dispatchEvent(event)
  }

  // Event handlers
  handleOnline() {
    this.isOnline = true
    this.checkConnection()
  }

  handleOffline() {
    this.isOnline = false
    this.updateConnectionState('offline')
  }

  handleCableConnected() {
    if (this.connectionState !== 'online') {
      this.checkConnection()
    }
  }

  handleCableDisconnected() {
    this.updateConnectionState('degraded')
  }

  handleCableRejected() {
    this.updateConnectionState('offline')
  }

  handleTurboError(event) {
    console.warn('Turbo request failed:', event.detail)
    if (this.connectionState === 'online') {
      this.checkConnection()
    }
  }

  // Icon methods
  getOnlineIcon() {
    return `<svg class="w-4 h-4 text-green-600 inline mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
    </svg>`
  }

  getOfflineIcon() {
    return `<svg class="w-4 h-4 text-red-600 inline mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18.364 5.636l-12.728 12.728m0-12.728l12.728 12.728"></path>
    </svg>`
  }

  getWarningIcon() {
    return `<svg class="w-4 h-4 text-yellow-600 inline mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"></path>
    </svg>`
  }

  getSlowIcon() {
    return `<svg class="w-4 h-4 text-orange-600 inline mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
    </svg>`
  }

  getUnknownIcon() {
    return `<svg class="w-4 h-4 text-gray-600 inline mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
    </svg>`
  }

  cleanup() {
    if (this.checkTimer) {
      clearInterval(this.checkTimer)
    }
    
    window.removeEventListener('online', this.handleOnline.bind(this))
    window.removeEventListener('offline', this.handleOffline.bind(this))
    document.removeEventListener('turbo:fetch-request-error', this.handleTurboError.bind(this))
    document.removeEventListener('turbo:frame-missing', this.handleTurboError.bind(this))
  }

  // Public methods for manual checks
  forceCheck() {
    this.retryCount = 0
    this.checkConnection()
  }

  get isConnected() {
    return this.connectionState === 'online'
  }

  get connectionStatus() {
    return {
      state: this.connectionState,
      isOnline: this.isOnline,
      retryCount: this.retryCount
    }
  }
}