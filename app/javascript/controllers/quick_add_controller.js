// app/javascript/controllers/quick_add_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["options", "optionsText", "optionsIcon", "titleInput", "submitButton", "submitText"]

  connect() {
    this.optionsVisible = false
  }

  toggleOptions(event) {
    event.preventDefault()
    
    this.optionsVisible = !this.optionsVisible
    
    if (this.optionsVisible) {
      this.optionsTarget.classList.remove("hidden")
      this.optionsTextTarget.textContent = "Less options"
      this.optionsIconTarget.style.transform = "rotate(180deg)"
    } else {
      this.optionsTarget.classList.add("hidden")
      this.optionsTextTarget.textContent = "More options"
      this.optionsIconTarget.style.transform = "rotate(0deg)"
    }
  }

  handleKeydown(event) {
    // Submit form on Ctrl/Cmd + Enter
    if ((event.ctrlKey || event.metaKey) && event.key === "Enter") {
      event.preventDefault()
      this.element.querySelector('form').submit()
    }
  }

  // Clear errors when user starts typing or submitting
  clearError() {
    const errorContainer = this.element.querySelector('#form-errors')
    if (errorContainer) {
      errorContainer.innerHTML = ''
    }
    
    // Remove error styling from title input
    if (this.hasTitleInputTarget) {
      this.titleInputTarget.classList.remove('border-red-300', 'focus:border-red-500', 'focus:ring-red-500')
      this.titleInputTarget.classList.add('border-gray-300', 'focus:border-blue-500', 'focus:ring-blue-500')
    }
  }

  reset() {
    // Reset form and hide options after successful submission
    const form = this.element.querySelector('form')
    if (form) {
      form.reset()
    }
    
    // Clear any error messages
    this.clearError()
    
    if (this.optionsVisible) {
      this.toggleOptions({ preventDefault: () => {} })
    }
    
    // Focus back on title input
    if (this.hasTitleInputTarget) {
      // Small delay to ensure form is reset
      setTimeout(() => {
        this.titleInputTarget.focus()
      }, 100)
    }
    
    // Reset submit button text if it was changed
    if (this.hasSubmitTextTarget) {
      this.submitTextTarget.textContent = "Add"
    }
  }

  // Provide visual feedback during submission
  submitting() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
    }
    
    if (this.hasSubmitTextTarget) {
      this.submitTextTarget.textContent = "Adding..."
    }
  }

  // Reset after submission (whether successful or not)
  submitted() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = false
    }
    
    if (this.hasSubmitTextTarget) {
      this.submitTextTarget.textContent = "Add"
    }
  }
}