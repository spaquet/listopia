// app/javascript/controllers/filters_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "searchInput", 
    "searchForm", 
    "clearButton",
    "statusField",
    "visibilityField", 
    "collaborationField"
  ]
  
  connect() {
    this.timeout = null
    this.lastSearchValue = this.searchInputTarget.value
    
    // Show/hide clear button based on initial search value
    this.updateClearButtonVisibility()
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  // Handle real-time search input
  handleSearchInput(event) {
    const currentValue = event.target.value
    
    // Update clear button visibility immediately
    this.updateClearButtonVisibility()
    
    // Clear existing timeout
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
    
    // Only submit if value has actually changed
    if (currentValue !== this.lastSearchValue) {
      // Set new timeout for debounced search
      this.timeout = setTimeout(() => {
        this.submitSearch()
        this.lastSearchValue = currentValue
      }, 300) // 300ms debounce for real-time feel
    }
  }

  // Handle keyboard shortcuts in search
  handleSearchKeydown(event) {
    // Handle Enter key
    if (event.key === 'Enter') {
      event.preventDefault()
      
      // Clear timeout and submit immediately
      if (this.timeout) {
        clearTimeout(this.timeout)
      }
      
      this.submitSearch()
      this.lastSearchValue = this.searchInputTarget.value
    }
    
    // Handle Escape key to clear search
    if (event.key === 'Escape') {
      event.preventDefault()
      this.clearSearch()
    }
  }

  // Clear search input and submit
  clearSearch() {
    // Clear the search input
    this.searchInputTarget.value = ''
    
    // Hide clear button
    this.updateClearButtonVisibility()
    
    // Clear any pending timeout
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
    
    // Submit the form to reset the search
    this.submitSearch()
    this.lastSearchValue = ''
    
    // Keep focus on search input for better UX
    this.searchInputTarget.focus()
  }

  // Legacy method name for backward compatibility
  search(event) {
    this.handleSearchInput(event)
  }

  // Submit the search form
  submitSearch() {
    if (this.hasSearchFormTarget) {
      // Use requestSubmit to trigger Turbo properly
      this.searchFormTarget.requestSubmit()
    } else {
      // Fallback to finding the form
      const form = this.searchInputTarget.closest('form')
      if (form) {
        form.requestSubmit()
      }
    }
  }

  // Update clear button visibility based on search input value
  updateClearButtonVisibility() {
    if (this.hasClearButtonTarget) {
      const hasValue = this.searchInputTarget.value.trim() !== ''
      
      if (hasValue) {
        this.clearButtonTarget.classList.remove('hidden')
      } else {
        this.clearButtonTarget.classList.add('hidden')
      }
    }
  }

  // Focus search input (useful for keyboard shortcuts)
  focusSearch() {
    this.searchInputTarget.focus()
    this.searchInputTarget.select()
  }

  // Method to programmatically update filter values (useful for URL updates)
  updateFilters(params) {
    // Update hidden fields
    if (this.hasStatusFieldTarget && params.status !== undefined) {
      this.statusFieldTarget.value = params.status || ''
    }
    
    if (this.hasVisibilityFieldTarget && params.visibility !== undefined) {
      this.visibilityFieldTarget.value = params.visibility || ''
    }
    
    if (this.hasCollaborationFieldTarget && params.collaboration !== undefined) {
      this.collaborationFieldTarget.value = params.collaboration || ''
    }
    
    // Update search input
    if (params.search !== undefined) {
      this.searchInputTarget.value = params.search || ''
      this.updateClearButtonVisibility()
      this.lastSearchValue = this.searchInputTarget.value
    }
  }
}