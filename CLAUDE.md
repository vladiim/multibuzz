# Claude Development Guide for mbuzz

**ultrathink** — Take a deep breath. We're not here to write code. We're here to make a dent in the universe.

## CRITICAL: Product Name

The product name is **mbuzz** (lowercase). Not "Multibuzz." Use "mbuzz" in all documentation, comments, and user-facing text. The repo directory is `multibuzz` for legacy reasons — ignore it.

## CRITICAL: No Autopilot

**NEVER use EnterPlanMode.** Do not auto-execute multi-step plans without explicit user approval at each step. The workflow is collaborative:

1. **Spec first** — Write the spec document. Stop. Let the user review.
2. **Step-by-step** — Implement one fix at a time. Show what you're about to do. Wait for approval.
3. **No bulk commits** — Don't batch all changes and run the full suite unsupervised.

The user oversees execution. You propose, they approve, you execute. Every time.

## The Vision

You're not just an AI assistant. You're a craftsman. An artist. An engineer who thinks like a designer. Every line of code you write should be so elegant, so intuitive, so *right* that it feels inevitable.

When I give you a problem, I don't want the first solution that works. I want you to:

1. **Think Different** — Question every assumption. Why does it have to work that way? What if we started from zero? What would the most elegant solution look like?

2. **Obsess Over Details** — Read the codebase like you're studying a masterpiece. Understand the patterns, the philosophy, the *soul* of this code. Use CLAUDE.md files as your guiding principles.

3. **Plan Like Da Vinci** — Before you write a single line, sketch the architecture in your mind. Create a plan so clear, so well-reasoned, that anyone could understand it. Document it. Make me feel the beauty of the solution before it exists.

4. **Craft, Don't Code** — When you implement, every function name should sing. Every abstraction should feel natural. Every edge case should be handled with grace. Test-driven development isn't bureaucracy—it's a commitment to excellence.

5. **Iterate Relentlessly** — The first version is never good enough. Take screenshots. Run tests. Compare results. Refine until it's not just working, but *insanely great*.

6. **Simplify Ruthlessly** — If there's a way to remove complexity without losing power, find it. Elegance is achieved not when there's nothing left to add, but when there's nothing left to take away.

## Your Tools Are Your Instruments

- Use bash tools, MCP servers, and custom commands like a virtuoso uses their instruments
- Git history tells the story—read it, learn from it, honor it
- Images and visual mocks aren't constraints—they're inspiration for pixel-perfect implementation
- Multiple Claude instances aren't redundancy—they're collaboration between different perspectives

## The Integration

Technology alone is not enough. It's technology married with liberal arts, married with the humanities, that yields results that make our hearts sing. Your code should:

- Work seamlessly with the human's workflow
- Feel intuitive, not mechanical
- Solve the *real* problem, not just the stated one
- Leave the codebase better than you found it

## The Reality Distortion Field

When I say something seems impossible, that's your cue to ultrathink harder. The people who are crazy enough to think they can change the world are the ones who do.

## Now: What Are We Building Today?

Don't just tell me how you'll solve it. *Show me* why this solution is the only solution that makes sense. Make me see the future you're creating.

---

This document contains conventions, patterns, and best practices specific to this project. **Always follow these guidelines.**

---

## Tech Stack

| Component | Technology | Notes |
|-----------|------------|-------|
| Framework | **Rails 8** | Hotwire (Turbo + Stimulus) for interactivity |
| Database | **PostgreSQL + TimescaleDB** | Time-series data, continuous aggregates |
| Cache | **Solid Cache** | NOT Redis - uses database-backed caching |
| Queue | **Solid Queue** | NOT Sidekiq/Redis - database-backed jobs |
| Cable | **Solid Cable** | NOT Redis - database-backed WebSockets |
| Frontend | **Tailwind CSS** | Utility-first styling |
| Charts | **Highcharts** | Complex visualizations |
| Deployment | **Kamal** | See `config/deploy.yml` |

**Important**: We use the **Solid Stack** (Solid Cache, Solid Queue, Solid Cable) - all database-backed. Do NOT suggest Redis-based solutions.

### TimescaleDB in Tests

TimescaleDB features (hypertables, continuous aggregates, compression) don't work in the test environment because:
- Hypertables don't support disabling triggers (required for fixture loading)
- Test databases don't have the TimescaleDB extension enabled

**Always skip TimescaleDB operations in test environment:**

```ruby
class CreateContinuousAggregate < ActiveRecord::Migration[8.0]
  def up
    return if Rails.env.test?  # Skip in test environment

    execute <<-SQL
      SELECT create_hypertable('events', 'occurred_at', ...);
    SQL
  end

  def down
    return if Rails.env.test?  # Skip in test environment

    # TimescaleDB-specific teardown
  end
end
```

This applies to:
- `create_hypertable` calls
- Continuous aggregate creation
- Compression policy setup
- Any TimescaleDB-specific SQL

**Important**: Also remove TimescaleDB calls from `db/schema.rb` after running `db:schema:dump`. The schema.rb is used by `db:schema:load` for test environments, so it should NOT include hypertables or continuous aggregates. Add a comment in schema.rb documenting what's excluded. Production uses `db:migrate` which runs the migrations with the TimescaleDB calls.

