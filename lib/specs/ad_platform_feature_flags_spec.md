# Ad Platform Feature Flags

**Date:** 2026-04-28
**Priority:** P1
**Status:** Drafting — awaiting approval to begin TDD
**Branch:** `feature/ad-platforms-meta-linkedin-rollout`
**Parent spec:** `lib/specs/ad_platforms_meta_linkedin_rollout_spec.md` (Phase 1)

---

## Summary

Generic per-account allowlist for beta features, used first to gate Meta Ads and LinkedIn Ads integrations behind explicit opt-in. Same mechanism is reusable for any future beta feature (scenario modeling, custom attribution models, etc.). Account-scoped, queryable, audit-friendly. Admin-only flip via UI or rake task. No usage gates wired in this phase — Phase 2 (Meta) and Phase 3 (LinkedIn) consume the predicate.

---

## Current State

- No feature-flag mechanism exists in the codebase. No Flipper, no `Account::FeatureFlags`, no allowlist column.
- `Account` concerns: `Validations`, `Relationships`, `StatusManagement`, `Billing`, `Callbacks`, `Onboarding` (`app/models/account.rb:5-10`).
- Admin namespace exists with `Admin::BaseController` enforcing `require_admin` (`app/controllers/admin/base_controller.rb`). Existing admin pages: `accounts`, `billing`, `customer_metrics`, `data_integrity`, `submissions`.

---

## Design

### Storage — dedicated table

```ruby
create_table :account_feature_flags do |t|
  t.references :account, null: false, foreign_key: true, index: true
  t.string :flag_name, null: false
  t.timestamps
end
add_index :account_feature_flags, [:account_id, :flag_name], unique: true
add_index :account_feature_flags, :flag_name
```

Why a table over a JSONB column on `accounts`:
- Queryable: `Account.joins(:feature_flags).where(account_feature_flags: { flag_name: "meta_ads_integration" })` — answer "who has Meta enabled?" trivially.
- Audit trail via `created_at` (and optional `enabled_by_id` later if we need attribution).
- Indexable both ways.
- Cleaner deletes — `disable_feature!` is a single `delete_all`, no JSONB merge.

### Model — `AccountFeatureFlag`

```ruby
class AccountFeatureFlag < ApplicationRecord
  belongs_to :account
  validates :flag_name, presence: true, uniqueness: { scope: :account_id }
end
```

No `KNOWN_FLAGS` validation on the model — keeping it open for ad-hoc flags. Known names live in a constant for the admin-UI dropdown only (see below).

### Concern — `Account::FeatureFlags`

```ruby
module Account::FeatureFlags
  extend ActiveSupport::Concern

  included do
    has_many :feature_flags, class_name: "AccountFeatureFlag", dependent: :destroy
  end

  def feature_enabled?(name)
    enabled_feature_names.include?(name.to_s)
  end

  def enable_feature!(name)
    feature_flags.find_or_create_by!(flag_name: name.to_s)
    @enabled_feature_names = nil
  end

  def disable_feature!(name)
    feature_flags.where(flag_name: name.to_s).delete_all
    @enabled_feature_names = nil
  end

  private

  def enabled_feature_names
    @enabled_feature_names ||= feature_flags.pluck(:flag_name).to_set
  end
end
```

Memoization invalidated on enable/disable. Symbol-or-string tolerant via `to_s`.

### Known flags constant

`app/constants/feature_flags.rb`:

```ruby
module FeatureFlags
  META_ADS_INTEGRATION = "meta_ads_integration"
  LINKEDIN_ADS_INTEGRATION = "linkedin_ads_integration"

  ALL = [META_ADS_INTEGRATION, LINKEDIN_ADS_INTEGRATION].freeze
end
```

Used by admin UI dropdown + rake task validation. Phase 2 / Phase 3 will reference these constants at gate sites.

### Admin UI — `Admin::FeatureFlagsController`

