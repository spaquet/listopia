import { Controller } from "@hotwired/stimulus"

/**
 * ChatNavigationController handles navigation triggered by chat messages.
 * When the LLM suggests navigating to a page, this controller detects
 * the navigation message and redirects the user appropriately.
 */
export default class extends Controller {
  static targets = ["messagesContainer"]
  static values = { chatId: String }

  connect() {
    // Observe messages container for new navigation messages
    this.observeNewMessages()
  }

  /**
   * Observe for new messages added to the chat
   */
  observeNewMessages() {
    // Use MutationObserver to detect new message elements
    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.addedNodes.length > 0) {
          mutation.addedNodes.forEach((node) => {
            if (node.nodeType === Node.ELEMENT_NODE) {
              this.checkForNavigationMessage(node)
            }
          })
        }
      })
    })

    if (this.hasMessagesContainerTarget) {
      observer.observe(this.messagesContainerTarget, {
        childList: true,
        subtree: true
      })
    }
  }

  /**
   * Check if the message is a navigation message and handle it
   */
  checkForNavigationMessage(element) {
    // Look for navigation marker
    const navigationData = element.querySelector('[data-chat-navigation]')
    if (navigationData) {
      const navigation = JSON.parse(navigationData.dataset.chatNavigation)
      this.navigate(navigation)
    }

    // Look for tool result marker
    const toolResult = element.querySelector('[data-tool-result]')
    if (toolResult) {
      const result = JSON.parse(toolResult.dataset.toolResult)
      this.handleToolResult(result)
    }
  }

  /**
   * Navigate to the specified path
   */
  navigate(navigation) {
    const { path, filters = {} } = navigation

    // Build URL with optional filters
    let url = path
    const params = new URLSearchParams()

    // Add filters to query params if present
    if (Object.keys(filters).length > 0) {
      Object.entries(filters).forEach(([key, value]) => {
        if (value) params.append(key, value)
      })

      const queryString = params.toString()
      url = queryString ? `${path}?${queryString}` : path
    }

    // Navigate using Turbo for smooth transitions
    Turbo.visit(url, { action: "replace" })
  }

  /**
   * Handle tool result display
   */
  handleToolResult(result) {
    const { type, total_count, resource_type } = result

    switch (type) {
      case "navigation":
        // Already handled by navigate()
        break
      case "list":
        this.showListResult(result)
        break
      case "search_results":
        this.showSearchResults(result)
        break
      case "resource":
        this.showResourceResult(result)
        break
    }
  }

  /**
   * Show list results in a friendly format
   */
  showListResult(result) {
    const { total_count, resource_type } = result
    // Message is already shown in the chat, just log for debugging
    console.log(`Displaying ${total_count} ${resource_type.toLowerCase()} records`)
  }

  /**
   * Show search results
   */
  showSearchResults(result) {
    const { query, total_count } = result
    console.log(`Search for "${query}" returned ${total_count} results`)
  }

  /**
   * Show resource creation/update result
   */
  showResourceResult(result) {
    const { action, resource_type } = result
    console.log(`Successfully ${action} ${resource_type}`)
  }
}
