═══════════════════════════════════════════════════════════════════════════════
LISTOPIA DESIGN SYSTEM MIGRATION — COMPLETE RESTART PROMPT
═══════════════════════════════════════════════════════════════════════════════

PROJECT: Apply Secure Mail Design System (Editorial light + Console dark themes)
STATUS: Phases 1-4.5 complete. All list management views styled. Ready for Phase 5.
BRANCH: fix/version-0.9

═══════════════════════════════════════════════════════════════════════════════
WHAT'S COMPLETE (13 Git Commits)
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

PHASE 5: Search & Filtering Views
  - Search results view styling (/lists/search or relevant)
  - Filter sidebar + facets styling
  - Search result rows with design tokens
  - Filter pills and clear buttons
  - Search input styling

PHASE 8: Chat Interface (if exists)
  - Unified chat styling
  - Message bubbles (user vs AI)
  - Chat input area
  - Typing indicator

PHASE 9-12: Admin, Email, Testing, Polish
  - Admin dashboard styling
  - Email templates
  - Dark theme comprehensive testing
  - Accessibility & responsive design
  - Browser compatibility

═══════════════════════════════════════════════════════════════════════════════
HOW TO RESUME FOR PHASE 5
═══════════════════════════════════════════════════════════════════════════════

1. Auto-loads memory from:
   ~/.claude/projects/-Users-spaquet-Sites-listopia/memory/design_system_migration.md

2. Verify recent commits exist:
   git log --oneline -5
   Should show: e9f0f73, 6e87650, 10af895, 3f951d3, 54f42ea

3. Verify all design system files exist:
   app/assets/stylesheets/design-system/
     ✓ tokens.css (Editorial + Console themes, colors, typography)
     ✓ components.css (.card, .btn, .form-group, .pill, .alert, etc.)
     ✓ utilities.css (color, typography, spacing, .form-label, .form-input)
   app/javascript/controllers/theme_controller.js (toggle + localStorage)

4. Files to update for Phase 5:
   - Find search views (app/views/lists/search* or similar)
   - Find filter components
   - Identify any sidebar/facet templates

5. Ready for Phase 5: Search & Filtering views styling

═══════════════════════════════════════════════════════════════════════════════
