# Claude Development Guide for Multibuzz

This document contains conventions, patterns, and best practices specific to this project. **Always follow these guidelines.**

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

### ✅ GOOD - Thin Model with Concerns

```ruby
# app/models/account.rb
class Account < ApplicationRecord
  include Account::Validations
  include Account::Relationships
  include Account::Scopes
  include Account::StatusManagement
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

## Service Objects - Only `initialize` and `call` Public

**CRITICAL: Service objects should ONLY expose `initialize` and `call` as public methods. Everything else is private.**

### ✅ GOOD - Only Public Methods: initialize, call

```ruby
module Event
  class IngestionService
    def initialize(account)
      @account = account
    end

    def call(events_data)
      {
        accepted: valid_events(events_data).count,
        rejected: rejected_events(events_data)
      }.tap { |result| queue_valid_events(events_data) }
    end

    private

    attr_reader :account

    def valid_events(events_data)
      events_data.select { |event| valid_event?(event) }
    end

    def rejected_events(events_data)
      events_data
        .reject { |event| valid_event?(event) }
        .map { |event| rejection_info(event) }
    end

    def queue_valid_events(events_data)
      valid_events(events_data).each { |event| queue_event(event) }
    end

    def queue_event(event)
      Event::ProcessingJob.perform_later(account.id, event)
    end

    def valid_event?(event)
      validator.valid?(event)
    end

    def validator
      @validator ||= Event::ValidationService.new
    end

    def rejection_info(event)
      {
        event: event,
        errors: validator.errors_for(event)
      }
    end
  end
end

# Usage
result = Event::IngestionService.new(account).call(events_data)
```

#### ❌ BAD - Public Methods Exposing Implementation

```ruby
module Event
  class IngestionService
    def initialize(account)
      @account = account
    end

    def call(events_data)
      # ...
    end

    # ❌ These should be private!
    def valid_events(events_data)
      # ...
    end

    def rejected_events(events_data)
      # ...
    end

    def queue_event(event)
      # ...
    end
  end
end
```

### Service Object Pattern Template

**Use this as your standard template:**

```ruby
module EntityName
  class ActionService
    def initialize(required_param, optional: nil)
      @required_param = required_param
      @optional = optional
    end

    def call(input = nil)
      # Main logic here
      # Return value or hash
    end

    private

    attr_reader :required_param, :optional

    # All helper methods go here
    def helper_method
      # ...
    end

    def another_helper
      # ...
    end

    # Memoized methods
    def expensive_calculation
      @expensive_calculation ||= perform_calculation
    end
  end
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
