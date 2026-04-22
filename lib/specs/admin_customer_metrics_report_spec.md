# Admin Customer Metrics Report Specification

**Date:** 2026-04-23
**Priority:** P1
**Status:** Ready
**Branch:** `feature/session-bot-detection`

---

## Summary

Right now there is no single page that answers "how is each customer doing?" Admins have to bounce between Stripe, the events table, and the onboarding view to assemble even the basics. This spec adds an admin-only `Customer Metrics` report: one row per account, columns for the SaaS basics that matter at a glance — sign-up date, LTV, MRR, record volumes, login activity, subscription tenure, churn date, and time-to-value milestones. The data is derived from existing tables plus three small denormalised columns for the values that are too expensive to compute on the fly.

---

## Current State

### What Exists

| Surface | Location | Notes |
|---------|----------|-------|
| Admin namespace | `app/controllers/admin/base_controller.rb` | Already enforces `require_admin` and `skip_marketing_analytics` |
| Admin routes | `config/routes.rb` `namespace :admin` | `accounts`, `billing`, `submissions`, `data_integrity` |
| Account billing concern | `app/models/concerns/account/billing.rb` | Plan, billing_status, subscription dates, usage helpers |
| Account onboarding concern | `app/models/concerns/account/onboarding.rb` | `activated_at`, `onboarding_completed_at`, `onboarding_progress` |
| `accounts.cancelled_at` | `db/schema.rb` accounts table | Already exists — use directly for churn date |
| Events table | TimescaleDB hypertable `events` | `is_test` flag, `account_id`, `occurred_at` |
| Plans table | `app/models/plan.rb` | `monthly_price_cents`, `monthly_price` helper |
| Ad platform connections | `ad_platform_connections` | Per-account integration count |

### What's Missing

| Need | Today | Action |
|------|-------|--------|
| Admin customer metrics view | Doesn't exist | Build |
| User login tracking | `users` table has only `email`, `password_digest`, `is_admin` | Add `last_sign_in_at` (datetime) + `sign_in_count` (integer) |
| LTV per account | Locked in Stripe payloads inside `billing_events.payload` JSONB | Add `accounts.lifetime_value_cents` (bigint, default 0); see lifecycle spec Phase 3 |

---

## Proposed Solution

### Architecture

```
GET /admin/customer_metrics
  → Admin::CustomerMetricsController#index
    → Admin::CustomerMetricsQuery.new(scope_params).call
      → returns Array<CustomerMetricsRow>  (Data.define struct, one per account)
        → Rendered in app/views/admin/customer_metrics/index.html.erb (sortable table)
        → CSV export at /admin/customer_metrics.csv via the same query
```

`Admin::CustomerMetricsQuery` is a **query object**, not an `ApplicationService` — it returns domain rows, not success/fail. Per CLAUDE.md service-object guidance, query objects skip ApplicationService.

### Key Files

| File | Purpose | Change |
|------|---------|--------|
| `db/migrate/{ts}_add_login_tracking_to_users.rb` | Adds `last_sign_in_at`, `sign_in_count` | New |
| `db/migrate/{ts}_add_lifetime_value_to_accounts.rb` | Adds `lifetime_value_cents` | New (also referenced by lifecycle spec) |
| `app/controllers/sessions_controller.rb` | Bump login counters on successful login | Edit |
| `app/services/billing/handlers/invoice_paid.rb` | Increment `lifetime_value_cents` on every paid invoice | Edit |
| `app/controllers/admin/customer_metrics_controller.rb` | Index + CSV | New |
| `app/services/admin/customer_metrics_query.rb` | Computes all per-account metrics | New |
| `app/services/admin/customer_metrics_row.rb` | `Data.define` struct for one row | New |
| `app/views/admin/customer_metrics/index.html.erb` | Sortable HTML table | New |
| `app/views/layouts/admin.html.erb` (or existing nav partial) | Add nav link | Edit |
| `config/routes.rb` | `resources :customer_metrics, only: [:index]` inside admin | Edit |
| `test/services/admin/customer_metrics_query_test.rb` | Query correctness | New |
| `test/controllers/admin/customer_metrics_controller_test.rb` | Auth + render + CSV | New |
| `test/controllers/sessions_controller_test.rb` | Login counter bumped | Edit |

### Why Denormalise LTV and Login Counts?

