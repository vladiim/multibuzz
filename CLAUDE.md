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

## Smells to Avoid

Long methods, long param lists, feature envy, nested conditionals, god objects, public methods in services (beyond init/call), magic values, global state, unscoped queries.

**Fix with:** extract method, guard clauses, value objects, dependency injection, single responsibility, private methods.