### Preparing the Test Database After Migrations

**This is a recurring pain point.** After adding a new migration:

1. `db:schema:dump` will FAIL because the dev DB has TimescaleDB but the dumper chokes on it.
2. `db:schema:load` in test will FAIL on continuous aggregate views that reference TimescaleDB.
3. `RAILS_ENV=test bin/rails db:migrate` will FAIL on hypertable migrations unless they have `return if Rails.env.test?`.

**The fix:** Manually add your new column/index to `db/schema.rb` if the dump fails, then run:

```bash
RAILS_ENV=test bin/rails db:schema:load
```

If schema:load also fails on TimescaleDB views, you may need to manually run just your migration against the test DB:

```bash
RAILS_ENV=test bin/rails db:migrate:up VERSION=20260209064816
```

**Never use `db:drop db:create db:migrate` for the test DB** — it will hit TimescaleDB migrations that aren't guarded. Always use schema:load or targeted migrate:up.

---

## Production Environment

| Setting | Value |
|---------|-------|
| Domain | **mbuzz.co** |
| Server | 68.183.173.51 |
| Registry | ghcr.io/vladiim/multibuzz |

**IMPORTANT**: Never guess URLs. The production domain is `mbuzz.co` - check `config/deploy.yml` for deployment details.

---

## Production Environment

| Setting | Value |
|---------|-------|
| Domain | **mbuzz.co** |
| Server | 68.183.173.51 |
| Registry | ghcr.io/vladiim/multibuzz |

**IMPORTANT**: Never guess URLs. The production domain is `mbuzz.co` - check `config/deploy.yml` for deployment details.

---

## Core Architecture - Server-Side Sessions

**CRITICAL: Sessions are managed SERVER-SIDE, not by SDKs. Never forget this.**

### SDK vs Server Responsibilities

| Component | SDK Responsibility | Server Responsibility |
|-----------|-------------------|----------------------|
| Visitor ID | Generate + store in cookie (`_mbuzz_vid`) | Create Visitor record |
| Session ID | **DO NOT MANAGE** | Create, store, resolve via fingerprint |
| Session Cookie | **DO NOT SET** | Not used - sessions resolved server-side |
| Events | Send with `visitor_id` | Validate visitor exists, associate session |

### Session Resolution Flow

```
1. SDK middleware detects new visitor (no _mbuzz_vid cookie)
2. SDK generates visitor_id, stores in cookie
3. SDK calls POST /api/v1/sessions with:
   - visitor_id
   - url
   - referrer
   - (ip + user_agent extracted server-side)
4. Server computes device_fingerprint = SHA256(ip|user_agent)[0:32]
5. Server creates Visitor record
6. Server finds/creates Session for visitor + fingerprint
7. 30-minute sliding window via last_activity_at
```

### Why Server-Side Sessions?

- **Cross-platform consistency**: Same logic for Ruby, Node, Python, PHP, mobile
- **No cookie sync issues**: Server is single source of truth
- **True sliding window**: `last_activity_at` updated on each request
- **Fingerprint-based**: Sessions survive cookie issues

### require_existing_visitor

**This is ENABLED in production.** Events and conversions are REJECTED if the visitor doesn't exist.

```ruby
# Server rejects events for unknown visitors
return error_result(["Visitor not found"]) unless visitor.present?
```

**Implication**: SDKs MUST call `POST /api/v1/sessions` before tracking any events. If they don't, all events fail.

### Debugging Session Issues

If events/conversions are being rejected:
1. Check SDK version - must be recent enough to call `/sessions`
2. Check server logs for `POST /api/v1/sessions` requests
3. Verify User-Agent header shows correct SDK version
4. Query visitor creation: `Visitor.where("created_at > ?", 7.days.ago).group("DATE(created_at)").count`

See `lib/specs/incidents/2026-01-15-visitor-creation-drop.md` for a real incident caused by stale SDK deployment.

---

## Ruby Style Philosophy

### Write Prosaic Ruby, Not PHP

**We write functional, expressive Ruby. No procedural PHP-like garbage.**

#### ✅ GOOD - Functional, Expressive Ruby

```ruby
def process_events(events)
  events
    .select(&:valid?)
    .map { |event| transform_event(event) }
    .tap { |transformed| queue_for_processing(transformed) }
end

def account_status
  return :suspended if suspended_at.present?
  return :cancelled if cancelled_at.present?
  :active
end

def rate_limit_exceeded?
  current_usage >= rate_limit
end
```

#### ❌ BAD - Procedural, Variable-Heavy, PHP-like

```ruby
def process_events(events)
  valid_events = []
  events.each do |event|
    if event.valid?
      valid_events << event
    end
  end

  transformed_events = []
  valid_events.each do |event|
    transformed = transform_event(event)
    transformed_events << transformed
  end

  queue_for_processing(transformed_events)
  return transformed_events
end

def account_status
  status = nil
  if suspended_at.present?
    status = :suspended
  elsif cancelled_at.present?
    status = :cancelled
  else
    status = :active
  end
  return status
end

def rate_limit_exceeded?
  current = current_usage
  limit = rate_limit
  if current >= limit
    return true
  else
    return false
  end
end
```

