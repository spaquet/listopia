// app/javascript/controllers/realtime_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    listId: String, 
    userId: String,
    websocketUrl: String 
  }

  connect() {
    if (this.websocketUrlValue) {
      this.connectWebSocket()
    } else {
      // Fallback to polling for updates
      this.startPolling()
    }
  }

  disconnect() {
    if (this.websocket) {
      this.websocket.close()
    }
    
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval)
    }
  }

  connectWebSocket() {
    this.websocket = new WebSocket(this.websocketUrlValue)
    
    this.websocket.onopen = () => {
      console.log('WebSocket connected')
      // Subscribe to list updates
      this.websocket.send(JSON.stringify({
        action: 'subscribe',
        list_id: this.listIdValue
      }))
    }
    
    this.websocket.onmessage = (event) => {
      const data = JSON.parse(event.data)
      this.handleRealtimeUpdate(data)
    }
    
    this.websocket.onclose = () => {
      console.log('WebSocket disconnected')
      // Attempt to reconnect after 3 seconds
      setTimeout(() => {
        this.connectWebSocket()
      }, 3000)
    }
  }

  startPolling() {
    this.pollingInterval = setInterval(() => {
      this.checkForUpdates()
    }, 10000) // Poll every 10 seconds
  }

  async checkForUpdates() {
    try {
      const response = await fetch(`/lists/${this.listIdValue}/updates`, {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      if (response.ok) {
        const data = await response.json()
        if (data.updates && data.updates.length > 0) {
          this.handleUpdates(data.updates)
        }
      }
    } catch (error) {
      console.error('Error checking for updates:', error)
    }
  }

  handleRealtimeUpdate(data) {
    switch (data.type) {
      case 'item_updated':
        this.updateItem(data.item)
        break
      case 'item_created':
        this.addItem(data.item)
        break
      case 'item_deleted':
        this.removeItem(data.item_id)
        break
      case 'collaborator_joined':
        this.showNotification(`${data.user.name} joined the list`)
        break
      case 'collaborator_left':
        this.showNotification(`${data.user.name} left the list`)
        break
    }
  }

  updateItem(item) {
    const itemElement = document.getElementById(`list_item_${item.id}`)
    if (itemElement) {
      // Highlight the updated item
      itemElement.classList.add('bg-yellow-50', 'border-yellow-200')
      setTimeout(() => {
        itemElement.classList.remove('bg-yellow-50', 'border-yellow-200')
      }, 2000)
    }
  }

  addItem(item) {
    // Flash new item indicator
    this.showNotification('New item added')
  }

  removeItem(itemId) {
    const itemElement = document.getElementById(`list_item_${itemId}`)
    if (itemElement) {
      itemElement.style.transition = 'opacity 0.3s ease-out'
      itemElement.style.opacity = '0'
      setTimeout(() => {
        itemElement.remove()
      }, 300)
    }
  }

  showNotification(message) {
    const notification = document.createElement('div')
    notification.className = 'fixed top-20 right-4 z-50 bg-blue-50 border border-blue-200 text-blue-800 px-4 py-3 rounded-lg shadow-md max-w-md'
    notification.innerHTML = `
      <div class="flex items-center space-x-3">
        <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"></path>
        </svg>
        <span class="flex-1">${message}</span>
        <button onclick="this.parentElement.parentElement.remove()" 
                class="text-current hover:opacity-70">
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"></path>
          </svg>
        </button>
      </div>
    `
    
    document.body.appendChild(notification)
    
    // Auto-remove after 5 seconds
    setTimeout(() => {
      notification.remove()
    }, 5000)
  }
}