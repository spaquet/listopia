import { Controller } from "@hotwire/stimulus"

export default class extends Controller {
  static targets = ["input", "results", "footer", "viewAllLink", "container"]
  static values = {
    debounceDelay: { type: Number, default: 300 },
    limit: { type: Number, default: 5 }
  }

  connect() {
    this.debounceTimeout = null
    this.selectedIndex = -1
    this.currentResults = []
    this.totalCount = 0

    // Auto-focus search input
    this.inputTarget.focus()

    // Show empty state initially
    this.showEmptyState()
  }

  disconnect() {
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }
  }

  // ============================================================================
  // SEARCH & API
  // ============================================================================

  search(event) {
    const query = this.inputTarget.value.trim()

    // Clear previous debounce timeout
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout)
    }

    // Show empty state if no query
    if (query.length === 0) {
      this.showEmptyState()
      return
    }

    // Debounce the search
    this.debounceTimeout = setTimeout(() => {
      this.performSearch(query)
    }, this.debounceDelayValue)
  }

  async performSearch(query) {
    try {
      const url = `/search?q=${encodeURIComponent(query)}&limit=${this.limitValue}`
      const response = await fetch(url, {
        headers: { "Accept": "application/json" }
      })

      if (!response.ok) {
        this.showErrorState()
        return
      }

      const data = await response.json()
      this.currentResults = data.results || []
      this.totalCount = data.count || 0

      if (this.currentResults.length === 0) {
        this.showNoResultsState(query)
      } else {
        this.renderResults(this.currentResults, query)
      }
    } catch (error) {
      console.error("Search failed:", error)
      this.showErrorState()
    }
  }

  // ============================================================================
  // RENDERING
  // ============================================================================

  renderResults(results, query) {
    const html = results.map((result, index) => this.renderResultItem(result, index)).join("")
    this.resultsTarget.innerHTML = html

    // Show "View All Results" footer if more results exist
    if (this.totalCount > this.limitValue) {
      this.showViewAllFooter(query)
    } else {
      this.hideViewAllFooter()
    }

    this.selectedIndex = -1
  }

  renderResultItem(result, index) {
    const typeLabel = this.getTypeLabel(result.type)
    const typeBadgeClasses = this.getTypeBadgeClasses(result.type)
    const timeAgo = this.formatTimeAgo(result.updated_at)
    const description = result.description ? `<p class="text-sm text-gray-600 line-clamp-1 mt-1">${this.escapeHtml(result.description)}</p>` : ""

    return `
      <a href="${this.escapeHtml(result.url)}"
         data-result-index="${index}"
         class="block px-6 py-4 hover:bg-gray-50 border-b border-gray-100 transition-colors cursor-pointer"
         data-action="click->spotlight-search#selectResult">
        <div class="flex items-start gap-3">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${typeBadgeClasses}">
                ${typeLabel}
              </span>
              <h4 class="text-sm font-semibold text-gray-900 truncate">${this.escapeHtml(result.title)}</h4>
            </div>
            ${description}
            <p class="text-xs text-gray-500 mt-1">Updated ${timeAgo}</p>
          </div>
        </div>
      </a>
    `
  }

  // ============================================================================
  // KEYBOARD NAVIGATION
  // ============================================================================

  handleKeydown(event) {
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.navigateDown()
        break
      case "ArrowUp":
        event.preventDefault()
        this.navigateUp()
        break
      case "Enter":
        event.preventDefault()
        this.selectCurrentResult()
        break
      case "Escape":
        event.preventDefault()
        this.close()
        break
    }
  }

  handleGlobalKeydown(event) {
    // Listen for global Escape to close modal
    if (event.key === "Escape") {
      this.close()
    }
  }

  navigateDown() {
    const resultElements = this.resultsTarget.querySelectorAll("[data-result-index]")
    if (resultElements.length === 0) return

    this.selectedIndex = Math.min(this.selectedIndex + 1, resultElements.length - 1)
    this.highlightResult()
  }

  navigateUp() {
    const resultElements = this.resultsTarget.querySelectorAll("[data-result-index]")
    if (resultElements.length === 0) return

    if (this.selectedIndex <= 0) {
      this.selectedIndex = -1
      this.clearHighlight()
      this.inputTarget.focus()
      return
    }

    this.selectedIndex -= 1
    this.highlightResult()
  }

  highlightResult() {
    const resultElements = this.resultsTarget.querySelectorAll("[data-result-index]")
    this.clearHighlight()

    if (this.selectedIndex >= 0 && resultElements[this.selectedIndex]) {
      resultElements[this.selectedIndex].classList.add("bg-gray-100")
      resultElements[this.selectedIndex].scrollIntoView({ block: "nearest" })
    }
  }

  clearHighlight() {
    const resultElements = this.resultsTarget.querySelectorAll("[data-result-index]")
    resultElements.forEach((el) => el.classList.remove("bg-gray-100"))
  }

  selectCurrentResult() {
    if (this.selectedIndex === -1) {
      // No selection, submit to full search page
      const query = this.inputTarget.value.trim()
      if (query) {
        window.location.href = `/search?q=${encodeURIComponent(query)}`
      }
      return
    }

    const resultElements = this.resultsTarget.querySelectorAll("[data-result-index]")
    if (resultElements[this.selectedIndex]) {
      const url = resultElements[this.selectedIndex].href
      window.location.href = url
    }
  }

  selectResult(event) {
    // Close modal on result selection
    this.close()
  }

  // ============================================================================
  // MODAL ACTIONS
  // ============================================================================

  close() {
    // Remove modal from DOM
    this.element.remove()
  }

  // ============================================================================
  // EMPTY STATES
  // ============================================================================

  showEmptyState() {
    this.resultsTarget.innerHTML = `
      <div class="text-center py-12 px-6">
        <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
        </svg>
        <p class="mt-4 text-sm text-gray-600">Start typing to search...</p>
        <p class="mt-2 text-xs text-gray-500">Search lists, items, comments, and tags</p>
      </div>
    `
    this.hideViewAllFooter()
  }

  showNoResultsState(query) {
    this.resultsTarget.innerHTML = `
      <div class="text-center py-12 px-6">
        <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
        </svg>
        <p class="mt-4 text-sm font-medium text-gray-900">No results found</p>
        <p class="mt-1 text-sm text-gray-600">for "${this.escapeHtml(query)}"</p>
        <p class="mt-2 text-xs text-gray-500">Try different keywords</p>
      </div>
    `
    this.hideViewAllFooter()
  }

  showErrorState() {
    this.resultsTarget.innerHTML = `
      <div class="text-center py-12 px-6">
        <p class="text-sm text-red-600">Search failed. Please try again.</p>
      </div>
    `
  }

  showViewAllFooter(query) {
    const searchUrl = `/search?q=${encodeURIComponent(query)}`
    this.viewAllLinkTarget.href = searchUrl
    this.viewAllLinkTarget.textContent = `View All ${this.totalCount} Results →`
    this.footerTarget.classList.remove("hidden")
  }

  hideViewAllFooter() {
    this.footerTarget.classList.add("hidden")
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  getTypeLabel(type) {
    const labels = {
      "List": "List",
      "ListItem": "Item",
      "Comment": "Comment",
      "ActsAsTaggableOn::Tag": "Tag"
    }
    return labels[type] || type
  }

  getTypeBadgeClasses(type) {
    const classes = {
      "List": "bg-blue-100 text-blue-800",
      "ListItem": "bg-green-100 text-green-800",
      "Comment": "bg-purple-100 text-purple-800",
      "ActsAsTaggableOn::Tag": "bg-orange-100 text-orange-800"
    }
    return classes[type] || "bg-gray-100 text-gray-800"
  }

  formatTimeAgo(timestamp) {
    if (!timestamp) return "recently"

    const date = new Date(timestamp)
    const now = new Date()
    const seconds = Math.floor((now - date) / 1000)

    if (seconds < 60) return "just now"
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`
    if (seconds < 604800) return `${Math.floor(seconds / 86400)}d ago`

    return date.toLocaleDateString()
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