- **LTV from JSONB is slow.** `billing_events.payload->'data'->'object'->>'amount_paid'` aggregated across all accounts on every page load is wasteful. The Stripe webhook handler is already the single write path — increment a column there for ~constant cost.
- **Login counts from a `user_sessions` table is overkill** for what we need (count + last). Two columns on `users` matches Devise convention and is one update per login.
- **Source of truth stays correct:** Stripe is canonical for revenue (we can rebuild the column from `billing_events`); login activity is intrinsically user-facing state.

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Admin views report | `current_user.admin?` | Renders sortable table of all accounts |
| Non-admin tries to view | `current_user.admin?` false | Redirected by `Admin::BaseController#require_admin` |
| Logged-out tries to view | No session | Redirected by `require_login` |
| Account has no plan | `plan_id IS NULL` | Plan column shows "Free" / "—"; MRR = $0 |
| Account never paid | `lifetime_value_cents = 0` | LTV column shows "$0.00" |
| Account has no events | `count = 0` | Total records column shows 0; avg monthly = 0 |
| Account is < 1 month old | `created_at > 30.days.ago` | Avg monthly records uses fractional month (clamped to ≥1 to avoid divide-by-zero) |
| Account is cancelled | `cancelled_at IS NOT NULL` | Churn date shown; active subscription months calculated to `cancelled_at` |
| Account has zero users | Edge case | User count = 0; login count = 0 |
| Empty result set | No accounts | "No accounts to display" empty state |
| CSV export | `format: :csv` | Same data streamed via existing CSV pattern (use `Dashboard::CsvExportService` style) |

---

## Columns

| # | Column | Source | Notes |
|---|--------|--------|-------|
| 1 | Account | `accounts.name` + `prefix_id` | Linked to `admin_account_path` |
| 2 | Plan | `accounts.plan&.name` | "Free" if nil |
| 3 | Billing status | `accounts.billing_status` enum | Humanised |
| 4 | Sign up date | `accounts.created_at` | Date only |
| 5 | LTV | `accounts.lifetime_value_cents / 100.0` | Formatted as currency |
| 6 | MRR | `plan.monthly_price` if `billing_status` ∈ {trialing, active}, else `0` | Per-row method |
| 7 | Has test records | `EXISTS(events WHERE account_id=… AND is_test=true)` | Boolean |
| 8 | Total prod records | `COUNT(events WHERE account_id=… AND is_test=false)` | Integer |
| 9 | Avg monthly records | `total_prod_records / months_since_signup` (≥1) | Rounded |
| 10 | User count | `account_memberships.accepted` count | Integer |
| 11 | User login count | `SUM(users.sign_in_count)` across memberships | Integer |
| 12 | Avg monthly logins | `user_login_count / months_since_signup` (≥1) | Rounded |
| 13 | Active subscription months | `(end - subscription_started_at)` in months where `end = cancelled_at || now` | Integer |
| 14 | Churn date | `accounts.cancelled_at` | Date or "—" |
| 15 | Days to activation | `activated_at - created_at` | Integer or "—" |
| 16 | Days to first payment | First `BillingEvent.event_type = "invoice.payment_succeeded"` `created_at - accounts.created_at` | Integer or "—" |
| 17 | Onboarding % | `accounts.onboarding_progress` mapped via `Account::Onboarding` | Percentage |
| 18 | Last login at | `MAX(users.last_sign_in_at)` across memberships | Datetime or "—" |
| 19 | Last event at | `MAX(events.occurred_at WHERE account_id=…)` | Datetime or "—" |
| 20 | Connected integrations | `account.ad_platform_connections.count` | Integer |

`months_since_signup` is `[(Time.current - account.created_at) / 30.days, 1.0].max`.

### Sorting

- Default sort: `accounts.created_at DESC` (newest first)
- Sortable columns: 1, 4, 5, 6, 8, 13, 14, 18, 19 (the numeric/temporal ones that ship from Postgres without re-aggregation)
- Non-sortable for v1: derived columns (avg monthly, days-to-X) — we can sort client-side later if needed

### Performance Plan

- Single base query: `Account.includes(:plan).order(...)`
- Per-row scalar lookups: prod event count, has-test predicate, login aggregates, ad platform count, last event timestamp — done in batched queries (`pluck`/`group(:account_id).count`) before assembling rows, **not** N+1 in the view
- For < ~1k accounts the report renders in well under a second. Past that, add a daily `account_metrics_snapshots` materialised view refreshed by a cron job. **Not** built in v1.
- Cache the rendered HTML for 5 minutes via `expires_in` on the controller (admin-only, low traffic)

---

## Sensitive Routes

`/admin/customer_metrics` (and `.csv`) renders cross-account data — **sensitive**. `Admin::BaseController` already declares `skip_marketing_analytics`, so the new controller inherits it. No additional path patterns needed in `app/constants/sensitive_paths.rb` (admin paths are already covered by the deny-list).

---

