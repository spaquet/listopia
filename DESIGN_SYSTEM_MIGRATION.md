# Listopia → Secure Mail Design System Migration

**Design System**: Editorial (light) + Console (dark) themes from Secure Mail
**Timeline**: Phased approach (core → features → polish)
**Key Tech**: Tailwind CSS v4 with CSS variables, Turbo Streams, Stimulus

---

## Progress Summary

**✅ Phases Completed:**
- Phase 1.1 ✅ Design tokens setup (commit a1e18d6)
- Phase 1.2 ✅ Base styles & resets (commit 6972044)
- Phase 1.3 ✅ Utility classes (colors, typography, spacing)
- Phase 1.4 ✅ Typography system
- Phase 2 ✅ Navigation & headers (commit 01c5c5d)
- Phase 2.2-2.4 ✅ Cards, forms, buttons (commit a2efcca)
- Phase 4.1 ✅ Lists index & grid (commit 8defa86)
- Phase 4.2 ✅ List cards with design system

**Current Status:** 
- Design tokens & theme system fully operational
- All components (cards, buttons, forms, alerts) available
- Navigation redesigned with Editorial/Console themes
- Lists index/grid views updated to design system
- Theme toggle working with localStorage persistence

**Completed Templates:**
- app/views/shared/_navigation.html.erb ✅
- app/views/lists/index.html.erb ✅
- app/views/lists/_list_card.html.erb ✅

**Remaining Priority:**
- Phase 4.3: List show view & item rows
- Phase 4.4: List item editor (inline & modal)
- Phase 8-12: Chat, email, admin, testing & polish

---

## PHASE 1: Foundation & Theme Infrastructure

### 1.1 Setup Design Tokens ✅ COMPLETE
- [x] Copy `design-system/tokens.css` to `app/assets/stylesheets/design-system/`
- [x] Update `application.tailwind.css` to import new tokens
- [x] Create `app/views/layouts/application.html.erb` wrapper with `data-theme="editorial"` attribute
- [x] Add theme toggle controller in `app/javascript/controllers/theme_controller.js`
- [x] Create `app/assets/stylesheets/design-system/utilities.css` with semantic patterns
- [x] Create `app/views/shared/_theme_toggle.html.erb` component
- [x] Add theme toggle to navigation
- [ ] Test in dev browser (theme toggle + localStorage)

### 1.2 Update Base Styles & Resets ✅ COMPLETE
- [x] Update `application.tailwind.css` to use design tokens
- [x] Replace hardcoded colors with CSS variables (--color-*, --font-*)
- [x] Update custom-select-dropdown styling with design tokens
- [x] Add global html + body styles with smooth transitions
- [x] Style scrollbars with design colors
- [x] Update link colors and ::selection with design tokens

### 1.3 Create Utility Classes for Common Patterns ✅ COMPLETE
- [x] Add `.eyebrow`, `.kbd`, `.status-dot`, `.mark` utility classes
- [x] Add `.section-divider` for labeled horizontal rules
- [x] Add `.text-ink*` variants (ink, ink-muted, ink-subtle, ink-faint, ink-inverse)
- [x] Add `.bg-surface*` variants (surface, surface-raised, surface-sunken)
- [x] Create semantic color utilities (.text-success, .text-warning, .text-danger)
- [x] Add typography presets (.t-display-l, .t-body, .t-meta, .t-eyebrow)

### 1.4 Typography System Integration ✅ COMPLETE
- [x] Map design system font sizes (--text-2xs through --text-3xl)
- [x] Configure font families as CSS variables (--font-display, --font-body, --font-mono, etc.)
- [x] Create size scale helpers: `.text-display-l`, `.text-display-m`, `.text-display-s`, `.text-body-l`, `.text-body`, `.text-body-s`, `.text-meta`
- [x] Font weights mapped (--font-weight-regular through --font-weight-bold)
- [x] Leading/line-height tokens available (--leading-tight through --leading-relaxed)

---

## PHASE 2: Core Components & Layouts ✅ COMPLETE

### 2.1 Navigation & Header ✅ COMPLETE
- [x] Update navigation with new surface/rule colors
- [x] Redesign user menu dropdown using new surface-raised styles
- [x] Update theme toggle button styling
- [x] Replace gray/blue hardcoded colors with design tokens
- [x] Update all navigation links with hover:text-accent
- [x] Ensure Turbo Stream updates to nav work with new styles

