// app/javascript/controllers/inline_edit_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["titleInput", "submitButton"]
  static values = { 
    itemId: String,
    originalContent: String 
  }

  connect() {
    // Store the original content when we start editing
    // This will be used to restore if user cancels
    this.storeOriginalContent()
    
    // Focus on the title input
    if (this.hasTitleInputTarget) {
      this.titleInputTarget.focus()
      this.titleInputTarget.select()
    }
  }

  storeOriginalContent() {
    // Get the original item content from the page
    const itemElement = document.getElementById(`list_item_${this.itemIdValue}`)
    if (itemElement) {
      this.originalContentValue = itemElement.outerHTML
    }
  }

  cancel(event) {
    event.preventDefault()
    
    // Restore the original item display
    if (this.originalContentValue) {
      const itemElement = document.getElementById(`list_item_${this.itemIdValue}`)
      if (itemElement) {
        itemElement.outerHTML = this.originalContentValue
      }
    } else {
      // Fallback: reload the page section
      this.reloadItem()
    }
  }

  handleSuccess(event) {
    // The form submission was successful
    // Turbo will handle updating the content, so we don't need to do anything special
    console.log('Item updated successfully')
  }

  clearError() {
    // Clear any error messages when user starts typing
    const errorContainer = this.element.querySelector(`#edit-form-errors-${this.itemIdValue}`)
    if (errorContainer) {
      errorContainer.innerHTML = ''
    }
    
    // Remove error styling from title input
    if (this.hasTitleInputTarget) {
      this.titleInputTarget.classList.remove('border-red-300', 'focus:border-red-500', 'focus:ring-red-500')
      this.titleInputTarget.classList.add('border-gray-300', 'focus:border-blue-500', 'focus:ring-blue-500')
    }
  }

  // Handle keyboard shortcuts
  handleKeydown(event) {
    switch (event.key) {
      case 'Escape':
        event.preventDefault()
        this.cancel(event)
        break
      case 'Enter':
        // Only submit on Ctrl/Cmd + Enter to avoid accidental submissions
        if (event.ctrlKey || event.metaKey) {
          event.preventDefault()
          this.submit()
        }
        break
    }
  }

  submit() {
    const form = this.element.querySelector('form')
    if (form) {
      form.requestSubmit()
    }
  }

  // Fallback method to reload item if we can't restore original content
  async reloadItem() {
    try {
      const response = await fetch(window.location.href, {
        headers: {
          'Accept': 'text/html',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      if (response.ok) {
        const html = await response.text()
        const parser = new DOMParser()
        const doc = parser.parseFromString(html, 'text/html')
        const newItemElement = doc.getElementById(`list_item_${this.itemIdValue}`)
        
        if (newItemElement) {
          const currentItemElement = document.getElementById(`list_item_${this.itemIdValue}`)
          if (currentItemElement) {
            currentItemElement.outerHTML = newItemElement.outerHTML
          }
        }
      }
    } catch (error) {
      console.error('Failed to reload item:', error)
      // As a last resort, reload the page
      window.location.reload()
    }
  }
}