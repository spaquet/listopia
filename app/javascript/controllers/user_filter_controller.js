// app/javascript/controllers/user_filter_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "query", "clearBtn", "status", "role", "verified", "sortBy"]
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
    this.formTarget.requestSubmit()
  }

  clearFilters(event) {
    event.preventDefault()
    console.log("[UserFilter] Clear filters clicked")

    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }

    this.formTarget.reset()

    this.statusTarget.value = ""
    this.roleTarget.value = ""
    this.verifiedTarget.value = ""
    this.sortByTarget.value = "recent"
    this.queryTarget.value = ""

    this.updateClearButtonVisibility()
    this.submitForm()
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