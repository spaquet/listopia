# New Tables Description supporting Upcoming Features

This document describes the purpose of each new table added to the collaborative lists and task management application to support additional features.

## time_entries
**Purpose**: Logs time spent by users on specific tasks to support time tracking for productivity analysis and billing.
- `list_item_id`: References the task being tracked (foreign key to `list_items`).
- `user_id`: References the user tracking time (foreign key to `users`).
- `duration`: Stores the time spent in hours (decimal, precision 10, scale 2).
- `started_at` and `ended_at`: Record the start and end times of the tracking session.
- `notes`: Allows optional notes for context.
- `metadata`: Stores additional data as JSON.
- `created_at` and `updated_at`: Timestamps for record creation and updates.

## collaborators
**Purpose**: Tracks users collaborating on resources (e.g., tasks, lists) in a polymorphic manner, allowing multiple users to contribute without being the owner.
- `collaboratable_id` and `collaboratable_type`: Polymorphic association to the resource (e.g., `ListItem`, `List`).
- `user_id`: References the collaborating user (foreign key to `users`).
- `permission`: Defines the user’s permission level (e.g., 0 for read-only).
- `created_at` and `updated_at`: Timestamps for record creation and updates.
- Unique index on `collaboratable_id`, `collaboratable_type`, `user_id` prevents duplicate collaborations.

## invitations
**Purpose**: Manages invitations for users to collaborate on resources (e.g., tasks, lists) in a polymorphic manner, replacing the `list_collaborations` table.
- `invitable_id` and `invitable_type`: Polymorphic association to the resource being invited to.
- `user_id`: References the invited user (foreign key to `users`, optional).
- `email`: Email address for non-registered users.
- `invitation_token`: Unique token for accepting invitations.
- `invitation_sent_at` and `invitation_accepted_at`: Track invitation status.
- `invited_by_id`: References the user who sent the invitation (foreign key to `users`).
- `permission`: Defines the invited user’s permission level.
- `created_at` and `updated_at`: Timestamps for record creation and updates.
- Indices on `email` and `invitation_token` optimize queries; unique indices prevent duplicate invitations.

## board_columns
**Purpose**: Defines columns for Kanban board views within a list to organize tasks (e.g., "To Do," "In Progress").
- `list_id`: References the list the column belongs to (foreign key to `lists`).
- `name`: The column’s name.
- `position`: Defines the column’s order in the board.
- `metadata`: Stores additional data as JSON.
- `created_at` and `updated_at`: Timestamps for record creation and updates.
- Unique index on `list_id`, `position` ensures proper Kanban ordering.

## comments
**Purpose**: Stores user comments on resources (e.g., tasks, lists) in a polymorphic manner to support collaboration discussions.
- `commentable_id` and `commentable_type`: Polymorphic association to the resource (e.g., `ListItem`, `List`).
- `user_id`: References the commenting user (foreign key to `users`).
- `content`: The comment text.
- `metadata`: Stores additional data as JSON.
- `created_at` and `updated_at`: Timestamps for record creation and updates.

## relationships
**Purpose**: Manages relationships between resources (e.g., `ListItem` to `ListItem`, `List` to `ListItem`, `ListItem` to `List`) in a polymorphic manner to support hierarchical structures (e.g., subtasks) and dependencies (e.g., task ordering).
- `parent_id` and `parent_type`: Polymorphic association to the parent resource.
- `child_id` and `child_type`: Polymorphic association to the child resource.
- `relationship_type`: Integer enum (0 for `parent_child`, 1 for `dependency_finish_to_start`), enforced by the model, defaulting to `parent_child`.
- `metadata`: Stores additional data as JSON (e.g., dependency-specific rules).
- `created_at` and `updated_at`: Timestamps for record creation and updates.
- Unique index on `parent_id`, `parent_type`, `child_id`, `child_type` prevents duplicate relationships.