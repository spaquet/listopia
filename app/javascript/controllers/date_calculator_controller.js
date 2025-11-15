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
  static targets = ["startDate", "duration", "dueDate", "calculatedField"]

  connect() {
    this.updateCalculations()
  }

  // Event handlers for each field
  onStartDateChange() {
    this.updateCalculations()
  }

  onDurationChange() {
    this.updateCalculations()
  }

  onDueDateChange() {
    this.updateCalculations()
  }

  // Main calculation logic
  updateCalculations() {
    const startDate = this.getDateValue(this.startDateTarget)
    const dueDate = this.getDateValue(this.dueDateTarget)
    const duration = this.getDurationValue(this.durationTarget)

    // Scenario 1: Start Date + Duration → Calculate Due Date
    if (startDate && duration && !dueDate) {
      const calculated = this.addDaysToDate(startDate, duration)
      this.setDateValue(this.dueDateTarget, calculated)
      this.updateFieldState("dueDate", true)
      return
    }

    // Scenario 2: Due Date + Duration → Calculate Start Date
    if (dueDate && duration && !startDate) {
      const calculated = this.subtractDaysFromDate(dueDate, duration)
      this.setDateValue(this.startDateTarget, calculated)
      this.updateFieldState("startDate", true)
      return
    }

    // Scenario 3: Start Date + Due Date → Calculate Duration
    if (startDate && dueDate && !duration) {
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
    if (isCalculated && this.hasCalculatedFieldTarget) {
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
