// app/javascript/controllers/notifications_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bellIcon", "badge", "dropdown"]
  static values = { 
    refreshInterval: { type: Number, default: 30000 }, // 30 seconds
    autoRefresh: { type: Boolean, default: true }
  }

  connect() {
    this.startAutoRefresh()
  }

  disconnect() {
    this.stopAutoRefresh()
  }

  startAutoRefresh() {
    if (this.autoRefreshValue) {
      this.refreshTimer = setInterval(() => {
        this.refreshNotificationCount()
      }, this.refreshIntervalValue)
    }
  }

  stopAutoRefresh() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }

  async refreshNotificationCount() {
    try {
      const response = await fetch('/notifications/stats', {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })

      if (response.ok) {
        const stats = await response.json()
        this.updateBadge(stats.unseen)
      }
    } catch (error) {
      console.error('Failed to refresh notification count:', error)
    }
  }

  updateBadge(count) {
    if (this.hasBadgeTarget) {
      if (count > 0) {
        this.badgeTarget.textContent = count > 9 ? '9+' : count.toString()
        this.badgeTarget.classList.remove('hidden')
      } else {
        this.badgeTarget.classList.add('hidden')
      }
    }
  }

  async markAllAsSeen() {
    try {
      const response = await fetch('/notifications/mark_all_as_seen', {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })

      if (response.ok) {
        this.updateBadge(0)
      }
    } catch (error) {
      console.error('Failed to mark notifications as seen:', error)
    }
  }

  // Handle clicking on the notification bell
  toggleDropdown(event) {
    event.preventDefault()
    
    if (this.hasDropdownTarget) {
      const isHidden = this.dropdownTarget.classList.contains('hidden')
      
      if (isHidden) {
        this.openDropdown()
      } else {
        this.closeDropdown()
      }
    }
  }

  openDropdown() {
    if (this.hasDropdownTarget) {
      this.dropdownTarget.classList.remove('hidden')
      this.markAllAsSeen()
      
      // Close dropdown when clicking outside
      document.addEventListener('click', this.handleOutsideClick.bind(this))
    }
  }

  closeDropdown() {
    if (this.hasDropdownTarget) {
      this.dropdownTarget.classList.add('hidden')
      document.removeEventListener('click', this.handleOutsideClick.bind(this))
    }
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.closeDropdown()
    }
  }
}