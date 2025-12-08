// app/javascript/controllers/list_filter_controller.js
import { Controller } from "@hotwired/stimulus"

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
    // Delay update to allow permanent elements to be re-attached
    setTimeout(() => this.updateClearButtonVisibility(), 0)
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

    // Use fetch with Turbo Stream response to update only the lists grid
    fetch(url, {
      headers: {
        "Accept": "text/vnd.turbo-stream.html"
      }
    })
    .then(response => {
      if (!response.ok) throw new Error("Network response was not ok")
      return response.text()
    })
    .then(html => {
      // Process each turbo-stream action in the response
      const parser = new DOMParser()
      const doc = parser.parseFromString(html, "text/html")
      const turboStreams = doc.querySelectorAll("turbo-stream")

      turboStreams.forEach(element => {
        Turbo.connectStreamElement(element)
      })

      // Update URL without full page reload
      window.history.replaceState({}, "", url)
      console.log("[ListFilter] Filters applied successfully")
    })
    .catch(error => console.error("Error fetching filtered results:", error))
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
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.value = ""
    }

    this.updateClearButtonVisibility()

    console.log("[ListFilter] Clearing all filters")

    // Show loading indicator
    this.showLoadingIndicator()

    // Fetch base URL without filters using Turbo Stream
    const baseUrl = this.formTarget.action.split("?")[0]
    fetch(baseUrl, {
      headers: {
        "Accept": "text/vnd.turbo-stream.html"
      }
    })
    .then(response => {
      if (!response.ok) throw new Error("Network response was not ok")
      return response.text()
    })
    .then(html => {
      // Process each turbo-stream action in the response
      const parser = new DOMParser()
      const doc = parser.parseFromString(html, "text/html")
      const turboStreams = doc.querySelectorAll("turbo-stream")

      turboStreams.forEach(element => {
        Turbo.connectStreamElement(element)
      })

      // Update URL without full page reload
      window.history.replaceState({}, "", baseUrl)
      console.log("[ListFilter] All filters cleared successfully")
    })
    .catch(error => console.error("Error clearing filters:", error))
  }

  // Show/hide clear filters button based on whether any filters are active
  updateClearButtonVisibility() {
    // Check if targets exist before accessing them
    if (!this.hasSearchInputTarget || !this.hasClearBtnTarget) {
      return
    }

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
    console.log("[ListFilter] Loading...")
  }
}