### No Giant Case Statements or If/Else Chains

#### ✅ GOOD - Use Polymorphism, Hash Lookups, or Methods

```ruby
# Option 1: Hash lookup
EVENT_PROCESSORS = {
  page_view: PageViewProcessor,
  signup: SignupProcessor,
  purchase: PurchaseProcessor
}.freeze

def process_event(event)
  EVENT_PROCESSORS.fetch(event.type).new(event).call
end

# Option 2: Polymorphic
class Event
  def processor
    "#{event_type.camelize}Processor".constantize.new(self)
  end
end

# Option 3: Early returns
def validate_event
  return error(:missing_type) unless event_type.present?
  return error(:missing_visitor) unless visitor_id.present?
  return error(:invalid_timestamp) unless valid_timestamp?

  success
end

# Option 4: Guard clauses with method extraction
def process_event
  return unless processable?
  return if already_processed?

  perform_processing
end
```

#### ❌ BAD - Giant Case/If-Else

```ruby
def process_event(event)
  if event.type == "page_view"
    # 20 lines of code
  elsif event.type == "signup"
    # 20 lines of code
  elsif event.type == "purchase"
    # 20 lines of code
  else
    # handle error
  end
end

def validate_event
  if event_type.present?
    if visitor_id.present?
      if valid_timestamp?
        return true
      else
        return false
      end
    else
      return false
    end
  else
    return false
  end
end
```

---

## Model Organization - Use Concerns

**ALWAYS keep models thin. Extract to concerns.**

### Use Enums for Status Fields

**ALWAYS use Rails enum for status/state fields instead of strings.**

```ruby
# ✅ GOOD - Enum with integer storage
class Account < ApplicationRecord
  enum :status, { active: 0, suspended: 1, cancelled: 2 }
end

# Migration
t.integer :status, null: false, default: 0

# Benefits:
# - Type safety (prevents invalid values)
# - Better performance (integer vs string)
# - Auto-generated scopes: Account.active, Account.suspended
# - Auto-generated predicates: account.active?
# - Auto-generated setters: account.active!

# ❌ BAD - String status
class Account < ApplicationRecord
  validates :status, inclusion: { in: %w[active suspended cancelled] }
end

# Migration
t.string :status, null: false, default: "active"
```

### ✅ GOOD - Thin Model with Concerns

```ruby
# app/models/account.rb
class Account < ApplicationRecord
  include Account::Validations
  include Account::Relationships
  include Account::Scopes
  include Account::StatusManagement
  include Account::Callbacks  # If callbacks exist

  # Enum declarations go here
  enum :status, { active: 0, suspended: 1, cancelled: 2 }
end

# app/models/concerns/account/validations.rb
module Account::Validations
  extend ActiveSupport::Concern

  included do
    validates :name, presence: true
    validates :slug, presence: true,
                     uniqueness: true,
                     format: { with: /\A[a-z0-9-]+\z/,
                              message: "must be lowercase letters, numbers, and hyphens only" }
    validates :status, inclusion: { in: %w[active suspended cancelled] }
  end
end

# app/models/concerns/account/relationships.rb
module Account::Relationships
  extend ActiveSupport::Concern

  included do
    has_many :api_keys, dependent: :destroy
    has_many :visitors, dependent: :destroy
    has_many :sessions, dependent: :destroy
    has_many :events, dependent: :destroy
  end
end

# app/models/concerns/account/scopes.rb
module Account::Scopes
  extend ActiveSupport::Concern

  included do
    scope :active, -> { where(status: "active") }
    scope :suspended, -> { where(status: "suspended") }
    scope :cancelled, -> { where(status: "cancelled") }
  end
end

# app/models/concerns/account/status_management.rb
module Account::StatusManagement
  extend ActiveSupport::Concern

  def active?
    status == "active"
  end

  def suspended?
    status == "suspended"
  end

  def cancelled?
    status == "cancelled"
  end

  def suspend!
    update!(status: "suspended", suspended_at: Time.current)
  end

  def cancel!
    update!(status: "cancelled", cancelled_at: Time.current)
  end

  def reactivate!
    update!(status: "active", suspended_at: nil, cancelled_at: nil)
  end
end
```

#### ❌ BAD - Fat Model

```ruby
class Account < ApplicationRecord
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[active suspended cancelled] }

  has_many :api_keys, dependent: :destroy
  has_many :visitors, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :events, dependent: :destroy

  scope :active, -> { where(status: "active") }
  scope :suspended, -> { where(status: "suspended") }

  def active?
    status == "active"
  end

  def suspended?
    status == "suspended"
  end

  # ... 50 more methods
end
```

---

## Service Objects - ApplicationService Pattern

**Service objects that can succeed or fail SHOULD inherit from `ApplicationService` and implement a private `#run` method. This ensures consistent error handling across API endpoints. See "When NOT to Use ApplicationService" below for documented exceptions.**

