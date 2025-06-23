// app/javascript/controllers/clipboard_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String, successMessage: String }

  copy() {
    navigator.clipboard.writeText(this.textValue).then(() => {
      this.showSuccess()
    }).catch(err => {
      console.error('Failed to copy to clipboard:', err)
      this.showError()
    })
  }

  showSuccess() {
    const button = this.element
    const originalText = button.textContent
    const originalClasses = button.className

    // Update button appearance
    button.textContent = this.successMessageValue || 'Copied!'
    button.className = button.className.replace(/bg-\w+-\d+/g, 'bg-green-600')

    // Reset after 2 seconds
    setTimeout(() => {
      button.textContent = originalText
      button.className = originalClasses
    }, 2000)
  }

  showError() {
    const button = this.element
    const originalText = button.textContent
    const originalClasses = button.className

    // Update button appearance
    button.textContent = 'Failed to copy'
    button.className = button.className.replace(/bg-\w+-\d+/g, 'bg-red-600')

    // Reset after 2 seconds
    setTimeout(() => {
      button.textContent = originalText
      button.className = originalClasses
    }, 2000)
  }
}