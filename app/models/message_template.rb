# app/models/message_template.rb
#
# MessageTemplate registry and base class for rendering different message types
# Supports extensible template system for rich message rendering

class MessageTemplate
  # Registry of all available templates
  REGISTRY = {
    # User/Team/Org info
    "user_profile" => "UserProfileTemplate",
    "team_summary" => "TeamSummaryTemplate",
    "org_stats" => "OrgStatsTemplate",

    # List/Item operations
    "list_created" => "ListCreatedTemplate",
    "lists_created" => "ListsCreatedTemplate",
    "items_created" => "ItemsCreatedTemplate",
    "item_assigned" => "ItemAssignedTemplate",

    # Search & discovery
    "search_results" => "SearchResultsTemplate",
    "browse_results" => "BrowseResultsTemplate",
    "command_result" => "CommandResultTemplate",

    # File uploads
    "file_uploaded" => "FileUploadedTemplate",
    "files_processed" => "FilesProcessedTemplate",

    # Chat system & LLM tools
    "navigation" => "NavigationTemplate",
    "list" => "ListTemplate",
    "resource" => "ResourceTemplate",

    # System messages
    "rag_sources" => "RAGSourcesTemplate",
    "error" => "ErrorTemplate",
    "success" => "SuccessTemplate",
    "info" => "InfoTemplate",
    "help" => "HelpTemplate"
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

# Template for user profile cards
class UserProfileTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["user_id"].present?
  end

  def render_data
    {
      user_id: dig_data("user_id"),
      name: dig_data("name"),
      email: dig_data("email"),
      avatar_url: dig_data("avatar_url"),
      lists_count: dig_data("lists_count") || 0,
      teams_count: dig_data("teams_count") || 0
    }
  end
end

# Template for team summaries
class TeamSummaryTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["team_id"].present?
  end

  def render_data
    {
      team_id: dig_data("team_id"),
      name: dig_data("name"),
      member_count: dig_data("member_count") || 0,
      list_count: dig_data("list_count") || 0,
      description: dig_data("description")
    }
  end
end

# Template for organization stats
class OrgStatsTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["org_id"].present?
  end

  def render_data
    {
      org_id: dig_data("org_id"),
      name: dig_data("name"),
      member_count: dig_data("member_count") || 0,
      team_count: dig_data("team_count") || 0,
      list_count: dig_data("list_count") || 0
    }
  end
end

# Template for list creation confirmation
class ListCreatedTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["list_id"].present? && data["title"].present?
  end

  def render_data
    {
      list_id: dig_data("list_id"),
      title: dig_data("title"),
      url: dig_data("url"),
      item_count: dig_data("item_count") || 0
    }
  end
end

# Template for multiple lists creation
class ListsCreatedTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["lists"].is_a?(Array) && data["lists"].length > 0
  end

  def render_data
    {
      lists: dig_data("lists"),
      total_count: dig_data("lists").length
    }
  end
end

# Template for items created
class ItemsCreatedTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["items"].is_a?(Array) && data["items"].length > 0
  end

  def render_data
    {
      items: dig_data("items"),
      total_count: dig_data("items").length,
      list_id: dig_data("list_id"),
      list_title: dig_data("list_title")
    }
  end
end

# Template for item assignment
class ItemAssignedTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["item_id"].present? && data["assigned_to"].present?
  end

  def render_data
    {
      item_id: dig_data("item_id"),
      item_title: dig_data("item_title"),
      assigned_to_name: dig_data("assigned_to_name"),
      assigned_to_id: dig_data("assigned_to_id"),
      due_date: dig_data("due_date")
    }
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

# Template for command results
class CommandResultTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["command"].present?
  end

  def render_data
    {
      command: dig_data("command"),
      result: dig_data("result"),
      status: dig_data("status") || "success"
    }
  end
end

# Template for file uploads
class FileUploadedTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["file_name"].present?
  end

  def render_data
    {
      file_name: dig_data("file_name"),
      file_size: dig_data("file_size"),
      file_type: dig_data("file_type"),
      url: dig_data("url")
    }
  end
end

# Template for processed files
class FilesProcessedTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["files"].is_a?(Array)
  end

  def render_data
    {
      files: dig_data("files"),
      total_count: dig_data("files").length,
      status: dig_data("status") || "processed"
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

# Template for success messages
class SuccessTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["message"].present?
  end

  def render_data
    {
      message: dig_data("message"),
      details: dig_data("details"),
      action_url: dig_data("action_url"),
      action_text: dig_data("action_text")
    }
  end
end

# Template for info messages
class InfoTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["message"].present?
  end

  def render_data
    {
      message: dig_data("message"),
      details: dig_data("details"),
      icon: dig_data("icon") || "ℹ️"
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

# Template for list results from tools
class ListTemplate < BaseTemplate
  def self.validate_data(data)
    data.is_a?(Hash) && data["items"].is_a?(Array)
  end

  def render_data
    {
      resource_type: dig_data("resource_type"),
      total_count: dig_data("total_count") || 0,
      page: dig_data("page") || 1,
      items: dig_data("items")
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