## Implementation Tasks

### Phase 1: Schema

- [ ] **1.1** Migration: `add_login_tracking_to_users` adding `last_sign_in_at:datetime` and `sign_in_count:integer default 0 null false`
- [ ] **1.2** Migration: `add_lifetime_value_to_accounts` adding `lifetime_value_cents:bigint default 0 null false`
- [ ] **1.3** Update `db/schema.rb` (no TimescaleDB calls touched — these are vanilla PG)
- [ ] **1.4** Update fixtures if required to keep tests green

### Phase 2: Tracking Hooks

- [ ] **2.1** `SessionsController#create` increments `sign_in_count` and sets `last_sign_in_at` on successful login (single `update!` after the existing `Mbuzz` calls)
- [ ] **2.2** `Billing::Handlers::InvoicePaid` increments `accounts.lifetime_value_cents` by `event_object[:amount_paid]` before `track_payment`
- [ ] **2.3** Tests: sessions controller test asserts counters bump; invoice_paid handler test asserts LTV increment

### Phase 3: Query Object

- [ ] **3.1** `app/services/admin/customer_metrics_row.rb` — `Data.define` struct with all 20 fields
- [ ] **3.2** `app/services/admin/customer_metrics_query.rb` — `#initialize(sort:, direction:)`, `#call` returning `Array<CustomerMetricsRow>`
- [ ] **3.3** Implement batched per-row aggregates (avoid N+1)
- [ ] **3.4** Tests: cross-account isolation, empty result, account with zero events, churned account, freshly signed-up account

### Phase 4: Controller + View

- [ ] **4.1** Route: `resources :customer_metrics, only: [:index]` inside `namespace :admin`
- [ ] **4.2** `Admin::CustomerMetricsController#index` — thin, delegates to query object, supports `format.html` and `format.csv`
- [ ] **4.3** `app/views/admin/customer_metrics/index.html.erb` — sortable table using existing admin styling
- [ ] **4.4** Add nav link from existing admin layout/sidebar
- [ ] **4.5** Tests: auth (admin redirects non-admins), HTML render, CSV render, sort param applied

### Phase 5: Polish

- [ ] **5.1** Empty state copy
- [ ] **5.2** 5-minute HTML cache via `expires_in`
- [ ] **5.3** Manual QA on dev with fixture data and a real cancelled account
- [ ] **5.4** Update `lib/docs/BUSINESS_RULES.md` if any user-facing behaviour changed (likely not — admin-only)

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Query returns one row per account | `test/services/admin/customer_metrics_query_test.rb` | Row count == account count |
| Cross-account isolation | same | Account A's events never count for Account B |
| Churned account fields populated | same | `cancelled_at` → churn date, active months capped |
| Zero-event account | same | Records = 0, avg = 0, has_test = false |
| LTV reflects denormalised counter | same | `accounts.lifetime_value_cents` drives column |
| Login aggregates sum across memberships | same | Two members → `sign_in_count` summed |
| Sessions controller bumps counters | `test/controllers/sessions_controller_test.rb` | `sign_in_count` +1 and `last_sign_in_at` updated |
| InvoicePaid increments LTV | `test/services/billing/handlers/invoice_paid_test.rb` | `lifetime_value_cents += amount_paid` |
| Non-admin rejected | `test/controllers/admin/customer_metrics_controller_test.rb` | Redirect to root |
| Admin sees report | same | 200 OK, table rendered |
| CSV export works | same | Content-Type `text/csv`, rows present |

### Manual QA

1. As an admin, visit `/admin/customer_metrics` — confirm table renders with all columns.
2. Sort by LTV descending — confirm order.
3. Export CSV — confirm download with same data.
4. As a non-admin, visit `/admin/customer_metrics` — confirm redirect.
5. Cancel a test account in Stripe sandbox — confirm churn date populates after webhook processed.
6. Have a test account log in — confirm login count increments.

---

## Definition of Done

- [ ] All migrations applied (dev + production-ready)
- [ ] All implementation phases complete
- [ ] All tests pass (`bin/rails test`)
- [ ] Manual QA on dev passes
- [ ] Admin nav links to the report
- [ ] Spec updated with any deviations and moved to `lib/specs/old/`

---

## Out of Scope

- Per-customer drill-down view (use existing `admin/accounts#show`)
- Cohort analysis / retention curves (use existing dashboard cohort report)
- Real-time updates (5-minute cache is fine for admin reporting)
- MRR forecasting / pipeline metrics (future)
- Materialised view / snapshot table (only if performance demands it; defer)
- Slack/email alerts on churn (future — natural extension once `billing_cancelled` lifecycle event ships)
