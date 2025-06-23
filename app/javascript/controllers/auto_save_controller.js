// app/javascript/controllers/auto_save_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, delay: { type: Number, default: 1000 } }
  static targets = ["field"]

  connect() {
    this.timeout = null
    this.fieldTargets.forEach(field => {
      field.addEventListener('input', this.scheduleAutoSave.bind(this))
    })
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  scheduleAutoSave() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
    
    this.timeout = setTimeout(() => {
      this.autoSave()
    }, this.delayValue)
  }

  async autoSave() {
    const formData = new FormData()
    
    this.fieldTargets.forEach(field => {
      formData.append(field.name, field.value)
    })
    
    try {
      const response = await fetch(this.urlValue, {
        method: 'PATCH',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        },
        body: formData
      })
      
      if (response.ok) {
        this.showSaveStatus('saved')
      } else {
        this.showSaveStatus('error')
      }
    } catch (error) {
      console.error('Auto-save error:', error)
      this.showSaveStatus('error')
    }
  }

  showSaveStatus(status) {
    // Create or update save status indicator
    let statusElement = this.element.querySelector('.auto-save-status')
    
    if (!statusElement) {
      statusElement = document.createElement('div')
      statusElement.className = 'auto-save-status text-xs text-gray-500 mt-1'
      this.element.appendChild(statusElement)
    }
    
    if (status === 'saved') {
      statusElement.textContent = 'Saved'
      statusElement.className = 'auto-save-status text-xs text-green-600 mt-1'
    } else if (status === 'error') {
      statusElement.textContent = 'Error saving'
      statusElement.className = 'auto-save-status text-xs text-red-600 mt-1'
    }
    
    // Hide status after 2 seconds
    setTimeout(() => {
      statusElement.textContent = ''
    }, 2000)
  }
}
