# Fix: Filters on Funnel Tab Redirect to Conversions Tab

**Date:** 2026-01-29
**Status:** Draft
**Branch:** `feature/funnel-filter-redirect`

## Problem

When a user is viewing the Funnel tab on the dashboard and applies filters (date range, channels, etc.), the page redirects to the Conversions tab instead of staying on the Funnel tab. The filter form always submits to `dashboard_path` with `data-turbo-frame="_top"`, which triggers a full page navigation and resets the tab to its default ("conversions").

**Who's affected:** Any user trying to filter funnel data — they lose context every time they apply filters.

## Current State

The dashboard uses a client-side tab system (`toggle_controller.js`) to switch between Conversions, Funnel, and Events tabs. Tab state is managed purely in JavaScript with localStorage persistence — it is **not** reflected in the URL.

The shared filter form lives in `app/views/dashboard/filters/show.html.erb`:

```erb
<form action="<%= dashboard_path %>" method="get" data-turbo-frame="_top">
```

**Line 3** hardcodes the form action to `dashboard_path` and `_top` forces a full page navigation. When the page reloads, the toggle controller initializes with its default value of `"conversions"` (from `data-toggle-default-value="conversions"` on `app/views/dashboard/show.html.erb:13`).

### Why localStorage doesn't save it

The toggle controller does fall back to `loadPreference()` on connect, but the `persist` value is not set on the dashboard toggle controller — there's no `data-toggle-persist-value` attribute. So tab selection is lost on every full page load.

### Data Flow (Current)

```
1. User clicks Funnel tab → toggle controller shows funnel content (client-side only)
2. User opens Filters → turbo frame loads filter form
3. User clicks Apply → form submits GET to /dashboard with data-turbo-frame="_top"
4. Full page reload → toggle controller initializes with default "conversions"
5. User is now on Conversions tab with filters applied
```

## Solution

Pass the active tab as a URL parameter (`tab`) so the filter form preserves it across submissions. This keeps the solution server-aware without adding JavaScript complexity.

### Data Flow (Proposed)

```
1. User clicks Funnel tab → toggle controller shows funnel content + updates URL param ?tab=funnel
2. User opens Filters → turbo frame loads filter form (inherits URL params)
3. Filter form includes hidden field for tab param
4. User clicks Apply → form submits GET to /dashboard?tab=funnel&date_range=30d&...
5. Page loads → toggle controller reads default from server-rendered value → shows Funnel tab
```

### Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `app/views/dashboard/show.html.erb` | Dashboard with tab container | Set `data-toggle-default-value` from `params[:tab]` instead of hardcoded `"conversions"` |
| `app/views/dashboard/filters/show.html.erb` | Filter form | Add hidden field for `tab` param |
| `app/javascript/controllers/toggle_controller.js` | Tab switching | Add URL param update on tab select (optional, for consistency) |

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| How to persist tab state | URL `tab` param | Works with form submissions, bookmarkable, no JS state management needed |
| Update toggle controller? | Yes — update URL on tab switch | Ensures tab param stays in sync even before filters are opened |
| Default tab when no param | `"conversions"` | Backwards compatible — existing links/bookmarks keep working |

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| No tab param | First visit, old bookmarks | Default to Conversions tab (current behavior) |
| `?tab=funnel` | After clicking Funnel tab or filtering on Funnel | Show Funnel tab, funnel turbo frame loads |
| `?tab=events` | After clicking Events tab or filtering on Events | Show Events tab, events content loads |
| `?tab=conversions` | Explicit or after filtering on Conversions | Show Conversions tab |
| Invalid tab param | `?tab=bogus` | Fall back to `"conversions"` |
| Tab switch without filters | Click a tab | URL updates to `?tab=<value>`, no page reload |
| Filter apply on Funnel | Apply filters while on Funnel tab | Stays on Funnel tab, filters applied to all data |

## Acceptance Criteria

- [ ] Applying filters on the Funnel tab keeps the user on the Funnel tab
- [ ] Applying filters on the Events tab keeps the user on the Events tab
- [ ] Applying filters on the Conversions tab continues to work as before
- [ ] Clicking a tab updates the URL `tab` param without a page reload
- [ ] Direct navigation to `/dashboard?tab=funnel` opens the Funnel tab
- [ ] `/dashboard` with no `tab` param defaults to Conversions (backwards compatible)
- [ ] Invalid `tab` values fall back to Conversions

## Implementation Tasks

### Phase 1: Server-side tab awareness

- [ ] **1.1** In `app/views/dashboard/show.html.erb`, set `data-toggle-default-value` dynamically from `params[:tab]` with fallback to `"conversions"`
- [ ] **1.2** In `app/views/dashboard/filters/show.html.erb`, add a hidden field that passes the current `tab` param through the filter form
- [ ] **1.3** Write system test: apply filters on Funnel tab → verify user stays on Funnel tab

### Phase 2: Client-side URL sync

- [ ] **2.1** In `toggle_controller.js`, update the URL `tab` param on tab switch (using `history.replaceState` — no page reload)
- [ ] **2.2** Ensure the filter turbo frame `src` picks up the updated URL params so newly-opened filters include `tab`

## Testing Strategy

### System Tests

| Test | Verifies |
|------|----------|
| Filter on Funnel tab stays on Funnel | Core bug fix — tab param persists through filter submit |
| Filter on Events tab stays on Events | Same fix works for all tabs |
| Direct URL with `?tab=funnel` opens Funnel | Server-side default value works |
| Tab click updates URL param | Client-side sync works |

### Manual QA

1. Navigate to dashboard
2. Click Funnel tab
3. Open Filters, change date range to "Last 90 Days"
4. Click Apply
5. Verify Funnel tab is still active with updated data
6. Repeat for Events tab

## Out of Scope

- Changing the tab system to use URL-based routing (e.g., separate routes per tab) — that's a larger refactor
- Persisting other UI state (e.g., CLV mode toggle, log scale checkbox) through filter submissions
- Adding `tab` to the toggle controller's localStorage persistence — URL param is sufficient
