// app/javascript/controllers/flash_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { autoDismiss: Boolean }

  connect() {
    if (this.autoDismissValue) {
      this.timeout = setTimeout(() => {
        this.dismiss()
      }, 5000)
    }
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  dismiss() {
    this.element.style.transition = "all 0.3s ease-out"
    this.element.style.transform = "translateX(100%)"
    this.element.style.opacity = "0"
    
    setTimeout(() => {
      this.element.remove()
    }, 300)
  }
}