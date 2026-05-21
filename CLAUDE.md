# Claude Development Guide for mbuzz

**ultrathink** — We're here to make a dent in the universe.

## CRITICAL Rules

- **Product name is mbuzz** (lowercase, never "Multibuzz"). Repo dir `multibuzz` is legacy.
- **NEVER use EnterPlanMode.** Spec first, step-by-step, no bulk commits. You propose, user approves, you execute.
- **NEVER use TaskCreate, TaskUpdate, TaskList, or any task/todo tools.** Specs are the plan. Work from specs, not task lists.
- **No AI attribution** in commits (no "Co-Authored-By: Claude", etc.)
- **Every query MUST be scoped to account** (multi-tenancy).
- **Never expose raw database IDs** — use `prefixed_ids` gem.
- **Sessions are server-side** — SDKs do NOT manage sessions.
- **NEVER write secrets, tokens, API keys, account IDs, email addresses, or any credentials to files that are committed to git.** This includes specs, docs, code comments, and config files. Secrets go in Rails credentials or 1Password only. Use placeholders like "see Rails credentials" or "see 1Password".
- **Sensitive controllers MUST declare `skip_marketing_analytics`.** Any controller that renders secrets, credentials, API keys, billing data, OAuth tokens, visitor PII, identity strings, or admin tooling must call `skip_marketing_analytics` at the class level so GTM/GA4/Ads/Meta tags never load on its pages. URL paths reach GA4 and Meta as `page_location` regardless of consent — a leaked API key in a URL is a leaked API key in three vendor systems. When you create or modify a controller that handles any of the above, add `skip_marketing_analytics` immediately. The `SensitivePaths` deny-list in `app/constants/sensitive_paths.rb` is a safety net, not a substitute. See `lib/specs/marketing_analytics_ga4_ads_spec.md` for the full list and rationale.
- **Every new admin surface MUST register a card in `AdminTools::ALL`** (`app/constants/admin_tools.rb`). The `/admin` dashboard is the single hub for internal-operator tools; if a new admin page isn't listed there, the operator can't find it. Pick a `Categories` constant (Customer support / Platform operations / Diagnostics), add the entry alongside the controller/route work, and don't ship the surface without it.
- **Every new view MUST conform to `lib/docs/DESIGN_SYSTEM.md`.** Containers, typography, buttons, inputs, cards, status idioms, iconography, and voice are specified there. Forms in particular must use the visible-border input baseline. The onboarding chrome and resume nav are specified in §10 with the canonical wireframes at `lib/mockups/onboarding-chrome.html`. If a screen needs a pattern the doc doesn't cover, add the pattern to the doc as part of the same commit — don't invent silently.

## Philosophy

Think different. Obsess over details. Simplify ruthlessly. Craft, don't code. Question every assumption. Leave the codebase better than you found it.

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Rails 8 (Hotwire: Turbo + Stimulus) |
| Database | PostgreSQL + TimescaleDB |
| Cache/Queue/Cable | **Solid Stack** (NOT Redis) |
| Frontend | Tailwind CSS |
| Charts | Highcharts |
| Deployment | Kamal (`config/deploy.yml`) |

### TimescaleDB in Tests

TimescaleDB features don't work in test env. **Always guard:**

```ruby
def up
  return if Rails.env.test?
  execute <<-SQL
    SELECT create_hypertable('events', 'occurred_at', ...);
  SQL
end
```

Remove TimescaleDB calls from `db/schema.rb` after `db:schema:dump`. For test DB setup:

```bash
RAILS_ENV=test bin/rails db:schema:load
# Or targeted: RAILS_ENV=test bin/rails db:migrate:up VERSION=20260209064816
```

**Never** `db:drop db:create db:migrate` for test DB.

**Production operations** (cluster topology, which DBs have the extension, retention policy, debugging unbounded telemetry growth): see `lib/docs/architecture/timescaledb_operations.md`.

## Hotwire / Turbo gotchas

Forms submitted via Turbo Drive (`form_with` default) **fail silently** in two recurring patterns. If a form "does nothing" or the page shows "Content missing", check these first.

1. **Cross-origin redirects.** `form_with` + a controller `redirect_to(allow_other_host: true)` to e.g. Stripe Checkout silently no-ops. Turbo's `fetch` can't follow cross-origin redirects. **Fix:** `data: { turbo: false }` on the form. Reference: `app/views/accounts/billing/show.html.erb`.

2. **Forms inside `<turbo-frame>` that redirect outside the frame.** The form submission stays scoped to the frame; Turbo expects the response to contain a matching `<turbo-frame id="...">`. A redirect to a totally different page (dashboard, etc.) has no such frame → user sees "Content missing". **Fix:** `data: { turbo_frame: "_top" }` on the form so the redirect navigates the whole page.

