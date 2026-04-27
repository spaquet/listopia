═══════════════════════════════════════════════════════════════════════════════
LISTOPIA DESIGN SYSTEM MIGRATION — COMPLETE RESTART PROMPT
═══════════════════════════════════════════════════════════════════════════════

PROJECT: Apply Secure Mail Design System (Editorial light + Console dark themes)
STATUS: Phases 1-8 mostly complete. All views updated with design tokens. 5 modals still need .modal-* wrapper classes. Ready for Phase 9 (testing/polish).
BRANCH: fix/version-0.9

═══════════════════════════════════════════════════════════════════════════════
WHAT'S COMPLETE (18 Git Commits)
═══════════════════════════════════════════════════════════════════════════════

✅ PHASE 1.1: Design Tokens + Theme Infrastructure (a1e18d6)
   - app/assets/stylesheets/design-system/tokens.css (Editorial + Console themes)
   - app/javascript/controllers/theme_controller.js (toggle + localStorage)
   - app/views/layouts/application.html.erb (data-theme attribute)
   - app/views/shared/_theme_toggle.html.erb (toggle button)

✅ PHASE 1.2: Base Styles (6972044)
   - Updated application.tailwind.css with design tokens
   - Global html/body/scrollbar styling
   - Link colors, selection colors, smooth transitions

✅ PHASE 2: Navigation Redesigned (01c5c5d)
   - app/views/shared/_navigation.html.erb fully updated
   - Uses design tokens: bg-surface, text-ink, hover:text-accent
   - Buttons use .btn-primary, .btn-secondary, .btn-ghost
   - Dropdowns styled with surface-raised + rules

✅ PHASE 3: Component Library (a2efcca)
   - app/assets/stylesheets/design-system/components.css created
   - .card, .card-header, .card-body, .card-footer
   - .btn (primary/secondary/ghost) + sizes (sm/md/lg)
   - .form-group, input/textarea/select, .checkbox, .radio
   - .pill (badge), .alert, .dropdown-menu

✅ PHASE 4.1-4.2: Lists Views Updated (8defa86)
   - app/views/lists/index.html.erb redesigned
   - app/views/lists/_list_card.html.erb using .card + .pill components
   - Progress bar uses accent color
   - All badges/pills styled with design tokens

✅ PHASE 4.3: List Show Page & Item Rows (10af895)
   - app/views/lists/show.html.erb with design tokens
   - app/views/lists/_header.html.erb (title, stats, buttons)
   - app/views/list_items/_item.html.erb (item rows, checkboxes)
   - Sub-lists with .pill status variants
   - All text colors: text-ink, text-ink-muted, text-danger, text-accent

✅ PHASE 4.4: List Item Editor Modal (6e87650)
   - app/views/list_items/edit.html.erb fully styled
   - Added .form-label and .form-input utilities to utilities.css
   - Form sections: Content, Classification, Timeline, Recurrence, Assignment
   - Modal: surface bg, border-rule, shadow-pop, rounded-md
   - Error messages: alert alert-danger

✅ PHASE 4.5: Quick Add Form & Custom Selects (e9f0f73)
   - app/views/list_items/_quick_add_form.html.erb with design tokens
   - app/views/shared/_item_type_select.html.erb custom select dropdown
   - app/views/list_items/_recurrence_fields.html.erb
   - All custom selects: surface-sunken trigger, surface-raised dropdown
   - Priority colors: success/warning/accent/danger indicator dots

✅ PHASE 5: Search & Filter Views (e6f620e, cd903f3, dc1ea3b)
   - app/views/lists/_filters.html.erb fully redesigned with design system
     * Search input: .form-input class
     * Filter buttons: styled links with active state (bg-surface-raised + border-rule + text-accent)
     * Active filters: .alert component with .pill badges
   - app/views/team_members/search.turbo_stream.erb (dropdown member search)
     * bg-surface-raised + border-rule dropdown
     * Hover: bg-surface-sunken with duration-fast
   - app/views/message_templates/_search_results.html.erb (chat search results)
     * Result titles: text-accent with hover state
     * Type badges: bg-surface-sunken + text-ink
     * All text: text-ink / text-ink-muted semantic colors
   - app/views/connectors/storage/google_drive/files/index.html.erb (file browser)
     * Table header: bg-surface-sunken + t-eyebrow
     * Table rows: hover:bg-surface-raised
     * Links: text-accent with transitions
     * Pagination & buttons use .btn .btn-primary

