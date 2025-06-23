// app/javascript/controllers/filters_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Auto-submit search form on input with debouncing
    const searchInput = this.element.querySelector('input[name="search"]')
    if (searchInput) {
      let timeout
      searchInput.addEventListener('input', (event) => {
        clearTimeout(timeout)
        timeout = setTimeout(() => {
          event.target.form.submit()
        }, 300) // 300ms debounce
      })
    }
  }
}