### 2.2 Cards & Surfaces ✅ COMPLETE
- [x] Create `.card` component using surface-raised with proper rule borders
- [x] Style `.card-header` with typography sizing
- [x] Design `.card-body` with proper padding (using spacing tokens)
- [x] Create `.card-footer` with rules
- [x] Style `.card:hover` state with shadow-pop
- [x] Component ready for template integration

### 2.3 Forms & Inputs ✅ COMPLETE
- [x] Update `<input>` base styles (surface-sunken bg, ink text, rule borders)
- [x] Style `:focus` states with accent color + box-shadow
- [x] Create `.form-group` wrapper with proper spacing
- [x] Style `<label>` with uppercase text styling
- [x] Create `.checkbox` and `.radio` components
- [x] Style `.form-error` messages (danger color)
- [x] Create `.input-prefix` and `.input-suffix` for icons

### 2.4 Buttons & Actions ✅ COMPLETE
- [x] Create `.btn` base with font tokens, padding, radius-sm
- [x] Design `.btn-primary` (accent bg, ink-inverse text)
- [x] Design `.btn-secondary` (surface-raised bg, ink text, rule border)
- [x] Design `.btn-ghost` (transparent, ink text, hover: surface-raised)
- [x] Create `.btn-sm`, `.btn-md`, `.btn-lg` size variants
- [x] Style `:active`, `:disabled`, `:focus` states
- [x] Ready for template integration

### 2.5 Lists & Tables
- [ ] Design `.list-row` structure with padding (--row-pad-x, --row-pad-y)
- [ ] Create `.list-row-header` with eyebrow labels
- [ ] Style `.list-row-item` with rule-soft dividers
- [ ] Add `.list-row.is-unread` with surface-overlay tint
- [ ] Create column alignment utilities
- [ ] Update `list_items/` table view
- [ ] Ensure Turbo Stream row replacements preserve styles

### 2.6 Empty States & Placeholders
- [ ] Design `.empty-state` card with centered content
- [ ] Create `.empty-state-icon` sizing
- [ ] Style `.empty-state-text` with ink-muted
- [ ] Update all empty state messages in views
- [ ] Create placeholder skeleton loaders

---

## PHASE 3: Lists & List Items Views

### 3.1 Lists Index & Grid
- [ ] Update `/lists/index.html.erb` layout (grid, spacing)
- [ ] Restyle `.list-card` component with new colors/rules
- [ ] Update `.list-card-header` with proper typography
- [ ] Create `.list-card-meta` section (item count, last activity)
- [ ] Add `.list-card-actions` with new button styles
- [ ] Ensure responsive grid adapts to dark theme

### 3.2 List Show & Detail View
- [ ] Update `/lists/show.html.erb` layout
- [ ] Redesign `.list-header` (title, org selector, actions)
- [ ] Update `.list-filter-bar` with new pill styles
- [ ] Restyle `.list-items-container` row structure
- [ ] Update `.list-item-row` component:
  - [ ] Checkbox styling (surface-sunken, accent checked)
  - [ ] Priority indicator colors (danger, warning, success)
  - [ ] Status badges (new pill design)
  - [ ] Assignee avatars
  - [ ] Due date formatting
  - [ ] Collaborator flags
  - [ ] Delete + expand buttons

### 3.3 List Item Editor (Inline & Modal)
- [ ] Update inline `.list-item-edit` form styles
- [ ] Redesign modal `.list-item-detail-view`
- [ ] Create `.list-item-section` dividers with labels
- [ ] Style `.list-item-description` editor
- [ ] Update `.list-item-metadata` (dates, priority, assignees)
- [ ] Design `.list-item-attachments` display
- [ ] Style comment threads with new colors

### 3.4 Kanban View
- [ ] Update `/lists/kanban.html.erb` layout
- [ ] Restyle `.kanban-column` with new borders/spacing
- [ ] Create `.kanban-card` design (matches list-item styling)
- [ ] Add drag-drop visual feedback
- [ ] Ensure Turbo Stream updates preserve drag state

---

## PHASE 4: Chat & AI Features

### 4.1 Chat Interface
- [ ] Update `/chat/_unified_chat.html.erb` layout
- [ ] Restyle `.chat-message` (user vs AI styling)
- [ ] Create `.ai-summary` card with mark highlighting
- [ ] Update `.chat-input-area` styling
- [ ] Add `.typing-indicator` animation
- [ ] Style `.ai-confidence-badge` with semantic colors

### 4.2 AI Agent Resources
- [ ] Update `/ai_agent_resources/` views
- [ ] Restyle resource cards with new surface colors
- [ ] Create `.resource-tag` pill design
- [ ] Update `.resource-parameter` form fields
- [ ] Style `.resource-action` buttons

