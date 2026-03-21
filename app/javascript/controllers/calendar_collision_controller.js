import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dueDateInput", "collisionWarning"]
  static values = { debounceMs: { type: Number, default: 600 } }

  connect() {
    this._timeout = null
  }

  disconnect() {
    clearTimeout(this._timeout)
  }

  check() {
    clearTimeout(this._timeout)
    this._timeout = setTimeout(() => this._performCheck(), this.debounceMsValue)
  }

  async _performCheck() {
    const dueDate = this.dueDateInputTarget.value
    if (!dueDate) {
      this._clearWarning()
      return
    }

    // Use due_date as end_time, 1 hour before as start_time (approximation)
    const endTime = new Date(dueDate)
    const startTime = new Date(endTime.getTime() - 60 * 60 * 1000)

    this._showLoading()

    try {
      const resp = await fetch("/connectors/calendars/collisions/check", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        body: JSON.stringify({
          start_time: startTime.toISOString(),
          end_time: endTime.toISOString()
        })
      })

      if (!resp.ok) { this._clearWarning(); return }

      const data = await resp.json()
      data.has_conflicts ? this._showConflicts(data.collisions) : this._showClear()
    } catch {
      this._clearWarning()
    }
  }

  _showLoading() {
    if (!this.hasCollisionWarningTarget) return
    this.collisionWarningTarget.innerHTML = `
      <div class="flex items-center gap-2 text-xs text-gray-500 mt-1">
        <svg class="w-3 h-3 animate-spin" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"/>
        </svg>
        Checking calendar...
      </div>`
  }

  _showClear() {
    if (!this.hasCollisionWarningTarget) return
    this.collisionWarningTarget.innerHTML = `
      <p class="flex items-center gap-1 text-xs text-green-600 mt-1">
        <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
        </svg>
        No calendar conflicts
      </p>`
    setTimeout(() => this._clearWarning(), 3000)
  }

  _showConflicts(collisions) {
    if (!this.hasCollisionWarningTarget) return
    const items = collisions.slice(0, 3).map(c => {
      const start = new Date(c.start).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
      return `<li class="truncate">${c.title} @ ${start} <span class="text-gray-400">(${c.calendar})</span></li>`
    }).join("")
    this.collisionWarningTarget.innerHTML = `
      <div class="mt-1 text-xs border border-amber-200 bg-amber-50 rounded p-2">
        <p class="font-medium text-amber-700 flex items-center gap-1 mb-1">
          <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
          </svg>
          ${collisions.length} calendar conflict${collisions.length > 1 ? 's' : ''}
        </p>
        <ul class="space-y-0.5 text-amber-600">${items}</ul>
      </div>`
  }

  _clearWarning() {
    if (!this.hasCollisionWarningTarget) return
    this.collisionWarningTarget.innerHTML = ""
  }
}
