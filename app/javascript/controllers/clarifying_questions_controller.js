import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"

export default class extends Controller {
  static targets = ["form"]

  submit(e) {
    e.preventDefault()

    const form = this.element
    const formData = new FormData(form)
    const chatId = this.data.get("chatId")

    // Collect answers
    const answers = {}
    const questions = JSON.parse(this.data.get("questions"))

    questions.forEach((q, idx) => {
      const value = formData.get(`message[answers][${idx}]`)
      answers[idx] = value
    })

    // Send answers as chat message
    post(`/chats/${chatId}/create_message`, {
      body: JSON.stringify({
        message: {
          content: JSON.stringify(answers),
          answers: answers
        }
      }),
      contentType: "application/json"
    })
  }

  skip(e) {
    e.preventDefault()
    // Dismiss the form without sending
    this.element.remove()
  }
}
