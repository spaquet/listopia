// app/javascript/controllers/user_filter_controller.js
import { Controller } from "@hotwired/stimulus"
import { debounce } from "lodash"

export default class extends Controller {
  static targets = ["form", "query", "status", "role", "verified", "sortBy", "clearBtn", "resultsContainer", "loading", "noResults"]
  static values = { submitUrl: String, debounceDelay: { type: Number, default: 500 } }

  connect() {
    // Debounce search input to avoid too many requests
    this.debouncedSubmit = debounce(() => this.submitForm(), this.debounceDelayValue)

    // Set up event listeners
    this.setupEventListeners()
    this.updateClearButtonVisibility()
    this.setupFormPersistence()

    // Listen for Turbo navigation completion to restore focus
    document.addEventListener('turbo:load', () => this.restoreFocus())
  }

  disconnect() {
    // Clean up event listeners
    document.removeEventListener('turbo:load', () => this.restoreFocus())
  }

  setupEventListeners() {
    // Search input - debounced
    if (this.hasQueryTarget) {
      this.queryTarget.addEventListener("input", () => {
        // Save focus state before submitting
        this.saveFocusState()
        this.debouncedSubmit()
      })
    }

    // Filters - immediate submission
    [this.statusTarget, this.roleTarget, this.verifiedTarget, this.sortByTarget].forEach(target => {
      if (target) {
        target.addEventListener("change", () => this.submitForm())
      }
    })

    // Clear filters button
    if (this.hasClearBtnTarget) {
      this.clearBtnTarget.addEventListener("click", (e) => {
        e.preventDefault()
        this.clearFilters()
      })
    }

    // Form submission handling
    if (this.hasFormTarget) {
      this.formTarget.addEventListener("submit", (e) => {
        e.preventDefault()
        this.submitForm()
      })
    }
  }

  setupFormPersistence() {
    // Save filter state to sessionStorage to restore on page reload
    const filterState = {
      query: this.queryTarget?.value || "",
      status: this.statusTarget?.value || "",
      role: this.roleTarget?.value || "",
      verified: this.verifiedTarget?.value || "",
      sortBy: this.sortByTarget?.value || "recent"
    }

    sessionStorage.setItem("userFilters", JSON.stringify(filterState))
  }

  submitForm() {
    // Validate that we have form data
    if (!this.hasFormTarget) {
      console.error("Form target not found")
      return
    }

    // Show loading state
    this.showLoading()

    // Use Turbo to submit the form
    const formData = new FormData(this.formTarget)
    const queryParams = new URLSearchParams(formData)
    const url = `${this.submitUrlValue}?${queryParams.toString()}`

    // Use Turbo.visit for form submission with Turbo Streams
    Turbo.visit(url, { action: "replace" })

    // Save filter state
    this.setupFormPersistence()
    this.updateClearButtonVisibility()
  }

  clearFilters(e) {
    if (e) {
      e.preventDefault()
    }

    // Reset all filter inputs
    if (this.hasQueryTarget) this.queryTarget.value = ""
    if (this.hasStatusTarget) this.statusTarget.value = ""
    if (this.hasRoleTarget) this.roleTarget.value = ""
    if (this.hasVerifiedTarget) this.verifiedTarget.value = ""
    if (this.hasSortByTarget) this.sortByTarget.value = "recent"

    // Clear sessionStorage
    sessionStorage.removeItem("userFilters")

    // Submit form to apply clear filters
    this.submitForm()
  }

  updateClearButtonVisibility() {
    if (!this.hasClearBtnTarget) return

    const hasActiveFilters = [
      this.queryTarget?.value,
      this.statusTarget?.value,
      this.roleTarget?.value,
      this.verifiedTarget?.value,
      this.sortByTarget?.value !== "recent"
    ].some(val => val)

    if (hasActiveFilters) {
      this.clearBtnTarget.classList.remove("hidden")
    } else {
      this.clearBtnTarget.classList.add("hidden")
    }
  }

  showLoading() {
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.remove("hidden")
    }
    if (this.hasResultsContainerTarget) {
      this.resultsContainerTarget.classList.add("opacity-50", "pointer-events-none")
    }
  }

  hideLoading() {
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.add("hidden")
    }
    if (this.hasResultsContainerTarget) {
      this.resultsContainerTarget.classList.remove("opacity-50", "pointer-events-none")
    }
  }

  showNoResults() {
    if (this.hasNoResultsTarget) {
      this.noResultsTarget.classList.remove("hidden")
    }
  }

  hideNoResults() {
    if (this.hasNoResultsTarget) {
      this.noResultsTarget.classList.add("hidden")
    }
  }

  // Turbo Stream callback - called after results are loaded
  updateComplete() {
    this.hideLoading()
    this.updateClearButtonVisibility()
    this.restoreFocus()
  }

  saveFocusState() {
    // Store which input has focus and its cursor position
    if (this.hasQueryTarget && this.queryTarget === document.activeElement) {
      this.focusedField = "query"
      this.cursorPosition = this.queryTarget.selectionStart
    }
  }

  restoreFocus() {
    // Restore focus to the search input after Turbo update
    if (this.hasQueryTarget && this.focusedField === "query") {
      // Use requestAnimationFrame to ensure DOM is ready
      requestAnimationFrame(() => {
        this.queryTarget.focus()
        // Restore cursor position if possible
        if (this.cursorPosition !== undefined) {
          this.queryTarget.setSelectionRange(this.cursorPosition, this.cursorPosition)
        }
      })
    }
  }
}