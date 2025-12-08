class SearchController < ApplicationController
  before_action :authenticate_user!

  def index
    @query = params[:q]&.strip
    @limit = params[:limit]&.to_i || 20

    @results = if @query.present?
      result = SearchService.call(
        query: @query,
        user: current_user,
        limit: @limit
      )

      if result.success?
        result.data
      else
        Rails.logger.warn("Search failed: #{result.errors.join(', ')}")
        []
      end
    else
      []
    end

    respond_to do |format|
      format.html
      format.turbo_stream
      format.json { render json: format_json_response }
    end
  end

  private

  def format_json_response
    {
      query: @query,
      results: @results.map { |record| format_result_json(record) },
      count: @results.length
    }
  end

  def format_result_json(record)
    {
      id: record.id,
      type: record.class.name,
      title: extract_title(record),
      description: extract_description(record),
      url: result_url(record),
      created_at: record.created_at,
      updated_at: record.updated_at
    }
  end

  def extract_title(record)
    case record
    when List
      record.title
    when ListItem
      record.title
    when Comment
      "Comment by #{record.user.name}"
    when ActsAsTaggableOn::Tag
      record.name
    else
      "Unknown"
    end
  end

  def extract_description(record)
    case record
    when List
      record.description
    when ListItem
      record.description
    when Comment
      record.content
    when ActsAsTaggableOn::Tag
      nil
    else
      nil
    end
  end

  def result_url(record)
    case record
    when List
      list_path(record)
    when ListItem
      list_item_path(record.list, record)
    when Comment
      case record.commentable
      when List
        list_path(record.commentable)
      when ListItem
        list_item_path(record.commentable.list, record.commentable)
      else
        root_path
      end
    when ActsAsTaggableOn::Tag
      root_path
    else
      root_path
    end
  end
end