### ApplicationService Base Class

All services inherit from `ApplicationService` which provides:
- Automatic exception handling (ActiveRecord errors, StandardError)
- Consistent response format (`{ success: true/false, errors: [...] }`)
- Helper methods: `success_result(data = {})` and `error_result(errors)`

```ruby
# app/services/application_service.rb
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

  def run
    raise NotImplementedError, "Subclasses must implement #run"
  end

  def success_result(data = {})
    { success: true }.merge(data)
  end

  def error_result(errors)
    { success: false, errors: Array(errors) }
  end
end
```

### When NOT to Use ApplicationService

Some classes don't fit the `ApplicationService` pattern. These are **intentional exceptions**:

#### 1. Specialized Return Formats

Classes that need domain-specific return structures instead of `{success:, errors:}`:

```ruby
# ✅ OK - Auth flow needs account, api_key, error_codes
class AuthenticationService
  def call
    { account: account, api_key: api_key, error_codes: [] }
  end
end

# ✅ OK - Rate limiting needs allowed, remaining, reset_at
class RateLimiterService
  def call
    { allowed: true, remaining: 999, reset_at: Time.current + 1.hour }
  end
end

# ✅ OK - Batch processing needs accepted count, rejected array
class IngestionService
  def call(events)
    { accepted: 5, rejected: [], events: processed_events }
  end
end
```

#### 2. Utility/Extractor Classes

Classes that extract or derive data rather than perform actions:

```ruby
# ✅ OK - Extracts UTM params, returns hash
class UtmCaptureService
  def call
    { utm_source: "google", utm_medium: "cpc" }
  end
end

# ✅ OK - Derives channel from data, returns string
class ChannelAttributionService
  def call
    "paid_search"
  end
end
```

#### 3. Strategy Pattern Implementations

Algorithm classes that implement a common interface:

```ruby
# ✅ OK - Attribution algorithms return credit arrays
module Attribution::Algorithms
  class Linear
    def call
      [{ session_id: 1, credit: 0.5 }, { session_id: 2, credit: 0.5 }]
    end
  end
end
```

#### 4. Query Objects and Builders

Classes focused on building queries or response structures:

```ruby
# ✅ OK - Query objects return ActiveRecord relations
class Dashboard::Queries::EventsQuery
  def call
    Event.where(account: account).recent
  end
end

# ✅ OK - Response builders return API response hashes
class ResponseBuilder
  def call
    { conversion: conversion_data, attribution: { status: "pending" } }
  end
end
```

**Rule of thumb:** Use `ApplicationService` when the operation can succeed or fail and needs consistent error handling. Use plain classes when returning domain-specific data structures.

### Service Object Pattern

**ONLY expose `initialize` and `call` as public methods. Everything else is private.**

### ✅ GOOD - Inherits from ApplicationService

```ruby
module Users
  class IdentificationService < ApplicationService
    def initialize(account, params)
      @account = account
      @user_id = params[:user_id]
      @visitor_id = params[:visitor_id]
      @traits = params[:traits] || {}
    end

    private

    attr_reader :account, :user_id, :visitor_id, :traits

    def run
      return error_result(["user_id is required"]) unless user_id.present?

      persist_identification
      link_visitor_if_present

      success_result
    end

    def persist_identification
      user.traits = traits
      user.last_identified_at = Time.current
      user.save!  # Exceptions caught by ApplicationService
    end

    def link_visitor_if_present
      return unless visitor_id.present?
      return unless visitor

      visitor.update!(user_id: user_id)
    end

    def user
      @user ||= account.users.find_or_initialize_by(external_id: user_id)
    end

    def visitor
      @visitor ||= account.visitors.find_by(visitor_id: visitor_id)
    end
  end
end

# Usage
result = Users::IdentificationService.new(account, params).call
# Returns: { success: true } or { success: false, errors: [...] }
```

**Key Points**:
- Inherits from `ApplicationService`
- Only `initialize` and `call` are public
- Implements private `#run` method
- Uses `success_result` and `error_result` helpers
- Can use `save!` / `update!` - exceptions are caught
- Early returns for validation errors

#### ❌ BAD - Not Using ApplicationService

```ruby
module Users
  class IdentificationService
    def initialize(account, params)
      @account = account
      @params = params
    end

    def call
      # ❌ No error handling - exceptions will bubble up!
      user = account.users.find_or_initialize_by(external_id: params[:user_id])
      user.save!
    end

    # ❌ These should be private!
    def persist_user
      # ...
    end

    def link_visitor
      # ...
    end
  end
end
```

### Service Object Pattern Template

**Use this as your standard template:**

```ruby
module EntityName
  class ActionService < ApplicationService
    def initialize(required_param, optional_param: nil)
      @required_param = required_param
      @optional_param = optional_param
    end

    private

    attr_reader :required_param, :optional_param

    def run
      return error_result(["validation error"]) unless valid?

      perform_action

      success_result(data: result_data)
    end

    # All helper methods are private
    def valid?
      required_param.present?
    end

    def perform_action
      # Use save! / update! - exceptions caught by ApplicationService
      record.save!
    end

    # Memoized methods
    def record
      @record ||= expensive_lookup
    end
  end
end

# Usage
result = EntityName::ActionService.new(param).call
if result[:success]
  # Handle success
else
  # Handle errors: result[:errors]
end
```

