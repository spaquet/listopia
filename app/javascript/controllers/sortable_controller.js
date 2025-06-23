// app/javascript/controllers/sortable_controller.js
import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.sortable = Sortable.create(this.element, {
      handle: '[data-sortable-handle]',
      animation: 150,
      ghostClass: 'opacity-50',
      onEnd: this.onEnd.bind(this)
    })
  }

  disconnect() {
    if (this.sortable) {
      this.sortable.destroy()
    }
  }

  onEnd(event) {
    const itemId = event.item.dataset.itemId
    const newPosition = event.newIndex
    
    // Send position update to server
    this.updatePosition(itemId, newPosition)
  }

  async updatePosition(itemId, position) {
    try {
      const response = await fetch(this.urlValue, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        },
        body: JSON.stringify({
          positions: { [itemId]: position }
        })
      })

      if (!response.ok) {
        throw new Error('Failed to update position')
      }
    } catch (error) {
      console.error('Error updating position:', error)
      // Revert the visual change on error
      location.reload()
    }
  }
}