import { Schema } from 'prosemirror-model'

// Use the default markdown schema that prosemirror-markdown expects
export const schema = new Schema({
  nodes: {
    doc: {
      content: 'block+'
    },
    paragraph: {
      content: 'inline*',
      group: 'block',
      parseDOM: [{ tag: 'p' }],
      toDOM: () => ['p', 0]
    },
    blockquote: {
      content: 'block+',
      group: 'block',
      parseDOM: [{ tag: 'blockquote' }],
      toDOM: () => ['blockquote', 0]
    },
    bullet_list: {
      content: 'list_item+',
      group: 'block',
      parseDOM: [{ tag: 'ul' }],
      toDOM: () => ['ul', 0]
    },
    ordered_list: {
      content: 'list_item+',
      group: 'block',
      parseDOM: [{ tag: 'ol', getAttrs: (dom) => ({ order: dom.hasAttribute('start') ? +dom.getAttribute('start') : 1 }) }],
      toDOM: (node) => (node.attrs.order === 1 ? ['ol', 0] : ['ol', { start: node.attrs.order }, 0]),
      attrs: { order: { default: 1 } }
    },
    list_item: {
      content: 'paragraph block*',
      parseDOM: [{ tag: 'li' }],
      toDOM: () => ['li', 0],
      defining: true
    },
    heading: {
      attrs: { level: { default: 1 } },
      content: 'inline*',
      group: 'block',
      parseDOM: [
        { tag: 'h1', attrs: { level: 1 } },
        { tag: 'h2', attrs: { level: 2 } },
        { tag: 'h3', attrs: { level: 3 } },
        { tag: 'h4', attrs: { level: 4 } },
        { tag: 'h5', attrs: { level: 5 } },
        { tag: 'h6', attrs: { level: 6 } }
      ],
      toDOM: (node) => [`h${node.attrs.level}`, 0]
    },
    code_block: {
      content: 'text*',
      group: 'block',
      code: true,
      parseDOM: [{ tag: 'pre', preserveWhitespace: 'full' }],
      toDOM: () => ['pre', ['code', 0]]
    },
    horizontal_rule: {
      group: 'block',
      parseDOM: [{ tag: 'hr' }],
      toDOM: () => ['hr']
    },
    text: {
      group: 'inline'
    },
    image: {
      inline: true,
      attrs: {
        src: {},
        alt: { default: '' },
        title: { default: '' }
      },
      group: 'inline',
      draggable: true,
      parseDOM: [
        {
          tag: 'img[src]',
          getAttrs: (dom) => ({
            src: dom.getAttribute('src'),
            alt: dom.getAttribute('alt'),
            title: dom.getAttribute('title')
          })
        }
      ],
      toDOM: (node) => ['img', node.attrs]
    },
    hard_break: {
      inline: true,
      group: 'inline',
      selectable: false,
      parseDOM: [{ tag: 'br' }],
      toDOM: () => ['br']
    }
  },
  marks: {
    em: {
      parseDOM: [{ tag: 'i' }, { tag: 'em' }, { style: 'font-style=italic' }],
      toDOM: () => ['em', 0]
    },
    strong: {
      parseDOM: [
        { tag: 'strong' },
        { tag: 'b' },
        { style: 'font-weight', getAttrs: (value) => /^(bold|[5-9]\d{2,})$/.test(value) && null }
      ],
      toDOM: () => ['strong', 0]
    },
    code: {
      parseDOM: [{ tag: 'code' }],
      toDOM: () => ['code', 0]
    },
    link: {
      attrs: {
        href: {},
        title: { default: '' }
      },
      inclusive: false,
      parseDOM: [
        {
          tag: 'a[href]',
          getAttrs: (dom) => ({
            href: dom.getAttribute('href'),
            title: dom.getAttribute('title')
          })
        }
      ],
      toDOM: (node) => ['a', node.attrs, 0]
    }
  }
})
