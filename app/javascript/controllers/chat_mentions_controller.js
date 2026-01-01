import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "suggestions"]
  static values = { chatId: String }

  connect() {
    this.suggestionsElement = null
    this.currentQuery = ""
    this.currentType = null // "user" or "reference"
    this.selectedIndex = -1
  }

  async handleInput(event) {
    const text = this.inputTarget.value
    const cursorPos = this.inputTarget.selectionStart
    const textBeforeCursor = text.substring(0, cursorPos)

    // Find the last @ or # symbol
    const atMatch = textBeforeCursor.lastIndexOf("@")
    const hashMatch = textBeforeCursor.lastIndexOf("#")

    let lastSymbolPos = -1
    let symbolType = null

    if (atMatch > hashMatch && atMatch !== -1) {
      lastSymbolPos = atMatch
      symbolType = "user"
    } else if (hashMatch !== -1) {
      lastSymbolPos = hashMatch
      symbolType = "reference"
    }

    // If no symbol found or symbol is not at the expected position, hide suggestions
    if (lastSymbolPos === -1) {
      this.hideSuggestions()
      return
    }

    // Get the query text after the symbol
    const queryStart = lastSymbolPos + 1
    const spaceIndex = textBeforeCursor.indexOf(" ", queryStart)
    const queryEnd = spaceIndex === -1 ? cursorPos : spaceIndex

    const query = textBeforeCursor.substring(queryStart, queryEnd).trim()

    // Only show suggestions if there's at least 1 character after the symbol
    if (query.length < 1) {
      this.hideSuggestions()
      return
    }

    this.currentQuery = query
    this.currentType = symbolType

    if (symbolType === "user") {
      await this.fetchUserSuggestions(query)
    } else if (symbolType === "reference") {
      await this.fetchReferenceSuggestions(query)
    }
  }

  async fetchUserSuggestions(query) {
    try {
      const response = await fetch(
        `/chats/${this.chatIdValue}/mentions/search_users?q=${encodeURIComponent(query)}`
      )
      const users = await response.json()
      this.showSuggestions(users, "user")
    } catch (error) {
      console.error("Error fetching user suggestions:", error)
      this.hideSuggestions()
    }
  }

  async fetchReferenceSuggestions(query) {
    try {
      const response = await fetch(
        `/chats/${this.chatIdValue}/mentions/search_references?q=${encodeURIComponent(query)}`
      )
      const references = await response.json()
      this.showSuggestions(references, "reference")
    } catch (error) {
      console.error("Error fetching reference suggestions:", error)
      this.hideSuggestions()
    }
  }

  showSuggestions(items, type) {
    if (items.length === 0) {
      this.hideSuggestions()
      return
    }

    // Remove existing suggestions element
    if (this.suggestionsElement) {
      this.suggestionsElement.remove()
    }

    // Create suggestions container
    const container = document.createElement("div")
    container.className = "absolute z-50 bg-white border border-gray-200 rounded-lg shadow-lg mt-1 max-h-64 overflow-y-auto"
    container.style.minWidth = "300px"

    items.forEach((item, index) => {
      const suggestion = document.createElement("div")
      suggestion.className = "px-4 py-2 cursor-pointer hover:bg-gray-100"
      suggestion.dataset.index = index
      suggestion.innerHTML = this.renderSuggestion(item, type)

      suggestion.addEventListener("click", () => this.selectSuggestion(item, type))
      suggestion.addEventListener("mouseenter", () => this.highlightSuggestion(index))

      container.appendChild(suggestion)
    })

    // Position the suggestions above the input
    const inputRect = this.inputTarget.getBoundingClientRect()
    container.style.position = "fixed"
    container.style.bottom = (window.innerHeight - inputRect.top + 5) + "px"
    container.style.left = inputRect.left + "px"

    document.body.appendChild(container)
    this.suggestionsElement = container
    this.selectedIndex = -1
  }

  renderSuggestion(item, type) {
    if (type === "user") {
      return `
        <div class="flex items-center gap-2">
          ${item.avatar_url ? `<img src="${item.avatar_url}" alt="${item.name}" class="w-6 h-6 rounded-full">` : `<div class="w-6 h-6 rounded-full bg-gray-300"></div>`}
          <div>
            <div class="font-semibold text-sm">${item.name}</div>
            <div class="text-xs text-gray-600">${item.email}</div>
          </div>
        </div>
      `
    } else {
      // reference
      const typeLabel = item.type === "item" ? "Item" : "List"
      const listInfo = item.list_title ? `<span class="text-xs text-gray-500"> in ${item.list_title}</span>` : ""
      return `
        <div>
          <div class="font-semibold text-sm">${item.title}</div>
          <div class="text-xs text-gray-600">${typeLabel}${listInfo}</div>
        </div>
      `
    }
  }

  selectSuggestion(item, type) {
    const input = this.inputTarget
    const text = input.value
    const cursorPos = input.selectionStart

    // Find the position of the last @ or #
    const textBeforeCursor = text.substring(0, cursorPos)
    const atMatch = textBeforeCursor.lastIndexOf("@")
    const hashMatch = textBeforeCursor.lastIndexOf("#")

    let symbolPos = Math.max(atMatch, hashMatch)

    if (symbolPos === -1) return

    // Get the mention text (e.g., "@john.doe" or "#project-alpha")
    const mentionText = type === "user" ? item.mention_text : item.reference_text

    // Find where to replace (from symbol to cursor or to next space)
    const spaceIndex = text.indexOf(" ", symbolPos)
    const replaceEnd = spaceIndex === -1 ? cursorPos : spaceIndex

    // Replace the text
    const newText = text.substring(0, symbolPos) + mentionText + " " + text.substring(replaceEnd)
    input.value = newText

    // Set cursor position after the mention
    const newCursorPos = symbolPos + mentionText.length + 1
    input.setSelectionRange(newCursorPos, newCursorPos)

    // Focus the input
    input.focus()

    // Hide suggestions
    this.hideSuggestions()

    // Trigger input event for any listeners
    input.dispatchEvent(new Event("input", { bubbles: true }))
  }

  highlightSuggestion(index) {
    if (this.suggestionsElement) {
      const items = this.suggestionsElement.querySelectorAll("[data-index]")
      items.forEach(item => {
        item.classList.remove("bg-gray-100")
      })
      if (items[index]) {
        items[index].classList.add("bg-gray-100")
      }
    }
    this.selectedIndex = index
  }

  handleKeyDown(event) {
    if (!this.suggestionsElement) return

    const items = this.suggestionsElement.querySelectorAll("[data-index]")
    if (items.length === 0) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.selectedIndex = Math.min(this.selectedIndex + 1, items.length - 1)
        this.highlightSuggestion(this.selectedIndex)
        break

      case "ArrowUp":
        event.preventDefault()
        this.selectedIndex = Math.max(this.selectedIndex - 1, -1)
        if (this.selectedIndex === -1) {
          this.inputTarget.focus()
        } else {
          this.highlightSuggestion(this.selectedIndex)
        }
        break

      case "Enter":
        if (this.selectedIndex !== -1) {
          event.preventDefault()
          const selectedItem = items[this.selectedIndex]
          selectedItem.click()
        }
        break

      case "Escape":
        event.preventDefault()
        this.hideSuggestions()
        break
    }
  }

  hideSuggestions() {
    if (this.suggestionsElement) {
      this.suggestionsElement.remove()
      this.suggestionsElement = null
    }
    this.selectedIndex = -1
    this.currentQuery = ""
    this.currentType = null
  }

  disconnect() {
    this.hideSuggestions()
  }
}
