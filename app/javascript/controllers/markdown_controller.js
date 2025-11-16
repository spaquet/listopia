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
    if (this.hasPreviewTarget) {
      if (this.hasInputTarget && this.inputTarget.value) {
        // If input field exists, render from input
        this.render()
      } else if (!this.hasInputTarget) {
        // If only preview exists (show view), render its content as markdown
        const content = this.previewTarget.textContent.trim()
        if (content && content !== 'Preview appears here...') {
          this.renderMarkdown(content)
        }
      }
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

    // Determine if this is the edit preview or show view based on parent context
    const isEditPreview = this.element.querySelector('[data-markdown-target="input"]') !== null

    // Prose-like styling with Tailwind
    // Use different sizing for edit preview vs show view
    const pClasses = isEditPreview
      ? ['mb-3', 'text-gray-900', 'dark:text-gray-200', 'leading-relaxed', 'text-sm']
      : ['mb-4', 'text-gray-900', 'leading-relaxed']

    content.querySelectorAll('p').forEach(p => {
      p.classList.add(...pClasses)
    })

    // Different heading sizes for edit preview vs show view
    const h1Classes = isEditPreview
      ? ['text-lg', 'font-bold', 'mb-3', 'mt-4', 'text-gray-900', 'dark:text-gray-100']
      : ['text-2xl', 'font-bold', 'mb-4', 'mt-6', 'text-gray-900']

    const h2Classes = isEditPreview
      ? ['text-base', 'font-bold', 'mb-2', 'mt-3', 'text-gray-900', 'dark:text-gray-100']
      : ['text-xl', 'font-bold', 'mb-3', 'mt-5', 'text-gray-900']

    const h3Classes = isEditPreview
      ? ['text-sm', 'font-semibold', 'mb-2', 'mt-3', 'text-gray-800', 'dark:text-gray-200']
      : ['text-lg', 'font-semibold', 'mb-2', 'mt-4', 'text-gray-800']

    content.querySelectorAll('h1').forEach(h => {
      h.classList.add(...h1Classes)
    })

    content.querySelectorAll('h2').forEach(h => {
      h.classList.add(...h2Classes)
    })

    content.querySelectorAll('h3').forEach(h => {
      h.classList.add(...h3Classes)
    })
    
    // Lists - different spacing for edit preview vs show view
    const ulClasses = isEditPreview
      ? ['list-disc', 'list-inside', 'mb-3', 'space-y-1', 'text-gray-900', 'dark:text-gray-200', 'text-sm']
      : ['list-disc', 'list-inside', 'mb-4', 'space-y-2', 'text-gray-900']

    const olClasses = isEditPreview
      ? ['list-decimal', 'list-inside', 'mb-3', 'space-y-1', 'text-gray-900', 'dark:text-gray-200', 'text-sm']
      : ['list-decimal', 'list-inside', 'mb-4', 'space-y-2', 'text-gray-900']

    const liClasses = isEditPreview
      ? ['ml-2', 'text-sm']
      : ['ml-4']

    content.querySelectorAll('ul').forEach(ul => {
      ul.classList.add(...ulClasses)
    })

    content.querySelectorAll('ol').forEach(ol => {
      ol.classList.add(...olClasses)
    })

    content.querySelectorAll('li').forEach(li => {
      li.classList.add(...liClasses)
    })
    
    // Links - matching your app's primary color
    content.querySelectorAll('a').forEach(a => {
      a.classList.add('text-blue-600', 'dark:text-blue-400', 'hover:text-blue-800', 'dark:hover:text-blue-300', 'underline', 'transition-colors')
      a.setAttribute('target', '_blank')
      a.setAttribute('rel', 'noopener noreferrer')
    })
    
    // Code blocks - modern dark theme
    const preClasses = isEditPreview
      ? ['rounded-lg', 'p-3', 'mb-3', 'overflow-x-auto', 'bg-gray-900', 'dark:bg-gray-950', 'shadow-lg']
      : ['rounded-lg', 'p-4', 'mb-4', 'overflow-x-auto', 'bg-gray-900', 'dark:bg-gray-950', 'shadow-lg']

    const codeInPreClasses = isEditPreview
      ? ['text-xs', 'font-mono', 'text-gray-100']
      : ['text-sm', 'font-mono', 'text-gray-100']

    content.querySelectorAll('pre').forEach(pre => {
      pre.classList.add(...preClasses)
    })

    content.querySelectorAll('pre code').forEach(code => {
      code.classList.add(...codeInPreClasses)
    })

    // Inline code - subtle background
    content.querySelectorAll('code:not(pre code)').forEach(code => {
      code.classList.add(
        'bg-gray-100',
        'dark:bg-gray-800',
        'text-pink-600',
        'dark:text-pink-400',
        'px-1',
        'py-0.5',
        'rounded',
        'text-xs',
        'font-mono',
        'font-medium'
      )
    })
    
    // Blockquotes - elegant border
    const blockquoteClasses = isEditPreview
      ? ['border-l-4', 'border-blue-500', 'dark:border-blue-400', 'pl-3', 'py-2', 'my-3', 'italic', 'text-gray-900', 'dark:text-gray-200', 'bg-gray-50', 'dark:bg-gray-800/50', 'rounded-r', 'text-sm']
      : ['border-l-4', 'border-blue-500', 'pl-4', 'py-2', 'my-4', 'italic', 'text-gray-900', 'bg-gray-50', 'rounded-r']

    content.querySelectorAll('blockquote').forEach(bq => {
      bq.classList.add(...blockquoteClasses)
    })

    // Tables - clean design with context-aware sizing
    const tableClasses = isEditPreview
      ? ['min-w-full', 'divide-y', 'divide-gray-200', 'dark:divide-gray-700', 'mb-3', 'border', 'border-gray-200', 'dark:border-gray-700', 'rounded-lg', 'overflow-hidden', 'text-sm']
      : ['min-w-full', 'divide-y', 'divide-gray-200', 'mb-4', 'border', 'border-gray-200', 'rounded-lg', 'overflow-hidden']

    const thClasses = isEditPreview
      ? ['px-3', 'py-2', 'text-left', 'text-xs', 'font-semibold', 'text-gray-900', 'dark:text-gray-200', 'uppercase', 'tracking-wider']
      : ['px-4', 'py-3', 'text-left', 'text-xs', 'font-semibold', 'text-gray-900', 'uppercase', 'tracking-wider']

    const tdClasses = isEditPreview
      ? ['px-3', 'py-2', 'text-xs', 'text-gray-900', 'dark:text-gray-200']
      : ['px-4', 'py-3', 'text-sm', 'text-gray-900']

    content.querySelectorAll('table').forEach(table => {
      table.classList.add(...tableClasses)
    })

    content.querySelectorAll('thead').forEach(thead => {
      if (isEditPreview) {
        thead.classList.add('bg-gray-50', 'dark:bg-gray-800')
      } else {
        thead.classList.add('bg-gray-50')
      }
    })

    content.querySelectorAll('th').forEach(th => {
      th.classList.add(...thClasses)
    })

    content.querySelectorAll('tbody').forEach(tbody => {
      if (isEditPreview) {
        tbody.classList.add('bg-white', 'dark:bg-gray-900', 'divide-y', 'divide-gray-200', 'dark:divide-gray-700')
      } else {
        tbody.classList.add('bg-white', 'divide-y', 'divide-gray-200')
      }
    })

    content.querySelectorAll('td').forEach(td => {
      td.classList.add(...tdClasses)
    })
    
    // Horizontal rules
    const hrClasses = isEditPreview
      ? ['my-3', 'border-gray-200', 'dark:border-gray-700']
      : ['my-6', 'border-gray-200', 'dark:border-gray-700']

    content.querySelectorAll('hr').forEach(hr => {
      hr.classList.add(...hrClasses)
    })

    // Strong/Bold - only add dark mode for edit preview
    content.querySelectorAll('strong').forEach(strong => {
      if (isEditPreview) {
        strong.classList.add('font-bold', 'text-gray-900', 'dark:text-gray-100')
      } else {
        strong.classList.add('font-bold', 'text-gray-900')
      }
    })

    // Emphasis/Italic - only add dark mode for edit preview
    content.querySelectorAll('em').forEach(em => {
      if (isEditPreview) {
        em.classList.add('italic', 'text-gray-800', 'dark:text-gray-200')
      } else {
        em.classList.add('italic', 'text-gray-800')
      }
    })
  }

  disconnect() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
  }
}