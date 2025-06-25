// app/javascript/controllers/notification_filters_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submitForm() {
    // Small delay to ensure the select value is updated
    setTimeout(() => {
      this.element.requestSubmit()
    }, 50)
  }

  clearFilters() {
    // Reset all select elements to their default values
    this.element.querySelectorAll('select').forEach(select => {
      select.selectedIndex = 0
    })
    
    this.submitForm()
  }
}