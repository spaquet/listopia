// app/javascript/controllers/message_rating_controller.js
// Handles message rating (helpful/unhelpful/harmful) functionality

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    messageId: String,
    chatId: String
  }

  /**
   * Rate a message as helpful/unhelpful/harmful
   */
  async rate(event) {
    event.preventDefault()
    const rating = event.currentTarget.dataset.rating

    const button = event.currentTarget
    button.disabled = true

    try {
      const response = await fetch(`/chats/${this.chatIdValue}/messages/${this.messageIdValue}/feedbacks`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCsrfToken()
        },
        body: JSON.stringify({
          message_feedback: {
            rating: rating
          }
        })
      })

      if (!response.ok) {
        throw new Error("Failed to submit feedback")
      }

      // Show confirmation
      this.showRatingConfirmation(rating)

      // Update button state to show it's been rated
      this.markAsRated(button, rating)
    } catch (error) {
      console.error("Error submitting rating:", error)
      this.showError("Failed to submit feedback")
    } finally {
      button.disabled = false
    }
  }

  /**
   * Show report modal for harmful content
   */
  showReportModal(event) {
    event.preventDefault()

    // Create a simple modal for reporting
    const modal = document.createElement("div")
    modal.className = "fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
    modal.innerHTML = `
      <div class="bg-white rounded-lg p-6 max-w-md w-full mx-4 shadow-lg">
        <h2 class="text-lg font-semibold mb-3">Report Harmful Content</h2>

        <textarea
          id="reportComment"
          placeholder="Please describe why you think this content is harmful..."
          class="w-full border border-gray-300 rounded px-3 py-2 mb-4 text-sm focus:outline-none focus:ring-2 focus:ring-red-500"
          rows="4"></textarea>

        <div class="flex gap-2 justify-end">
          <button
            onclick="this.closest('.fixed').remove()"
            class="px-4 py-2 text-gray-700 border border-gray-300 rounded hover:bg-gray-50 transition-colors">
            Cancel
          </button>
          <button
            onclick="document.querySelector('[data-controller=message-rating]')._submitHarmfulReport()"
            class="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 transition-colors">
            Report
          </button>
        </div>
      </div>
    `

    document.body.appendChild(modal)
    document.getElementById("reportComment").focus()

    // Store reference for submission
    this._currentReportModal = modal
  }

  /**
   * Submit harmful content report
   */
  async _submitHarmfulReport() {
    const comment = document.getElementById("reportComment")?.value || ""

    try {
      const response = await fetch(`/chats/${this.chatIdValue}/messages/${this.messageIdValue}/feedbacks`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCsrfToken()
        },
        body: JSON.stringify({
          message_feedback: {
            rating: "harmful",
            comment: comment
          }
        })
      })

      if (!response.ok) {
        throw new Error("Failed to submit report")
      }

      // Close modal and show confirmation
      if (this._currentReportModal) {
        this._currentReportModal.remove()
      }

      this.showRatingConfirmation("harmful", "Your report has been submitted. Thank you!")
    } catch (error) {
      console.error("Error submitting report:", error)
      this.showError("Failed to submit report")
    }
  }

  /**
   * Show confirmation message
   */
  showRatingConfirmation(rating, customMessage = null) {
    const messages = {
      helpful: "👍 Thanks! We're glad this was helpful.",
      neutral: "👌 Thanks for the feedback.",
      unhelpful: "👎 Thanks for letting us know. We'll improve.",
      harmful: customMessage || "⚠️ Thank you for reporting. We'll review this."
    }

    const message = messages[rating] || "Thanks for your feedback!"
    this.showNotification(message, "success")
  }

  /**
   * Mark button as rated
   */
  markAsRated(button, rating) {
    // Add visual indication that button was clicked
    button.classList.add("opacity-50", "cursor-default")
    button.disabled = true

    // Show a checkmark or similar indicator
    const icon = button.querySelector("svg")
    if (icon) {
      icon.classList.add("text-green-500")
    }
  }

  /**
   * Show notification
   */
  showNotification(message, type = "info") {
    const notification = document.createElement("div")
    const bgColor = type === "success" ? "bg-green-500" : "bg-blue-500"

    notification.className = `fixed bottom-4 right-4 ${bgColor} text-white rounded-lg px-4 py-3 shadow-lg z-50 animation-slide-in`
    notification.textContent = message

    document.body.appendChild(notification)

    // Auto-remove after 3 seconds
    setTimeout(() => {
      notification.remove()
    }, 3000)
  }

  /**
   * Show error message
   */
  showError(message) {
    const notification = document.createElement("div")
    notification.className = "fixed bottom-4 right-4 bg-red-500 text-white rounded-lg px-4 py-3 shadow-lg z-50"
    notification.textContent = message

    document.body.appendChild(notification)

    setTimeout(() => {
      notification.remove()
    }, 4000)
  }

  /**
   * Get CSRF token
   */
  getCsrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
