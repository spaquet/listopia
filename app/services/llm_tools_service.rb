# app/services/llm_tools_service.rb
#
# Defines available tools/functions that the LLM can call.
# These tools provide the LLM with access to manage users, teams, organizations,
# lists, and other Listopia resources through structured tool calls.
#
# This service builds the tools specification that gets sent to the LLM
# (compatible with OpenAI's function calling API and similar).

class LLMToolsService < ApplicationService
  def initialize(user:, organization:, chat_context:)
    @user = user
    @organization = organization
    @chat_context = chat_context
  end

  def call
    success(data: build_tools)
  end

  private

  def build_tools
    [
      navigate_tool,
      list_users_tool,
      list_teams_tool,
      list_organizations_tool,
      list_lists_tool,
      search_tool,
      create_user_tool,
      create_team_tool,
      create_list_tool,
      update_user_tool,
      update_team_tool,
      suspend_user_tool
    ]
  end

  # Tool: Navigate to a page
  def navigate_tool
    {
      type: "function",
      function: {
        name: "navigate_to_page",
        description: "Navigate to a page in the Listopia app. Use this when the user asks to see a list of users, organizations, teams, or other management pages.",
        parameters: {
          type: "object",
          properties: {
            page: {
              type: "string",
              enum: [
                "admin_users",
                "admin_organizations",
                "admin_teams",
                "organization_teams",
                "admin_dashboard",
                "lists",
                "profile",
                "settings"
              ],
              description: "The page to navigate to. Examples: admin_users (show all users), admin_organizations (show all organizations), admin_dashboard (show admin dashboard)."
            },
            filter: {
              type: "object",
              description: "Optional filters to apply on the page",
              properties: {
                status: {
                  type: "string",
                  description: "Filter by status (e.g., 'active', 'suspended', 'archived')"
                },
                query: {
                  type: "string",
                  description: "Search query to filter results"
                },
                role: {
                  type: "string",
                  description: "Filter by role (e.g., 'admin', 'member', 'owner')"
                }
              }
            }
          },
          required: [ "page" ]
        }
      }
    }
  end

  # Tool: List users
  def list_users_tool
    {
      type: "function",
      function: {
        name: "list_users",
        description: "Get a list of all users in the current organization with optional filtering. Returns paginated results.",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Search by name or email"
            },
            status: {
              type: "string",
              enum: [ "active", "suspended", "inactive" ],
              description: "Filter by user status"
            },
            role: {
              type: "string",
              enum: [ "admin", "member" ],
              description: "Filter by role in organization"
            },
            page: {
              type: "integer",
              description: "Page number for pagination (default: 1)"
            },
            per_page: {
              type: "integer",
              description: "Results per page (default: 20, max: 100)"
            }
          }
        }
      }
    }
  end

  # Tool: List teams
  def list_teams_tool
    {
      type: "function",
      function: {
        name: "list_teams",
        description: "Get a list of all teams in the current organization.",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Search by team name"
            },
            page: {
              type: "integer",
              description: "Page number for pagination (default: 1)"
            },
            per_page: {
              type: "integer",
              description: "Results per page (default: 20, max: 100)"
            }
          }
        }
      }
    }
  end

  # Tool: List organizations
  def list_organizations_tool
    {
      type: "function",
      function: {
        name: "list_organizations",
        description: "Get a list of all organizations the current user is part of or manages.",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Search by organization name or slug"
            },
            status: {
              type: "string",
              enum: [ "active", "suspended", "archived" ],
              description: "Filter by organization status"
            },
            page: {
              type: "integer",
              description: "Page number for pagination (default: 1)"
            }
          }
        }
      }
    }
  end

  # Tool: List lists (list items)
  def list_lists_tool
    {
      type: "function",
      function: {
        name: "list_lists",
        description: "Get a list of all lists in the current organization with optional filtering.",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Search by list title or description"
            },
            status: {
              type: "string",
              enum: [ "draft", "active", "completed", "archived" ],
              description: "Filter by list status"
            },
            owner: {
              type: "string",
              description: "Filter by owner name or email"
            },
            page: {
              type: "integer",
              description: "Page number for pagination (default: 1)"
            }
          }
        }
      }
    }
  end

  # Tool: Search across resources
  def search_tool
    {
      type: "function",
      function: {
        name: "search",
        description: "Search across users, lists, teams, and other resources in the organization.",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "The search query"
            },
            resource_type: {
              type: "string",
              enum: [ "user", "list", "team", "organization", "all" ],
              description: "Type of resource to search for (default: all)"
            },
            limit: {
              type: "integer",
              description: "Number of results to return (default: 10, max: 50)"
            }
          },
          required: [ "query" ]
        }
      }
    }
  end

  # Tool: Create user
  def create_user_tool
    {
      type: "function",
      function: {
        name: "create_user",
        description: "Create a new user and add them to the current organization. Sends invitation email.",
        parameters: {
          type: "object",
          properties: {
            email: {
              type: "string",
              format: "email",
              description: "User's email address"
            },
            name: {
              type: "string",
              description: "User's full name"
            },
            role: {
              type: "string",
              enum: [ "member", "admin" ],
              description: "Role in organization (default: member)"
            }
          },
          required: [ "email", "name" ]
        }
      }
    }
  end

  # Tool: Create team
  def create_team_tool
    {
      type: "function",
      function: {
        name: "create_team",
        description: "Create a new team in the current organization.",
        parameters: {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "Team name"
            },
            description: {
              type: "string",
              description: "Team description"
            }
          },
          required: [ "name" ]
        }
      }
    }
  end

  # Tool: Create list
  def create_list_tool
    {
      type: "function",
      function: {
        name: "create_list",
        description: "Create a new list in the current organization or a specific team.",
        parameters: {
          type: "object",
          properties: {
            title: {
              type: "string",
              description: "List title"
            },
            description: {
              type: "string",
              description: "List description"
            },
            team_id: {
              type: "string",
              description: "Optional team ID to create list in a team"
            }
          },
          required: [ "title" ]
        }
      }
    }
  end

  # Tool: Update user
  def update_user_tool
    {
      type: "function",
      function: {
        name: "update_user",
        description: "Update user information or change their role/status.",
        parameters: {
          type: "object",
          properties: {
            user_id: {
              type: "string",
              description: "UUID of the user to update"
            },
            name: {
              type: "string",
              description: "New name"
            },
            email: {
              type: "string",
              format: "email",
              description: "New email address"
            },
            role: {
              type: "string",
              enum: [ "member", "admin" ],
              description: "New role in organization"
            },
            status: {
              type: "string",
              enum: [ "active", "suspended" ],
              description: "User account status"
            }
          },
          required: [ "user_id" ]
        }
      }
    }
  end

  # Tool: Update team
  def update_team_tool
    {
      type: "function",
      function: {
        name: "update_team",
        description: "Update team information.",
        parameters: {
          type: "object",
          properties: {
            team_id: {
              type: "string",
              description: "UUID of the team to update"
            },
            name: {
              type: "string",
              description: "New team name"
            },
            description: {
              type: "string",
              description: "New team description"
            }
          },
          required: [ "team_id" ]
        }
      }
    }
  end

  # Tool: Suspend user
  def suspend_user_tool
    {
      type: "function",
      function: {
        name: "suspend_user",
        description: "Suspend or unsuspend a user account in the organization.",
        parameters: {
          type: "object",
          properties: {
            user_id: {
              type: "string",
              description: "UUID of the user to suspend/unsuspend"
            },
            action: {
              type: "string",
              enum: [ "suspend", "unsuspend" ],
              description: "Whether to suspend or unsuspend the user"
            },
            reason: {
              type: "string",
              description: "Reason for suspension (optional)"
            }
          },
          required: [ "user_id", "action" ]
        }
      }
    }
  end
end