Routes:
```ruby
namespace :admin do
  resources :feature_flags, only: [:index, :create, :destroy]
end
```

| Action | Behavior |
|---|---|
| `#index` | Two views: (1) by-flag — count + sample of accounts with each flag; (2) by-account — search bar, paginated account list with checkboxes per flag. |
| `#create` | POST `account_id`, `flag_name` → `account.enable_feature!(flag_name)` → redirect back with notice. |
| `#destroy` | DELETE with `account_id`, `flag_name` → `account.disable_feature!(flag_name)` → redirect back with notice. |

`flag_name` param validated against `FeatureFlags::ALL` to prevent typos in the UI.

Inherits from `Admin::BaseController` (already enforces `require_admin` + `skip_marketing_analytics`).

### Rake task — `lib/tasks/feature_flags.rake`

```bash
bin/rails feature_flags:enable ACCT=acct_xxx FLAG=meta_ads_integration
bin/rails feature_flags:disable ACCT=acct_xxx FLAG=meta_ads_integration
bin/rails feature_flags:list ACCT=acct_xxx
bin/rails feature_flags:accounts FLAG=meta_ads_integration  # list accounts with flag
```

Validates `FLAG` against `FeatureFlags::ALL`, looks up account via `find_by_prefix_id!(ACCT)`. Idempotent. Prints clear status lines.

---

## Tasks (TDD order)

### 1. Migration + model

- [ ] **1.1** RED: write `test/models/account_feature_flag_test.rb` — `belongs_to :account`, `flag_name` presence, uniqueness scoped to account_id. Test fails (no model).
- [ ] **1.2** GREEN: generate migration `CreateAccountFeatureFlags`, model `app/models/account_feature_flag.rb`. Run migration. Tests pass.

### 2. Account concern

- [ ] **2.1** RED: write `test/models/account/feature_flags_test.rb` — predicate false by default, true after enable, idempotent enable/disable, cross-account isolation, symbol-or-string tolerance, memoization invalidated on enable/disable.
- [ ] **2.2** GREEN: create `app/models/concerns/account/feature_flags.rb`, include in `Account` model.

### 3. Constants

- [ ] **3.1** Create `app/constants/feature_flags.rb` with `META_ADS_INTEGRATION`, `LINKEDIN_ADS_INTEGRATION`, `ALL`.

### 4. Admin UI

- [ ] **4.1** RED: write `test/controllers/admin/feature_flags_controller_test.rb` — non-admin redirected, admin sees index, create enables flag and redirects, destroy disables flag and redirects, invalid flag_name rejected.
- [ ] **4.2** GREEN: routes, controller, views (`index.html.erb` showing both grouped views with toggle forms).
- [ ] **4.3** Wire into existing admin nav in `app/views/admin/_nav.html.erb` (or wherever the admin nav lives — verify file before editing).

### 5. Rake task

- [ ] **5.1** RED: write `test/tasks/feature_flags_test.rb` invoking each task and asserting account state changes.
- [ ] **5.2** GREEN: `lib/tasks/feature_flags.rake`.

### 6. Wiring (deferred to Phase 2/3 where consumed)

No gates added in this phase. Phase 2's `Oauth::MetaAdsController#connect` will check `current_account.feature_enabled?(FeatureFlags::META_ADS_INTEGRATION)` as the first guard.

---

## Tests

No mocks. Fixtures + memoized helpers (per `feedback_no_mocks.md`, `feedback_code_style.md`).

### Model tests — `test/models/account_feature_flag_test.rb`

| Test | Verifies |
|---|---|
| `belongs to account` | Association resolves |
| `flag_name is required` | Presence validation fires |
| `flag_name unique per account` | Same flag twice on one account → invalid |
| `flag_name can repeat across accounts` | Cross-account uniqueness allowed |

### Concern tests — `test/models/account/feature_flags_test.rb`

