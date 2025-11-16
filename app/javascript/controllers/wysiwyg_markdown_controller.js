import { Controller } from "@hotwired/stimulus"
import { marked } from 'marked'
import hljs from 'highlight.js'

// Connects to data-controller="wysiwyg-markdown"
export default class extends Controller {
  static targets = ['editor', 'input']
  static values = {
    debounce: { type: Number, default: 500 }
  }

  connect() {
    // Configure Marked.js for markdown parsing
    this.configureMarked()
    this.debounceTimer = null
    this.isUpdatingDOM = false

    // Create contenteditable editor
    this.createWYSIWYGEditor()
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

  createWYSIWYGEditor() {
    const container = this.editorTarget
    container.classList.add('w-full', 'px-4', 'py-3', 'border', 'border-gray-300', 'rounded-lg',
      'focus-within:ring-2', 'focus-within:ring-blue-500', 'focus-within:border-blue-500',
      'transition-all', 'min-h-64', 'overflow-auto')

    // Create contenteditable div
    const editor = document.createElement('div')
    editor.contentEditable = true
    editor.className = 'outline-none text-gray-900 leading-relaxed whitespace-pre-wrap break-words'
    editor.setAttribute('data-wysiwyg-target', 'content')

    // Set initial content (render markdown as HTML)
    const initialMarkdown = this.inputTarget.value || ''
    if (initialMarkdown) {
      try {
        const html = marked.parse(initialMarkdown)
        editor.innerHTML = html
      } catch (e) {
        editor.textContent = initialMarkdown
      }
    } else {
      editor.innerHTML = '<p><br></p>'
    }

    container.appendChild(editor)

    // Handle input and sync to hidden field
    editor.addEventListener('input', (e) => {
      this.syncToHiddenInput(editor)
    })

    // Handle paste events to convert markdown to HTML
    editor.addEventListener('paste', (e) => {
      e.preventDefault()
      const text = e.clipboardData.getData('text/plain')
      try {
        const html = marked.parse(text)
        document.execCommand('insertHTML', false, html)
      } catch (error) {
        document.execCommand('insertText', false, text)
      }
    })

    // Apply styling
    this.applyEditorStyles(editor)
  }

  syncToHiddenInput(editor) {
    if (this.isUpdatingDOM) return

    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }

    this.debounceTimer = setTimeout(() => {
      // Convert HTML back to markdown for storage
      const html = editor.innerHTML
      const markdown = this.htmlToMarkdown(html)
      this.inputTarget.value = markdown

      // Apply/refresh styling
      this.applyEditorStyles(editor)
    }, this.debounceValue)
  }

  htmlToMarkdown(html) {
    const temp = document.createElement('div')
    temp.innerHTML = html

    let markdown = ''
    const processNode = (node) => {
      if (node.nodeType === 3) { // Text node
        return node.textContent
      }

      if (node.nodeType !== 1) return '' // Not an element

      const tag = node.tagName.toLowerCase()
      let content = Array.from(node.childNodes).map(processNode).join('')

      switch (tag) {
        case 'h1':
          return `# ${content}\n\n`
        case 'h2':
          return `## ${content}\n\n`
        case 'h3':
          return `### ${content}\n\n`
        case 'p':
          return content + '\n\n'
        case 'strong':
          return `**${content}**`
        case 'em':
          return `*${content}*`
        case 'code':
          return `\`${content}\``
        case 'pre':
          return `\`\`\`\n${content}\n\`\`\`\n\n`
        case 'blockquote':
          return `> ${content}\n\n`
        case 'ul':
        case 'ol':
          return content
        case 'li':
          const bullet = node.parentElement.tagName === 'UL' ? '- ' : '1. '
          return bullet + content + '\n'
        case 'br':
          return '\n'
        case 'hr':
          return '---\n\n'
        default:
          return content
      }
    }

    Array.from(temp.childNodes).forEach(node => {
      markdown += processNode(node)
    })

    return markdown.trim()
  }

  applyEditorStyles(editor) {
    this.isUpdatingDOM = true

    // Apply Tailwind classes to elements
    const styleHeading = (selector, classes) => {
      editor.querySelectorAll(selector).forEach(el => {
        el.className = ''
        el.classList.add(...classes)
      })
    }

    styleHeading('h1', ['text-2xl', 'font-bold', 'mb-4', 'mt-6', 'text-gray-900'])
    styleHeading('h2', ['text-xl', 'font-bold', 'mb-3', 'mt-5', 'text-gray-900'])
    styleHeading('h3', ['text-lg', 'font-semibold', 'mb-2', 'mt-4', 'text-gray-800'])
    styleHeading('p', ['mb-3', 'text-gray-900', 'leading-relaxed'])
    styleHeading('strong', ['font-bold', 'text-gray-900'])
    styleHeading('em', ['italic', 'text-gray-800'])

    editor.querySelectorAll('code:not(pre code)').forEach(el => {
      el.className = ''
      el.classList.add('bg-gray-100', 'text-pink-600', 'px-1', 'py-0.5', 'rounded', 'text-xs', 'font-mono')
    })

    editor.querySelectorAll('pre').forEach(el => {
      el.className = ''
      el.classList.add('rounded-lg', 'p-4', 'mb-4', 'overflow-x-auto', 'bg-gray-900', 'shadow-lg')
    })

    editor.querySelectorAll('pre code').forEach(el => {
      el.className = ''
      el.classList.add('text-sm', 'font-mono', 'text-gray-100')
    })

    editor.querySelectorAll('blockquote').forEach(el => {
      el.className = ''
      el.classList.add('border-l-4', 'border-blue-500', 'pl-4', 'py-2', 'my-4', 'italic', 'text-gray-900', 'bg-gray-50', 'rounded-r')
    })

    editor.querySelectorAll('ul, ol').forEach(el => {
      el.className = ''
      el.classList.add('list-inside', 'mb-4', 'space-y-2', 'text-gray-900')
      if (el.tagName === 'UL') {
        el.classList.add('list-disc')
      } else {
        el.classList.add('list-decimal')
      }
    })

    editor.querySelectorAll('li').forEach(el => {
      el.className = ''
      el.classList.add('ml-4', 'text-gray-900')
    })

    editor.querySelectorAll('a').forEach(el => {
      el.className = ''
      el.classList.add('text-blue-600', 'hover:text-blue-800', 'underline', 'transition-colors')
      el.setAttribute('target', '_blank')
      el.setAttribute('rel', 'noopener noreferrer')
    })

    this.isUpdatingDOM = false
  }

  disconnect() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
  }
}
