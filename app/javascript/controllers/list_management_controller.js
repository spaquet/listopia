// app/javascript/controllers/list_management_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  editItem(event) {
    event.preventDefault()
    const itemId = event.currentTarget.dataset.itemId
    
    if (!itemId) {
      console.error('No item ID found')
      return
    }
    
    // Make a request to get the edit form
    this.loadEditForm(itemId)
  }

  async loadEditForm(itemId) {
    try {
      const listId = this.getListId()
      const response = await fetch(`/lists/${listId}/items/${itemId}/edit`, {
        headers: {
          'Accept': 'text/vnd.turbo-stream.html',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      if (response.ok) {
        const streamHtml = await response.text()
        Turbo.renderStreamMessage(streamHtml)
      } else {
        console.error('Failed to load edit form')
        this.showNotification('Failed to load edit form', 'error')
      }
    } catch (error) {
      console.error('Error loading edit form:', error)
      this.showNotification('Error loading edit form', 'error')
    }
  }

  getListId() {
    // Extract list ID from the current URL
    const pathParts = window.location.pathname.split('/')
    const listsIndex = pathParts.indexOf('lists')
    return listsIndex >= 0 ? pathParts[listsIndex + 1] : null
  }

  showNotification(message, type = 'info') {
    const notification = document.createElement('div')
    notification.className = `fixed top-20 right-4 z-50 px-4 py-3 rounded-lg shadow-md max-w-md ${
      type === 'error' ? 'bg-red-50 border border-red-200 text-red-800' : 
      type === 'success' ? 'bg-green-50 border border-green-200 text-green-800' :
      'bg-blue-50 border border-blue-200 text-blue-800'
    }`
    
    notification.innerHTML = `
      <div class="flex items-center space-x-3">
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