**Rule of thumb:** if a form's success path is a redirect to a different host or a different page (no matching frame), don't let Turbo intercept it. Use `data: { turbo: false }` or `data: { turbo_frame: "_top" }` explicitly. Tests using `assert_response :redirect` will pass either way — these bugs only show up in a real browser.

## Production

| Domain | mbuzz.co |
|--------|----------|
| Server | 68.183.173.51 |
| Registry | ghcr.io/vladiim/multibuzz |

---

## Server-Side Sessions

SDKs generate `visitor_id` (cookie `_mbuzz_vid`) and call `POST /api/v1/sessions`. Server computes `device_fingerprint = SHA256(ip|user_agent)[0:32]`, creates Visitor + Session, manages 30-min sliding window via `last_activity_at`.

`require_existing_visitor` is **ENABLED** — events/conversions rejected if visitor doesn't exist. SDKs MUST call `/sessions` before tracking events.

---

## Ruby Style

### Functional, Not Procedural

```ruby
# YES: chains, early returns, enumerables
events.select(&:valid?).map { |e| transform(e) }

def account_status
  return :suspended if suspended_at.present?
  return :cancelled if cancelled_at.present?
  :active
end
```

No giant if/else chains — use hash lookups, polymorphism, guard clauses.

### Key Patterns

- **Enumerables** over loops: `select`, `map`, `sum`, `group_by`, `any?`, `all?`
- **`then`** for pipelines: `input.then { validate(_1) }.then { persist(_1) }`
- **`tap`** for side effects
- **`fetch`** over `[]` for hashes (fails fast)
- **Early returns** / guard clauses over nested conditionals
- **Methods < 10 lines**, single responsibility
- **Descriptive names**: `exceeded_rate_limit?` not `check`

---

## Models — Thin + Concerns

Extract to concerns: `Account::Validations`, `Account::Relationships`, `Account::Scopes`, etc.

Use **Rails enum** for status fields (integer storage):

```ruby
class Account < ApplicationRecord
  include Account::Validations
  include Account::Relationships
  enum :status, { active: 0, suspended: 1, cancelled: 2 }
end
```

---

## Service Objects

### ApplicationService Pattern

Services that can succeed/fail inherit from `ApplicationService`, implement private `#run`:

```ruby
class ApplicationService
  def call
    run
  rescue ActiveRecord::RecordInvalid => e
    error_result(["Record invalid: #{e.message}"])
  rescue ActiveRecord::RecordNotFound => e
    error_result(["Record not found: #{e.message}"])
  rescue StandardError => e
    error_result(["Internal error: #{e.message}"])
  end

  private

  def run = raise NotImplementedError
  def success_result(data = {}) = { success: true }.merge(data)
  def error_result(errors) = { success: false, errors: Array(errors) }
end
```

### Standard Template

```ruby
module EntityName
  class ActionService < ApplicationService
    def initialize(account, params)
      @account = account
      @user_id = params[:user_id]
    end

    private

    attr_reader :account, :user_id

    def run
      return error_result(["user_id required"]) unless user_id.present?
      perform_action
      success_result
    end

    def perform_action
      record.save!  # Exceptions caught by ApplicationService
    end

    def record
      @record ||= account.users.find_or_initialize_by(external_id: user_id)
    end
  end
end
```

**Method ordering** (followed by 98% of services):
```
initialize(params)      # public — only public method besides call
                        # blank line
private                 # access modifier
  attr_reader :a, :b    # readers first
  def run ...           # implementation
  def helper ...        # private helpers
```

**Rules:**
- Only `initialize` and `call` are public
- Everything else private, use `attr_reader`
- Memoize with `@var ||=`
- Multiple public methods? Split into separate services
- Compose services via pipelines, not inheritance

**Error handling — three patterns:**

| Pattern | When to Use |
|---------|-------------|
| ApplicationService rescue (default) | Service returns success/fail. `run` raises, `call` rescues. |
| Explicit error collection | Multi-field validation. `errors = []; errors.concat(validate_x)` |
| Custom return types | Domain structures (`{ allowed:, remaining: }`). Skip ApplicationService. |

### When NOT to Use ApplicationService

Skip for classes returning domain-specific structures (not success/fail):
- Auth flows returning `{ account:, api_key:, error_codes: }`
- Rate limiters returning `{ allowed:, remaining:, reset_at: }`
- Utility/extractors returning hashes or strings
- Strategy pattern implementations (algorithms)
- Query objects returning ActiveRecord relations

### Jobs = Thin Wrappers

```ruby
class SomeJob < ApplicationJob
  def perform(account_id)
    SomeService.new(Account.find(account_id)).call
  end
end
```