### 4.3 Pre-Creation Planning Form
- [ ] Update `.planning-form` styling
- [ ] Redesign `.clarifying-question` card
- [ ] Style `.question-option` radio/checkbox group
- [ ] Create `.planning-progress` indicator
- [ ] Update `.list-preview` card

---

## PHASE 5: Search & Filtering

### 5.1 Search Results View
- [ ] Restyle `/lists/search.html.erb` (if exists) or relevant search view
- [ ] Create `.search-result-row` component
- [ ] Update `.search-filter-sidebar` with new styles
- [ ] Add `.search-facet-pill` design
- [ ] Style `.result-highlight` for query terms
- [ ] Create `.result-metadata` section styling

### 5.2 Filter UI & Advanced Search
- [ ] Update `.filter-dropdown` styling
- [ ] Redesign `.filter-menu` items
- [ ] Create `.filter-tag` pill with remove button
- [ ] Update `.filter-input` with search styling
- [ ] Add `.filter-clear` button styling

---

## PHASE 6: Modals, Dialogs & Overlays

### 6.1 Modal Styling
- [ ] Create `.modal-overlay` background (rgba with dark theme awareness)
- [ ] Design `.modal-container` with proper spacing/shadow
- [ ] Style `.modal-header` with rule dividers
- [ ] Create `.modal-body` with proper padding/scrolling
- [ ] Design `.modal-footer` with action buttons
- [ ] Update all modal instances throughout app

### 6.2 Popovers & Tooltips
- [ ] Style `.popover-content` with surface-raised + rule
- [ ] Create arrow pointers with accent color
- [ ] Design `.tooltip` with ink colors
- [ ] Update positioning utilities

### 6.3 Alerts & Notifications
- [ ] Create `.alert` component (success, warning, danger, info)
- [ ] Style `.alert-icon` with semantic colors
- [ ] Design `.alert-message` typography
- [ ] Add `.alert-dismiss` button
- [ ] Style `.toast-notification` for real-time updates

---

## PHASE 7: Collaborators & Sharing

### 7.1 Collaborator Components
- [ ] Update `/collaborators/index.html.erb` layout
- [ ] Restyle `.collaborator-card` with new colors
- [ ] Create `.collaborator-avatar-group` component
- [ ] Update `.collaborator-role-badge` styling
- [ ] Design `.collaborator-action-buttons` layout

### 7.2 Sharing & Permissions
- [ ] Update share view styling
- [ ] Create `.permission-level-selector` design
- [ ] Style `.link-copy-button` interaction
- [ ] Design `.invite-form` layout

---

## PHASE 8: Turbo Streams & Dynamic Updates

### 8.1 Turbo Stream Styling
- [ ] Ensure `.turbo-frame` and `.turbo-stream` updates preserve styles
- [ ] Create smooth transitions for replaced elements
- [ ] Style `.turbo-progress-bar` with accent color
- [ ] Add fade-in animation for newly inserted elements (motion tokens)
- [ ] Test list item additions/removals with proper styling

### 8.2 Real-Time Collaboration Indicators
- [ ] Style `.collaborator-cursor` with unique accent colors
- [ ] Create `.collaborator-selection-highlight` styling
- [ ] Design `.item-being-edited` visual indicator
- [ ] Create `.presence-indicator` badge

### 8.3 Loading States
- [ ] Create skeleton loader component using surface-sunken
- [ ] Design `.loading-spinner` with accent color
- [ ] Style `.loading-text` with ink-muted
- [ ] Update Turbo loading state styling

---

## PHASE 9: Stimulus Controllers & JavaScript

### 9.1 Theme Controller
- [ ] Create `app/javascript/controllers/theme_controller.js`
- [ ] Implement theme toggle with localStorage persistence
- [ ] Watch for system preference changes (prefers-color-scheme)
- [ ] Ensure smooth CSS transitions between themes

### 9.2 Interactive Components
- [ ] Update all Stimulus controllers to use design system classes
- [ ] Ensure dropdowns work with new color scheme
- [ ] Style dynamic popovers/tooltips
- [ ] Update sortable/draggable visual feedback

### 9.3 Form Validation Styling
- [ ] Update `.field_with_errors` styling with new danger color
- [ ] Create `.form-error-message` component
- [ ] Style inline validation indicators
- [ ] Design success/check icons

---

## PHASE 10: Email Views & Mailers

### 10.1 Email Templates
- [ ] Update `/auth_mailer/` email templates with new design tokens
- [ ] Restyle magic link email
- [ ] Update collaborative list notification emails
- [ ] Create branded email header/footer

---

## PHASE 11: Admin & Settings

