# app/services/item_generation_service.rb
#
# Generic, intelligent item generation service
# Works with ANY type of list (roadshow, vacation, learning, project, etc.)
# and ANY type of subdivision (locations, phases, weeks, chapters, etc.)
#
# Rather than hardcoded rules for specific cases, this service uses
# a sophisticated LLM to understand the context and generate appropriate items.
#
# Usage:
#   ItemGenerationService.new(
#     list_title: "Plan US Roadshow",
#     description: "Budget: $500k | Timeline: June-Sept",
#     category: "professional",
#     planning_context: { locations: [...], budget: "...", timeline: "..." },
#     sublist_title: "New York"  # Optional - if generating for a sublist
#   ).call

class ItemGenerationService < ApplicationService
  def initialize(
    list_title:,
    description: "",
    category: "professional",
    planning_context: {},
    sublist_title: nil
  )
    @list_title = list_title
    @description = description
    @category = category
    @planning_context = planning_context
    @sublist_title = sublist_title
  end

  def call
    begin
      Rails.logger.info("ItemGenerationService - Generating items for: #{@list_title}")
      Rails.logger.info("ItemGenerationService - Sublist: #{@sublist_title}") if @sublist_title.present?

      items = generate_items_with_llm

      # Convert string items to proper format
      formatted_items = format_items(items)

      Rails.logger.info("ItemGenerationService - Generated #{formatted_items.length} items")
      success(data: formatted_items)
    rescue => e
      Rails.logger.error("ItemGenerationService - Generation failed: #{e.message}")
      Rails.logger.error(e.backtrace.take(5).join("\n"))
      # Graceful fallback - return empty array instead of crashing
      success(data: [])
    end
  end

  private

  def generate_items_with_llm
    prompt = build_intelligent_prompt
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-5.4-2026-03-05")

    llm_chat.add_message(role: "system", content: prompt)
    llm_chat.add_message(
      role: "user",
      content: "Generate specific, actionable items for this planning context."
    )

    response = llm_chat.complete
    response_text = extract_response_content(response)

    # Extract JSON array from response
    json_match = response_text.match(/\[[\s\S]*\]/m)
    return [] unless json_match

    begin
      JSON.parse(json_match[0])
    rescue JSON::ParserError => e
      Rails.logger.error("ItemGenerationService - JSON parse error: #{e.message}")
      Rails.logger.error("Response was: #{response_text[0..500]}")
      []
    end
  end

  def build_intelligent_prompt
    <<~PROMPT
      You are an intelligent planning assistant with expertise in breaking down complex tasks.
      Analyze the planning request and generate 5-8 specific, actionable items.

      ==== PLANNING REQUEST ====
      Title: "#{@list_title}"
      Category: #{@category}
      #{@description.present? ? "Description: #{@description}" : ""}

      #{if @sublist_title.present?
        "Focus: Generate items SPECIFICALLY for: #{@sublist_title}"
        else
        "Focus: Generate items for the overall plan"
        end}

      ==== PLANNING CONTEXT ====
      #{format_planning_context}

      ==== YOUR TASK ====
      1. Understand the DOMAIN of this planning (event, travel, learning, project, business, etc.)
         - Analyze the title and description to determine the actual domain
         - Consider what kinds of items make sense for this domain

      2. Generate items that are SPECIFIC and APPROPRIATE
         #{if @sublist_title.present?
           "- These items should be unique to #{@sublist_title}, not generic duplicates"
           else
           "- Items should be relevant to the overall planning context"
           end}
         - Each item should be actionable and concrete
         - Items should reflect actual work that needs to be done
         - Consider constraints, timeline, budget, locations, phases, etc.

      3. Avoid generic or placeholder items
         - Do NOT just repeat base items
         - Do NOT create lists like "Task 1", "Task 2", "Task 3"
         - Be SPECIFIC to this context

      4. Consider what's different about this item/subdivision
         #{if @sublist_title.present?
           "- If this is a location: what local logistics, vendors, regulations are needed?"
           elsif @planning_context["phases"].present?
           "- If this is a phase: what's unique to this phase vs others?"
           else
           "- What makes each item distinct and necessary?"
           end}

      ==== RESPONSE FORMAT (REQUIRED) ====
      Respond with ONLY a valid JSON array. Each item MUST have:
      - title: Specific, action-oriented task (1-10 words)
      - description: Detailed explanation of what to do and why (1-3 sentences)
      - type: "task" | "milestone" | "reminder" | "note"
      - priority: "high" | "medium" | "low"

      Example:
      [
        {
          "title": "Specific action for #{@sublist_title || @list_title}",
          "description": "Detailed explanation of what needs to be done, considering the context.",
          "type": "task",
          "priority": "high"
        },
        {
          "title": "Another specific action",
          "description": "Why this matters and how to approach it.",
          "type": "task",
          "priority": "medium"
        }
      ]

      CRITICAL: Return ONLY the JSON array. No markdown, no text before or after.
    PROMPT
  end

  def format_planning_context
    return "(No planning context provided)" if @planning_context.blank?

    context_lines = []

    @planning_context.each do |key, value|
      next if value.blank?

      case key
      when "locations"
        context_lines << "- Locations: #{Array(value).join(", ")}"
      when "budget"
        context_lines << "- Budget: #{value}"
      when "duration", "timeline"
        context_lines << "- Timeline: #{value}"
      when "start_date"
        context_lines << "- Start Date: #{value}"
      when "team_size"
        context_lines << "- Team Size: #{value}"
      when "phases"
        context_lines << "- Phases: #{Array(value).join(", ")}"
      when "preferences"
        context_lines << "- Preferences: #{value}"
      when "other_details"
        context_lines << "- Additional Details: #{value}"
      else
        context_lines << "- #{key.humanize}: #{value}"
      end
    end

    context_lines.join("\n")
  end

  def format_items(items)
    # Items can come in as strings or hashes
    # Convert to consistent hash format
    Array(items).map do |item|
      if item.is_a?(Hash)
        {
          title: item["title"] || item[:title] || "Task",
          description: item["description"] || item[:description] || "",
          type: item["type"] || item[:type] || "task",
          priority: item["priority"] || item[:priority] || "medium"
        }
      elsif item.is_a?(String)
        {
          title: item.strip,
          description: "",
          type: "task",
          priority: "medium"
        }
      end
    end.compact
  end

  def extract_response_content(response)
    case response
    when String
      response
    when Hash
      response["content"] || response[:content] || response.to_s
    else
      if response.respond_to?(:content)
        content = response.content
        if content.respond_to?(:text)
          content.text
        else
          content
        end
      elsif response.respond_to?(:message)
        response.message
      elsif response.respond_to?(:text)
        response.text
      else
        response.to_s
      end
    end
  end
end