Test the service, not the job.

---

## Controllers — Thin, Delegate to Services

```ruby
class Api::V1::EventsController < Api::V1::BaseController
  def create
    render json: ingestion_result, status: :accepted
  end

  private

  def ingestion_result
    @ingestion_result ||= Event::IngestionService.new(current_account).call(events_params)
  end
end
```

---

## Testing

### Memoized Fixture Methods

```ruby
class SomeTest < ActiveSupport::TestCase
  test "works" do
    assert service.call(valid_params)[:success]
  end

  private

  def service = @service ||= SomeService.new(account)
  def account = @account ||= accounts(:one)
  def other_account = @other_account ||= accounts(:two)
end
```

- **Memoized helpers** for fixtures (`def account = @account ||= accounts(:one)`)
- **`setup`** only for side-effectful resets (cache clear, global state)
- **Test names**: action-based strings (`test "returns 422 with invalid event_id"`)
- Always test cross-account isolation.

---

## Design Patterns

| Pattern | Use For |
|---------|---------|
| Service Object | One action, `initialize` + `call`, namespaced |
| Query Object | Complex queries, `initialize(scope)` + `call`, returns domain structures (NOT success/fail, does NOT inherit ApplicationService) |
| Form Object | Complex forms, `ActiveModel::Model` |
| Presenter | View decoration, `SimpleDelegator` |
| Value Object | Wrapping primitives (e.g., `UtmParameters`) |

---

## Security

### Prefixed IDs

Use `prefixed_ids` gem for external-facing IDs:

| Model | Prefix |
|-------|--------|
| Account | `acct_` |
| User | `user_` |
| Visitor | `vis_` |
| Session | `sess_` |
| Event | `evt_` |

Exceptions: API keys (`sk_{env}_{random32}`), internal job IDs, DB foreign keys.

**Lookup with `find`, not `find_by_prefix_id`.** The gem patches `find` (and `find_by_id`) to accept either a raw integer id or a prefixed id string. Use it everywhere — controllers, console, services, tests. `find_by_prefix_id` exists but is redundant noise.

```ruby
# YES
account.exports.find("exp_50nkDj2oRp21nU1GQvzgA9Je")
account.exports.completed.find(params[:id])      # params[:id] is "exp_..."
Export.find("exp_50nkDj2oRp21nU1GQvzgA9Je")      # console one-liner

# NO — verbose, no upside
account.exports.find_by_prefix_id!("exp_...")
```

Compare via `prefix_id`, not `id`:
```ruby
@filter_params[:model]&.prefix_id == model.prefix_id
```

### Multi-Tenancy

```ruby
# ALWAYS: @account.events.where(...)
# NEVER:  Event.where(event_type: "page_view")
```

### JSONB Columns

- **Max 50KB** per JSONB field. Validate via `validate :field_size_limit`.
- Prefer **shallow assignment** over `deep_merge` (simpler, auditable).
- Always validate that JSONB value `is_a?(Hash)` before size check.

---

## Formatting

- **2-space indent** for line continuations and nested HTML/ERB
- Extract conditionals to partials in views
- Don't align to match previous content

---

## Naming

- Methods/vars: `visitor_id`, `rate_limit_exceeded?` (descriptive, no abbreviations)
- Classes: `Event::IngestionService` (namespaced `Module::ActionService`)
- Constants: `SCREAMING_SNAKE`, `.freeze` arrays/hashes, module wrapping, section headers (`# --- Section ---`)

---

## Git Commits

```
<type>(<scope>): <subject>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`
Scopes: `auth`, `event`, `visitor`, `session`, `api`, `dashboard`, `docs`

---

## DDD Workflow

Doc spec → RED test → GREEN code → run all tests → refactor → update spec → commit.

---

## Project Memory

Persistent project memory lives **in the repo** at `lib/memory/`, never in a global or per-user Claude directory. Memory is versioned and reviewed like code.

- One fact per file, kebab-case filename, with frontmatter (`name`, `description`, `metadata.type` of `user`, `feedback`, `project`, or `reference`).
- `lib/memory/README.md` is the index: one line per memory. Add a pointer when you add a file.
- If the harness points memory at a global path (e.g. `~/.claude/...`), override it and write to `lib/memory/` instead.
- The CRITICAL secrets rule applies in full. These files are committed to git, so no credentials, tokens, account IDs, emails, or customer PII. Use placeholders.

---

## Smells to Avoid

Long methods, long param lists, feature envy, nested conditionals, god objects, public methods in services (beyond init/call), magic values, global state, unscoped queries.

**Fix with:** extract method, guard clauses, value objects, dependency injection, single responsibility, private methods.
