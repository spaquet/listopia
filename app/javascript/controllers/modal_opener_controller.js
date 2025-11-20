import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  openModal(event) {
    event.preventDefault()
    console.log('Opening modal from URL:', this.urlValue)

    fetch(this.urlValue, {
      headers: {
        'Accept': 'text/html'
      }
    })
      .then(response => {
        console.log('Response status:', response.status)
        return response.text()
      })
      .then(html => {
        console.log('Received HTML, length:', html.length)
        const container = document.getElementById('admin_modals_container')
        if (container) {
          // Extract just the modal div from the response
          const tempDiv = document.createElement('div')
          tempDiv.innerHTML = html
          const modalDiv = tempDiv.querySelector('[data-controller="modal"]')

          if (modalDiv) {
            container.innerHTML = ''
            container.appendChild(modalDiv)
            console.log('Modal HTML inserted')
          } else {
            console.warn('Modal div not found in response, inserting all HTML')
            container.innerHTML = html
          }
        } else {
          console.error('Container not found')
        }
      })
      .catch(error => console.error('Error loading modal:', error))
  }
}
