// app/javascript/controllers/collaboration_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["emailInput", "permissionSelect"]

  addCollaborator(event) {
    event.preventDefault()
    
    const email = this.emailInputTarget.value.trim()
    const permission = this.permissionSelectTarget.value
    
    if (!email) {
      this.showError('Please enter an email address')
      return
    }
    
    if (!this.isValidEmail(email)) {
      this.showError('Please enter a valid email address')
      return
    }
    
    // Submit the form
    event.target.submit()
  }

  isValidEmail(email) {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    return emailRegex.test(email)
  }

  showError(message) {
    // Create or update error message
    let errorElement = this.element.querySelector('.error-message')
    
    if (!errorElement) {
      errorElement = document.createElement('div')
      errorElement.className = 'error-message text-red-600 text-sm mt-2'
      this.emailInputTarget.parentNode.appendChild(errorElement)
    }
    
    errorElement.textContent = message
    
    // Remove error after 3 seconds
    setTimeout(() => {
      errorElement.remove()
    }, 3000)
  }

  clearError() {
    const errorElement = this.element.querySelector('.error-message')
    if (errorElement) {
      errorElement.remove()
    }
  }
}