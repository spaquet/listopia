// app/javascript/controllers/keyboard_shortcuts_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    document.addEventListener('keydown', this.handleKeydown.bind(this))
  }

  disconnect() {
    document.removeEventListener('keydown', this.handleKeydown.bind(this))
  }

  handleKeydown(event) {
    // Only handle shortcuts when not in input fields
    if (event.target.tagName === 'INPUT' || event.target.tagName === 'TEXTAREA') {
      return
    }

    // Cmd/Ctrl + K: Open spotlight search modal
    if ((event.metaKey || event.ctrlKey) && event.key === 'k') {
      event.preventDefault()
      document.dispatchEvent(new CustomEvent('spotlight:open'))
    }

    // Cmd/Ctrl + N: New list
    if ((event.metaKey || event.ctrlKey) && event.key === 'n') {
      event.preventDefault()
      const newListLink = document.querySelector('a[href*="lists/new"]')
      if (newListLink) {
        newListLink.click()
      }
    }

    // Escape: Close dropdowns and modals
    if (event.key === 'Escape') {
      document.querySelectorAll('[data-dropdown-target="menu"]:not(.hidden)').forEach(menu => {
        menu.classList.add('hidden')
      })
    }
  }
}