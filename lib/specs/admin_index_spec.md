# Admin Index Page

**Date:** 2026-05-11
**Status:** Draft
**Branch:** `feat/conversion-feedback` (lands alongside Phase 7 of conversion feedback)

## Problem

Today `GET /admin` returns a routing error. Operators reach admin tools by typing remembered URLs (`/admin/feature_flags`, `/admin/submissions`) or by reading `config/routes.rb`. Conversion feedback (`conversion_feedback_spec.md` Phase 7) is about to add another admin surface (`/admin/conversion_dispatches`), making the "you can't find what's there" cost worse. A single landing page that lists every admin tool with a one-line description fixes this and creates the natural home for future admin surfaces.

## Solution

Add `Admin::DashboardController#index` mounted at `/admin`. Renders a server-rendered HTML list (no Turbo Frames, no Stimulus — pure links) of every admin destination, grouped by category.

The list of tools lives in `app/constants/admin_tools.rb` as a frozen array of `Data.define` structs (category, name, path, description). Mirrors the `SdkRegistry` and `AdPlatforms::Registry` patterns already established in the codebase. New admin tools register by adding one line; no controller changes needed.

The controller is one line: `def index; @tools = AdminTools.all; end`. The view groups by category and renders each tool as a card with a heading, description, and link.

`Admin::BaseController` already declares `skip_marketing_analytics` and `require_admin`. Inheriting picks both up for free.

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| Where the list lives | `app/constants/admin_tools.rb` as `Data.define` structs | Matches `SdkRegistry` / `AdPlatforms::Registry`. Explicit, greppable, intentional descriptions per tool. |
| Auto-discovery vs explicit registration | Explicit registration | Auto-discovering from `routes.rb` would pull in non-admin-tool routes (e.g. SolidErrors engine sub-paths) and miss descriptions. Explicit list stays curated. |
| Grouping | Three categories: **Customer support** (Accounts, Billing, Submissions), **Platform operations** (Feature Flags, Conversion Dispatches), **Diagnostics** (Customer Metrics, Data Integrity, Errors) | Today's tools fit cleanly. Add more categories when needed; the registry struct already has the field. |
| External engines (SolidErrors) | List as a regular tool with `path: "/admin/errors"` | Engines mount where they mount; the index doesn't care. |
| Layout | Reuse the existing admin layout (whatever `Admin::SubmissionsController#index` renders into) | No new Tailwind component clusters. |

## Acceptance Criteria

- [ ] `GET /admin` renders the index page (200, HTML)
- [ ] Non-admin users redirect to root with "Access denied" flash (inherited from `Admin::BaseController#require_admin`)
- [ ] Every admin tool currently in `config/routes.rb` under `namespace :admin` appears in the list with a working link
- [ ] Adding a new entry to `AdminTools::ALL` causes it to appear on `/admin` without controller or view changes (test asserts this — a fixture entry shows up)
- [ ] Tools are grouped by category in the rendered output
- [ ] `skip_marketing_analytics` declared (verified via `BaseController` inheritance test or path-pattern test)
- [ ] Test: every linked path resolves to a real route (uses `Rails.application.routes.recognize_path` per entry)

## Tools to List (initial set)

| Category | Name | Path | Description |
|---|---|---|---|
| Customer support | Accounts | `/admin/accounts/:id` (linked via search later) | View and update account records |
| Customer support | Submissions | `/admin/submissions` | Inbound form submissions across accounts |
| Customer support | Billing | `/admin/billing` | Billing summary and usage |
| Platform operations | Feature Flags | `/admin/feature_flags` | Toggle features per account |
| Platform operations | Conversion Dispatches | `/admin/conversion_dispatches` | Conversion-feedback dispatches to Meta CAPI + Google EC (see `conversion_feedback_spec.md` Phase 7) |
| Diagnostics | Customer Metrics | `/admin/customer_metrics` | Aggregate platform usage and trends |
| Diagnostics | Data Integrity | `/admin/data_integrity` | Data integrity checks across accounts |
| Diagnostics | Errors | `/admin/errors` | Recent server errors (SolidErrors UI) |

Accounts index doesn't exist as a list page today (only `show`/`update`). The admin index entry links to a future `Admin::AccountsController#index` — out of scope for this spec; the entry can either be omitted or link to a deferred-build placeholder. Decision: omit the Accounts entry until an index action exists.

## Implementation Tasks

1. Create `app/constants/admin_tools.rb` — `Data.define(:category, :name, :path, :description)`, frozen array constant `ALL`, helper `AdminTools.grouped` returning `{ category => [tool, …] }`.
2. Create `Admin::DashboardController < Admin::BaseController` with `index` action.
3. Add route: `root to: "dashboard#index"` inside `namespace :admin`.
4. Create `app/views/admin/dashboard/index.html.erb` — Tailwind cards grouped by category.
5. Tests:
   - `test/controllers/admin/dashboard_controller_test.rb` — admin sees the page, non-admin redirects, every `AdminTools::ALL` entry's path resolves via `Rails.application.routes.recognize_path`.
   - `test/constants/admin_tools_test.rb` — `.grouped` returns the right shape.

## Testing Strategy

### Unit

| Test | File | Verifies |
|---|---|---|
| `AdminTools.grouped` returns category → tools hash | `test/constants/admin_tools_test.rb` | Group keys match registered categories |
| Every registered path resolves to a real route | `test/constants/admin_tools_test.rb` | `Rails.application.routes.recognize_path(tool.path, method: :get)` does not raise |

### Controller

| Test | File | Verifies |
|---|---|---|
| Admin sees the index | `test/controllers/admin/dashboard_controller_test.rb` | 200, body includes each tool name |
| Non-admin redirects | same | 302 to root, "Access denied" flash |
| `skip_marketing_analytics` declared | same | `Admin::DashboardController._skip_marketing_analytics` truthy (or path-pattern check) |

### Manual QA

1. Sign in as admin, navigate to `/admin` — see categorised cards.
2. Click each link — every one lands on the expected page.
3. Sign in as a non-admin — `/admin` redirects.

## Definition of Done

- [ ] `GET /admin` renders the index
- [ ] All current admin tools listed
- [ ] All linked paths resolve
- [ ] Tests pass
- [ ] `conversion_feedback_spec.md` Phase 7.6 (registering Conversion Dispatches) checked off after that spec ships its controller
- [ ] Spec moved to `lib/specs/old/` once stable for 7 days

## Out of Scope

- Per-tool permissions (today everything is `require_admin` — that's enough).
- Search across admin tools.
- Live counts on cards ("23 errors this hour"). Per-page enhancements when each page warrants it.
- A top-nav admin breadcrumb. Each admin page already links back via the existing layout.
- An admin section on the marketing site. This is internal-operator UI.
