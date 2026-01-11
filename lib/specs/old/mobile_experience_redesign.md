# Spec: Mobile Experience Redesign

**Status**: In Progress
**Priority**: High
**Last Updated**: 2026-01-11

---

## Executive Summary

The dashboard and account sections have significant mobile usability issues. This spec outlines a comprehensive redesign following mobile-first principles and 2025 best practices.

**Key Problems Identified**:
1. Event panel (384px) overflows on phones < 400px
2. Charts have fixed heights consuming excessive viewport
3. KPI cards cramped at 2 columns on small screens
4. Account sidebar completely hidden on mobile with poor tab fallback
5. Filter dropdowns overflow viewport
6. No touch-optimized interactions
7. Test/Live toggle clutters nav bar and uses session-only storage

---

## Design Principles

Based on research from [Toptal](https://www.toptal.com/designers/dashboard-design/mobile-dashboard-ui), [DesignRush](https://www.designrush.com/agency/ui-ux-design/dashboard/trends/dashboard-ux), and [Material Design](https://m1.material.io/patterns/settings.html):

| Principle | Description |
|-----------|-------------|
| **Mobile-First** | Design for 375px first, then enhance for larger screens |
| **Single-Column Priority** | Vertical scrolling > horizontal panning |
| **5-Second Rule** | Users should grasp main KPIs within 5 seconds |
| **Touch-Friendly** | Minimum 48px touch targets, swipe gestures for common actions |
| **Progressive Disclosure** | Show summary first, details on tap |
| **KPI Limit** | 4-6 KPIs maximum visible without scrolling (73% higher adoption per [Houseware](https://www.houseware.io/blog/mobile-app-analytics-dashboard)) |

---

## Current State Analysis

### Breakpoint Usage
- `sm:` (640px) - Minimal usage, mostly padding
- `md:` (768px) - Primary layout breakpoint
- `lg:` (1024px) - Grid expansion

**Problem**: No `xs` breakpoint. Layout jumps abruptly at `md:` creating poor experience on phones.

### Component Issues

| Component | Current State | Problem |
|-----------|--------------|---------|
| Event Panel | Fixed 384px width | Overflows all phones < 400px |
| Charts | Fixed h-72/h-80/h-96 | Consumes 50%+ viewport on phones |
| KPI Grid | 2 columns always | Cards cramped on < 375px screens |
| Filters | Fixed-width dropdowns | Overflow viewport, no mobile pattern |
| Account Nav | Hidden sidebar, horizontal tabs | 5 tabs overflow on XS screens |
| Dashboard Tabs | gap-6 spacing | May wrap awkwardly on small screens |

---

## Phase 1: Critical Fixes

### 1.1 Event Panel - Full-Width Mobile Pattern

**Pattern**: Slide-in panel that takes full viewport width on mobile

**Specifications**:
- Mobile (< 640px): Full viewport width with background overlay
- Tablet+: Fixed 384px width (current behavior)
- Add visible close button in top-right corner
- Implement swipe-right-to-close gesture via Stimulus controller
- Background overlay dims content and closes panel on tap

**Files**: `dashboard/show.html.erb`, `event_panel_controller.js`

---

### 1.2 Chart Heights - Responsive Scaling

**Pattern**: Viewport-proportional chart heights

**Specifications**:

| Chart Type | Mobile (< 640px) | Tablet (640-1024px) | Desktop (> 1024px) |
|------------|------------------|---------------------|-------------------|
| Time Series | 192px | 256px | 288px |
| Channel Bar | 224px | 288px | 320px |
| Funnel | 256px | 320px | 384px |

**Additional Changes**:
- Legend moves from side to bottom on mobile
- Legend font reduces from 12px to 10px on mobile
- Limit data series to 5 per chart for clarity
- Weekly aggregates instead of daily on mobile time series

**Files**: `_full_dashboard.html.erb`, `funnel/show.html.erb`, `chart_controller.js`

---

### 1.3 KPI Cards - Responsive Grid

**Pattern**: Progressive grid expansion

**Specifications**:
- XS (< 375px): 1 column, full-width cards
- SM (375-640px): 2 columns with reduced gap (0.5rem)
- MD (640-1024px): 2 columns with standard gap (1rem)
- LG (> 1024px): 3 columns

**Card Internal Changes**:
- Padding: 0.75rem on mobile, 1rem on tablet+
- Label text: xs on mobile, sm on tablet+
- Value text: lg on mobile, 2xl on tablet+

**Files**: `_full_dashboard.html.erb`, `_kpi_card.html.erb`

---

### 1.4 Account Navigation - Stacked List Pattern

**Pattern**: Vertical stacked list replacing horizontal tabs on mobile

**Mobile Behavior**:
- Full-width card with dividers between items
- Each item shows icon + label + active indicator
- Active item has indigo background highlight
- No horizontal scrolling required

**Specifications**:
- Item height: 48px minimum (touch-friendly)
- Icon size: 20px
- Visual active state: indigo-50 background, indigo-600 text
- Dividers between items

**Desktop Behavior**: Current sidebar (unchanged)

**Files**: `_account_nav_tabs.html.erb`

---

### 1.5 Test/Live Data Toggle - Move to Account Settings

**Current State**:
- Toggle visible in main nav bar (`layouts/_nav.html.erb`)
- Uses session storage only (`session[:view_mode]`)
- Defaults to "test" during onboarding, "production" after
- Clutters nav bar on mobile (competes for limited space)

**Pattern**: Hidden developer setting with persistent preference

**Behavior Changes**:

| Aspect | Current | New |
|--------|---------|-----|
| Location | Main nav bar | Account Settings (General tab) |
| Storage | Session only | Database (account.live_mode_enabled) |
| Default | Test during onboarding | Test until explicitly enabled |
| Persistence | Lost on logout | Persists across sessions |

**User Flow**:
1. New accounts start in test mode (see test data only)
2. User completes SDK integration, sees test events flowing
3. User goes to Account Settings → General
4. User enables "Live Mode" toggle
5. Dashboard immediately switches to live data
6. Preference persists - future sessions default to live mode
7. User can still access test mode via Account Settings if needed

**Database Changes**:
- Add `live_mode_enabled` boolean to accounts table (default: false)
- Migration: `add_column :accounts, :live_mode_enabled, :boolean, default: false, null: false`

**Controller Logic**:
- Remove toggle from nav bar
- Add toggle to AccountsController#show (General settings)
- Update `default_view_mode` in ApplicationController:
  - If `live_mode_enabled` is true → default to "production"
  - If `live_mode_enabled` is false → default to "test"
- Session still overrides for temporary switching (testing purposes)

**View Changes**:
- Remove: `render "layouts/view_mode_toggle"` from `_nav.html.erb`
- Add: Data mode section in account settings general tab
- Show current mode indicator in account dropdown (subtle, non-interactive)

**Account Settings UI**:
- Section: "Data Mode"
- Toggle: "Enable Live Mode"
- Helper text: "When enabled, dashboard shows production data by default. Test data remains accessible in settings."
- Warning on first enable: "Make sure your SDK is sending production events before enabling."

**Specifications**:
- Toggle uses standard form submission (not AJAX) for reliability
- Success flash: "Live mode enabled. Dashboard now shows production data."
- Account dropdown shows subtle indicator: small colored dot (amber=test, green=live)

**Files**:
- `app/views/layouts/_nav.html.erb` - Remove toggle
- `app/views/accounts/show.html.erb` - Add data mode section
- `app/controllers/accounts_controller.rb` - Handle toggle update
- `app/controllers/application_controller.rb` - Update default_view_mode logic
- `app/models/account.rb` - Add live_mode_enabled attribute
- `db/migrate/xxx_add_live_mode_enabled_to_accounts.rb` - Migration

---

## Phase 2: Enhanced Mobile UX

### 2.1 Dashboard Tabs - Compact Mobile Spacing

**Pattern**: Reduced spacing with horizontal scroll fallback

**Specifications**:
- Gap: 0.75rem on mobile, 1.5rem on desktop
- Horizontal scroll with hidden scrollbar if needed
- Active tab indicator scales proportionally

**Files**: `dashboard/show.html.erb`

---

### 2.2 Touch-Optimized Charts

**Pattern**: Mobile-optimized Highcharts configuration

**Specifications**:
- Larger tooltip snap radius (30px vs 10px)
- Tooltips positioned to avoid viewport edges
- Pinch-to-zoom enabled, pan disabled on mobile
- Tap-and-hold for detailed tooltip (vs hover)

**Files**: `chart_controller.js`

---

### 2.3 Cohort Table - Horizontal Scroll with Sticky Column

**Pattern**: Scrollable table with fixed first column

**Specifications**:
- First column (cohort name) sticky on left
- Horizontal scroll for remaining columns
- Scroll shadow indicators on left/right edges
- Table container with negative margin trick for edge-to-edge feel

**Files**: `_cohort_table.html.erb`

---

### 2.4 Funnel Stage Cards - Vertical Stacking

**Pattern**: Cards stack vertically on mobile, horizontal on desktop

**Specifications**:
- Mobile: Vertical stack with connecting lines between stages
- Tablet+: Horizontal flow (current)
- Stage value text responsive sizing

**Files**: `funnel/show.html.erb`

---

## Phase 3: Infrastructure & Polish

### 3.1 Custom XS Breakpoint

**Specification**: Add 375px breakpoint to Tailwind config for iPhone SE targeting

**Rationale**: Current smallest breakpoint is 640px (sm), leaving no granular control for 320-639px range

**Files**: `tailwind.config.js`

---

### 3.2 Responsive Typography Utilities

**Pattern**: Fluid text sizing utilities

**Specifications**:
- `text-responsive-sm`: xs on mobile, sm on tablet+
- `text-responsive-base`: sm on mobile, base on tablet+
- `text-responsive-lg`: base on mobile, lg on tablet+
- `text-responsive-xl`: lg on mobile, xl on tablet+, 2xl on desktop

**Files**: `application.css`

---

### 3.3 Pull-to-Refresh

**Pattern**: Native-feeling refresh gesture

**Specifications**:
- Only active when scrolled to top
- Visual indicator showing pull progress
- Threshold: 80px pull distance to trigger
- Triggers Turbo page refresh

**Files**: New `refresh_controller.js`

---

### 3.4 Offline Indicator

**Pattern**: Persistent banner when offline

**Specifications**:
- Fixed position at viewport bottom
- Yellow warning styling
- Shows when `navigator.onLine` is false
- Hides automatically when connection restored

**Files**: New `online_status_controller.js`, layout update

---

## Implementation Order

### Sprint 1: Critical Fixes ✅ COMPLETE
1. ✅ Event panel responsive width (`w-full sm:w-96`)
2. ✅ Chart responsive heights (`h-48 sm:h-64 lg:h-72` etc.)
3. ✅ KPI card grid and padding (`gap-2 sm:gap-4`, `p-3 sm:p-5`)
4. ✅ Test/Live toggle relocation + persistence (moved to Account Settings, database-backed)

### Sprint 2: Navigation & Tables ✅ COMPLETE
5. ✅ Account nav mobile redesign (vertical stacked list with icons)
6. ✅ Dashboard tabs spacing (`gap-3 sm:gap-6`)
7. ✅ Cohort table horizontal scroll with sticky first column
8. ✅ Funnel cards stacking (`flex-col sm:flex-row`)

### Sprint 3: Polish (pending)
9. ⏳ Tailwind XS breakpoint
10. ⏳ Touch-optimized charts
11. ⏳ Pull-to-refresh
12. ⏳ Offline indicator

---

## Files to Modify

| File | Changes | Priority |
|------|---------|----------|
| `app/views/dashboard/show.html.erb` | Event panel, tabs | HIGH |
| `app/views/dashboard/conversions/_full_dashboard.html.erb` | Charts, KPI grid | HIGH |
| `app/views/dashboard/conversions/_kpi_card.html.erb` | Responsive padding/text | HIGH |
| `app/views/layouts/_nav.html.erb` | Remove test/live toggle | HIGH |
| `app/views/accounts/show.html.erb` | Add data mode section | HIGH |
| `app/controllers/accounts_controller.rb` | Handle live_mode toggle | HIGH |
| `app/controllers/application_controller.rb` | Update default_view_mode | HIGH |
| `db/migrate/xxx_add_live_mode_enabled_to_accounts.rb` | New column | HIGH |
| `app/views/layouts/_account_nav_tabs.html.erb` | Stacked list | MEDIUM |
| `app/views/dashboard/funnel/show.html.erb` | Chart, cards | MEDIUM |
| `app/javascript/controllers/event_panel_controller.js` | Swipe gesture | MEDIUM |
| `app/javascript/controllers/chart_controller.js` | Responsive config | MEDIUM |
| `config/tailwind.config.js` | XS breakpoint | LOW |
| `app/assets/stylesheets/application.css` | Typography utilities | LOW |

---

## Testing Requirements

### Device Matrix
| Device | Screen Size | Priority |
|--------|-------------|----------|
| iPhone SE | 375 x 667 | Critical |
| iPhone 14 | 390 x 844 | Critical |
| iPhone 14 Pro Max | 430 x 932 | High |
| iPad Mini | 768 x 1024 | High |
| iPad Pro | 1024 x 1366 | Medium |

### Acceptance Criteria
- [ ] Dashboard loads in < 3 seconds on 3G
- [x] KPIs visible without scrolling on iPhone SE
- [x] No horizontal scrolling required on any phone
- [x] Event panel doesn't overflow on any device
- [x] Account settings fully navigable on mobile
- [x] All touch targets minimum 48px (account nav)
- [ ] Landscape orientation doesn't break layouts
- [x] Test/Live toggle accessible in Account Settings
- [x] Live mode preference persists across sessions

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Mobile Usability Score | > 90 (Lighthouse) |
| First Contentful Paint | < 1.5s on 4G |
| Time to Interactive | < 3s on 4G |
| Touch Target Compliance | 100% at 48px minimum |
| Horizontal Scroll Issues | 0 on any tested device |

---

## References

- [Toptal: Mobile Dashboard UI Best Practices](https://www.toptal.com/designers/dashboard-design/mobile-dashboard-ui)
- [DesignRush: Dashboard UX 2025](https://www.designrush.com/agency/ui-ux-design/dashboard/trends/dashboard-ux)
- [Material Design: Settings Patterns](https://m1.material.io/patterns/settings.html)
- [Houseware: Mobile Analytics Dashboard](https://www.houseware.io/blog/mobile-app-analytics-dashboard)
- [Smashing Magazine: Mobile Navigation Design](https://www.smashingmagazine.com/2022/11/navigation-design-mobile-ux/)
- [SetProduct: Settings UI Design](https://www.setproduct.com/blog/settings-ui-design)
