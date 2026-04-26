═══════════════════════════════════════════════════════════════════════════════
LISTOPIA DESIGN SYSTEM MIGRATION — COMPLETE RESTART PROMPT
═══════════════════════════════════════════════════════════════════════════════

PROJECT: Apply Secure Mail Design System (Editorial light + Console dark themes)
STATUS: Phases 1-4 complete. Foundation fully operational.
BRANCH: fix/version-0.9

═══════════════════════════════════════════════════════════════════════════════
WHAT'S COMPLETE (6 Git Commits)
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

✅ PHASE 4.3-4.4: Still TODO

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

PHASE 4.3: List Show Page & Item Rows
  - Update /lists/show view
  - Redesign list item row component
  - Update status badges, priority indicators, due dates
  - Ensure Turbo Stream updates work with new styles

PHASE 4.4: List Item Editor
  - Style inline editor form
  - Update modal list-item-detail-view
  - Form inputs using .form-group

PHASE 5: Search & Filtering
  - Search results view styling
  - Filter sidebar + facets

PHASE 8-12: Chat, Admin, Testing
  - Chat interface styling
  - Admin dashboard
  - Dark theme testing
  - Accessibility & responsive testing

═══════════════════════════════════════════════════════════════════════════════
HOW TO RESUME
═══════════════════════════════════════════════════════════════════════════════

1. I'll auto-load memory from:
   ~/.claude/projects/-Users-spaquet-Sites-listopia/memory/design_system_migration.md

2. Verify git status: git log --oneline (should see commits a1e18d6...54f42ea)

3. Check design system files exist:
   app/assets/stylesheets/design-system/ (tokens.css, utilities.css, components.css)
   app/javascript/controllers/theme_controller.js

4. Start dev server: rails s

5. Test theme toggle in browser (nav bar)

6. Continue with Phase 4.3 (list show page)

═══════════════════════════════════════════════════════════════════════════════
