// app/javascript/controllers/custom_select_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "dropdown", "selectedDisplay", "hiddenInput"]
  static values = { 
    name: String,
    value: String
  }

  connect() {
    this.setupInitialState()
    this.boundCloseOnClickOutside = this.closeOnClickOutside.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.boundCloseOnClickOutside)
  }

  setupInitialState() {
    // Set up the initial display based on the current value
    this.updateSelectedDisplay(this.valueValue)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    
    if (this.dropdownTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.dropdownTarget.classList.remove("hidden")
    document.addEventListener("click", this.boundCloseOnClickOutside)
    
    // Add visual feedback
    this.triggerTarget.classList.add("ring-2", "ring-blue-500", "border-blue-500")
  }

  close() {
    this.dropdownTarget.classList.add("hidden")
    document.removeEventListener("click", this.boundCloseOnClickOutside)
    
    // Remove visual feedback
    this.triggerTarget.classList.remove("ring-2", "ring-blue-500", "border-blue-500")
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  select(event) {
    event.preventDefault()
    const value = event.currentTarget.dataset.value
    const displayContent = event.currentTarget.innerHTML
    
    // Update the hidden input
    this.hiddenInputTarget.value = value
    
    // Update the display
    this.selectedDisplayTarget.innerHTML = displayContent
    
    // Update the stored value
    this.valueValue = value
    
    // Close the dropdown
    this.close()
    
    // Trigger a change event for any listeners
    this.hiddenInputTarget.dispatchEvent(new Event('change', { bubbles: true }))
  }

  updateSelectedDisplay(value) {
    // Find the option element with this value and update display
    const optionElement = this.element.querySelector(`[data-value="${value}"]`)
    if (optionElement) {
      this.selectedDisplayTarget.innerHTML = optionElement.innerHTML
      this.hiddenInputTarget.value = value
    }
  }

  // Helper method to programmatically set value (useful for resetting forms)
  setValue(value) {
    this.valueValue = value
    this.updateSelectedDisplay(value)
  }

  // Keyboard navigation support
  handleKeydown(event) {
    if (!this.dropdownTarget.classList.contains("hidden")) {
      switch (event.key) {
        case "Escape":
          event.preventDefault()
          this.close()
          this.triggerTarget.focus()
          break
        case "ArrowDown":
        case "ArrowUp":
          event.preventDefault()
          this.navigateOptions(event.key === "ArrowDown" ? 1 : -1)
          break
        case "Enter":
        case " ":
          event.preventDefault()
          const focusedOption = this.dropdownTarget.querySelector(":focus")
          if (focusedOption) {
            focusedOption.click()
          }
          break
      }
    } else if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      this.open()
    }
  }

  navigateOptions(direction) {
    const options = Array.from(this.dropdownTarget.querySelectorAll("button"))
    const currentIndex = options.findIndex(option => option === document.activeElement)
    let nextIndex = currentIndex + direction
    
    if (nextIndex < 0) nextIndex = options.length - 1
    if (nextIndex >= options.length) nextIndex = 0
    
    options[nextIndex].focus()
  }
}