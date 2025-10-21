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
   * Debounced submission for search input (300ms delay)
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
   * Submit the form only if values have changed
   */
  submitNow() {
    const currentValues = this.getCurrentFormValues()
    const valuesChanged = JSON.stringify(currentValues) !== JSON.stringify(this.lastSubmittedValues)

    console.log("[UserFilter] submitNow", { currentValues, valuesChanged })

    if (valuesChanged) {
      this.lastSubmittedValues = currentValues
      
      // Request submit will trigger Turbo and Turbo:submit-start/end events
      this.formTarget.requestSubmit()
    }
  }

  /**
   * Clear all filters and search
   */
  clearFilters(event) {
    event?.preventDefault()
    console.log("[UserFilter] clearFilters called")

    // Reset all form fields
    this.queryTarget.value = ""
    this.statusTarget.value = ""
    this.roleTarget.value = ""
    this.verifiedTarget.value = ""
    this.sortByTarget.value = "recent"

    // Update tracking
    this.lastSubmittedValues = this.getCurrentFormValues()
    this.updateClearButtonVisibility()

    // Submit form
    this.formTarget.requestSubmit()
    this.queryTarget.focus()
  }

  /**
   * Get current form field values
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
   * Toggle clear button visibility based on active filters
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
      const loadingEl = document.querySelector('[data-user-filter-target="loading"]')
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