### 11.1 Admin Dashboard
- [ ] Update `/admin/dashboard/` styling
- [ ] Restyle audit trail displays
- [ ] Update charts/graphs with design colors
- [ ] Design admin data tables

### 11.2 Settings Pages
- [ ] Update user preferences styling (even though not primary)
- [ ] Restyle organization settings
- [ ] Design permission management UI

---

## PHASE 12: Polish & Edge Cases

### 12.1 Responsive Design
- [ ] Test all views at mobile/tablet/desktop
- [ ] Update responsive spacing breakpoints
- [ ] Ensure dark theme works on all screen sizes
- [ ] Test touch targets (buttons, controls)

### 12.2 Accessibility
- [ ] Verify color contrast ratios meet WCAG AA
- [ ] Test focus states on all interactive elements
- [ ] Ensure keyboard navigation works
- [ ] Add proper ARIA labels where needed

### 12.3 Performance
- [ ] Test CSS file size and load time
- [ ] Ensure no unnecessary DOM reflows during theme switches
- [ ] Optimize font loading (preload display fonts)
- [ ] Check animation performance

### 12.4 Browser Compatibility
- [ ] Test in modern browsers (Chrome, Firefox, Safari, Edge)
- [ ] Verify CSS Grid/Flex usage is compatible
- [ ] Test CSS variable support
- [ ] Ensure graceful degradation for older browsers

### 12.5 Dark Theme Edge Cases
- [ ] Test all images/SVGs in dark theme
- [ ] Verify borders and rules are visible
- [ ] Check code blocks/examples contrast
- [ ] Test embedded content (iframes, etc.)

---

## Design System Reference

**Theme Toggle**: `data-theme="editorial"` or `data-theme="console"` on `<html>` element

**Color Variables** (use in new CSS):
- Surfaces: `--color-surface`, `--color-surface-raised`, `--color-surface-sunken`
- Text: `--color-ink`, `--color-ink-muted`, `--color-ink-subtle`, `--color-ink-faint`
- Lines: `--color-rule`, `--color-rule-soft`, `--color-rule-strong`
- Semantic: `--color-accent`, `--color-success`, `--color-warning`, `--color-danger`

**Typography Variables**:
- Families: `--font-display`, `--font-body`, `--font-mono`, `--font-ui`, `--font-sans-alt`
- Sizes: `--text-2xs` (10px) through `--text-3xl` (36px)
- Weights: `--font-weight-regular` (400) through `--font-weight-bold` (700)

**Spacing & Layout**:
- Base unit: `--spacing` (0.25rem / 4px)
- Row padding: `--row-pad-x` (32px), `--row-pad-y` (16px)
- Radius: `--radius-none`, `--radius-xs`, `--radius-sm`, `--radius-md`, `--radius-pill`
- Gap: `--row-gap-sm` (0.5rem), `--row-gap` (0.75rem)

**Motion**:
- Timing: `--duration-fast` (120ms), `--duration-base` (200ms), `--duration-slow` (360ms)
- Easing: `--ease-out`, `--ease-in-out`

---

## Key Implementation Notes

1. **Turbo Streams**: When replacing elements with turbo_stream, the new HTML will automatically pick up design tokens. Test that:
   - New list items appear with correct styling
   - Updated items maintain focus
   - Animations work smoothly

2. **Dynamic Classes**: Use CSS variables instead of hardcoding colors so theme switching works without JS manipulation:
   ```erb
   <div class="bg-surface border border-rule">
     <!-- This will auto-update when data-theme changes -->
   </div>
   ```

3. **Responsive Images**: Editorial theme uses warm paper bg; test all images/logos against both themes

4. **Console Theme**: Terminal aesthetic means:
   - Flat corners (radius: 0)
   - Grid lines instead of shadows
   - Monospace typography
   - No rounded buttons

5. **AI Features**: Use `--color-ai-mark` for summary highlights, `--color-ai-action` for AI-generated buttons

6. **Accessibility**: Maintain sufficient contrast:
   - Editorial: Dark navy on warm paper ✓
   - Console: Phosphor green/amber on near-black ✓

---

## Testing Checklist

- [ ] All views render without console errors
- [ ] Theme toggle works (localStorage persists)
- [ ] Colors update correctly on theme switch
- [ ] No flashing/jank during transitions
- [ ] Mobile responsive at all breakpoints
- [ ] Keyboard navigation works
- [ ] Color contrast passes WCAG AA
- [ ] Turbo updates work with new styles
- [ ] Images/avatars visible in both themes
- [ ] Print stylesheet (if any) works

