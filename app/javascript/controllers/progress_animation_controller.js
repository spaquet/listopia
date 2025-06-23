// app/javascript/controllers/progress_animation_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { percentage: Number }

  connect() {
    this.animateProgress()
  }

  animateProgress() {
    const progressBar = this.element.querySelector('.progress-bar')
    if (!progressBar) return

    // Start from 0 and animate to target percentage
    let currentWidth = 0
    const targetWidth = this.percentageValue
    const increment = targetWidth / 30 // 30 frames for smooth animation

    const animate = () => {
      currentWidth += increment
      
      if (currentWidth >= targetWidth) {
        currentWidth = targetWidth
        progressBar.style.width = `${currentWidth}%`
        return
      }
      
      progressBar.style.width = `${currentWidth}%`
      requestAnimationFrame(animate)
    }

    requestAnimationFrame(animate)
  }
}