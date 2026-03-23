# app/models/message_template.rb
#
# MessageTemplate registry and base class for rendering different message types
# Supports extensible template system for rich message rendering

class MessageTemplate
  # Registry of all available templates (only actively used templates)
  REGISTRY = {
    # Search & discovery
    "search_results" => "SearchResultsTemplate",
    "browse_results" => "BrowseResultsTemplate",

    # Navigation & routing
    "navigation" => "NavigationTemplate",

    # Resource operations (user/team/list creation/update)
    "resource" => "ResourceTemplate",

    # List planning
    "pre_creation_planning" => "PreCreationPlanningTemplate",
    "context_reuse_options" => "ContextReuseOptionsTemplate",

    # General conversation
    "clarifying_questions" => "ClarifyingQuestionsTemplate",

    # System messages
    "rag_sources" => "RAGSourcesTemplate",
    "error" => "ErrorTemplate",
    "help" => "HelpTemplate",
    "new_chat_confirmation" => "NewChatConfirmationTemplate"
  }.freeze

  # Get template class by type
  def self.find(template_type)
    class_name = REGISTRY[template_type]
    return nil unless class_name

    "#{class_name}".constantize
  end

  # Check if template exists
  def self.exists?(template_type)
    REGISTRY.key?(template_type)
  end

  # List all available templates
  def self.available
    REGISTRY.keys
  end

  # Validate template data structure
  def self.validate_data(template_type, data)
    template_class = find(template_type)
    return false unless template_class

    template_class.validate_data(data)
  end
end

# Base template class that all templates should inherit from
class BaseTemplate
  attr_reader :data

  def initialize(data)
    @data = data
  end

  # Override in subclasses
  def self.validate_data(data)
    true
  end

  # Helper to safely access nested data
  protected

  def dig_data(*keys)
    data.dig(*keys)
  end

  def data_present?(*keys)
    dig_data(*keys).present?
  end
end

# Template for search results
class SearchResultsTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["results"].is_a?(Array)
  end

  def render_data
    {
      query: dig_data("query"),
      results: dig_data("results"),
      total_count: dig_data("total_count") || dig_data("results").length,
      search_type: dig_data("search_type") || "all"
    }
  end
end

# Template for RAG sources
class RAGSourcesTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Array) || (data.is_a?(Hash) && data["sources"].is_a?(Array))
  end

  def render_data
    sources = data.is_a?(Array) ? data : dig_data("sources")
    { sources: sources }
  end
end

# Template for error messages
class ErrorTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["message"].present?
  end

  def render_data
    {
      message: dig_data("message"),
      error_code: dig_data("error_code"),
      details: dig_data("details")
    }
  end
end

# Template for help command
class HelpTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["commands"].is_a?(Array) && data["features"].is_a?(Array)
  end

  def render_data
    {
      commands: dig_data("commands"),
      features: dig_data("features")
    }
  end
end

# Chat system templates

# Template for navigation messages (directing user to pages)
class NavigationTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["navigation"].is_a?(Hash) && data["navigation"]["path"].present?
  end

  def render_data
    {
      navigation: dig_data("navigation"),
      path: dig_data("navigation", "path"),
      filters: dig_data("navigation", "filters") || {}
    }
  end
end

# Template for resource creation/update results
class ResourceTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["resource_type"].present? && data["action"].present?
  end

  def render_data
    {
      resource_type: dig_data("resource_type"),
      action: dig_data("action"),
      item: dig_data("item")
    }
  end
end

# Template for new chat confirmation dialog
class NewChatConfirmationTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["current_chat_id"].present?
  end

  def render_data
    {
      current_chat_id: dig_data("current_chat_id"),
      message_count: dig_data("message_count") || 0,
      confirm_url: dig_data("confirm_url"),
      dismiss_url: dig_data("dismiss_url")
    }
  end
end

# Template for pre-creation planning questions form
class PreCreationPlanningTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["questions"].is_a?(Array) && data["chat_id"].present?
  end

  def render_data
    {
      questions: dig_data("questions"),
      chat_id: dig_data("chat_id"),
      list_title: dig_data("list_title")
    }
  end
end

# Template for context reuse options (use existing plan or clear)
class ContextReuseOptionsTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["items_count"].is_a?(Integer) && data["sublists_count"].is_a?(Integer) && data["chat_id"].present?
  end

  def render_data
    {
      items_count: dig_data("items_count"),
      sublists_count: dig_data("sublists_count"),
      chat_id: dig_data("chat_id")
    }
  end
end

# Template for clarifying questions in general conversations
class ClarifyingQuestionsTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["questions"].is_a?(Array) && data["chat_id"].present?
  end

  def render_data
    {
      questions: dig_data("questions"),
      chat_id: dig_data("chat_id"),
      context_title: dig_data("context_title") || "Please answer the following questions"
    }
  end
end
