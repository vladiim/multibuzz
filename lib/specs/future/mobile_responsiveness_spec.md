# Mobile Responsiveness Spec

## Overview

Comprehensive fixes to make the application mobile-friendly. Currently, many views have fixed widths, non-responsive grids, and layout issues that break on screens < 768px.

---

## Priority 1: Account Navigation (Critical)

### Problem

The account settings pages use a fixed `w-48` (192px) sidebar that consumes 51% of viewport on mobile (375px), leaving only ~183px for content.

**Affected Files:**
- `app/views/layouts/_account_nav.html.erb`
- `app/views/account/show.html.erb`
- `app/views/accounts/billing/show.html.erb`
- `app/views/accounts/team/show.html.erb`
- `app/views/accounts/api_keys/index.html.erb`
- `app/views/accounts/attribution_models/index.html.erb`

### Solution: Horizontal Tabs on Mobile

```
Mobile (< 768px):
┌─ General | Billing | Team | API | Attr... ─┐  (scrollable)
├────────────────────────────────────────────┤
│ Page content (full width)                  │
└────────────────────────────────────────────┘

Desktop (>= 768px):
┌──────────────┬─────────────────────────────┐
│ General      │ Page content                │
│ Billing      │                             │
│ Team         │                             │
│ API Keys     │                             │
│ Attribution  │                             │
└──────────────┴─────────────────────────────┘
```

### Implementation

1. **Update `_account_nav.html.erb`:**
   - Add `hidden md:flex` to hide sidebar on mobile
   - Keep existing sidebar structure for desktop

2. **Create `_account_nav_tabs.html.erb`:**
   - Horizontal scrollable tabs for mobile
   - Use `md:hidden` to show only on mobile
   - Active tab indicator based on `current_page?`

3. **Update all account page layouts:**
   - Change `flex gap-8` to `flex flex-col md:flex-row gap-4 md:gap-8`
   - Render both nav components (tabs + sidebar)

---

## Priority 2: Dashboard Filters (Critical)

### Problem

Dashboard filters use fixed widths (`w-36`, `w-48`, `w-44`) that overflow on mobile.

**File:** `app/views/dashboard/filters/show.html.erb`

### Changes

| Line | Current | Change To |
|------|---------|-----------|
| 3 | `flex flex-wrap gap-4` | `grid grid-cols-1 sm:grid-cols-2 lg:flex lg:flex-wrap gap-4` |
| 15 | `w-36` (Date Range) | `w-full sm:w-36` |
| 44 | `w-48` (Attribution) | `w-full sm:w-48` |
| 101 | `w-44` (Channels) | `w-full sm:w-44` |

---

## Priority 3: Conversion Filters Dropdown (Critical)

### Problem

Dropdown has `min-w-[480px]` which overflows mobile screens.

**File:** `app/views/dashboard/conversion_filters/_conversion_filters.html.erb`

### Changes

| Line | Current | Change To |
|------|---------|-----------|
| 8 | `w-44` | `w-full sm:w-44` |
| 15 | `min-w-[480px]` | `w-[calc(100vw-2rem)] sm:w-[480px]` |

**File:** `app/views/dashboard/conversion_filters/_filter_row.html.erb`

| Line | Current | Change To |
|------|---------|-----------|
| 1 | `flex items-center gap-2` | `grid grid-cols-1 sm:flex sm:items-center gap-2` |
| 8 | `w-36` | `w-full sm:w-36` |
| 17 | `w-24` | `w-full sm:w-24` |

---

## Priority 4: Event Panel (Critical)

### Problem

Side panel has fixed `w-96` (384px) which exceeds mobile viewport (375px).

**File:** `app/views/dashboard/show.html.erb`

### Change

| Line | Current | Change To |
|------|---------|-----------|
| 195 | `w-96` | `w-full sm:w-96` |

---

## Priority 5: Dashboard Grids

### Problem

KPI card grids use `grid-cols-2` without single-column mobile breakpoint.

### Changes

**File:** `app/views/dashboard/conversions/_full_dashboard.html.erb`

| Line | Current | Change To |
|------|---------|-----------|
| 7 | `grid-cols-2 lg:grid-cols-3` | `grid-cols-1 sm:grid-cols-2 lg:grid-cols-3` |

**File:** `app/views/dashboard/conversions/_clv_kpi_cards.html.erb`

| Line | Current | Change To |
|------|---------|-----------|
| 15 | `grid-cols-2 lg:grid-cols-3` | `grid-cols-1 sm:grid-cols-2 lg:grid-cols-3` |

**File:** `app/views/dashboard/conversions/show.html.erb`

| Line | Current | Change To |
|------|---------|-----------|
| 10 | `grid grid-cols-2 gap-6` | `grid grid-cols-1 lg:grid-cols-2 gap-6` |

---

## Priority 6: Dashboard Tabs

### Problem

Tab navigation has tight spacing that causes overflow on mobile.

**File:** `app/views/dashboard/show.html.erb`

### Changes

