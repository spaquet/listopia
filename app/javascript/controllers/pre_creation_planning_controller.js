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

    // Get the form data and build content from answers
    const formData = new FormData(form)
    const content = this.buildMessageContent(formData)

    // Find the message wrapper to remove it after submission
    const messageWrapper = this.element.closest("[id^='message-']")
    const messageId = messageWrapper?.id || null

    // Get the submit button
    const submitButton = form.querySelector("button[type='submit']")
    if (submitButton) {
      submitButton.disabled = true
      submitButton.textContent = "Submitting..."
    }

    // Replace the form with a loading state immediately
    const messageContent = form.querySelector(".message-content") || this.element.closest("[data-message-id]")?.querySelector(".message-content")
    if (messageContent) {
      messageContent.innerHTML = `
        <div class="flex items-center gap-2">
          <div class="flex gap-1">
            <span class="w-2 h-2 bg-gray-400 rounded-full animate-bounce"></span>
            <span class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.2s"></span>
            <span class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.4s"></span>
          </div>
          <span class="text-xs text-gray-600">Processing your answers...</span>
        </div>
      `
    }

    // Submit to server with Turbo Stream response
    const form_action = form.getAttribute("action")
    const csrfToken = this.getAuthToken()

    // Use fetch with proper Turbo Stream handling
    fetch(form_action, {
      method: "POST",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"
      },
      body: new URLSearchParams({
        "message[content]": content,
        "authenticity_token": csrfToken
      })
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
      return response.text()
    })
    .then(html => {
      // Manually process Turbo Stream response
      // This handles the HTML that Turbo Stream returns
      const parser = new DOMParser()
      const doc = parser.parseFromString(html, "text/html")

      // Find all turbo-stream elements
      const turboStreams = doc.querySelectorAll("turbo-stream")

      if (turboStreams.length > 0) {
        // Process each turbo-stream element
        turboStreams.forEach(stream => {
          // Dispatch the turbo:submit-end event to trigger Turbo processing
          const action = stream.getAttribute("action")
          const target = stream.getAttribute("target")
          const template = stream.querySelector("template")

          if (action === "append" && target && template) {
            const targetElement = document.getElementById(target)
            if (targetElement) {
              const content = template.content.cloneNode(true)
              targetElement.appendChild(content)
            }
          } else if (action === "replace" && target && template) {
            const targetElement = document.getElementById(target)
            if (targetElement) {
              const content = template.content.cloneNode(true)
              targetElement.replaceWith(content)
            }
          }
        })
      }

      // Remove the original form message after processing
      if (messageId) {
        const formMessageElement = document.getElementById(messageId)
        if (formMessageElement) {
          formMessageElement.remove()
        }
      }

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

      console.log("Form submitted and Turbo Streams processed successfully")
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
    const form = this.element.closest("form")

    // Extract all answer values in order
    let idx = 0
    while (true) {
      const value = formData.get(`message[answers][${idx}]`)
      if (value === null) break
      answers.push(value)
      idx++
    }

    // Get questions from form data attribute (stored as JSON)
    const questionsJson = form.getAttribute("data-questions")
    let questions = []
    try {
      questions = questionsJson ? JSON.parse(questionsJson) : []
    } catch (e) {
      console.warn("Failed to parse questions JSON:", e)
    }

    const questionsAndAnswers = []

    // Build Q&A pairs from questions data
    questions.forEach((question, idx) => {
      const questionText = question.question || ""
      const answer = answers[idx] || ""

      if (questionText && answer) {
        questionsAndAnswers.push(`**${questionText}**\n${answer}`)
      }
    })

    // Format: show questions and answers together
    return questionsAndAnswers.join("\n\n")
  }

  getAuthToken() {
    const token = document.querySelector('meta[name="csrf-token"]')
    return token ? token.getAttribute("content") : ""
  }
}
