// app/javascript/controllers/user_filter_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "form",
    "query",
    "status",
    "role",
    "verified",
    "sortBy",
    "loading",
    "clearBtn"
  ]

  static values = {
    debounceDelay: { type: Number, default: 300 }
  }

  connect() {
    this.debounceTimeout = null
    this.lastSubmittedValues = this.getCurrentFormValues()
    this.updateClearButtonVisibility()
  }

  disconnect() {
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }
  }

  /**
   * Handle search input - debounced submission
   */
  submitForm(event) {
    // For search input, debounce the submission
    if (event?.target === this.queryTarget) {
      this.debounceSubmit()
    } else {
      // For select changes, submit immediately
      this.submitNow()
    }

    // Update clear button visibility
    this.updateClearButtonVisibility()
  }

  /**
   * Debounced form submission for search
   */
  debounceSubmit() {
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }

    // Show loading indicator
    this.setLoading(true)

    this.debounceTimeout = setTimeout(() => {
      this.submitNow()
    }, this.debounceDelayValue)
  }

  /**
   * Execute form submission immediately
   */
  submitNow() {
    const currentValues = this.getCurrentFormValues()

    // Only submit if values have changed
    if (JSON.stringify(currentValues) !== JSON.stringify(this.lastSubmittedValues)) {
      this.lastSubmittedValues = currentValues

      // Turbo will handle the form submission automatically
      // and replace the results via Turbo Stream response
      this.formTarget.requestSubmit()
    }
  }

  /**
   * Clear all filters and search
   */
  clearFilters(event) {
    event?.preventDefault()

    // Reset all form fields
    this.queryTarget.value = ""
    this.statusTarget.value = ""
    this.roleTarget.value = ""
    this.verifiedTarget.value = ""
    this.sortByTarget.value = "recent"

    // Update last submitted values
    this.lastSubmittedValues = this.getCurrentFormValues()

    // Update clear button
    this.updateClearButtonVisibility()

    // Submit form
    this.setLoading(true)
    this.formTarget.requestSubmit()

    // Keep focus on search input
    this.queryTarget.focus()
  }

  /**
   * Handle keyboard shortcuts
   */
  handleKeydown(event) {
    // Escape key - clear search
    if (event.key === "Escape") {
      event.preventDefault()
      this.queryTarget.value = ""
      this.updateClearButtonVisibility()
      this.queryTarget.blur()
    }

    // Ctrl/Cmd + A - focus search
    if ((event.ctrlKey || event.metaKey) && event.key === "a") {
      event.preventDefault()
      this.queryTarget.focus()
      this.queryTarget.select()
    }
  }

  /**
   * Get current form values
   */
  getCurrentFormValues() {
    return {
      query: this.queryTarget.value,
      status: this.statusTarget.value,
      role: this.roleTarget.value,
      verified: this.verifiedTarget.value,
      sortBy: this.sortByTarget.value
    }
  }

  /**
   * Update clear button visibility
   */
  updateClearButtonVisibility() {
    const hasFilters = this.hasActiveFilters()
    
    if (hasFilters) {
      this.clearBtnTarget.classList.remove("hidden")
    } else {
      this.clearBtnTarget.classList.add("hidden")
    }
  }

  /**
   * Check if any filters are active
   */
  hasActiveFilters() {
    return (
      this.queryTarget.value.trim() !== "" ||
      this.statusTarget.value !== "" ||
      this.roleTarget.value !== "" ||
      this.verifiedTarget.value !== "" ||
      this.sortByTarget.value !== "recent"
    )
  }

  /**
   * Show/hide loading indicator
   */
  setLoading(isLoading) {
    if (isLoading) {
      this.loadingTarget.classList.remove("hidden")
    } else {
      this.loadingTarget.classList.add("hidden")
    }
  }

  /**
   * Hide loading when results are rendered via Turbo Stream
   * Called automatically when Turbo Stream updates arrive
   */
  hideLoading() {
    this.setLoading(false)
  }
}