// app/javascript/controllers/list_management_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  editItem(event) {
    const itemId = event.currentTarget.dataset.itemId
    const itemElement = document.getElementById(`list_item_${itemId}`)
    
    if (itemElement) {
      // Create inline edit form
      this.createInlineEditForm(itemElement, itemId)
    }
  }

  createInlineEditForm(itemElement, itemId) {
    const titleElement = itemElement.querySelector('h3')
    const descriptionElement = itemElement.querySelector('p')
    
    const currentTitle = titleElement.textContent.trim()
    const currentDescription = descriptionElement ? descriptionElement.textContent.trim() : ''
    
    // Create edit form
    const editForm = document.createElement('div')
    editForm.className = 'space-y-3 p-4 bg-gray-50 rounded-lg'
    editForm.innerHTML = `
      <form data-action="submit->list-management#saveItem" data-item-id="${itemId}">
        <div class="space-y-3">
          <input type="text" 
                 name="title" 
                 value="${currentTitle}" 
                 class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                 required>
          <textarea name="description" 
                    rows="2" 
                    placeholder="Description..."
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500">${currentDescription}</textarea>
          <div class="flex space-x-2">
            <button type="submit" 
                    class="bg-blue-600 text-white px-3 py-1 rounded text-sm hover:bg-blue-700 transition-colors duration-200">
              Save
            </button>
            <button type="button" 
                    data-action="click->list-management#cancelEdit"
                    class="bg-gray-300 text-gray-700 px-3 py-1 rounded text-sm hover:bg-gray-400 transition-colors duration-200">
              Cancel
            </button>
          </div>
        </div>
      </form>
    `
    
    // Replace item content with edit form
    const contentDiv = itemElement.querySelector('.flex-1')
    contentDiv.innerHTML = ''
    contentDiv.appendChild(editForm)
    
    // Focus on title input
    editForm.querySelector('input[name="title"]').focus()
  }

  saveItem(event) {
    event.preventDefault()
    
    const form = event.target
    const itemId = form.dataset.itemId
    const formData = new FormData(form)
    
    // Make PATCH request to update item
    fetch(`/lists/${this.data.get("listId")}/items/${itemId}`, {
      method: 'PATCH',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'text/vnd.turbo-stream.html'
      },
      body: formData
    })
    .then(response => response.text())
    .then(html => {
      // Let Turbo handle the stream response
      Turbo.renderStreamMessage(html)
    })
    .catch(error => {
      console.error('Error updating item:', error)
      // Show error message
      this.showNotification('Error updating item', 'error')
    })
  }

  cancelEdit(event) {
    event.preventDefault()
    
    // Reload the page to restore original content
    // In a more sophisticated app, you'd restore from cached content
    location.reload()
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
