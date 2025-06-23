// app/javascript/controllers/dropdown_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.close = this.close.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.close)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    
    if (this.menuTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.menuTarget.classList.remove("hidden")
    document.addEventListener("click", this.close)
  }

  close() {
    this.menuTarget.classList.add("hidden")
    document.removeEventListener("click", this.close)
  }
}