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

    // Collect answers and questions
    const formData = new FormData(form)
    const chatId = this.data.get("chatId") || form.getAttribute("data-chat-id")
    const answers = {}
    const questions = JSON.parse(form.getAttribute("data-questions") || "[]")

    questions.forEach((q, idx) => {
      const value = formData.get(`message[answers][${idx}]`)
      answers[idx] = value
    })

    // Submit via JSON to match clarifying_questions format
    fetch(`/chats/${chatId}/create_message`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        message: {
          answers: answers,
          questions: questions
        }
      })
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
      return response.text()
    })
    .then(html => {
      // Clear input and scroll
      const input = document.querySelector('[data-unified-chat-target="messageInput"]')
      if (input) {
        input.value = ''
        input.focus()
      }

      const container = document.querySelector('[data-unified-chat-target="messagesContainer"]')
      if (container) {
        container.scrollTop = container.scrollHeight
      }

      console.log("Pre-creation planning answers submitted successfully")
    })
    .catch(error => {
      console.error("Error submitting form:", error)
    })
  }

  cancel() {
    const form = this.element.closest("form")
    if (form) {
      form.reset()
    }
  }
}
