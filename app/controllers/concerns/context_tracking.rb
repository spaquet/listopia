# app/controllers/concerns/context_tracking.rb
module ContextTracking
  extend ActiveSupport::Concern

  included do
    before_action :initialize_context_manager
    after_action :track_page_visit, unless: -> { request.xhr? || turbo_frame_request? }
  end

  private

  def initialize_context_manager
    return unless current_user

    @context_manager = ConversationContextManager.new(
      user: current_user,
      chat: current_user.current_chat,
      current_context: build_current_context
    )
  end

  def track_action(action, entity, metadata = {})
    return unless @context_manager && entity

    @context_manager.track_action(
      action: action,
      entity: entity,
      metadata: metadata.merge(
        controller: controller_name,
        action: action_name,
        request_id: request.request_id
      )
    )
  end

  def track_page_visit
    return unless current_user && @context_manager

    # Create a simple page entity without OpenStruct
    page_entity = PageEntity.new("#{controller_name}##{action_name}")

    @context_manager.track_action(
      action: "page_visited",
      entity: page_entity,
      metadata: {
        path: request.path,
        method: request.method,
        params: filtered_params,
        referrer: request.referrer,
        user_agent: request.user_agent
      }
    )
  end

  def build_current_context
    context = {
      page: "#{controller_name}##{action_name}",
      path: request.path,
      timestamp: Time.current.iso8601
    }

    # Add entity-specific context
    if defined?(@list) && @list
      context.merge!(
        list_id: @list.id,
        list_title: @list.title,
        list_status: @list.status
      )
    end

    if defined?(@list_item) && @list_item
      context.merge!(
        item_id: @list_item.id,
        item_title: @list_item.title,
        item_status: @list_item.status
      )
    end

    # Add selected items from session
    if session[:selected_items].present?
      context[:selected_items] = session[:selected_items]
    end

    context
  end

  def filtered_params
    # Remove sensitive parameters
    params.except(:password, :password_confirmation, :authenticity_token).to_unsafe_h
  end

  # Helper method for controllers to track specific actions
  def track_entity_action(action, entity, metadata = {})
    track_action(action, entity, metadata.merge(immediate_context: true))
  end

  # Simple page entity class to replace OpenStruct
  class PageEntity
    attr_reader :id

    def initialize(page_identifier)
      @id = page_identifier
    end

    def class
      PageEntityClass.new
    end
  end

  # Simple class wrapper to provide class.name method
  class PageEntityClass
    def name
      "Page"
    end
  end
end
