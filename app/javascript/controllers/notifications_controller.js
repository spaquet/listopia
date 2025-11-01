// app/javascript/controllers/notifications_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bellIcon", "badge", "dropdown"]
  static values = { 
    refreshInterval: { type: Number, default: 30000 }, // 30 seconds
    autoRefresh: { type: Boolean, default: true }
  }

  connect() {
    // Only initialize if all required targets exist
    if (this.hasAllRequiredTargets()) {
      this.startAutoRefresh()
    } else {
      console.log("[Notifications] Skipping init - missing required targets")
    }
  }

  disconnect() {
    this.stopAutoRefresh()
  }

  /**
   * Check if all required targets are present
   */
  hasAllRequiredTargets() {
    try {
      return this.hasBellIconTarget && this.hasBadgeTarget
    } catch (e) {
      return false
    }
  }

  /**
   * Get CSRF token safely - returns null if not found
   */
  getCsrfToken() {
    try {
      const token = document.querySelector('[name="csrf-token"]')
      if (token && token.content) {
        return token.content
      }
      return null
    } catch (e) {
      return null
    }
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
      const csrfToken = this.getCsrfToken()
      if (!csrfToken) {
        console.warn("[Notifications] CSRF token not found")
        return
      }

      const response = await fetch('/notifications/stats', {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': csrfToken
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
    try {
      if (this.hasBadgeTarget) {
        if (count > 0) {
          this.badgeTarget.textContent = count > 9 ? '9+' : count.toString()
          this.badgeTarget.classList.remove('hidden')
        } else {
          this.badgeTarget.classList.add('hidden')
        }
      }
    } catch (e) {
      console.error("[Notifications] Error updating badge:", e.message)
    }
  }

  async markAllAsSeen() {
    try {
      const csrfToken = this.getCsrfToken()
      if (!csrfToken) {
        console.warn("[Notifications] CSRF token not found for marking as seen")
        return
      }

      const response = await fetch('/notifications/mark_all_as_seen', {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
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
      this.boundHandleOutsideClick = this.handleOutsideClick.bind(this)
      document.addEventListener('click', this.boundHandleOutsideClick)
    }
  }

  closeDropdown() {
    if (this.hasDropdownTarget) {
      this.dropdownTarget.classList.add('hidden')
      
      // Remove event listener
      if (this.boundHandleOutsideClick) {
        document.removeEventListener('click', this.boundHandleOutsideClick)
      }
    }
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.closeDropdown()
    }
  }
}