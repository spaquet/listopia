import { Controller } from "@hotwired/stimulus"

/**
 * Date Calculator Controller
 * Handles automatic calculation of dates and duration based on user input
 *
 * Supports three scenarios:
 * 1. Start Date + Duration → calculates Due Date
 * 2. Due Date + Duration → calculates Start Date
 * 3. Start Date + Due Date → calculates Duration
 */
export default class extends Controller {
  static targets = ["startDate", "duration", "dueDate"]

  // Track which fields the user explicitly filled (vs which were auto-calculated)
  connect() {
    this.userFilledFields = new Set()

    // Mark all currently filled fields as user-filled on page load
    if (this.startDateTarget.value) this.userFilledFields.add("startDate")
    if (this.dueDateTarget.value) this.userFilledFields.add("dueDate")
    if (this.durationTarget.value) this.userFilledFields.add("duration")
  }

  // Set start date to today
  setTodayStartDate() {
    const today = new Date()
    this.setDateValue(this.startDateTarget, today)
    this.updateCalculations()
  }

  // Clear duration field
  clearDuration() {
    this.durationTarget.value = ""
    this.updateCalculations()
  }

  // Clear all timeline fields (start date, duration, due date)
  clearAllDates() {
    this.startDateTarget.value = ""
    this.durationTarget.value = ""
    this.dueDateTarget.value = ""
    this.userFilledFields.clear()
    this.updateCalculations()
  }

  // Event handlers for each field
  onStartDateChange() {
    if (this.startDateTarget.value) {
      this.userFilledFields.add("startDate")
    } else {
      this.userFilledFields.delete("startDate")
    }
    this.updateCalculations()
  }

  onDurationChange() {
    if (this.durationTarget.value) {
      this.userFilledFields.add("duration")
    } else {
      this.userFilledFields.delete("duration")
    }
    this.updateCalculations()
  }

  onDueDateChange() {
    if (this.dueDateTarget.value) {
      this.userFilledFields.add("dueDate")
    } else {
      this.userFilledFields.delete("dueDate")
    }
    this.updateCalculations()
  }

  // Main calculation logic
  // Only calculates if the user hasn't explicitly filled the target field
  updateCalculations() {
    const startDate = this.getDateValue(this.startDateTarget)
    const dueDate = this.getDateValue(this.dueDateTarget)
    const duration = this.getDurationValue(this.durationTarget)

    // Scenario 1: Start Date + Duration → Calculate Due Date
    // ONLY if user didn't explicitly set a due date
    // (unless they just changed duration - then we update it for them)
    if (startDate && duration && !this.userFilledFields.has("dueDate")) {
      const calculated = this.addDaysToDate(startDate, duration)
      this.setDateValue(this.dueDateTarget, calculated)
      this.updateFieldState("dueDate", this.isDurationFieldActive())
      return
    }

    // Scenario 2: Due Date + Duration → Calculate Start Date
    // ONLY if user didn't explicitly set a start date
    if (dueDate && duration && !this.userFilledFields.has("startDate")) {
      const calculated = this.subtractDaysFromDate(dueDate, duration)
      this.setDateValue(this.startDateTarget, calculated)
      this.updateFieldState("startDate", true)
      return
    }

    // Scenario 3: Start Date + Due Date → Calculate Duration
    // ONLY if user didn't explicitly set a duration
    if (startDate && dueDate && !this.userFilledFields.has("duration")) {
      const calculated = this.calculateDurationDays(startDate, dueDate)
      if (calculated >= 0) {
        this.durationTarget.value = calculated
        this.updateFieldState("duration", true)
      }
      return
    }

    // Reset field states if conditions aren't met
    this.clearCalculatedStates()
  }

  // Check if duration field was the trigger for the calculation
  isDurationFieldActive() {
    return document.activeElement === this.durationTarget
  }

  // Helper methods for date calculations
  getDateValue(target) {
    const value = target.value
    if (!value) return null
    const date = new Date(value)
    return isNaN(date.getTime()) ? null : date
  }

  getDurationValue(target) {
    const value = parseInt(target.value, 10)
    return value > 0 ? value : null
  }

  setDateValue(target, date) {
    if (!date) {
      target.value = ""
      return
    }
    target.value = this.formatDateTimeLocal(date)
  }

  formatDateTimeLocal(date) {
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day = String(date.getDate()).padStart(2, "0")
    const hours = String(date.getHours()).padStart(2, "0")
    const minutes = String(date.getMinutes()).padStart(2, "0")
    return `${year}-${month}-${day}T${hours}:${minutes}`
  }

  addDaysToDate(date, days) {
    const result = new Date(date)
    result.setDate(result.getDate() + days)
    return result
  }

  subtractDaysFromDate(date, days) {
    const result = new Date(date)
    result.setDate(result.getDate() - days)
    return result
  }

  calculateDurationDays(startDate, dueDate) {
    const msPerDay = 24 * 60 * 60 * 1000
    return Math.ceil((dueDate - startDate) / msPerDay)
  }

  // Visual feedback for calculated fields
  updateFieldState(fieldType, isCalculated) {
    if (isCalculated) {
      const target = this.getTargetByFieldType(fieldType)
      target.classList.add("bg-blue-50", "border-blue-300", "ring-blue-100")
      target.classList.remove("border-gray-300")

      // Add aria-label to indicate field was auto-calculated
      target.setAttribute("aria-label", `${fieldType} (auto-calculated)`)
    }
  }

  clearCalculatedStates() {
    ;[this.startDateTarget, this.dueDateTarget, this.durationTarget].forEach((target) => {
      target.classList.remove("bg-blue-50", "border-blue-300", "ring-blue-100")
      target.classList.add("border-gray-300")
      target.removeAttribute("aria-label")
    })
  }

  getTargetByFieldType(fieldType) {
    switch (fieldType) {
      case "startDate":
        return this.startDateTarget
      case "dueDate":
        return this.dueDateTarget
      case "duration":
        return this.durationTarget
      default:
        return null
    }
  }
}
