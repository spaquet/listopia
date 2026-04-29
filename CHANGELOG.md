# Changelog

All notable changes to Listopia are documented in this file.

## [0.9.0] - 2026-04-29

### Highlights

- Introduced the new Listopia design system across the application, with semantic design tokens, reusable component classes, and full light/dark theme support.
- Added a persistent theme toggle backed by the new `theme` Stimulus controller and CSS variable-based Editorial/Console themes.
- Migrated major UI surfaces to the new design system, including navigation, dashboard, lists, list items, kanban, search/filtering, auth, settings, admin, notifications, invitations, AI agents, chat, connectors, modals, mailers, loading states, and shared components.
- Added modal, toast, spinner, toggle, tab, alert, card, button, form, pill, pagination, and theme-toggle primitives for reuse across views.
- Added fiber-capable Solid Queue support by using `solid_queue` from `https://github.com/crmne/solid_queue.git` on the `async-worker-execution-mode` branch.

### Added

- Complete AI Agents system with four-scope access control, agent resources, team memberships, runs, run steps, feedback, event triggers, scheduling hooks, token budgeting, and tool execution.
- Agent UI for browsing, creating, editing, running, and reviewing agents, including run progress, run result, status, and interaction partials.
- AI agent documentation and visual guides covering architecture, lifecycle, HITL flow, triggers, chat integration, and UI usage.
- Event system, audit trail, compliance report, and admin audit views.
- Calendar connector event sync, webhook subscriptions, conflict detection, attendee contact enrichment, people pages, and conflict UI.
- Recurring tasks with recurrence models, jobs, services, specs, and recurrence form fields.
- Generic clarifying-question and follow-up-question UI flows for chat and list creation.
- Context reuse flows after list creation, including buttons to keep or clear planning context.
- AI-generated follow-up options after list creation.
- Shared `AGENTS.md` guidance for coding agents and updated dependency documentation.

### Changed

- Upgraded to Rails 8.1.3 and Ruby 4.0.3.
- Upgraded Puma to 8.0.1.
- Upgraded Pagy to 43.4.2 and updated pagination integration.
- Updated current gem and JavaScript dependency documentation.
- Refactored chat orchestration toward a unified AI agent-based flow.
- Renamed and reorganized chat context concepts around `ChatUiContext`.
- Migrated mailer layouts and notification mailers to the design system.
- Updated Docker and CI/runtime dependency alignment.
- Removed unused JavaScript dependencies, including lodash and unused ProseMirror packages.

### Fixed

- Fixed profile edit route generation by posting the form to `profile_path` and sending Cancel back to `profile_path`.
- Fixed AI agent form tabs so fields render under the design-system `.tab-content.active` convention.
- Fixed invitations index ERB syntax and form rendering errors.
- Fixed list filter ERB syntax issues.
- Fixed duplicate stylesheet asset loading.
- Fixed duplicate `htmlElement` declaration in theme scripts.
- Fixed Stimulus theme controller registration and console theme toggle helpers.
- Fixed primary button and New List button text contrast on hover.
- Fixed AI agent active scope usage in `AgentEventDispatchJob`.
- Fixed AI agent run enum method names by using status-prefixed predicates.
- Fixed AgentContextBuilder field usage after schema changes.
- Fixed AI agent resource delete buttons to use the correct Turbo confirmation behavior.
- Fixed AI agent resource edit/delete authorization gates.
- Fixed AI agent parameter handling for both string and hash formats.
- Fixed RubyLLM tool integration so tool objects are recognized correctly.
- Fixed AiAgentRunStep token recording.
- Fixed HITL `ask_user` pausing in agent chat flow.
- Fixed List Creator agent behavior so it can create lists and items correctly.
- Fixed clarifying-question rendering, answer submission, Turbo Stream broadcasts, and parameter conversion.
- Fixed structured JSON follow-up question detection and prevented JSON payloads from leaking as user-visible messages.
- Fixed context reuse buttons and completed-context handling in chat.
- Fixed planning context references and hierarchy generation after chat-context refactors.
- Fixed generic subdivision generation so sublists can be created from arbitrary array data.
- Fixed redundant complexity analysis by reusing the first intent/complexity result.
- Fixed template variable errors in planning state and item generation progress views.
- Fixed unsupported or mismatched item-generation parameters.
- Fixed test failures from ChatContext removal.
- Fixed pre-creation planning controller import errors.
- Fixed recurring item background safety-net behavior.

### Removed

- Removed legacy list refinement services and specs replaced by the unified chat/list generation flow.
- Removed the old pre-creation planning JavaScript controller and obsolete planning partials.
- Removed outdated documentation files after migration into the refreshed docs structure.
