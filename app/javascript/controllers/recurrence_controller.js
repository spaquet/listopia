import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["ruleSelect", "endDateWrapper"]

  connect() {
    this.toggleEndDate()
  }

  ruleChanged() {
    this.toggleEndDate()
  }

  toggleEndDate() {
    const isRecurring = this.ruleSelectTarget.value !== "none"
    this.endDateWrapperTarget.classList.toggle("hidden", !isRecurring)
  }
}
