// app/javascript/controllers/toggle_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["personalButton", "professionalButton", "hiddenInput"]
  static values = { value: String }

  connect() {
    this.updateUI()
  }

  selectOption(event) {
    const option = event.currentTarget.dataset.toggleOption
    this.hiddenInputTarget.value = option
    this.valueValue = option
    this.updateUI()
  }

  updateUI() {
    const isPersonal = this.valueValue === "personal"
    
    // Update personal button
    if (isPersonal) {
      this.personalButtonTarget.className = "bg-white text-blue-600 shadow-sm relative w-1/2 rounded-md py-2 text-sm font-medium transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
    } else {
      this.personalButtonTarget.className = "text-gray-500 hover:text-gray-700 relative w-1/2 rounded-md py-2 text-sm font-medium transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
    }
    
    // Update professional button
    if (!isPersonal) {
      this.professionalButtonTarget.className = "bg-white text-purple-600 shadow-sm relative w-1/2 rounded-md py-2 text-sm font-medium transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:ring-offset-2"
    } else {
      this.professionalButtonTarget.className = "text-gray-500 hover:text-gray-700 relative w-1/2 rounded-md py-2 text-sm font-medium transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:ring-offset-2"
    }
  }
}