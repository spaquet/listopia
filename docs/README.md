# Listopia Developer Documentation

Technical reference for developers and AI coding agents contributing to Listopia.

## Architecture Overview

Listopia is a Rails 8 collaborative list management application with real-time updates via Hotwire Turbo Streams, AI-powered interactions via Ruby LLM, and robust authorization patterns.

### Core Stack
- **Backend**: Ruby on Rails 8 with PostgreSQL
- **Frontend**: Hotwire Turbo Streams + Stimulus controllers + Tailwind CSS
- **Real-time**: Turbo Streams for live collaboration
- **Authentication**: Email/password with magic link support using Rails 8 `has_secure_password`
- **Authorization**: Pundit for policy-based access control + Rolify for role management
- **AI Integration**: Ruby LLM (OpenAI/Anthropic) for AI chat with tool-calling capabilities
- **Jobs**: Solid Queue for background processing

## Key Concepts

### Lists & Items
- Users create and own **Lists** (collections of tasks/items)
- **List Items** belong to lists with status tracking (pending/completed)
- Items support priorities, due dates, and assignments
- Metadata JSON field allows flexible custom properties

### Collaboration
- **List Collaborations** manage sharing and permissions
- Collaborators can be invited via email with unique invitation tokens
- Permission system controls access levels
- Real-time updates when collaborators make changes

### Real-time Features
- Turbo Streams broadcast changes to all active viewers
- Stimulus controllers handle client-side interactions
- Optimistic UI updates for responsive feel

### Authentication
- Email/password authentication with bcrypt
- Magic link authentication for passwordless sign-in
- Email verification required for account activation

## Database Schema

Key models and relationships:
- `User` → owns multiple `List`s
- `List` → has many `ListItem`s and `ListCollaboration`s
- `ListItem` → belongs to `List`, optionally assigned to `User`
- `ListCollaboration` → manages list sharing and permissions
- Uses UUID primary keys throughout

See `DATABASE.md` for detailed schema and query patterns.

## Development Standards

- Follow Rails conventions and best practices
- Use enums for status/state fields (e.g., `status: { draft: 0, active: 1, completed: 2, archived: 3 }`)
- Implement model validations for data integrity
- Write tests for new features
- Use Turbo Streams for real-time updates
- Keep CSS/markup with Tailwind utility classes

## Common Tasks

**Adding a feature**: Update models → add migrations → implement controller logic → create views with Stimulus/Turbo → add tests

**Real-time updates**: Broadcast changes via `broadcast_*` methods in models or explicitly use Turbo Stream templates

**Background jobs**: Enqueue with Solid Queue for email, notifications, and async tasks

See `CONTRIBUTING.md` for setup and workflow details.