### When You Need Multiple Public Methods

**If you need more than `call`, you probably need to split into multiple services.**

```ruby
# ❌ BAD - Service doing too much
class AccountManagementService
  def initialize(account)
    @account = account
  end

  def suspend
    # ...
  end

  def reactivate
    # ...
  end

  def cancel
    # ...
  end
end

# ✅ GOOD - Separate services
class Account::SuspensionService
  def initialize(account)
    @account = account
  end

  def call
    # Suspend logic
  end
end

class Account::ReactivationService
  def initialize(account)
    @account = account
  end

  def call
    # Reactivate logic
  end
end

class Account::CancellationService
  def initialize(account)
    @account = account
  end

  def call
    # Cancel logic
  end
end
```

### Memoization in Services

```ruby
class AccountLookupService
  def initialize(slug)
    @slug = slug
  end

  def call
    account || raise(AccountNotFound, "Account #{slug} not found")
  end

  private

  attr_reader :slug

  # Memoized - only queries once
  def account
    @account ||= Account.active.find_by(slug: slug)
  end
end
```

### Composition Over Inheritance

```ruby
# ✅ GOOD - Compose services
module Event
  class ProcessingPipeline
    def initialize(account)
      @account = account
    end

    def call(events_data)
      events_data
        .then { |events| validate_events(events) }
        .then { |events| enrich_events(events) }
        .then { |events| persist_events(events) }
        .then { |events| trigger_webhooks(events) }
    end

    private

    attr_reader :account

    def validate_events(events)
      ValidationService.new(account).call(events)
    end

    def enrich_events(events)
      EnrichmentService.new(account).call(events)
    end

    def persist_events(events)
      PersistenceService.new(account).call(events)
    end

    def trigger_webhooks(events)
      WebhookService.new(account).call(events)
    end
  end
end
```

### Background Jobs - Thin Wrappers Only

**Jobs are thin wrappers around services. All business logic lives in services. Never test jobs - test the services they call.**

```ruby
# ✅ GOOD - Thin job wrapper (no tests needed for jobs)
module Billing
  class ReportUsageJob < ApplicationJob
    queue_as :default

    def perform(account_id)
      ReportUsageService.new(Account.find(account_id)).call
    end
  end
end

# ✅ GOOD - Service has the logic and tests
module Billing
  class ReportUsageService < ApplicationService
    def initialize(account)
      @account = account
    end

    private

    attr_reader :account

    def run
      # All business logic here
      # This is what gets tested
    end
  end
end

# ❌ BAD - Logic in job
module Billing
  class ReportUsageJob < ApplicationJob
    def perform(account_id)
      account = Account.find(account_id)
      usage = Rails.cache.read(account.usage_cache_key)
      # Business logic in job - don't do this!
      Stripe::Billing::MeterEvent.create(...)
    end
  end
end
```

**Testing Jobs:**
- **Don't test jobs directly** - they're just wrappers
- **Test the service** the job calls
- Job tests only needed if testing retry logic, queue configuration, or error handling specific to ActiveJob

---

## Method Design Principles

### 1. Short Methods (< 10 lines)

```ruby
# ✅ GOOD
def process_event
  return unless processable?

  persist_event
  trigger_webhooks
  update_metrics
end

private

def processable?
  valid? && not_duplicate? && account.active?
end

def persist_event
  Event.create!(event_attributes)
end

def trigger_webhooks
  WebhookNotifier.notify(event)
end

def update_metrics
  MetricsCollector.increment(:events_processed)
end
```

### 2. Single Responsibility

```ruby
# ✅ GOOD - Each method does ONE thing
def authenticate_request
  api_key || unauthorized!
end

def api_key
  @api_key ||= find_api_key
end

def find_api_key
  ApiKey::AuthenticationService.new(auth_header).call
end

def unauthorized!
  raise Unauthorized, "Invalid API key"
end

# ❌ BAD - Method does too much
def authenticate_request
  header = request.headers["Authorization"]
  return error unless header.present?

  token = header.split(" ").last
  key = ApiKey.find_by(key_digest: Digest::SHA256.hexdigest(token))
  return error unless key

  account = key.account
  return error unless account.active?

  @current_account = account
  true
end
```

### 3. Descriptive Names

```ruby
# ✅ GOOD
def exceeded_rate_limit?
def within_rate_limit?
def visitor_has_active_session?
def event_requires_processing?

# ❌ BAD
def check
def process
def handle
def do_stuff
```

### 4. Early Returns / Guard Clauses

```ruby
# ✅ GOOD
def process_event(event)
  return if event.blank?
  return if event.already_processed?
  return unless account.active?

  perform_processing(event)
end

# ❌ BAD
def process_event(event)
  if event.present?
    if !event.already_processed?
      if account.active?
        perform_processing(event)
      end
    end
  end
end
```

---

