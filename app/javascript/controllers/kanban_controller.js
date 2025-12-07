import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["column", "card"]

  connect() {
    // Initialize drag-and-drop for existing cards and columns
    this.initializeDragAndDrop()

    // Bind turbo:load listener to re-initialize after page transitions
    this.boundTurboLoad = () => this.initializeDragAndDrop()
    document.addEventListener("turbo:load", this.boundTurboLoad)

    // Listen for custom event to re-initialize after Turbo Stream updates
    this.boundReInitialize = () => this.initializeDragAndDrop()
    this.element.addEventListener("kanban:reinitialize", this.boundReInitialize)

    // Also listen on document for bubbled custom events
    this.boundDocumentReInitialize = () => this.initializeDragAndDrop()
    document.addEventListener("kanban:reinitialize", this.boundDocumentReInitialize)
  }

  disconnect() {
    // Clean up event listeners
    if (this.boundTurboLoad) {
      document.removeEventListener("turbo:load", this.boundTurboLoad)
    }
    if (this.boundReInitialize) {
      this.element.removeEventListener("kanban:reinitialize", this.boundReInitialize)
    }
    if (this.boundDocumentReInitialize) {
      document.removeEventListener("kanban:reinitialize", this.boundDocumentReInitialize)
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
        card.removeEventListener("mousedown", handlers.mousedown)
        card.removeEventListener("mouseup", handlers.mouseup)
      }

      // Start with draggable = false
      card.draggable = false

      // Create bound handlers for this card
      const dragstart = (e) => this.handleDragStart(e)
      const dragend = (e) => this.handleDragEnd(e)
      const mousedown = (e) => this.handleMouseDown(e)
      const mouseup = (e) => this.handleMouseUp(e)

      card.addEventListener("dragstart", dragstart)
      card.addEventListener("dragend", dragend)
      card.addEventListener("mousedown", mousedown)
      card.addEventListener("mouseup", mouseup)

      // Store handlers for potential cleanup
      this.dragHandlers.set(card, { dragstart, dragend, mousedown, mouseup })
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

  handleMouseDown(event) {
    const card = event.target.closest("[data-kanban-target='card']")
    if (!card) return

    // Check if mousedown is on an interactive element or inside one
    const interactiveElement = event.target.closest("a, button, form, [role='button'], input, textarea, select, svg")
    if (interactiveElement) {
      // Don't make the card draggable - let the click handler work
      card.draggable = false

      // If we clicked on an SVG, walk up to find if there's a link
      if (event.target.closest("svg")) {
        const parentLink = event.target.closest("a")
        if (parentLink) {
          // SVG is inside a link - allow the link click
          return
        }
      }

      return
    }

    // Only make the card draggable if clicking on empty card area
    card.draggable = true
  }

  handleMouseUp(event) {
    // Reset draggable state after mouse is released
    const card = event.target.closest("[data-kanban-target='card']")
    if (card) {
      card.draggable = false
    }
  }

  handleDragStart(event) {
    const card = event.target.closest("[data-kanban-target='card']")
    if (!card || !card.draggable) return

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

    // Get columnId - try data attribute first (for list-specific kanban),
    // then fall back to extracting from the element ID (for items_kanban)
    let columnId = column.dataset.columnId
    if (!columnId && column.id) {
      // Extract from id like "column_to-do" or "column_<uuid>"
      columnId = column.id.replace("column_", "")
    }

    if (itemId && columnId) {
      // Update the item's board_column via a hidden form submission with Turbo
      this.updateItemColumn(itemId, columnId)
    }
  }

  updateItemColumn(itemId, columnId) {
    // Find the item card element to get list ID
    const cardElement = document.querySelector(`[data-item-id="${itemId}"]`)
    if (!cardElement) return

    // Try to get list ID from card's data attribute (for items_kanban view)
    let listId = cardElement.dataset.listId

    // Fall back to getting from URL or element (for list-specific kanban)
    if (!listId) {
      listId = this.getListId()
    }

    if (!listId) return

    // Determine what status/column to set based on the target column
    // For items_kanban, columnId will be a parameterized string like "to-do", "in-progress", "done"
    // For list-specific kanban, columnId will be a UUID
    const statusMap = {
      "to-do": "pending",
      "in-progress": "in_progress",
      "done": "completed"
    }

    let updatePayload = {}

    // If columnId matches a status column name (items_kanban), update status
    if (statusMap[columnId]) {
      updatePayload["list_item[status]"] = statusMap[columnId]
      // Clear board_column_id so the turbo_stream response uses the items_kanban branch
      updatePayload["list_item[board_column_id]"] = ""
    } else {
      // Otherwise it's a board column ID (list-specific kanban), update board_column_id
      updatePayload["list_item[board_column_id]"] = columnId
    }

    // Build the FormData with the update payload
    const formData = new FormData()
    formData.append("_method", "patch")
    Object.entries(updatePayload).forEach(([key, value]) => {
      formData.append(key, value)
    })
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
