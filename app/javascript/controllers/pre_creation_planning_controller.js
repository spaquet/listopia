// app/javascript/controllers/pre_creation_planning_controller.js
// Handles the pre-creation planning form submission
// Collects answers and sends them back to the chat for processing

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("Pre-creation planning controller connected")
  }

  submit(event) {
    event.preventDefault()

    const form = event.target.closest("form") || this.element.closest("form")
    if (!form) {
      console.error("Form not found")
      return
    }

    // Validate all answer fields are filled
    const answerTextareas = form.querySelectorAll("textarea[name^='message']")
    let allFilled = true

    answerTextareas.forEach((textarea) => {
      const answer = textarea.value.trim()
      if (!answer) {
        textarea.classList.add("border-red-500", "focus:ring-red-500")
        allFilled = false
      } else {
        textarea.classList.remove("border-red-500", "focus:ring-red-500")
      }
    })

    if (!allFilled) {
      return
    }

    // Get the form data and submit
    const submitButton = form.querySelector("button[type='submit']")
    if (submitButton) {
      submitButton.disabled = true
      submitButton.textContent = "Submitting..."
    }

    // Build content from answers and submit
    const formData = new FormData(form)
    const content = this.buildMessageContent(formData)
    formData.set("message[content]", content)

    // Replace form data and submit
    const newFormData = new FormData()
    newFormData.append("message[content]", content)
    newFormData.append("authenticity_token", this.getAuthToken())

    // Submit via fetch with the proper format
    const form_action = form.getAttribute("action")
    fetch(form_action, {
      method: "POST",
      headers: {
        "X-CSRF-Token": this.getAuthToken(),
        "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"
      },
      body: newFormData
    })
      .then(response => response.text())
      .then(html => {
        // Turbo should handle the response automatically
        console.log("Form submitted successfully")
      })
      .catch(error => {
        console.error("Error submitting form:", error)
        if (submitButton) {
          submitButton.disabled = false
          submitButton.textContent = "Submit Answers"
        }
      })
  }

  cancel() {
    const form = this.element.closest("form")
    if (form) {
      form.reset()
    }
  }

  buildMessageContent(formData) {
    const answers = []

    // Extract all answer values in order
    let idx = 0
    while (true) {
      const value = formData.get(`message[answers][${idx}]`)
      if (value === null) break
      answers.push(value)
      idx++
    }

    return answers.join("\n---\n")
  }

  getAuthToken() {
    const token = document.querySelector('meta[name="csrf-token"]')
    return token ? token.getAttribute("content") : ""
  }
}
