// app/javascript/controllers/user_filter_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "query", "clearBtn"]
  static values = { debounceDelay: { type: Number, default: 300 } }

  connect() {
    console.log("[UserFilter] Controller connected")
    this.debounceTimeout = null
    this.updateClearButtonVisibility()
  }

  disconnect() {
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }
  }

  /**
   * Handle search input with debounce - PREVENTS FOCUS LOSS
   * The key: we update internal state WITHOUT submitting during typing
   * Only submit after user stops typing for 300ms
   */
  searchInput(event) {
    console.log("[UserFilter] Search input triggered, debouncing...")
    
    // Clear previous timeout
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }

    // Update clear button visibility immediately (doesn't cause Turbo requests)
    this.updateClearButtonVisibility()

    // Debounce the actual form submission
    this.debounceTimeout = setTimeout(() => {
      console.log("[UserFilter] Debounce complete, submitting search")
      this.submitForm()
    }, this.debounceDelayValue)
  }

  /**
   * Handle filter dropdown changes - submit immediately
   */
  filterChange(event) {
    console.log("[UserFilter] Filter changed, submitting immediately")
    
    // Clear any pending search debounce
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }

    this.updateClearButtonVisibility()
    this.submitForm()
  }

  /**
   * Submit the form via Turbo Stream
   * This is the ONLY place where form submission happens
   */
  submitForm() {
    console.log("[UserFilter] Submitting form via Turbo")
    this.formTarget.requestSubmit()
  }

  /**
   * Clear all filters and submit
   * Uses form.reset() to properly clear all fields
   */
  clearFilters(event) {
    event.preventDefault()
    console.log("[UserFilter] Clear filters clicked")

    // Clear any pending debounce
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }

    // Reset the entire form to defaults
    this.formTarget.reset()

    // Ensure sort_by is explicitly set to "recent"
    const sortBySelect = this.formTarget.querySelector('select[name="sort_by"]')
    if (sortBySelect) {
      sortBySelect.value = "recent"
    }

    // Update button visibility
    this.updateClearButtonVisibility()

    // Submit the cleared form
    console.log("[UserFilter] Form cleared, submitting...")
    this.submitForm()
  }

  /**
   * Update clear button visibility
   * This can be called without submitting the form
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
      console.log("[UserFilter] Clear button target not found")
    }
  }

  /**
   * Check if any filters are currently active
   */
  hasActiveFilters() {
    const query = this.queryTarget.value.trim()
    const status = this.formTarget.querySelector('select[name="status"]')?.value || ""
    const role = this.formTarget.querySelector('select[name="role"]')?.value || ""
    const verified = this.formTarget.querySelector('select[name="verified"]')?.value || ""
    const sortBy = this.formTarget.querySelector('select[name="sort_by"]')?.value || "recent"

    const hasFilters = (
      query !== "" ||
      status !== "" ||
      role !== "" ||
      verified !== "" ||
      sortBy !== "recent"
    )

    console.log("[UserFilter] Active filters check:", { query, status, role, verified, sortBy, hasFilters })
    return hasFilters
  }
}