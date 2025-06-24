// app/javascript/controllers/modal_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "backdrop"]

  connect() {
    // Auto-open modal when it loads
    this.open()
  }

  disconnect() {
    this.cleanup()
  }

  open() {
    // Enable body scroll lock
    document.body.classList.add('overflow-hidden')
    
    // Focus trap
    if (this.hasModalTarget) {
      this.modalTarget.focus()
    }
    
    // Close on escape key
    this.handleEscape = this.handleEscape.bind(this)
    document.addEventListener('keydown', this.handleEscape)
  }

  close() {
    // Remove the entire turbo frame, which will close the modal
    this.element.remove()
  }

  cleanup() {
    // Re-enable body scroll
    document.body.classList.remove('overflow-hidden')
    
    // Clean up event listeners
    if (this.handleEscape) {
      document.removeEventListener('keydown', this.handleEscape)
    }
  }

  handleEscape(event) {
    if (event.key === 'Escape') {
      this.close()
    }
  }

  clickOutside(event) {
    // Only close if clicking directly on the backdrop
    if (event.target === this.backdropTarget) {
      this.close()
    }
  }
}