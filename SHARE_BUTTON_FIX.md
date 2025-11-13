# Share Button Fix - Action Missing Error

## Problem
When clicking the "Share" button, the application threw an error:
```
AbstractController::ActionNotFound (The action 'index' could not be found for CollaborationsController)
```

## Root Cause
The Share button in `_header.html.erb` was linking to `list_collaborations_path(list)`, which is the collection route that defaults to `collaborations#index` action.

However, the CollaborationsController only had a `show` action implemented, not an `index` action.

## Solution
Added a `collaborations#index` action that:
1. Authorizes the user can manage collaborators
2. Loads all collaborators with associated user info
3. Loads all pending invitations
4. Determines if user has permission to manage collaborators
5. Responds with turbo_stream format to update the modal frame

```ruby
def index
  authorize @collaboratable, :manage_collaborators?, policy_class: get_policy_class

  @collaborators = @collaboratable.collaborators.includes(:user)
  @pending_invitations = @collaboratable.invitations.pending.includes(:invited_by)
  @can_manage_collaborators = can_manage_collaborators?(@collaboratable)
  @resource_type = @collaboratable.class.name
  @can_remove_collaborator = can_manage_collaborators?(@collaboratable)

  respond_to do |format|
    format.turbo_stream do
      render turbo_stream: turbo_stream.update(
        "modal",
        partial: "collaborations/share_modal",
        locals: {
          resource: @collaboratable,
          resource_type: @resource_type,
          collaborators: @collaborators,
          pending_invitations: @pending_invitations,
          can_manage_collaborators: @can_manage_collaborators,
          can_remove_collaborator: @can_remove_collaborator
        }
      )
    end
    format.html { render :index }
  end
end
```

## Changes Made

### 1. CollaborationsController
**File**: `app/controllers/collaborations_controller.rb`

- Added `:index` to the authorization exceptions
- Implemented `index` action with same logic as `show` (for now)
- Both actions render the same share modal partial

### 2. Route Behavior
**File**: `config/routes.rb`

- No changes needed - routes already configured correctly
- `GET /lists/:list_id/collaborations` → `collaborations#index` ✓
- `GET /lists/:list_id/collaborations/:id` → `collaborations#show` ✓

## User Workflow (Now Fixed)
1. User opens a List
2. User clicks "Share" button in header
3. Browser makes GET request to `/lists/:list_id/collaborations`
4. Rails routes to `CollaborationsController#index`
5. Controller:
   - Authenticates the user
   - Authorizes they can manage collaborators
   - Loads collaborators and invitations
   - Responds with turbo_stream
6. Turbo updates the "modal" frame with the share modal
7. Modal appears on screen with:
   - Current collaborators list
   - Pending invitations
   - Form to invite new people

## Why Both Index and Show?

We kept both actions for future flexibility:

- **`index`**: Collection view - shows ALL collaborators and pending invitations for a resource (used by Share button)
- **`show`**: Individual view - could show details about a specific collaboration (reserved for future use)

## Testing the Fix

### Via Browser (Recommended)
1. Navigate to a list you own
2. Click the "Share" button in the header
3. The modal should now appear with collaborators and invite form

### Via Rails Console
```ruby
# Check that the route exists
Rails.application.routes.routes.select { |r| r.name == "list_collaborations" }

# Verify it routes to index
# Output should show: collaborations#index
```

### Via curl (with proper authentication)
```bash
# Note: This requires proper session authentication
curl -H "Accept: text/vnd.turbo-stream.html" \
  "http://localhost:3000/lists/:id/collaborations"
```

## Summary
The Share button now works correctly and displays the collaboration modal for managing list access and permissions.

---

**Fix Commit**: cf5f7a2 - Add collaborations#index action to show share modal
**Status**: ✅ Fixed and Ready for Testing
