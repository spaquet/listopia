import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"

export default class extends Controller {
  static targets = ["form"]

  submit(e) {
    e.preventDefault()

    const form = this.element
    const formData = new FormData(form)
    const chatId = this.data.get("chatId")

    console.log("ClarifyingQuestionsController - Form data:", {
      chatId,
      dataQuestionsRaw: this.data.get("questions"),
      dataKeys: this.data.getAll ? this.data.getAll() : 'N/A'
    })

    // Collect answers and questions
    const answers = {}
    let questions = []

    try {
      const questionsRaw = this.data.get("questions")
      console.log("Questions raw from data:", questionsRaw ? questionsRaw.substring(0, 100) : "MISSING")

      if (questionsRaw) {
        questions = JSON.parse(questionsRaw)
        console.log("Parsed questions:", questions.length, questions)
      } else {
        console.error("NO questions data found on form!")
      }
    } catch (err) {
      console.error("Failed to parse questions:", err)
    }

    questions.forEach((q, idx) => {
      const value = formData.get(`message[answers][${idx}]`)
      answers[idx] = value
    })

    console.log("ClarifyingQuestionsController - Sending:", {
      answersCount: Object.keys(answers).length,
      questionsCount: questions.length
    })

    // Send answers as chat message with questions for context
    post(`/chats/${chatId}/create_message`, {
      body: JSON.stringify({
        message: {
          content: JSON.stringify(answers),
          answers: answers,
          questions: questions
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
