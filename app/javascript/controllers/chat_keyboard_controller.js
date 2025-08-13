// app/javascript/controllers/chat_keyboard_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea"]

  connect() {
    this.textareaTarget.addEventListener('keydown', this.handleKeydown.bind(this))
  }

  disconnect() {
    this.textareaTarget.removeEventListener('keydown', this.handleKeydown.bind(this))
  }

  handleKeydown(event) {
    // Ctrl/Cmd + Enter to send
    if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
      event.preventDefault()
      this.dispatchSendEvent()
      return
    }

    // Escape to clear/cancel
    if (event.key === 'Escape') {
      event.preventDefault()
      this.clear()
      return
    }
  }

  dispatchSendEvent() {
    const message = this.textareaTarget.value.trim()
    if (!message) return

    // Find the chat controller and call sendMessage directly
    const chatController = this.application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller*="chat"]'),
      'chat'
    )
    
    if (chatController && chatController.sendMessage) {
      chatController.sendMessage({ detail: { message } })
    }
  }

  clear() {
    this.textareaTarget.value = ''
    this.textareaTarget.focus()
    
    // Trigger input event to update autogrow and character counter
    this.textareaTarget.dispatchEvent(new Event('input', { bubbles: true }))
  }
}