import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="dashboard-action"
export default class extends Controller {
  static values = {
    itemId: String,
    listId: String
  }

  connect() {
    console.log("DashboardAction controller connected")
  }

  markComplete(event) {
    event.preventDefault()
    
    const itemId = this.itemIdValue
    const listId = this.listIdValue
    
    if (!itemId || !listId) {
      console.error("Missing item or list ID")
      return
    }

    // Send request to mark item as complete
    fetch(`/list_items/${itemId}/toggle_status`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({
        status: "completed"
      })
    })
    .then(response => {
      if (response.ok) {
        // Refresh the sidebar
        this.refreshAdaptiveSidebar(listId)
        this.showSuccessMessage("Item marked as complete!")
      } else {
        this.showErrorMessage("Failed to mark item as complete")
      }
    })
    .catch(error => {
      console.error("Error:", error)
      this.showErrorMessage("An error occurred")
    })
  }

  refreshAdaptiveSidebar(listId) {
    // Trigger a refresh of the adaptive sidebar
    const url = `/dashboard/focus_list?list_id=${listId}&format=turbo_stream`
    
    fetch(url, {
      method: "GET",
      headers: {
        "Accept": "text/vnd.turbo-stream.html"
      }
    })
    .then(response => response.text())
    .then(html => {
      Turbo.connectStreamSource(new EventSource(url))
    })
  }

  showSuccessMessage(message) {
    const messageEl = document.createElement('div')
    messageEl.className = 'fixed top-20 right-4 z-50 bg-green-50 border border-green-200 text-green-800 px-4 py-3 rounded-lg shadow-md flex items-center space-x-3 max-w-md'
    messageEl.innerHTML = `
      <svg class="w-5 h-5 text-green-600" fill="currentColor" viewBox="0 0 20 20">
        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"></path>
      </svg>
      <span>${message}</span>
    `
    
    document.body.appendChild(messageEl)
    
    setTimeout(() => {
      messageEl.remove()
    }, 3000)
  }

  showErrorMessage(message) {
    const messageEl = document.createElement('div')
    messageEl.className = 'fixed top-20 right-4 z-50 bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded-lg shadow-md flex items-center space-x-3 max-w-md'
    messageEl.innerHTML = `
      <svg class="w-5 h-5 text-red-600" fill="currentColor" viewBox="0 0 20 20">
        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"></path>
      </svg>
      <span>${message}</span>
    `
    
    document.body.appendChild(messageEl)
    
    setTimeout(() => {
      messageEl.remove()
    }, 3000)
  }
}