| Line | Current | Change To |
|------|---------|-----------|
| 21 | `gap-6` | `gap-2 sm:gap-6` |
| 23+ | `text-sm` on tabs | `text-xs sm:text-sm` |
| ~40 | Filter/Export buttons `flex items-center gap-2` | `flex items-center gap-1 sm:gap-2` |

---

## Priority 7: Chart Heights

### Problem

Charts use fixed heights that don't adapt to mobile.

### Changes

Apply responsive heights pattern: `h-48 sm:h-64 lg:h-80`

| File | Line | Current | Change To |
|------|------|---------|-----------|
| `_dashboard_panel.html.erb` | 69 | `h-48` | `h-40 sm:h-48` |
| `_dashboard_panel.html.erb` | 94 | `h-56` | `h-48 sm:h-56` |
| `_full_dashboard.html.erb` | 66 | `h-72` | `h-56 sm:h-72` |
| `_full_dashboard.html.erb` | 112 | `h-80` | `h-64 sm:h-80` |
| `_clv_dashboard.html.erb` | 22 | `h-80` | `h-64 sm:h-80` |
| `_clv_dashboard.html.erb` | 50 | `h-72` | `h-56 sm:h-72` |
| `funnel/show.html.erb` | 55 | `h-96` | `h-64 sm:h-80 lg:h-96` |

---

## Priority 8: Tables (Medium)

### Problem

Tables have no overflow handling, causing horizontal scroll issues.

### Solution

Wrap all tables in `overflow-x-auto` container.

**Files to update:**
- `app/views/accounts/api_keys/index.html.erb` - API Keys table
- `app/views/accounts/team/show.html.erb` - Team members table
- `app/views/accounts/attribution_models/index.html.erb` - Attribution models table

### Pattern

```erb
<div class="overflow-x-auto">
  <table class="min-w-full ...">
    ...
  </table>
</div>
```

---

## Priority 9: Team Invite Form

### Problem

Horizontal form layout overflows on mobile.

**File:** `app/views/accounts/team/_invite_form.html.erb`

### Change

| Line | Current | Change To |
|------|---------|-----------|
| 2 | `flex gap-4 items-end` | `flex flex-col sm:flex-row gap-4 sm:items-end` |

Also update the email input and role select to be full width on mobile.

---

## Priority 10: Attribution Model Buttons

### Problem

Multiple action buttons overflow horizontally on mobile.

**File:** `app/views/accounts/attribution_models/index.html.erb`

### Change

Button container should use flex-wrap:

```erb
<div class="flex flex-wrap items-center gap-2">
  <!-- buttons -->
</div>
```

---

## Priority 11: Event Cards

### Problem

Event card layout is cramped on mobile.

**File:** `app/views/dashboard/live_events/_event_card.html.erb`

### Change

| Line | Current | Change To |
|------|---------|-----------|
| 5 | `flex items-center justify-between` | `flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2` |

---

## Priority 12: Funnel Stage Cards

### Problem

Horizontal scroll with fixed-width cards is poor UX on mobile.

**File:** `app/views/dashboard/funnel/show.html.erb`

### Change

| Line | Current | Change To |
|------|---------|-----------|
| 27 | `flex gap-2 mb-6 overflow-x-auto` | `grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2 mb-6` |

Remove `min-w-[140px]` and `flex-shrink-0` from individual cards.

---

## Priority 13: Navigation Account Name

### Problem

Long account names can overflow in the navigation dropdown.

**File:** `app/views/layouts/_nav.html.erb`

### Change

Add truncate class to account name:

```erb
<span class="font-medium truncate max-w-[120px]"><%= current_account.name %></span>
```

---

## Priority 14: Marketing Pages (Low)

### Pricing Table

**File:** `app/views/pages/home/_pricing.html.erb`

- Reduce cell padding on mobile: `px-2 sm:px-6`
- Consider card layout for mobile (future enhancement)

### Comparison Table

**File:** `app/views/pages/home/_comparison.html.erb`

- Reduce cell padding on mobile: `px-2 sm:px-6`
- Ensure `overflow-x-auto` wrapper is present

---

## Testing Checklist

Test on these viewport widths:
- [ ] 320px (iPhone SE, small Android)
- [ ] 375px (iPhone 12/13/14)
- [ ] 390px (iPhone 14 Pro)
- [ ] 428px (iPhone 14 Pro Max)
- [ ] 768px (iPad portrait)
- [ ] 1024px (iPad landscape / small laptop)

Key flows to test:
- [ ] Account settings navigation (all 5 pages)
- [ ] Dashboard with filters applied
- [ ] Conversion filters dropdown
- [ ] Event panel slide-out
- [ ] API key management
- [ ] Team member management
- [ ] Attribution model management
- [ ] Billing page and upgrade flow

---

## Implementation Order

1. **Account Navigation** - Highest impact, affects all account pages
2. **Dashboard Filters** - Core user flow
3. **Event Panel** - Critical overflow fix
4. **Dashboard Grids** - Quick wins
5. **Tables** - Add overflow wrappers
6. **Forms** - Stack on mobile
7. **Marketing pages** - Lower priority
