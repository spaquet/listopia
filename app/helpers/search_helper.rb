module SearchHelper
  def result_type_label(record)
    case record
    when List
      "List"
    when ListItem
      "Item"
    when Comment
      "Comment"
    when ActsAsTaggableOn::Tag
      "Tag"
    else
      "Result"
    end
  end

  def result_type_classes(record)
    case record
    when List
      "bg-blue-100 text-blue-800"
    when ListItem
      "bg-green-100 text-green-800"
    when Comment
      "bg-purple-100 text-purple-800"
    when ActsAsTaggableOn::Tag
      "bg-orange-100 text-orange-800"
    else
      "bg-gray-100 text-gray-800"
    end
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
        list_path(record.commentable, anchor: "comment-#{record.id}")
      when ListItem
        list_item_path(record.commentable.list, record.commentable, anchor: "comment-#{record.id}")
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
