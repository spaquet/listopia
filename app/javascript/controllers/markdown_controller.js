import { Controller } from "@hotwired/stimulus"
import { marked } from 'marked'
import hljs from 'highlight.js'

// Connects to data-controller="markdown"
export default class extends Controller {
  static targets = ["input", "preview"]
  static values = {
    debounce: { type: Number, default: 300 }
  }

  connect() {
    // Configure Marked.js instance for this controller
    this.configureMarked()
    this.debounceTimer = null
    
    // Render existing content
    if (this.hasPreviewTarget && !this.hasInputTarget) {
      this.renderMarkdown(this.previewTarget.textContent)
    }
    
    if (this.hasInputTarget && this.inputTarget.value) {
      this.render()
    }
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

  render() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }

    this.debounceTimer = setTimeout(() => {
      const markdown = this.inputTarget.value
      this.renderMarkdown(markdown)
    }, this.debounceValue)
  }

  renderMarkdown(markdown) {
    if (!this.hasPreviewTarget) return
    
    try {
      const html = marked.parse(markdown || '')
      this.previewTarget.innerHTML = html
      this.highlightAndStyle()
    } catch (error) {
      console.error('Markdown rendering error:', error)
      this.previewTarget.textContent = markdown
    }
  }

  highlightAndStyle() {
    // Highlight code blocks
    this.previewTarget.querySelectorAll('pre code').forEach((block) => {
      hljs.highlightElement(block)
    })
    
    // Apply Tailwind classes
    this.applyTailwindStyles()
  }

  applyTailwindStyles() {
    const content = this.previewTarget
    
    // Prose-like styling with Tailwind
    content.querySelectorAll('p').forEach(p => {
      p.classList.add('mb-4', 'text-gray-700', 'dark:text-gray-300', 'leading-relaxed')
    })
    
    content.querySelectorAll('h1').forEach(h => {
      h.classList.add('text-2xl', 'font-bold', 'mb-4', 'mt-6', 'text-gray-900', 'dark:text-gray-100')
    })
    
    content.querySelectorAll('h2').forEach(h => {
      h.classList.add('text-xl', 'font-bold', 'mb-3', 'mt-5', 'text-gray-900', 'dark:text-gray-100')
    })
    
    content.querySelectorAll('h3').forEach(h => {
      h.classList.add('text-lg', 'font-semibold', 'mb-2', 'mt-4', 'text-gray-800', 'dark:text-gray-200')
    })
    
    // Lists
    content.querySelectorAll('ul').forEach(ul => {
      ul.classList.add('list-disc', 'list-inside', 'mb-4', 'space-y-2', 'text-gray-700', 'dark:text-gray-300')
    })
    
    content.querySelectorAll('ol').forEach(ol => {
      ol.classList.add('list-decimal', 'list-inside', 'mb-4', 'space-y-2', 'text-gray-700', 'dark:text-gray-300')
    })
    
    content.querySelectorAll('li').forEach(li => {
      li.classList.add('ml-4')
    })
    
    // Links - matching your app's primary color
    content.querySelectorAll('a').forEach(a => {
      a.classList.add('text-blue-600', 'dark:text-blue-400', 'hover:text-blue-800', 'dark:hover:text-blue-300', 'underline', 'transition-colors')
      a.setAttribute('target', '_blank')
      a.setAttribute('rel', 'noopener noreferrer')
    })
    
    // Code blocks - modern dark theme
    content.querySelectorAll('pre').forEach(pre => {
      pre.classList.add(
        'rounded-lg', 
        'p-4', 
        'mb-4', 
        'overflow-x-auto',
        'bg-gray-900',
        'dark:bg-gray-950',
        'shadow-lg'
      )
    })
    
    content.querySelectorAll('pre code').forEach(code => {
      code.classList.add('text-sm', 'font-mono', 'text-gray-100')
    })
    
    // Inline code - subtle background
    content.querySelectorAll('code:not(pre code)').forEach(code => {
      code.classList.add(
        'bg-gray-100',
        'dark:bg-gray-800',
        'text-pink-600',
        'dark:text-pink-400',
        'px-1.5',
        'py-0.5',
        'rounded',
        'text-sm',
        'font-mono',
        'font-medium'
      )
    })
    
    // Blockquotes - elegant border
    content.querySelectorAll('blockquote').forEach(bq => {
      bq.classList.add(
        'border-l-4',
        'border-blue-500',
        'dark:border-blue-400',
        'pl-4',
        'py-2',
        'my-4',
        'italic',
        'text-gray-700',
        'dark:text-gray-400',
        'bg-gray-50',
        'dark:bg-gray-800/50',
        'rounded-r'
      )
    })
    
    // Tables - clean design
    content.querySelectorAll('table').forEach(table => {
      table.classList.add(
        'min-w-full',
        'divide-y',
        'divide-gray-200',
        'dark:divide-gray-700',
        'mb-4',
        'border',
        'border-gray-200',
        'dark:border-gray-700',
        'rounded-lg',
        'overflow-hidden'
      )
    })
    
    content.querySelectorAll('thead').forEach(thead => {
      thead.classList.add('bg-gray-50', 'dark:bg-gray-800')
    })
    
    content.querySelectorAll('th').forEach(th => {
      th.classList.add(
        'px-4',
        'py-3',
        'text-left',
        'text-xs',
        'font-semibold',
        'text-gray-700',
        'dark:text-gray-300',
        'uppercase',
        'tracking-wider'
      )
    })
    
    content.querySelectorAll('tbody').forEach(tbody => {
      tbody.classList.add('bg-white', 'dark:bg-gray-900', 'divide-y', 'divide-gray-200', 'dark:divide-gray-700')
    })
    
    content.querySelectorAll('td').forEach(td => {
      td.classList.add(
        'px-4',
        'py-3',
        'text-sm',
        'text-gray-700',
        'dark:text-gray-300'
      )
    })
    
    // Horizontal rules
    content.querySelectorAll('hr').forEach(hr => {
      hr.classList.add('my-6', 'border-gray-200', 'dark:border-gray-700')
    })
    
    // Strong/Bold
    content.querySelectorAll('strong').forEach(strong => {
      strong.classList.add('font-bold', 'text-gray-900', 'dark:text-gray-100')
    })
    
    // Emphasis/Italic
    content.querySelectorAll('em').forEach(em => {
      em.classList.add('italic', 'text-gray-800', 'dark:text-gray-200')
    })
  }

  disconnect() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
  }
}