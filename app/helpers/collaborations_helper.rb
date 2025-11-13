# app/helpers/collaborations_helper.rb
module CollaborationsHelper
  def collaborations_path_for(resource)
    if resource.is_a?(List)
      list_collaborations_path(resource)
    elsif resource.is_a?(ListItem)
      list_list_item_collaborations_path(resource.list, resource)
    end
  end

  def collaboration_path_for(resource, collaboration)
    if resource.is_a?(List)
      list_collaboration_path(resource, collaboration)
    elsif resource.is_a?(ListItem)
      list_list_item_collaboration_path(resource.list, resource, collaboration)
    end
  end
end
