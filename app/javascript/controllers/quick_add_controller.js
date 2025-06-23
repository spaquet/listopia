// app/javascript/controllers/quick_add_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["options", "optionsText", "optionsIcon"]

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

  reset() {
    // Reset form and hide options after successful submission
    this.element.querySelector('form').reset()
    
    if (this.optionsVisible) {
      this.toggleOptions({ preventDefault: () => {} })
    }
    
    // Focus back on title input
    this.element.querySelector('input[name="list_item[title]"]').focus()
  }
}