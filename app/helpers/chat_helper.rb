# app/helpers/chat_helper.rb
#
# Helper methods for chat rendering including markdown support and message styling

require "redcarpet"
require "rouge"
require "rouge/plugins/redcarpet"

class ChatMarkdownRenderer < Redcarpet::Render::HTML
  include Rouge::Plugins::Redcarpet

  def initialize(options = {})
    super(
      filter_html: true,
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener noreferrer" },
      **options
    )
  end

  def block_code(code, language)
    lexer = language.present? ? Rouge::Lexer.find_by_name(language) : Rouge::Lexer.guess(code)
    lexer = Rouge::Lexers::PlainText.new if lexer.blank?

    formatter = Rouge::Formatters::HTML.new(css_class: "highlight")
    highlighted = formatter.format(lexer.lex(code))

    %(<div class="code-block" data-language="#{language}">#{highlighted}</div>)
  end

  def table(header, body)
    %(<table class="chat-table">#{header}#{body}</table>)
  end

  def table_head(content)
    %(<thead>#{content}</thead>)
  end

  def table_body(content)
    %(<tbody>#{content}</tbody>)
  end

  def table_row(content)
    %(<tr>#{content}</tr>)
  end

  def table_cell(content, options = {})
    tag_name = options[:header] ? "th" : "td"
    %(<#{tag_name}>#{content}</#{tag_name}>)
  end
end

module ChatHelper
  # Render markdown content with full syntax support
  def render_markdown(content)
    return "" if content.blank?

    markdown = Redcarpet::Markdown.new(
      ChatMarkdownRenderer.new(escape_html: true),
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      superscript: true,
      quote: true,
      footnotes: true,
      lax_spacing: true
    )

    sanitized_html = markdown.render(content)

    # Sanitize the HTML to prevent XSS while allowing markdown formatting
    sanitize(
      sanitized_html,
      tags: %w[
        p br h1 h2 h3 h4 h5 h6 strong em u code pre del sup sub
        ul ol li blockquote a img hr table thead tbody tr th td
        div span class
      ],
      attributes: {
        "a" => ["href", "target", "rel", "title"],
        "img" => ["src", "alt", "title"],
        "code" => ["class"],
        "pre" => ["class"],
        "div" => ["class", "data-language"],
        "span" => ["class"]
      }
    )
  end

  # Get CSS classes for message bubble based on role and location
  def message_bubble_classes(message)
    base = "max-w-xs lg:max-w-md px-4 py-2 rounded-lg"

    if message.user_message?
      "#{base} bg-blue-600 text-white"
    elsif message.assistant_message?
      "#{base} bg-gray-100 text-gray-900"
    elsif message.system_message?
      "#{base} bg-gray-200 text-gray-800 italic"
    else
      "#{base} bg-gray-100 text-gray-900"
    end
  end

  # Get icon for message role
  def message_role_icon(message)
    case message.role.to_sym
    when :user
      "👤"
    when :assistant
      "🤖"
    when :system
      "⚙️"
    when :tool
      "🔧"
    else
      "💬"
    end
  end

  # Format timestamp for message
  def message_timestamp(message)
    if message.created_at.today?
      message.created_at.strftime("%H:%M")
    else
      message.created_at.strftime("%b %d, %H:%M")
    end
  end

  # Check if message contains code blocks
  def has_code_blocks?(content)
    content.to_s.include?("```")
  end

  # Extract code from message
  def extract_code(content)
    regex = /```(?<lang>\w*)\n(?<code>.*?)\n```/m
    matches = content.scan(regex)
    matches.map { |lang, code| { language: lang || "plain", code: code } }
  end

  # Word count for message
  def message_word_count(content)
    content.to_s.split.length
  end

  # Check if message has attachments
  def has_attachments?(message)
    message.metadata["attachments"].present?
  end

  # Get attachment preview
  def attachment_preview(attachment)
    case attachment["type"]
    when "image"
      tag.img(src: attachment["url"], alt: attachment["name"], class: "max-w-xs rounded-lg")
    when "file"
      tag.a(attachment["name"], href: attachment["url"], class: "text-blue-600 hover:underline", download: true)
    else
      tag.span(attachment["name"], class: "text-gray-600")
    end
  end

  # Format feedback summary for a message
  def message_feedback_summary(feedbacks)
    return nil if feedbacks.blank?

    helpful = feedbacks.count { |f| f.rating == "helpful" }
    total = feedbacks.length

    "#{helpful}/#{total} found this helpful"
  end

  # Render message command suggestions
  def render_command_suggestions(suggestions)
    content_tag(:div, class: "space-y-2") do
      suggestions.map { |suggestion|
        content_tag(:button,
                    class: "block w-full text-left px-3 py-2 rounded-lg hover:bg-gray-100 transition-colors text-sm",
                    data: { action: "unified-chat#insertCommand", command: suggestion[:command] }) do
          concat content_tag(:span, suggestion[:command], class: "font-mono text-blue-600")
          concat " "
          concat suggestion[:description]
        end
      }.join.html_safe
    end
  end

  # Build HTML for code block with copy button
  def render_code_block(language, code)
    content_tag(:div, class: "code-block-container") do
      concat content_tag(:div, class: "code-block-header flex justify-between items-center bg-gray-900 text-white px-3 py-2 text-xs font-mono rounded-t") do
        concat content_tag(:span, language.presence || "code", class: "text-gray-400")
        concat content_tag(:button,
                          "Copy",
                          class: "btn btn-sm btn-ghost",
                          data: { action: "chat#copyCode", code: code })
      end

      concat content_tag(:div, class: "code-block-content bg-gray-800 text-gray-100 p-3 rounded-b overflow-x-auto") do
        concat content_tag(:pre, code, class: "text-xs font-mono")
      end
    end
  end
end