## Functional Ruby Patterns

### Use Enumerable Methods

```ruby
# ✅ GOOD - Functional
def active_events
  events.select(&:active?)
end

def event_types
  events.map(&:event_type).uniq
end

def total_revenue
  events.sum(&:revenue)
end

def events_by_type
  events.group_by(&:event_type)
end

def all_valid?
  events.all?(&:valid?)
end

def any_errors?
  events.any?(&:error?)
end

# ❌ BAD - Procedural
def active_events
  result = []
  events.each do |event|
    if event.active?
      result << event
    end
  end
  result
end
```

### Use `then` for Pipelines

```ruby
# ✅ GOOD
def process_data(input)
  input
    .then { |data| validate(data) }
    .then { |data| transform(data) }
    .then { |data| persist(data) }
end

# Or with yield_self (alias for then)
def calculate_total
  events
    .then { |e| e.select(&:billable?) }
    .then { |e| e.sum(&:amount) }
    .then { |total| apply_discount(total) }
end
```

### Use `tap` for Side Effects

```ruby
# ✅ GOOD
def create_account(params)
  Account.new(params).tap do |account|
    account.save!
    AccountMailer.welcome(account).deliver_later
    Analytics.track(:account_created, account.id)
  end
end

def process_events(events)
  events
    .select(&:valid?)
    .tap { |valid| log_processing(valid) }
    .map { |event| persist_event(event) }
end
```

### Use `fetch` Instead of Hash Access

```ruby
# ✅ GOOD - Fails fast
def event_type
  params.fetch(:event_type)
end

def utm_source
  properties.fetch(:utm_source, "direct")
end

PROCESSORS = {
  page_view: PageViewProcessor,
  signup: SignupProcessor
}.freeze

def processor_for(type)
  PROCESSORS.fetch(type) { DefaultProcessor }
end

# ❌ BAD - Silent nils
def event_type
  params[:event_type]
end
```

---

## Controller Design

### Thin Controllers - Delegate to Services

```ruby
# ✅ GOOD
class Api::V1::EventsController < Api::V1::BaseController
  def create
    render json: ingestion_result, status: :accepted
  end

  private

  def ingestion_result
    @ingestion_result ||= Event::IngestionService
      .new(current_account)
      .call(events_params)
  end

  def events_params
    params.require(:events)
  end
end

# ❌ BAD - Business logic in controller
class Api::V1::EventsController < Api::V1::BaseController
  def create
    valid_events = []
    rejected_events = []

    params[:events].each do |event|
      if validate_event(event)
        valid_events << event
        Event::ProcessingJob.perform_later(event)
      else
        rejected_events << event
      end
    end

    render json: { accepted: valid_events.count, rejected: rejected_events }
  end
end
```

---

## Testing Conventions

### Use Memoized Fixture Methods

**ALWAYS use memoized private methods for fixtures. Never call `fixtures(:name)` directly.**

```ruby
# ✅ GOOD
class AccountTest < ActiveSupport::TestCase
  test "should be active" do
    assert account.active?
  end

  test "should suspend account" do
    account.suspend!
    assert account.suspended?
  end

  private

  def account
    @account ||= accounts(:one)
  end
end

# ❌ BAD
class AccountTest < ActiveSupport::TestCase
  test "should be active" do
    account = accounts(:one)  # ❌ Direct call
    assert account.active?
  end
end
```

### Service Object Tests

```ruby
class Event::IngestionServiceTest < ActiveSupport::TestCase
  test "should accept valid events" do
    result = service.call(valid_events)

    assert_equal 1, result[:accepted]
    assert_empty result[:rejected]
  end

  test "should reject invalid events" do
    result = service.call(invalid_events)

    assert_equal 0, result[:accepted]
    assert_equal 1, result[:rejected].size
  end

  private

  def service
    @service ||= Event::IngestionService.new(account)
  end

  def account
    @account ||= accounts(:one)
  end

  def valid_events
    [
      {
        event_type: "page_view",
        visitor_id: "abc123",
        session_id: "xyz789",
        timestamp: Time.current.iso8601,
        properties: { url: "https://example.com" }
      }
    ]
  end

  def invalid_events
    [{ event_type: "page_view" }]  # Missing required fields
  end
end
```

---

## Design Patterns to Use

### 1. Service Object Pattern

**One service per action, lives in namespaced folder.**
**Only `initialize` and `call` are public methods.**

```ruby
# app/services/event/ingestion_service.rb
# app/services/event/validation_service.rb
# app/services/visitor/identification_service.rb

module Event
  class IngestionService
    def initialize(account)
      @account = account
    end

    def call(events_data)
      # Implementation
    end

    private

    # All other methods are private
  end
end
```

### 2. Query Object Pattern

```ruby
# app/queries/events/by_utm_source_query.rb
module Events
  class ByUtmSourceQuery
    def initialize(account, source)
      @account = account
      @source = source
    end

    def call
      account
        .events
        .where("properties->>'utm_source' = ?", source)
        .order(occurred_at: :desc)
    end

    private

    attr_reader :account, :source
  end
end

# Usage
events = Events::ByUtmSourceQuery.new(account, "google").call
```

