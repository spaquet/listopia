# app/services/mcp_tools/collaboration_tools.rb
module McpTools
  class CollaborationTools
    def initialize(user, context)
      @user = user
      @context = context
    end

    # MCP Tool Definitions
    def tools
      [
        {
          name: "invite_collaborator",
          description: "Invite a user to collaborate on a list or list item. Returns success/failure with detailed messages.",
          input_schema: {
            type: "object",
            properties: {
              resource_type: {
                type: "string",
                enum: [ "List", "ListItem" ],
                description: "Type of resource to share (List or ListItem)"
              },
              resource_id: {
                type: "string",
                description: "UUID of the list or list item to share"
              },
              email: {
                type: "string",
                format: "email",
                description: "Email address of the person to invite"
              },
              permission: {
                type: "string",
                enum: [ "read", "write" ],
                description: "Permission level: 'read' for view-only, 'write' for full edit access"
              },
              can_invite: {
                type: "boolean",
                description: "Allow this collaborator to invite others (delegation). Only applies to write permission.",
                default: false
              }
            },
            required: [ "resource_type", "resource_id", "email", "permission" ]
          }
        },
        {
          name: "list_resources_for_disambiguation",
          description: "Search for lists or list items by title to disambiguate when multiple matches exist. Use this before inviting if the resource name is ambiguous.",
          input_schema: {
            type: "object",
            properties: {
              resource_type: {
                type: "string",
                enum: [ "List", "ListItem" ],
                description: "Type of resource to search for"
              },
              search_term: {
                type: "string",
                description: "Search term to find matching resources by title"
              }
            },
            required: [ "resource_type", "search_term" ]
          }
        },
        {
          name: "list_collaborators",
          description: "Get a list of all collaborators for a specific list or list item",
          input_schema: {
            type: "object",
            properties: {
              resource_type: {
                type: "string",
                enum: [ "List", "ListItem" ],
                description: "Type of resource"
              },
              resource_id: {
                type: "string",
                description: "UUID of the resource"
              }
            },
            required: [ "resource_type", "resource_id" ]
          }
        },
        {
          name: "remove_collaborator",
          description: "Remove a collaborator from a list or list item",
          input_schema: {
            type: "object",
            properties: {
              resource_type: {
                type: "string",
                enum: [ "List", "ListItem" ],
                description: "Type of resource"
              },
              resource_id: {
                type: "string",
                description: "UUID of the resource"
              },
              email: {
                type: "string",
                format: "email",
                description: "Email of the collaborator to remove"
              }
            },
            required: [ "resource_type", "resource_id", "email" ]
          }
        }
      ]
    end

    # Tool Implementation - Disambiguation
    def list_resources_for_disambiguation(resource_type:, search_term:)
      organization_id = @context[:organization_id]

      resources = case resource_type
      when "List"
        query = @user.lists.where("title ILIKE ?", "%#{search_term}%")
        query = query.where(organization_id: organization_id) if organization_id.present?
        query.limit(10)
      when "ListItem"
        query = ListItem.joins(:list)
                        .where(lists: { user_id: @user.id })
                        .where("list_items.title ILIKE ?", "%#{search_term}%")
        query = query.where(lists: { organization_id: organization_id }) if organization_id.present?
        query.limit(10)
      else
        return error_response("Invalid resource type. Must be 'List' or 'ListItem'")
      end

      if resources.empty?
        {
          success: false,
          message: "No #{resource_type} found matching '#{search_term}'. Please check the spelling or try a different search term."
        }
      elsif resources.size == 1
        {
          success: true,
          single_match: true,
          resource: format_resource(resources.first),
          message: "Found one match: #{resources.first.title}"
        }
      else
        {
          success: true,
          multiple_matches: true,
          resources: resources.map { |r| format_resource(r) },
          message: "Found #{resources.size} matching #{resource_type}. Please specify which one you'd like to share."
        }
      end
    end

    # Tool Implementation - List Collaborators
    def list_collaborators(resource_type:, resource_id:)
      resource = find_resource(resource_type, resource_id)
      return error_response("Resource not found") unless resource
      return error_response("You don't have access to this resource") unless can_view?(resource)

      collaborators = resource.collaborators.includes(:user)
      invitations = resource.invitations.pending.includes(:invited_by)

      {
        success: true,
        resource: format_resource(resource),
        collaborators: collaborators.map do |collab|
          {
            name: collab.user.name,
            email: collab.user.email,
            permission: collab.permission,
            can_invite_others: collab.has_role?(:can_invite_collaborators),
            joined_at: collab.created_at
          }
        end,
        pending_invitations: invitations.map do |inv|
          {
            email: inv.email,
            permission: inv.permission,
            invited_by: inv.invited_by.name,
            invited_at: inv.invitation_sent_at
          }
        end,
        total_collaborators: collaborators.size,
        pending_count: invitations.size
      }
    rescue ActiveRecord::RecordNotFound
      error_response("Resource not found")
    end

    # Tool Implementation - Invitation
    def invite_collaborator(resource_type:, resource_id:, email:, permission:, can_invite: false)
      # Find resource
      resource = find_resource(resource_type, resource_id)
      return error_response("Resource not found") unless resource

      # Authorization check
      unless can_manage_collaborators?(resource)
        return error_response("You don't have permission to invite collaborators to this resource")
      end

      # Validate permission level
      unless [ "read", "write" ].include?(permission)
        return error_response("Invalid permission level. Must be 'read' or 'write'")
      end

      # can_invite only makes sense for write permission
      if can_invite && permission == "read"
        return error_response("Delegation (can_invite) is only available for write permission")
      end

      # Use InvitationService
      service = InvitationService.new(resource, @user)
      grant_roles = { can_invite_collaborators: can_invite }
      result = service.invite(email, permission, grant_roles)

      if result.success?
        {
          success: true,
          message: result.message,
          resource: {
            type: resource_type,
            id: resource_id,
            title: resource.title,
            url: polymorphic_url_for(resource)
          },
          invitee: email,
          permission: permission,
          can_invite_others: can_invite
        }
      else
        error_response(result.errors)
      end
    rescue ActiveRecord::RecordNotFound
      error_response("Resource not found")
    end

    # Tool Implementation - Remove Collaborator
    def remove_collaborator(resource_type:, resource_id:, email:)
      resource = find_resource(resource_type, resource_id)
      return error_response("Resource not found") unless resource

      unless can_manage_collaborators?(resource)
        return error_response("You don't have permission to remove collaborators")
      end

      user_to_remove = User.find_by(email: email)
      return error_response("No user found with email: #{email}") unless user_to_remove

      collaborator = resource.collaborators.find_by(user: user_to_remove)
      return error_response("#{email} is not a collaborator on this resource") unless collaborator

      collaborator.destroy
      CollaborationMailer.removed_from_resource(user_to_remove, resource).deliver_later

      {
        success: true,
        message: "#{email} has been removed from #{resource.title}",
        resource: format_resource(resource)
      }
    rescue ActiveRecord::RecordNotFound
      error_response("Resource not found")
    end

    private

    def find_resource(resource_type, resource_id)
      case resource_type
      when "List"
        List.find(resource_id)
      when "ListItem"
        ListItem.find(resource_id)
      else
        nil
      end
    end

    def format_resource(resource)
      base = {
        id: resource.id,
        title: resource.title,
        type: resource.class.name
      }

      case resource
      when ListItem
        base.merge(
          list_title: resource.list.title,
          list_id: resource.list.id,
          status: resource.status,
          priority: resource.priority
        )
      when List
        base.merge(
          status: resource.status,
          items_count: resource.list_items_count
        )
      else
        base
      end
    end

    def can_view?(resource)
      case resource
      when List
        resource.owner == @user ||
        resource.collaborators.exists?(user: @user) ||
        resource.is_public?
      when ListItem
        resource.list.owner == @user ||
        resource.list.collaborators.exists?(user: @user) ||
        resource.collaborators.exists?(user: @user)
      else
        false
      end
    end

    def can_manage_collaborators?(resource)
      case resource
      when List
        return true if resource.owner == @user

        collaborator = resource.collaborators.find_by(user: @user)
        return true if collaborator&.permission_write? && collaborator&.has_role?(:can_invite_collaborators)

        false
      when ListItem
        return true if resource.list.owner == @user

        list_collab = resource.list.collaborators.find_by(user: @user)
        return true if list_collab&.permission_write? && list_collab&.has_role?(:can_invite_collaborators)

        item_collab = resource.collaborators.find_by(user: @user)
        return true if item_collab&.permission_write? && item_collab&.has_role?(:can_invite_collaborators)

        false
      else
        false
      end
    end

    def polymorphic_url_for(resource)
      case resource
      when List
        Rails.application.routes.url_helpers.list_url(resource, host: ENV.fetch("APP_HOST", "localhost:3000"))
      when ListItem
        Rails.application.routes.url_helpers.list_url(resource.list, host: ENV.fetch("APP_HOST", "localhost:3000"))
      else
        nil
      end
    end

    def error_response(errors)
      {
        success: false,
        error: Array(errors).join(", ")
      }
    end
  end
end
