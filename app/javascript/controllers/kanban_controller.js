import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["column", "card"]

  connect() {
    // Initialize drag-and-drop for existing cards and columns
    this.initializeDragAndDrop()

    // Bind turbo:load listener to re-initialize after page transitions
    this.boundTurboLoad = () => this.initializeDragAndDrop()
    document.addEventListener("turbo:load", this.boundTurboLoad)
  }

  disconnect() {
    // Clean up event listeners
    if (this.boundTurboLoad) {
      document.removeEventListener("turbo:load", this.boundTurboLoad)
    }
  }

  initializeDragAndDrop() {
    // Get all cards and columns
    const cards = this.element.querySelectorAll("[data-kanban-target='card']")
    const columns = this.element.querySelectorAll("[data-kanban-target='column']")

    // Store bound handlers so we can remove them later
    if (!this.dragHandlers) {
      this.dragHandlers = new WeakMap()
    }

    // Make cards draggable
    cards.forEach(card => {
      // Check if this card already has handlers
      if (this.dragHandlers.has(card)) {
        const handlers = this.dragHandlers.get(card)
        card.removeEventListener("dragstart", handlers.dragstart)
        card.removeEventListener("dragend", handlers.dragend)
      }

      card.draggable = true

      // Create bound handlers for this card
      const dragstart = (e) => this.handleDragStart(e)
      const dragend = (e) => this.handleDragEnd(e)

      card.addEventListener("dragstart", dragstart)
      card.addEventListener("dragend", dragend)

      // Store handlers for potential cleanup
      this.dragHandlers.set(card, { dragstart, dragend })
    })

    // Make columns drop zones
    columns.forEach(column => {
      // Check if this column already has handlers
      if (this.dragHandlers.has(column)) {
        const handlers = this.dragHandlers.get(column)
        column.removeEventListener("dragover", handlers.dragover)
        column.removeEventListener("drop", handlers.drop)
        column.removeEventListener("dragleave", handlers.dragleave)
      }

      // Create bound handlers for this column
      const dragover = (e) => this.handleDragOver(e)
      const drop = (e) => this.handleDrop(e)
      const dragleave = (e) => this.handleDragLeave(e)

      column.addEventListener("dragover", dragover)
      column.addEventListener("drop", drop)
      column.addEventListener("dragleave", dragleave)

      // Store handlers for potential cleanup
      this.dragHandlers.set(column, { dragover, drop, dragleave })
    })
  }

  handleDragStart(event) {
    const card = event.target.closest("[data-kanban-target='card']")
    if (!card) return

    // Store data in the drag event
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/html", card.innerHTML)
    event.dataTransfer.setData("item-id", card.dataset.itemId)

    // Add visual feedback
    card.classList.add("opacity-50", "bg-gray-100")
    card.style.transform = "scale(0.95)"
  }

  handleDragEnd(event) {
    const card = event.target.closest("[data-kanban-target='card']")
    if (!card) return

    // Remove visual feedback
    card.classList.remove("opacity-50", "bg-gray-100")
    card.style.transform = ""
  }

  handleDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"

    const column = event.target.closest("[data-kanban-target='column']")
    if (column) {
      column.classList.add("bg-blue-50", "ring-2", "ring-blue-400")
    }
  }

  handleDragLeave(event) {
    const column = event.target.closest("[data-kanban-target='column']")
    if (column) {
      column.classList.remove("bg-blue-50", "ring-2", "ring-blue-400")
    }
  }

  handleDrop(event) {
    event.preventDefault()

    const column = event.target.closest("[data-kanban-target='column']")
    if (!column) return

    // Remove visual feedback
    column.classList.remove("bg-blue-50", "ring-2", "ring-blue-400")

    const itemId = event.dataTransfer.getData("item-id")
    const columnId = column.dataset.columnId

    if (itemId && columnId) {
      // Update the item's board_column via a hidden form submission with Turbo
      this.updateItemColumn(itemId, columnId)
    }
  }

  updateItemColumn(itemId, columnId) {
    // Find the list ID from the current URL or DOM
    const listId = this.getListId()
    if (!listId) return

    // Build the FormData with the update payload
    const formData = new FormData()
    formData.append("_method", "patch")
    formData.append("list_item[board_column_id]", columnId)
    formData.append("authenticity_token", this.getCsrfToken())

    // Make the PATCH request with Turbo-compatible headers
    fetch(`/lists/${listId}/items/${itemId}`, {
      method: "POST",
      body: formData,
      headers: {
        "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
    .then(response => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      return response.text()
    })
    .then(html => {
      // Process the Turbo Stream response
      Turbo.renderStreamMessage(html)

      // Wait for Turbo to finish DOM updates, then re-initialize drag-and-drop
      // Use setTimeout with 0 to defer to next event loop after Turbo processing
      requestAnimationFrame(() => {
        this.initializeDragAndDrop()
        this.updateColumnCounts()
      })
    })
    .catch(error => {
      console.error("Error updating item column:", error)
    })
  }

  getListId() {
    // Try to get from URL
    const match = window.location.pathname.match(/lists\/([a-f0-9-]+)/)
    if (match) return match[1]

    // Try to get from data attribute
    return this.element.dataset.listId
  }

  getCsrfToken() {
    const token = document.querySelector("meta[name='csrf-token']")
    return token ? token.getAttribute("content") : ""
  }

  toggleAddForm(event) {
    const columnId = event.currentTarget.dataset.kanbanColumnId
    const column = this.element.querySelector(`[data-column-id="${columnId}"]`)

    if (!column) return

    // Toggle visibility of form (simple implementation)
    const existingForm = column.querySelector("[data-kanban-target='add-form']")
    if (existingForm) {
      existingForm.remove()
      return
    }

    // Create a simple inline add form
    const form = document.createElement("div")
    form.setAttribute("data-kanban-target", "add-form")
    form.className = "bg-gray-50 border-t border-gray-200 p-3 rounded-b-lg"
    form.innerHTML = `
      <form class="space-y-2">
        <input type="text" placeholder="Item title..." class="w-full px-3 py-2 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent" required>
        <div class="flex gap-2">
          <button type="submit" class="flex-1 px-3 py-1.5 text-xs font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700">Add</button>
          <button type="button" class="flex-1 px-3 py-1.5 text-xs text-gray-600 border border-gray-300 rounded-lg hover:bg-gray-50">Cancel</button>
        </div>
      </form>
    `

    column.appendChild(form)
    form.querySelector("input").focus()
  }

  scrollToAdd() {
    // Scroll to quick add form if present
    const addForm = document.querySelector("[data-kanban-target='add-form']")
    if (addForm) {
      addForm.scrollIntoView({ behavior: "smooth" })
      addForm.querySelector("input")?.focus()
    }
  }

  updateColumnCounts() {
    // Get all columns and update their item counts
    const columns = this.element.querySelectorAll("[data-kanban-target='column']")
    columns.forEach(column => {
      const columnId = column.dataset.columnId
      const itemCount = column.querySelectorAll("[data-kanban-target='card']").length

      // Update the count display
      const countDisplay = this.element.querySelector(`.column-count[data-column-id="${columnId}"]`)
      if (countDisplay) {
        countDisplay.textContent = itemCount
      }
    })
  }
}