| Test | Verifies |
|---|---|
| `feature_enabled? false when not set` | Default state |
| `feature_enabled? true after enable_feature!` | Round trip |
| `feature_enabled? false after disable_feature!` | Removal |
| `enable_feature! is idempotent` | Calling twice raises nothing, one row exists |
| `disable_feature! is idempotent (no flag set)` | Calling on absent flag is no-op |
| `feature_enabled? accepts symbol and string` | `:foo` and `"foo"` both work |
| `flags are isolated per account` | Account A enabling does not enable for Account B |
| `memoization invalidates on enable_feature!` | Re-query within same instance reflects change |
| `memoization invalidates on disable_feature!` | Same as above |

### Controller tests — `test/controllers/admin/feature_flags_controller_test.rb`

| Test | Verifies |
|---|---|
| `non-admin user is redirected` | `require_admin` from `Admin::BaseController` |
| `admin sees index` | 200 response, lists known flags |
| `create enables flag for given account` | POST → account has flag |
| `create with unknown flag_name is rejected` | 422 or redirect with alert, no flag created |
| `destroy disables flag` | DELETE → account no longer has flag |
| `cross-account isolation` | Modifying account A doesn't touch account B |

### Rake task tests — `test/tasks/feature_flags_test.rb`

| Test | Verifies |
|---|---|
| `enable task adds flag` | `bin/rails feature_flags:enable ACCT=... FLAG=...` toggles state |
| `disable task removes flag` | Same in reverse |
| `list task prints flags` | Output includes flag names |
| `accounts task lists accounts with flag` | Output includes prefix ids |
| `unknown flag is rejected` | Exits non-zero with clear error |

### Manual QA (after implementation)

1. `bin/rails feature_flags:enable ACCT=<dev account prefix id> FLAG=meta_ads_integration` — confirm row appears in DB.
2. Visit `/admin/feature_flags` as an admin — confirm UI shows flag, account count.
3. Toggle flag off via UI — confirm DB row gone, UI updated.
4. As non-admin user, hit `/admin/feature_flags` directly — confirm redirected.

---

## Definition of Done

- [ ] Migration ships, table exists in dev DB
- [ ] All tests green: `bin/rails test test/models/account_feature_flag_test.rb test/models/account/feature_flags_test.rb test/controllers/admin/feature_flags_controller_test.rb test/tasks/feature_flags_test.rb`
- [ ] No regressions in full suite: `bin/rails test`
- [ ] Admin UI wired into admin nav, accessible to admins, blocked for non-admins
- [ ] Rake task usable from prod console (smoke-tested locally)
- [ ] Phase 2 (Meta adapter) can `current_account.feature_enabled?(FeatureFlags::META_ADS_INTEGRATION)` immediately
- [ ] Spec moved to `lib/specs/old/` after Phase 5 completes (parent rollout merge)

---

## Out of Scope

- **Per-user feature flags** — flags are account-scoped only. If we ever need per-user (e.g. internal beta testing for select team members), add a `user_feature_flags` table later.
- **Percentage rollouts** — no `enable_for_percent: 5` semantics. If we want canaries, layer it on top later.
- **Flag expiration** — no automatic disable after N days.
- **Audit log of who flipped what** — `created_at` gives "when". If we need "who", add `enabled_by_id` later. Cheap to bolt on.
- **Public-facing UI** — accounts cannot see or self-serve their own flags. Admin-only.
- **Webhook on toggle** — no notifications fire when flag changes.

---

## Open Questions

1. **Admin nav file.** I'll grep `app/views/admin/` for the existing nav partial to wire in. If there's no nav or it's hardcoded across pages, I'll add a clean one.
2. **Where does `current_account` come from in admin views?** Admin pages typically don't operate "on behalf of" a single account — they pick one via URL/dropdown. The `Admin::FeatureFlagsController` uses `Account.find(params[:account_id])` (admin-scoped lookup), not `current_account`. Confirm this matches the rest of the admin UI.