✅ PHASE 6: AI Agent Runs & Chat Interface (462e8e3)
   - AI Agent Run Views
     * app/views/ai_agents/runs.html.erb - Agent runs list with .card, status pills
     * app/views/ai_agent_runs/show.html.erb - Full run details page with forms
     * app/views/ai_agents/_run_step.html.erb - Step progress with color-coded borders
     * app/views/ai_agents/_run_status.html.erb - Status spinner & badge
     * app/views/ai_agents/_run_progress.html.erb - Progress bar with accent color
     * app/views/ai_agents/_run_result.html.erb - Result summary (.alert variants)
     * app/views/ai_agents/_run_placeholder.html.erb - Initial container
   - Chat Interface Views
     * app/views/chats/show.html.erb - Chat page with metadata cards
     * app/views/chat/_unified_chat.html.erb - Main chat UI with header/messages/input
     * app/views/shared/_chat_message.html.erb - Message bubbles (CSS variables for themes)
     * app/views/chats/_hitl_question.html.erb - HITL interaction form
     * app/views/chats/_hitl_answered.html.erb - HITL answered state
     * app/views/chat/_floating_chat.html.erb - Floating chat widget
   - Helper Updates
     * app/helpers/chat_helper.rb - Updated message_bubble_classes, links, badges with tokens

✅ PHASE 7: Dashboard, Admin & Email Views (68256a3)
   - Admin dashboard & user/organization management with design tokens
   - User profile & team views fully styled
   - Email templates with design system CSS