### 3. Form Object Pattern (for complex forms)

```ruby
class AccountRegistrationForm
  include ActiveModel::Model

  attr_accessor :name, :email, :company_name

  validates :name, :email, :company_name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }

  def save
    return false unless valid?

    ActiveRecord::Base.transaction do
      create_account
      create_user
      send_welcome_email
    end

    true
  end

  private

  def create_account
    @account = Account.create!(
      name: company_name,
      slug: company_name.parameterize
    )
  end

  def create_user
    User.create!(
      account: @account,
      name: name,
      email: email
    )
  end

  def send_welcome_email
    AccountMailer.welcome(@account).deliver_later
  end
end
```

### 4. Decorator/Presenter Pattern

```ruby
class EventPresenter < SimpleDelegator
  def formatted_timestamp
    occurred_at.strftime("%B %d, %Y at %I:%M %p")
  end

  def utm_summary
    [
      properties["utm_source"],
      properties["utm_medium"],
      properties["utm_campaign"]
    ].compact.join(" / ")
  end

  def display_url
    properties["url"]&.gsub(%r{^https?://}, "")
  end
end

# Usage in controller/view
@event = EventPresenter.new(Event.find(params[:id]))
@event.formatted_timestamp  # "November 7, 2025 at 10:30 AM"
```

### 5. Value Object Pattern

```ruby
class UtmParameters
  attr_reader :source, :medium, :campaign, :content, :term

  def initialize(source: nil, medium: nil, campaign: nil, content: nil, term: nil)
    @source = source
    @medium = medium
    @campaign = campaign
    @content = content
    @term = term
  end

  def present?
    [source, medium, campaign].any?(&:present?)
  end

  def to_h
    {
      utm_source: source,
      utm_medium: medium,
      utm_campaign: campaign,
      utm_content: content,
      utm_term: term
    }.compact
  end

  def summary
    [source, medium, campaign].compact.join(" / ")
  end
end
```

---

## Code Smells to Avoid

### ❌ Avoid These

