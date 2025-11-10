// app/javascript/controllers/list_filter_controller.js
import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="list-filter"
export default class extends Controller {
  static targets = [
    "form",
    "searchInput",
    "statusFilter",
    "visibilityFilter",
    "collaborationFilter",
    "clearBtn"
  ]
  static values = { debounceDelay: { type: Number, default: 300 } }

  connect() {
    console.log("[ListFilter] Controller connected v1.0")
    this.debounceTimeout = null
    this.updateClearButtonVisibility()
  }

  disconnect() {
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }
  }

  // Handle search input with debounce
  handleSearchInput(event) {
    console.log("[ListFilter] Search input triggered, debouncing...")

    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }

    this.updateClearButtonVisibility()

    this.debounceTimeout = setTimeout(() => {
      console.log("[ListFilter] Debounce complete, submitting search")
      this.submitForm()
    }, this.debounceDelayValue)
  }

  // Handle filter button clicks (immediate submit, no debounce)
  filterChange(event) {
    console.log("[ListFilter] Filter changed:", event.currentTarget.dataset.filterType)

    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }

    this.updateClearButtonVisibility()
    this.submitForm()
  }

  // Submit form via Turbo Stream
  submitForm() {
    console.log("[ListFilter] Submitting form")

    // Build FormData and clean up empty values
    const formData = new FormData(this.formTarget)

    // Build clean params object
    const params = {}
    for (let [key, value] of formData.entries()) {
      // Skip empty values
      if (value === "") continue
      params[key] = value
    }

    // Build URL with clean params
    const searchParams = new URLSearchParams(params)
    const queryString = searchParams.toString()
    const baseUrl = this.formTarget.action.split("?")[0]
    const url = queryString ? `${baseUrl}?${queryString}` : baseUrl

    console.log("[ListFilter] Fetching from:", url)

    // Show loading indicator
    this.showLoadingIndicator()

    // Use Turbo's visitAction to reload with the new URL and stream response
    Turbo.visit(url, { action: "replace" })
  }

  // Clear all filters
  clearFilters(event) {
    event.preventDefault()
    console.log("[ListFilter] Clear filters clicked")

    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }

    // Reset form
    this.formTarget.reset()

    // Reset all filter inputs to empty
    this.searchInputTarget.value = ""

    // Reset all filter buttons to "All" state by clearing their values
    // (the HTML structure uses link_to which doesn't have form inputs,
    // so we just navigate to the base URL)

    this.updateClearButtonVisibility()

    console.log("[ListFilter] Navigating to base lists path")

    // Show loading indicator
    this.showLoadingIndicator()

    // Visit the base URL without filters
    Turbo.visit(this.formTarget.action, { action: "replace" })
  }

  // Show/hide clear filters button based on whether any filters are active
  updateClearButtonVisibility() {
    const hasSearch = this.searchInputTarget.value.trim() !== ""

    // Check if any filter is applied by looking at the current URL params
    const url = new URL(window.location.href)
    const hasFilters =
      hasSearch ||
      url.searchParams.has("status") ||
      url.searchParams.has("visibility") ||
      url.searchParams.has("collaboration")

    if (hasFilters) {
      this.clearBtnTarget.classList.remove("hidden")
    } else {
      this.clearBtnTarget.classList.add("hidden")
    }
  }

  // Show loading indicator with subtle animation
  showLoadingIndicator() {
    // If you want to add a spinner or loading state, you can do it here
    // For now, we'll keep it invisible but this is where you'd add visual feedback
    console.log("[ListFilter] Loading...")
  }
}