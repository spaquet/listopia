// app/javascript/controllers/user_filter_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "query", "clearBtn", "status", "role", "verified", "sortBy"]
  static values = { debounceDelay: { type: Number, default: 300 } }

  connect() {
    console.log("[UserFilter] Controller connected v1.0")
    this.debounceTimeout = null
    this.updateClearButtonVisibility()
  }

  disconnect() {
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }
  }

  searchInput(event) {
    console.log("[UserFilter] Search input triggered, debouncing...")
    
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }

    this.updateClearButtonVisibility()

    this.debounceTimeout = setTimeout(() => {
      console.log("[UserFilter] Debounce complete, submitting")
      this.submitForm()
    }, this.debounceDelayValue)
  }

  filterChange(event) {
    console.log("[UserFilter] Filter changed:", event.target.name)
    
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }

    this.updateClearButtonVisibility()
    this.submitForm()
  }

  submitForm() {
    console.log("[UserFilter] Submitting form")
    
    // Build FormData and clean up empty values
    const formData = new FormData(this.formTarget)
    
    // Build clean params object
    const params = {}
    for (let [key, value] of formData.entries()) {
      // Skip empty values
      if (value === "") continue
      // Skip default sort_by value
      if (key === "sort_by" && value === "recent") continue
      params[key] = value
    }
    
    // Build URL with clean params
    const searchParams = new URLSearchParams(params)
    const queryString = searchParams.toString()
    const baseUrl = this.formTarget.action.split('?')[0]
    const url = queryString ? `${baseUrl}?${queryString}` : baseUrl
    
    console.log("[UserFilter] Fetching from:", url)
    
    // Use Turbo's visitAction to reload with the new URL
    Turbo.visit(url, { action: 'replace' })
  }

  clearFilters(event) {
    event.preventDefault()
    console.log("[UserFilter] Clear filters clicked")

    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }

    // Reset form
    this.formTarget.reset()
    
    // Reset all select values to empty/default
    this.queryTarget.value = ""
    this.statusTarget.value = ""
    this.roleTarget.value = ""
    this.verifiedTarget.value = ""
    this.sortByTarget.value = "recent"

    this.updateClearButtonVisibility()
    
    // Visit the base URL without filters
    const baseUrl = this.formTarget.action.split('?')[0]
    console.log("[UserFilter] Clearing filters, visiting:", baseUrl)
    Turbo.visit(baseUrl, { action: 'replace' })
  }

  updateClearButtonVisibility() {
    const hasQuery = this.queryTarget.value.trim() !== ""
    const hasStatus = this.statusTarget.value !== ""
    const hasRole = this.roleTarget.value !== ""
    const hasVerified = this.verifiedTarget.value !== ""
    const isSorted = this.sortByTarget.value !== "recent"

    const hasAnyFilter = hasQuery || hasStatus || hasRole || hasVerified || isSorted

    if (hasAnyFilter) {
      this.clearBtnTarget.classList.remove("hidden")
    } else {
      this.clearBtnTarget.classList.add("hidden")
    }
  }
}