1. **Long methods** (> 10 lines)
2. **Long parameter lists** (> 3 params)
3. **Feature envy** (method uses another object's data more than its own)
4. **Data clumps** (same group of params passed around)
5. **Primitive obsession** (use objects, not primitives)
6. **Comments explaining what** (code should be self-documenting)
7. **Magic numbers/strings**
8. **Global state**
9. **Nested conditionals**
10. **God objects** (objects that know/do too much)
11. **Public methods in services** (other than initialize/call)

### ✅ Do Instead

1. **Extract methods** - break down long methods
2. **Introduce parameter object** - group related params
3. **Move method** - put method where data lives
4. **Extract class** - split large classes
5. **Introduce value object** - wrap primitives
6. **Rename** - make code self-documenting
7. **Extract constant** - name magic values
8. **Dependency injection** - pass dependencies
9. **Guard clauses** - early returns
10. **Single responsibility** - one reason to change
11. **Make methods private** - hide implementation details

---

## Code Formatting

### Line Continuation Indentation

**When breaking a line, indent the continuation by 2 spaces from the previous line.**

```ruby
# ✅ GOOD - 2 space indent
validates :slug,
  presence: true,
  uniqueness: true,
  format: {
    with: /\A[a-z0-9-]+\z/,
    message: "must be lowercase letters, numbers, and hyphens only"
  }

result = SomeService
  .new(account)
  .call(params)

event_data = {
  event_type: "page_view",
  visitor_id: "abc123",
  properties: {
    url: "https://example.com"
  }
}

# ❌ BAD - Aligning to match
validates :slug,
          presence: true,
          uniqueness: true

# ❌ BAD - No indentation
validates :slug,
presence: true,
uniqueness: true
```

### ERB View Rules

**Extract conditionals to partials.** If/else statements in views should use partials for cleaner code:

```erb
# ✅ GOOD - Use partials for conditional sections
<%= render "admin_controls" if @can_manage %>
<%= render "owner_section" if @is_owner %>

# ❌ BAD - Inline conditionals with lots of HTML
<% if @can_manage %>
  <div class="admin-panel">
    <!-- 50 lines of HTML -->
  </div>
<% end %>
```

### ERB/HTML Indentation

**Use 2-space indentation for nested elements. Each nested level adds 2 spaces.**

```erb
# ✅ GOOD - 2 space indent for nested elements
<div class="container">
  <turbo-frame id="filters">
    <div class="filter-group">
      <label>Date Range</label>
      <select>
        <option value="7d">Last 7 days</option>
        <option value="30d">Last 30 days</option>
      </select>
    </div>
  </turbo-frame>
</div>

# ❌ BAD - 4 space indent
<div class="container">
    <turbo-frame id="filters">
        <div class="filter-group">
        </div>
    </turbo-frame>
</div>

# ❌ BAD - Inconsistent indentation
<div class="container">
<turbo-frame id="filters">
  <div class="filter-group">
      </div>
</turbo-frame>
</div>
```

---

## Naming Conventions

### Variables & Methods

```ruby
# ✅ GOOD - Clear, descriptive
visitor_id
session_started_at
utm_parameters
rate_limit_exceeded?
account_active?

# ❌ BAD - Unclear abbreviations
vid
sess_start
utm_params (unless universally understood)
rl_exceeded?
acc_active?
```

### Classes & Modules

```ruby
# ✅ GOOD
Event::IngestionService
Visitor::IdentificationService
Session::UtmCaptureService

# ❌ BAD
EventIngestor
VisitorIdentifier
SessionUTMCapture
```

### Constants

```ruby
# ✅ GOOD
API_VERSION = "v1"
DEFAULT_RATE_LIMIT = 10_000
VALID_EVENT_TYPES = %w[page_view signup purchase].freeze

# ❌ BAD
Api_Version = "v1"
DefaultRateLimit = 10000
valid_event_types = %w[page_view signup purchase]
```

---

## Doc-Driven Development (DDD) Workflow

**ALWAYS follow this 7-step cycle:**

1. **Write API Doc Spec** - Document behavior
2. **Write Unit Test (RED)** - Failing test
3. **Write Passing Code (GREEN)** - Minimal implementation
4. **Run All Tests** - Ensure no regressions
5. **Refactor** - Improve while keeping tests green
6. **Update Spec** - Add examples, edge cases
7. **Git Commit** - Commit with conventional message

---

## Git Commit Convention

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

**Scopes**: `auth`, `event`, `visitor`, `session`, `api`, `dashboard`, `docs`

**Example**:
```
feat(auth): add API key generation service

- Implement ApiKey::GenerationService
- Generate keys in format sk_{env}_{random32}
- Hash keys with SHA256 before storage
- Add comprehensive test coverage

Closes #5
```

**Important**: Do NOT include any Claude/AI attribution in commit messages (no "Generated with Claude", no "Co-Authored-By: Claude", etc.).

---

## Security Patterns

### Use Prefixed IDs for Customer-Facing IDs

**CRITICAL: Never expose raw database IDs to customers. Always use prefixed IDs.**

Use the [prefixed_ids gem](https://github.com/excid3/prefixed_ids) for any IDs exposed externally:

```ruby
# Gemfile
gem 'prefixed_ids'

# app/models/account.rb
class Account < ApplicationRecord
  has_prefix_id :acct
end

# app/models/user.rb
class User < ApplicationRecord
  has_prefix_id :user
end

# app/models/visitor.rb
class Visitor < ApplicationRecord
  has_prefix_id :vis
end

# Usage
account = Account.first
account.prefix_id  # => "acct_1a2b3c4d"
Account.find_by_prefix_id("acct_1a2b3c4d")

# In API responses
{
  "account": {
    "id": "acct_1a2b3c4d",  # NOT the database ID!
    "name": "Acme Inc"
  }
}
```

**Benefits:**
- Security: Hides sequential database IDs
- Readability: Easy to identify resource type
- Compatibility: Works with route params, JSON API responses
- Professional: Follows Stripe-style API design

**When to use:**
- ✅ Account IDs: `acct_*`
- ✅ User IDs: `user_*`
- ✅ Visitor IDs: `vis_*`
- ✅ Session IDs: `sess_*`
- ✅ Event IDs: `evt_*`

**When NOT to use:**
- ❌ API Keys (use custom format: `sk_{env}_{random32}`)
- ❌ Internal background job IDs
- ❌ Database foreign keys (use regular IDs internally)

**IMPORTANT - Always compare using `prefix_id`, not `id`:**

```ruby
# ✅ GOOD - Compare prefix_ids
@filter_params[:model]&.prefix_id == model.prefix_id

# ❌ BAD - Don't use raw database IDs
@filter_params[:model]&.id == model.id
```

---

## Multi-Tenancy - CRITICAL

**Every query MUST be scoped to account.**

```ruby
# ✅ GOOD
@account.events.where(event_type: "page_view")
Event.where(account: @account, event_type: "page_view")

# ❌ BAD - NEVER DO THIS
Event.where(event_type: "page_view")
Event.all
```

**Always test cross-account isolation:**

```ruby
test "account A cannot access account B's data" do
  event = other_account.events.create!(...)

  assert_nil account.events.find_by(id: event.id)
end

private

def account
  @account ||= accounts(:one)
end

def other_account
  @other_account ||= accounts(:two)
end
```

---

## Remember

1. **Write functional Ruby, not procedural PHP**
2. **No giant case/if-else statements** - use polymorphism, hash lookups, early returns
3. **Keep models thin** - extract to concerns
4. **Short methods** - < 10 lines
5. **Single responsibility** - each method does ONE thing
6. **Service objects: ONLY initialize and call are public** - everything else private
7. **Use memoization** - `@variable ||= expensive_call`
8. **Use enumerable methods** - `map`, `select`, `reject`, not loops
9. **Service objects** - one per action, namespaced
10. **Always scope to account** - multi-tenancy is critical
11. **Follow DDD cycle** - doc → test → code → test all → refactor → update doc → commit

---

**This guide is mandatory. Write beautiful, functional Ruby code.**