✅ PHASE 8: Forms, Modals & Special Components (21 commits, partial)
   - Commit f2d3e9b: Added design system components (modal, toast, spinner, toggle, tabs, alert-info, pill.pending)
   - Commit 7012207: Updated 7 forms (flash, lists, comments, orgs, ai_agents, ai_agent_resources, admin)
   - Commit b0e64bf: Updated team_members form with tabs
   - Commit c7f9b0f: Updated auth forms (registrations/new, setup_password)
   - Commit ea126bd: Updated loading states (chat, ai_agent_runs)
   - ⏳ REMAINING: 5 modals need .modal-* wrapper classes (org_switcher, spotlight, share, share_modal_content, admin)
   - Admin Dashboard & Management Views (25 files)
     * app/views/admin/dashboard/index.html.erb - Stats cards with .card, text tokens
     * app/views/admin/users/* - User CRUD forms with form-label, form-input
     * app/views/admin/organizations/* - Organization management with .btn variants
     * app/views/admin/audit/* - Audit trail & compliance reports with tables
     * app/views/admin/lists/index.html.erb - Lists management
   - User Views (3 files)
     * app/views/users/settings.html.erb - Notification preferences with toggles
     * app/views/users/edit.html.erb - Profile edit form
     * app/views/users/show.html.erb - Profile display with activity stats
   - Team Views (5 files)
     * app/views/teams/index.html.erb - Team list with .card, member counts
     * app/views/teams/show.html.erb - Team details with member table
     * app/views/teams/_form.html.erb - Team form with design tokens
   - Email Templates (6 files)
     * app/views/layouts/mailer.html.erb - Email layout with design system CSS
     * app/views/auth_mailer/magic_link.html.erb, email_verification.html.erb
     * app/views/collaboration_mailer/invitation.html.erb, added_to_list.html.erb
     * app/views/notification_mailer/item_completed.html.erb

═══════════════════════════════════════════════════════════════════════════════
DESIGN SYSTEM FILES LOCATION & REFERENCE
═══════════════════════════════════════════════════════════════════════════════

CREATED FILES (committed to repo):
  📄 app/assets/stylesheets/design-system/tokens.css
  📄 app/assets/stylesheets/design-system/utilities.css
  📄 app/assets/stylesheets/design-system/components.css
  📄 app/javascript/controllers/theme_controller.js

MEMORY REFERENCE (auto-loaded on restart):
  📋 ~/.claude/projects/.../memory/design_system_migration.md
     → Complete token reference, component library, next steps

SOURCE DESIGN FILES (for reference):
  📁 ~/.claude/projects/.../tool-results/secure-mail/project/
     → Secure Mail.html (design exploration)
     → Design System.html (token showcase)
     → design-system/tokens.css (original source)

═══════════════════════════════════════════════════════════════════════════════
DESIGN TOKENS QUICK REFERENCE
═══════════════════════════════════════════════════════════════════════════════

COLORS (Editorial light | Console dark)
  Surface:   #f7f4ee | #0e0e0d       → --color-surface
  Ink:       #13243a | #cfd6c0       → --color-ink
  Accent:    #8a2c2c | #7ec96f       → --color-accent (bordeaux | green)
  Rules:     #d9d2c1 | #1f201c       → --color-rule
  Success:   #3f8a4a | #7ec96f       → --color-success
  Warning:   #b8741a | #d8a657       → --color-warning
  Danger:    #8a2c2c | #d8a657       → --color-danger

TYPOGRAPHY
  Families: --font-display (serif), --font-body (Inter), --font-mono (Plex Mono)
  Scale: --text-2xs (10px) → --text-3xl (36px)
  Presets: .t-display-l/m/s, .t-body-l/s, .t-meta, .t-eyebrow

LAYOUT
  Spacing: --spacing (4px base), --row-pad-x (32px), --row-pad-y (16px)
  Radius: --radius-sm (2px), --radius-md (4px), --radius-pill (9999px)
  Motion: --duration-fast (120ms), --ease-out

═══════════════════════════════════════════════════════════════════════════════
COMPONENT LIBRARY QUICK REFERENCE
═══════════════════════════════════════════════════════════════════════════════

CARDS:
  .card → Main container (surface-raised, rule border, shadow-pop hover)
  .card-header / .card-body / .card-footer → Sections with rules

BUTTONS:
  .btn-primary → accent bg, inverse text
  .btn-secondary → surface-raised bg, rule border
  .btn-ghost → transparent, no border
  Sizes: .btn-sm, .btn-md, .btn-lg

FORMS:
  .form-group → Flex container
  input/textarea/select → surface-sunken bg, accent focus
  .checkbox, .radio → Custom styled
  .form-error → danger color

UI:
  .pill → Badge/chip (with .accent, .success, .warning, .danger)
  .alert → Alert box (with color variants)
  .dropdown-menu → Dropdown styling
  .mark → Inline highlight (AI)
  .kbd → Keyboard shortcut
  .status-dot → Small indicator

UTILITIES:
  Colors: .text-ink*, .bg-surface*, .text-accent, .text-success, etc.
  Typography: .font-display, .font-body, .font-mono
  Spacing: .row-pad, .row-pad-x, .row-pad-y, .row-gap
  Border: .border-rule, .border-rule-soft, .border-rule-strong
  Motion: .duration-fast, .ease-out, .shadow-card, .shadow-pop

═══════════════════════════════════════════════════════════════════════════════
NEXT PRIORITIES
═══════════════════════════════════════════════════════════════════════════════

PHASE 8: Forms, Modals & Special Components (MOSTLY DONE - 5 modals left)
  ✅ Form validations & error messages (using .alert.danger)
  ✅ Form fields (using .form-label, .form-input, .checkbox)
  ✅ Flash notifications (using .alert variants)
  ✅ Spinners & loading dots
  ⏳ Modals & overlays (5 modals still need refactor)
  ✅ Dropdowns & custom selects (already completed in Phase 5)
  ✅ Tab components (using .tab-nav, .tab-item)

PHASE 9: Complete Modals + Dark Theme Testing + Polish
  - Comprehensive dark theme (Console) testing
  - Accessibility testing (contrast, focus states, etc.)
  - Responsive design testing (mobile, tablet, desktop)
  - Browser compatibility (Chrome, Safari, Firefox, Edge)
  - Fine-tuning animations & transitions
  - Performance optimization

═══════════════════════════════════════════════════════════════════════════════
HOW TO RESUME FOR PHASE 8
═══════════════════════════════════════════════════════════════════════════════

1. Auto-loads memory from:
   ~/.claude/projects/-Users-spaquet-Sites-listopia/memory/design_system_migration.md

2. Verify recent commits exist:
   git log --oneline -5
   Should show: 68256a3 (Phase 7), 462e8e3, e6f620e, cd903f3, dc1ea3b

3. Verify all design system files exist:
   app/assets/stylesheets/design-system/
     ✓ tokens.css (Editorial + Console themes, colors, typography)
     ✓ components.css (.card, .btn, .form-group, .pill, .alert, etc.)
     ✓ utilities.css (color, typography, spacing, .form-label, .form-input)
   app/javascript/controllers/theme_controller.js (toggle + localStorage)

4. Phase 7 coverage: 39 files (dashboard, admin, users, teams, email)
   - All views now use design tokens: text-ink, bg-surface, border-rule
   - Forms use: form-label, form-input, form-group
   - Buttons: .btn-primary, .btn-secondary, .btn-danger
   - Cards: .card with .card-header, .card-body, .card-footer

5. Ready for Phase 8: Forms, Modals & Special Components
   - Identify form validation error states
   - Find modal/overlay templates
   - Locate select/dropdown patterns
   - Find toast/alert notification patterns
   - Locate loading spinners and skeleton screens

═══════════════════════════════════════════════════════════════════════════════
