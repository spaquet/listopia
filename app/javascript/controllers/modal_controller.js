// app/javascript/controllers/modal_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "backdrop"]

  connect() {
    this.close = this.close.bind(this)
  }

  open() {
    this.modalTarget.classList.remove('hidden')
    document.body.classList.add('overflow-hidden')
    
    // Focus trap
    this.modalTarget.focus()
    
    // Close on backdrop click
    this.backdropTarget.addEventListener('click', this.close)
    
    // Close on escape key
    document.addEventListener('keydown', this.handleEscape.bind(this))
  }

  close() {
    this.modalTarget.classList.add('hidden')
    document.body.classList.remove('overflow-hidden')
    
    // Clean up event listeners
    this.backdropTarget.removeEventListener('click', this.close)
    document.removeEventListener('keydown', this.handleEscape.bind(this))
  }

  handleEscape(event) {
    if (event.key === 'Escape') {
      this.close()
    }
  }

  clickOutside(event) {
    if (event.target === this.backdropTarget) {
      this.close()
    }
  }
}