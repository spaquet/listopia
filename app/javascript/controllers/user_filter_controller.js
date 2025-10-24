// app/javascript/controllers/user_filter_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "query", "status", "role", "verified", "sortBy", "loading", "clearBtn"]

  static values = {
    debounceDelay: { type: Number, default: 300 }
  }

  connect() {
    console.log("[UserFilter] Controller connected")
    this.debounceTimeout = null
    this.lastSubmittedValues = this.getCurrentFormValues()
    this.updateClearButtonVisibility()

    // Bind Turbo event handlers with proper context
    this.handleTurboSubmitStart = () => {
      console.log("[UserFilter] Turbo submit start")
      this.setLoading(true)
    }
    this.handleTurboSubmitEnd = () => {
      console.log("[UserFilter] Turbo submit end")
      this.setLoading(false)
      // Update clear button visibility after Turbo Stream updates
      this.updateClearButtonVisibility()
    }

    // Attach listeners
    document.addEventListener("turbo:submit-start", this.handleTurboSubmitStart)
    document.addEventListener("turbo:submit-end", this.handleTurboSubmitEnd)
  }

  disconnect() {
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }

    // Clean up event listeners with proper reference
    document.removeEventListener("turbo:submit-start", this.handleTurboSubmitStart)
    document.removeEventListener("turbo:submit-end", this.handleTurboSubmitEnd)
  }

  /**
   * Handle form field changes - entry point for filters
   */
  submitForm(event) {
    console.log("[UserFilter] submitForm called", event?.target?.name)

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
   * Debounced form submission for search input
   */
  debounceSubmit() {
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }

    this.debounceTimeout = setTimeout(() => {
      this.submitNow()
    }, this.debounceDelayValue)
  }

  /**
   * Immediate form submission
   */
  submitNow() {
    console.log("[UserFilter] submitNow called")

    const currentValues = this.getCurrentFormValues()

    // Only submit if values have actually changed
    if (JSON.stringify(currentValues) === JSON.stringify(this.lastSubmittedValues)) {
      console.log("[UserFilter] Values unchanged, skipping submission")
      return
    }

    console.log("[UserFilter] Submitting form with values:", currentValues)

    // Submit the form via Turbo
    this.formTarget.requestSubmit()
    this.lastSubmittedValues = currentValues
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
   * Clear all filters and reset form
   */
  clearFilters(event) {
    event.preventDefault()
    console.log("[UserFilter] Clearing filters")

    // Reset all form fields
    this.queryTarget.value = ""
    this.statusTarget.value = ""
    this.roleTarget.value = ""
    this.verifiedTarget.value = ""
    this.sortByTarget.value = "recent"

    // Reset tracking
    this.lastSubmittedValues = this.getCurrentFormValues()
    this.updateClearButtonVisibility()

    // Submit the cleared form
    this.submitNow()
  }

  /**
   * Update clear button visibility based on active filters
   */
  updateClearButtonVisibility() {
    const hasFilters = this.hasActiveFilters()

    try {
      if (hasFilters) {
        this.clearBtnTarget.classList.remove("hidden")
      } else {
        this.clearBtnTarget.classList.add("hidden")
      }
    } catch (e) {
      // Clear button target not found, ignore
      console.log("[UserFilter] Clear button not found")
    }
  }

  /**
   * Check if any filters are currently active
   */
  hasActiveFilters() {
    const values = this.getCurrentFormValues()
    return (
      values.query.trim() !== "" ||
      values.status !== "" ||
      values.role !== "" ||
      values.verified !== "" ||
      values.sortBy !== "recent"
    )
  }

  /**
   * Show/hide loading indicator
   */
  setLoading(isLoading) {
    try {
      const loadingEl = this.loadingTarget
      if (!loadingEl) {
        console.log("[UserFilter] Loading element not in DOM, skipping")
        return
      }

      if (isLoading) {
        loadingEl.classList.remove("hidden")
      } else {
        loadingEl.classList.add("hidden")
      }
    } catch (e) {
      console.log("[UserFilter] Error setting loading state:", e.message)
    }
  }

  /**
   * Handle keyboard shortcuts
   */
  handleKeydown(event) {
    // Escape - clear search field
    if (event.key === "Escape") {
      event.preventDefault()
      this.queryTarget.value = ""
      this.updateClearButtonVisibility()
      this.submitNow()
      this.queryTarget.blur()
    }

    // Cmd/Ctrl + K - focus search
    if ((event.ctrlKey || event.metaKey) && event.key === "k") {
      event.preventDefault()
      this.queryTarget.focus()
      this.queryTarget.select()
    }
  }
}