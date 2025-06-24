// app/javascript/controllers/filters_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["searchInput"]
  
  connect() {
    this.timeout = null
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  search(event) {
    // Clear existing timeout
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
    
    // Set new timeout for debounced search
    this.timeout = setTimeout(() => {
      this.submitSearch()
    }, 500) // 500ms debounce instead of 300ms for better UX
  }

  submitSearch() {
    const form = this.searchInputTarget.closest('form')
    if (form) {
      // Submit the form with Turbo
      form.requestSubmit()
    }
  }
}