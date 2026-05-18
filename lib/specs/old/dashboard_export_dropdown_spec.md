# Dashboard Export Dropdown — Single Tab-Aware Line

**Date:** 2026-05-13
**Status:** Complete
**Branch:** `feat/conversion-feedback`
**Depends on:** `spend_csv_export_spec.md` (Spend export must exist before the dropdown can target it) — shipped 2026-05-12

---

## Problem

The Export dropdown at `app/views/dashboard/show.html.erb:75–107` shows three lines regardless of which dashboard tab is active:

1. `Conversions CSV` — submits with default `export_type`
2. `Funnel CSV` — submits with `export_type=funnel`
3. `API Extract` waitlist button + "Coming soon" hint

The dashboard is tabbed (Conversions / Funnel / Spend / Events). The dropdown ignores the tab, so:

- On the Funnel tab, "Conversions CSV" is the prominent first option
- On the Spend tab, neither option matches what the user is looking at
- The "API Extract" waitlist row is becoming obsolete — `data_downloads_api_spec.md` covers the actual feature
- Three lines for what should be one decision: "download what I'm looking at"

## Solution

Collapse the dropdown to a single row labeled "Download CSV". A small Stimulus controller (`export_button_controller.js`) listens for tab-change events from the existing `toggle` controller (the one that drives the tabs at `show.html.erb:35–52`) and rewrites the form's `export_type` hidden field + the visible label based on the active tab.

When the active tab has no export (Events today), hide the button entirely — better than a disabled control that prompts "why can't I click this?"

### Tab → export mapping

| Active tab | Visible label | `export_type` submitted | State |
|---|---|---|---|
| Conversions | "Download CSV" | `conversions` | shipped |
| Funnel | "Download CSV" | `funnel` | shipped |
| Spend | "Download CSV" | `spend` | requires `spend_csv_export_spec.md` |
| Events | (button hidden) | — | no export exists |

Label stays "Download CSV" across tabs — the tab itself is context. No "Download Spend CSV" / "Download Conversions CSV" variation; the tab name above the button already tells the user what they're getting.

### Files

| File | Purpose | Change |
|------|---------|--------|
| `app/views/dashboard/show.html.erb` | Export dropdown markup | Replace lines 74–107: single button, single form, Stimulus-controlled hidden field. Drop "API Extract" row. |
| `app/javascript/controllers/export_button_controller.js` | Tab → export_type binding | **Create** — small controller, listens to `toggle:sync` event emitted by `toggle_controller.js`, updates hidden input + hides button on Events |
| `app/javascript/controllers/toggle_controller.js` | Tab switcher | No change — already emits `toggle:sync` events for cross-controller sync (see lines 47–51) |

### Why a new Stimulus controller (not extending `toggle`)

`toggle_controller.js` is generic show/hide + tabbed switching. Wiring "rewrite a form field based on the active value" into it would muddy its API. The new controller is ~25 lines, single responsibility: keep `<input name="export_type">` and button visibility in sync with the active dashboard tab.

Frontend Decision Tree in `GUIDE.md`: "Existing controller close? --> Extend it" — but extension would mean adding a `formField` target + per-target value mapping into `toggle`, which makes it less generic, not more. New controller is the right call.

### Why drop the "API Extract" waitlist row

It's a placeholder for the feature delivered by `data_downloads_api_spec.md`. When the API endpoints ship, the waitlist button has no destination. Removing it from this dropdown also de-clutters; the API is a separate surface (docs page, API keys page), not a CSV-style download. The `WaitlistButton` widget continues to live wherever else it's used.

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| One label, tab-derived target | Single "Download CSV" button | Removes cognitive load. The tab is the noun. |
| Hide on Events tab | Hide, not disable | Disabled controls invite "why can't I?" Hidden is cleaner. |
| New Stimulus controller | Yes (`export_button_controller`) | Single responsibility. Extending `toggle` would degrade its generality. |
| Drop API Extract row | Yes | Replaced by `data_downloads_api_spec.md`. Cluttering this dropdown serves no one. |
| Persist tab choice across sessions | Reuses `toggle` controller's existing `persist` value | Whatever tab the user last viewed, the button is already correct. |

## Acceptance Criteria

- [x] Export dropdown shows exactly one row: "Download CSV"
- [x] Submitting on Conversions tab POSTs with `export_type=conversions`
- [x] Submitting on Funnel tab POSTs with `export_type=funnel`
- [x] Submitting on Spend tab POSTs with `export_type=spend`
- [x] On the Events tab, the entire Export dropdown button is hidden (Stimulus toggles a `hidden` class on the trigger)
- [x] No "API Extract" / "Coming soon" row anywhere in the dropdown
- [x] Tab switching updates the hidden field without a page reload (Stimulus action chain `toggle#select export-button#tabSelected`)
- [x] All existing query params (date range, filters, channels, test mode) still pass through via `hidden_params_for(request.query_parameters.except("export_type"))` — `except` added so the hidden input is the only source for `export_type`
- [ ] System test (`test/system/dashboard_export_test.rb`) walks: switch tab → click Download → verify correct `export_type` reached the controller — **deferred**; no system tests exist in this codebase yet, scope would have to include setting up Selenium fixtures. Server-rendered HTML assertions in `Dashboard::ExportsControllerTest` cover the static state per tab; the JS click → input rewrite is the only thing not tested.

## Deviations from draft

- The view's pre-existing `active_tab` magic string array (`%w[conversions funnel spend events]`) was replaced with `DashboardTabs::ALL` — one less duplicate of the tab string list.
- Tab `data-value` attributes now reference `DashboardTabs::CONVERSIONS` / `FUNNEL` / `SPEND` / `EVENTS` directly in the ERB, eliminating magic strings in the markup.
- The form's `hidden_params_for(request.query_parameters)` was changed to `.except("export_type")` so the Stimulus-managed hidden input is the single source of truth for that param — otherwise a stale `export_type` from the URL would round-trip back into the submitted form.

## Out of Scope

- Renaming "Export" to something else (the trigger button label stays as is for now)
- A "download as JSON" option (covered by the API spec — different surface)
- Per-tab format options (PDF, Excel, etc.) — single format keeps the affordance honest
- Touching `WaitlistButton` elsewhere — it stays where it's used outside this dropdown

## Dependencies

`spend_csv_export_spec.md` ships first. Without it, the Spend tab can't be a valid target and we'd have to either ship-with-Spend-hidden or stub a 422.
