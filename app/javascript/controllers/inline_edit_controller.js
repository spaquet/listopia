// app/javascript/controllers/inline_edit_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["titleInput", "submitButton"]
  static values = { itemId: String }

  connect() {
    if (this.hasTitleInputTarget) {
      this.titleInputTarget.focus()
      this.titleInputTarget.select()
    }
  }

  cancel(event) {
    event.preventDefault()
    
    // Make a simple GET request to the item's show action
    const listId = this.getListId()
    const itemId = this.itemIdValue
    
    fetch(`/lists/${listId}/items/${itemId}`, {
      method: 'GET',
      headers: {
        'Accept': 'text/vnd.turbo-stream.html',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => response.text())
    .then(html => Turbo.renderStreamMessage(html))
    .catch(error => console.error('Error:', error))
  }

  handleSuccess(event) {
    console.log('Item updated successfully')
  }

  clearError() {
    const errorContainer = this.element.querySelector(`#edit-form-errors-${this.itemIdValue}`)
    if (errorContainer) {
      errorContainer.innerHTML = ''
    }
    
    if (this.hasTitleInputTarget) {
      this.titleInputTarget.classList.remove('border-red-300', 'focus:border-red-500', 'focus:ring-red-500')
      this.titleInputTarget.classList.add('border-gray-300', 'focus:border-blue-500', 'focus:ring-blue-500')
    }
  }

  handleKeydown(event) {
    if (event.key === 'Escape') {
      event.preventDefault()
      this.cancel(event)
    } else if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
      event.preventDefault()
      if (this.hasSubmitButtonTarget) {
        this.submitButtonTarget.click()
      }
    }
  }

  getListId() {
    const pathParts = window.location.pathname.split('/')
    const listsIndex = pathParts.indexOf('lists')
    return listsIndex >= 0 ? pathParts[listsIndex + 1] : null
  }
}