// app/javascript/controllers/markdown_message_controller.js

import { Controller } from "@hotwired/stimulus"
import { marked } from 'marked'
import hljs from 'highlight.js'

// Connects to data-controller="markdown-message"
export default class extends Controller {
  static targets = ["content"]

  connect() {
    this.configureMarked()
    this.renderContent()
  }

  configureMarked() {
    marked.setOptions({
      highlight: (code, lang) => {
        const language = hljs.getLanguage(lang) ? lang : 'plaintext'
        return hljs.highlight(code, { language }).value
      },
      breaks: true,
      gfm: true,
      headerIds: false,
      mangle: false
    })
  }

  renderContent() {
    if (!this.hasContentTarget) return
    
    const markdown = this.contentTarget.dataset.markdown || this.contentTarget.textContent
    
    try {
      const html = marked.parse(markdown)
      this.contentTarget.innerHTML = html
      
      this.contentTarget.querySelectorAll('pre code').forEach((block) => {
        hljs.highlightElement(block)
      })
      
      this.applyTailwindStyles()
    } catch (error) {
      console.error('Markdown rendering error:', error)
    }
  }

  applyTailwindStyles() {
    const content = this.contentTarget
    
    // Check if this is a user message (blue background) or assistant message (gray background)
    const isUserMessage = content.closest('.bg-blue-600') !== null
    
    // Use darker colors for better contrast on gray-100 background
    const textColor = isUserMessage ? 'text-white' : 'text-gray-900'
    const mutedColor = isUserMessage ? 'text-blue-100' : 'text-gray-700'
    
    content.querySelectorAll('p').forEach(p => {
      p.classList.add('mb-3', textColor, 'leading-relaxed')
    })
    
    content.querySelectorAll('h1').forEach(h => {
      h.classList.add('text-2xl', 'font-bold', 'mb-4', 'mt-6', textColor)
    })
    
    content.querySelectorAll('h2').forEach(h => {
      h.classList.add('text-xl', 'font-bold', 'mb-3', 'mt-5', textColor)
    })
    
    content.querySelectorAll('h3').forEach(h => {
      h.classList.add('text-lg', 'font-semibold', 'mb-2', 'mt-4', textColor)
    })
    
    content.querySelectorAll('ul').forEach(ul => {
      ul.classList.add('list-disc', 'list-inside', 'mb-3', 'space-y-1', textColor)
    })
    
    content.querySelectorAll('ol').forEach(ol => {
      ol.classList.add('list-decimal', 'list-inside', 'mb-3', 'space-y-1', textColor)
    })
    
    content.querySelectorAll('li').forEach(li => {
      li.classList.add('ml-4')
    })
    
    // Links - different colors based on background
    content.querySelectorAll('a').forEach(a => {
      if (isUserMessage) {
        a.classList.add('text-blue-100', 'hover:text-white', 'underline', 'transition-colors', 'font-medium')
      } else {
        a.classList.add('text-blue-700', 'hover:text-blue-900', 'underline', 'transition-colors', 'font-medium')
      }
      a.setAttribute('target', '_blank')
      a.setAttribute('rel', 'noopener noreferrer')
    })
    
    // Code blocks - darker background for contrast
    content.querySelectorAll('pre').forEach(pre => {
      pre.classList.add('rounded-lg', 'p-4', 'mb-3', 'overflow-x-auto', 'bg-gray-900', 'shadow-md')
    })
    
    content.querySelectorAll('pre code').forEach(code => {
      code.classList.add('text-sm', 'font-mono', 'text-gray-100')
    })
    
    // Inline code - higher contrast
    content.querySelectorAll('code:not(pre code)').forEach(code => {
      if (isUserMessage) {
        code.classList.add('bg-blue-700', 'text-blue-100', 'px-1.5', 'py-0.5', 'rounded', 'text-sm', 'font-mono', 'font-medium')
      } else {
        code.classList.add('bg-gray-800', 'text-gray-100', 'px-1.5', 'py-0.5', 'rounded', 'text-sm', 'font-mono', 'font-medium')
      }
    })
    
    // Blockquotes
    content.querySelectorAll('blockquote').forEach(bq => {
      if (isUserMessage) {
        bq.classList.add('border-l-4', 'border-blue-300', 'pl-4', 'py-2', 'my-3', 'italic', 'text-blue-100', 'bg-blue-700/30', 'rounded-r')
      } else {
        bq.classList.add('border-l-4', 'border-blue-600', 'pl-4', 'py-2', 'my-3', 'italic', 'text-gray-800', 'bg-blue-50', 'rounded-r')
      }
    })
    
    // Tables
    content.querySelectorAll('table').forEach(table => {
      table.classList.add('min-w-full', 'divide-y', 'divide-gray-300', 'mb-3', 'border', 'border-gray-300', 'rounded-lg', 'overflow-hidden', 'text-sm')
    })
    
    content.querySelectorAll('thead').forEach(thead => {
      thead.classList.add(isUserMessage ? 'bg-blue-700' : 'bg-gray-200')
    })
    
    content.querySelectorAll('th').forEach(th => {
      th.classList.add('px-4', 'py-2', 'text-left', 'text-xs', 'font-semibold', isUserMessage ? 'text-white' : 'text-gray-900', 'uppercase', 'tracking-wider')
    })
    
    content.querySelectorAll('tbody').forEach(tbody => {
      tbody.classList.add(isUserMessage ? 'bg-blue-600' : 'bg-white', 'divide-y', 'divide-gray-200')
    })
    
    content.querySelectorAll('td').forEach(td => {
      td.classList.add('px-4', 'py-2', 'text-sm', textColor)
    })
    
    // Horizontal rules
    content.querySelectorAll('hr').forEach(hr => {
      hr.classList.add('my-4', isUserMessage ? 'border-blue-400' : 'border-gray-300')
    })
    
    // Strong/Bold - darker for emphasis
    content.querySelectorAll('strong').forEach(strong => {
      strong.classList.add('font-bold', isUserMessage ? 'text-white' : 'text-gray-950')
    })
    
    // Emphasis/Italic
    content.querySelectorAll('em').forEach(em => {
      em.classList.add('italic', mutedColor)
    })
  }
}