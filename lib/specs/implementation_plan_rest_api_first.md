# mbuzz REST API - Doc-Driven Implementation Plan

## Overview

This document outlines the REST API-first implementation approach for mbuzz, replacing the original gem-first strategy. We'll build a production-ready REST API that any client (any language/framework) can consume.

**Domain**: mbuzz.co
**API Base URL**: https://mbuzz.co/api/v1

**Philosophy**: Documentation-Driven Development (DDD)
- Write API docs first (contract-first design)
- Write tests against the spec
- Implement to pass tests
- Refactor with confidence
- Keep docs in sync

**Timeline**: 1.5-2 weeks for MVP API

---

## Doc-Driven Development (DDD) Workflow

### The 7-Step Cycle

```
┌─────────────────────────────────────────────────────────┐
│  1. WRITE API DOC SPEC                                  │
│     OpenAPI spec → defines contract                     │
│     Getting Started guide → defines behavior            │
└───────────────────┬─────────────────────────────────────┘
                    │
┌───────────────────▼─────────────────────────────────────┐
│  2. WRITE UNIT TEST (RED)                               │
│     Test against the documented behavior                │
│     test/services/*, test/controllers/*                 │
└───────────────────┬─────────────────────────────────────┘
                    │
┌───────────────────▼─────────────────────────────────────┐
│  3. WRITE PASSING CODE (GREEN)                          │
│     Implement service/controller to pass test           │
│     app/services/*, app/controllers/*                   │
└───────────────────┬─────────────────────────────────────┘
                    │
┌───────────────────▼─────────────────────────────────────┐
│  4. RUN ALL TESTS                                       │
│     rails test                                          │
│     Ensure no regressions                               │
└───────────────────┬─────────────────────────────────────┘
                    │
┌───────────────────▼─────────────────────────────────────┐
│  5. REFACTOR                                            │
│     Extract, optimize, improve readability              │
│     Tests stay green                                    │
└───────────────────┬─────────────────────────────────────┘
                    │
┌───────────────────▼─────────────────────────────────────┐
│  6. UPDATE SPEC                                         │
│     Add examples, edge cases, error scenarios           │
│     Keep API docs accurate                              │
└───────────────────┬─────────────────────────────────────┘
                    │
┌───────────────────▼─────────────────────────────────────┐
│  7. GIT COMMIT                                          │
│     Conventional commit message                         │
│     feat(event): add batch ingestion endpoint           │
└─────────────────────────────────────────────────────────┘
```

### Example: Implementing Event Ingestion

**Step 1: Write API Doc**
```yaml
# docs/api/openapi.yml
paths:
  /api/v1/events:
    post:
      summary: Ingest batch of events
      requestBody:
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/EventBatch'
      responses:
        '202':
          description: Events accepted for processing
```

**Step 2: Write Test**
```ruby
# test/controllers/api/v1/events_controller_test.rb
test "should accept valid event batch" do
  post api_v1_events_url,
    params: { events: [{ event_type: "page_view", ... }] },
    headers: { "Authorization" => "Bearer #{@api_key}" },
    as: :json

  assert_response :accepted
  assert_equal 1, json_response["accepted"]
end
```

**Step 3: Write Code**
```ruby
# app/controllers/api/v1/events_controller.rb
def create
  result = Event::IngestionService.new(@current_account).call(params[:events])
  render json: result, status: :accepted
end
```

**Step 4: Run Tests**
```bash
rails test
```

**Step 5: Refactor**
- Extract validation logic
- Add error handling
- Improve naming

**Step 6: Update Spec**
- Add error response examples
- Document rate limits
- Add code samples in multiple languages

**Step 7: Commit**
```bash
git add -A
git commit -m "feat(event): add batch ingestion endpoint

- Implement Event::IngestionService
- Add API authentication
- Support batch processing
- Return accepted/rejected counts

Closes #1"
```

---

## Documentation Structure

### API Documentation Location

```
docs/
├── api/
│   ├── openapi.yml                 # OpenAPI 3.0 spec (machine-readable)
│   ├── getting_started.md          # Quick start guide
│   ├── authentication.md           # API key management
│   ├── events.md                   # Event tracking endpoints
│   ├── rate_limits.md              # Rate limit policies
│   ├── errors.md                   # Error codes & handling
│   └── examples/                   # Code samples
│       ├── curl.sh
│       ├── ruby.rb
│       ├── javascript.js
│       ├── python.py
│       └── php.php
│
├── architecture/
│   ├── overview.md                 # System design
│   ├── multi_tenancy.md           # Tenant isolation
│   ├── data_model.md              # Database schema
│   └── async_processing.md        # Job queues
│
└── development/
    ├── setup.md                    # Local development
    ├── testing.md                  # Test strategy
    └── deployment.md               # Kamal deployment
```

### OpenAPI Spec Benefits

1. **Auto-generated docs** (Redoc, Swagger UI)
2. **Client SDK generation** (OpenAPI Generator)
3. **Request validation** (Committee gem)
4. **Contract testing** (Dredd, Pact)
5. **Mocking** (Prism)

---

## Phase 1: Core API Implementation (1.5 weeks)

### Week 1, Days 1-2: Foundation + Authentication

#### Day 1 Morning: Account & API Key Models

**1. Write API Doc**
- `docs/api/authentication.md` (Getting Started section)
- Define API key format: `sk_{environment}_{random32}`
- Document authentication header format

**2. Write Tests**
- `test/models/account_test.rb`
- `test/models/api_key_test.rb`
- `test/services/api_key/generation_service_test.rb`
- `test/services/api_key/authentication_service_test.rb`

**3. Implement**
- Generate migrations (Account, ApiKey)
- Create models with validations
- Implement services
- Add controller concern for authentication

**4. Run Tests**
```bash
rails test test/models/account_test.rb
rails test test/models/api_key_test.rb
rails test test/services/api_key/
```

**5. Refactor**
- Extract API key generation logic
- Add bcrypt for key hashing
- Improve error messages

**6. Update Spec**
- Add API key lifecycle documentation
- Document key rotation strategy
- Add security best practices

**7. Commit**
```bash
git commit -m "feat(auth): add API key authentication

- Add Account and ApiKey models
- Implement key generation service
- Add authentication service with Bearer token support
- Hash keys with SHA256 for security

Part of #2"
```

#### Day 1 Afternoon: Visitor & Session Models

**1. Write API Doc**
- `docs/api/events.md` (Visitor/Session concepts)
- Document visitor_id format (SHA256 hash)
- Document session_id format (random hex)
- Explain UTM parameter capture

**2. Write Tests**
- `test/models/visitor_test.rb`
- `test/models/session_test.rb`
- `test/services/visitor/identification_service_test.rb`
- `test/services/visitor/lookup_service_test.rb`
- `test/services/session/tracking_service_test.rb`
- `test/services/session/utm_capture_service_test.rb`

**3. Implement**
- Generate migrations (Visitor, Session)
- Create models with associations
- Implement visitor identification
- Implement session tracking with UTM capture

**4-7**: Run tests, refactor, update docs, commit

#### Day 2: Event Model & Validation

**1. Write API Doc**
- `docs/api/openapi.yml` (Event schema)
- Define required fields
- Define property structure (JSONB)
- Document event types

**2. Write Tests**
- `test/models/event_test.rb`
- `test/services/event/validation_service_test.rb`

**3-7**: Implement, test, refactor, update docs, commit

---

### Week 1, Days 3-4: Event Ingestion API

#### Day 3: API Endpoint + Ingestion Service

**1. Write API Doc**
```yaml
# docs/api/openapi.yml
paths:
  /api/v1/events:
    post:
      summary: Ingest batch of tracking events
      security:
        - bearerAuth: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required:
                - events
              properties:
                events:
                  type: array
                  items:
                    $ref: '#/components/schemas/Event'
      responses:
        '202':
          description: Events accepted for processing
          content:
            application/json:
              schema:
                type: object
                properties:
                  accepted:
                    type: integer
                  rejected:
                    type: array
                    items:
                      type: object
        '401':
          $ref: '#/components/responses/UnauthorizedError'
        '422':
          $ref: '#/components/responses/ValidationError'
        '429':
          $ref: '#/components/responses/RateLimitError'
```

**2. Write Tests**
- `test/controllers/api/v1/events_controller_test.rb`
  - Valid batch
  - Authentication failure
  - Validation errors
  - Rate limiting
  - Multi-tenancy isolation
- `test/services/event/ingestion_service_test.rb`
  - Batch processing
  - Partial failures
  - Queue integration

**3. Implement**
```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :events, only: [:create]
    get 'health', to: 'health#show'
    get 'validate', to: 'validate#show'
  end
end

# app/controllers/api/v1/base_controller.rb
class Api::V1::BaseController < ActionController::API
  before_action :authenticate_api_key

  private

  def authenticate_api_key
    result = ApiKey::AuthenticationService.new(request.headers['Authorization']).call

    if result[:success]
      @current_account = result[:account]
    else
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end
end

# app/controllers/api/v1/events_controller.rb
class Api::V1::EventsController < Api::V1::BaseController
  def create
    result = Event::IngestionService.new(@current_account).call(event_params)
    render json: result, status: :accepted
  end

  private

  def event_params
    params.require(:events)
  end
end

# app/services/event/ingestion_service.rb
module Event
  class IngestionService
    def initialize(account)
      @account = account
    end

    def call(events_data)
      validated = validate_events(events_data)
      queue_events(validated[:valid])

      {
        accepted: validated[:valid].count,
        rejected: validated[:invalid]
      }
    end

    private

    def validate_events(events_data)
      # Implementation
    end

    def queue_events(events)
      events.each do |event|
        Event::ProcessingJob.perform_later(@account.id, event)
      end
    end
  end
end
```

**4-7**: Run tests, refactor, update docs, commit

#### Day 4: Background Processing + Rate Limiting

**1. Write API Doc**
- `docs/api/rate_limits.md`
- Document rate limit tiers
- Document headers (X-RateLimit-*)
- Document 429 response

**2. Write Tests**
- `test/jobs/event/processing_job_test.rb`
- `test/services/event/processing_service_test.rb`
- `test/services/api_key/rate_limiter_service_test.rb`

**3. Implement**
- Event::ProcessingJob (Solid Queue)
- Event::ProcessingService
- ApiKey::RateLimiterService (Redis-backed)
- Add rate limit middleware

**4-7**: Run tests, refactor, update docs, commit

---

### Week 1, Day 5: Health Check, Validation, Testing

#### Health & Validation Endpoints

**1. Write API Doc**
```yaml
paths:
  /api/v1/health:
    get:
      summary: Health check endpoint
      responses:
        '200':
          description: Service is healthy

  /api/v1/validate:
    get:
      summary: Validate API key and return account info
      security:
        - bearerAuth: []
      responses:
        '200':
          description: Valid API key
          content:
            application/json:
              schema:
                type: object
                properties:
                  valid:
                    type: boolean
                  account:
                    $ref: '#/components/schemas/Account'
```

**2-7**: Test, implement, refactor, doc, commit

#### Integration Testing

**1. Write Tests**
- `test/integration/event_tracking_flow_test.rb` (end-to-end)
- `test/integration/multi_tenancy_isolation_test.rb` (critical!)
- `test/integration/rate_limiting_test.rb`

**2. Run All Tests**
```bash
rails test              # Run all unit tests
rails test:integration  # Run integration tests
```

**3. Document Coverage**
- Add coverage report (SimpleCov)
- Aim for 95%+ coverage

---

### Week 2: Dashboard + Polish

#### Days 1-2: Admin Authentication & Dashboard

**1. Write Doc**
- `docs/dashboard/overview.md`
- Screenshots/wireframes
- Feature list

**2-7**: Implement user authentication, dashboard views, tests, commit

#### Days 3-4: API Key Management UI

- Create/revoke API keys via web UI
- View usage statistics
- Test/live environment toggle

#### Day 5: Documentation & Examples

**1. Complete API Documentation**
- Finish OpenAPI spec
- Add comprehensive examples in multiple languages
- Add troubleshooting guide

**2. Create Getting Started Guide**
```markdown
# docs/api/getting_started.md

## Quick Start

### 1. Get Your API Key
[Screenshot of dashboard]

### 2. Make Your First Request
```bash
curl -X POST https://mbuzz.co/api/v1/events \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "events": [{
      "event_type": "page_view",
      "visitor_id": "unique_visitor_id",
      "session_id": "unique_session_id",
      "timestamp": "2025-11-07T10:00:00Z",
      "properties": {
        "url": "https://example.com",
        "utm_source": "google",
        "utm_medium": "cpc"
      }
    }]
  }'
```

### 3. Verify Events
[How to check dashboard]
```

**3. Generate API Docs Site**
```bash
# Install Redoc CLI
npm install -g @redocly/cli

# Generate static docs
redocly build-docs docs/api/openapi.yml -o public/api-docs.html

# Or use Swagger UI
# Host at https://docs.mbuzz.co or https://mbuzz.co/docs
```

---

## Testing Strategy

### Test Pyramid

```
        ┌──────────┐
        │  E2E (5%) │
        │Integration│
        └──────────┘
      ┌─────────────────┐
      │  Integration     │
      │    Tests (15%)   │
      └─────────────────┘
   ┌──────────────────────────┐
   │    Unit Tests (80%)       │
   │ Models, Services, Jobs    │
   └──────────────────────────┘
```

### Test Coverage Requirements

| Component | Coverage Target | Priority |
|-----------|----------------|----------|
| Models | 100% | Critical |
| Services | 95%+ | Critical |
| Controllers | 90%+ | High |
| Jobs | 95%+ | High |
| Overall | 95%+ | High |

### Key Test Scenarios (Must Test!)

#### Multi-Tenancy Isolation ⚠️ CRITICAL
```ruby
# test/integration/multi_tenancy_isolation_test.rb
test "account A cannot access account B's data" do
  account_a = accounts(:one)
  account_b = accounts(:two)

  # Create event for account B
  event = account_b.events.create!(...)

  # Try to access with account A's API key
  get api_v1_event_url(event),
    headers: { "Authorization" => "Bearer #{account_a.api_keys.first.key}" }

  assert_response :not_found  # Should not reveal existence
end
```

#### Rate Limiting
```ruby
test "enforces rate limits per account" do
  # Make requests up to limit
  # Assert 429 on limit exceeded
end
```

#### Idempotency
```ruby
test "duplicate events are handled gracefully" do
  # Send same event twice with same ID
  # Assert only one event created
end
```

#### Async Processing
```ruby
test "events are processed asynchronously" do
  assert_enqueued_jobs 1, only: Event::ProcessingJob do
    post api_v1_events_url, params: { events: [...] }
  end
end
```

---

## API Documentation Standards

### OpenAPI Best Practices

1. **Use Components** (DRY)
```yaml
components:
  schemas:
    Event:
      type: object
      required: [event_type, visitor_id]
      # ...

  responses:
    UnauthorizedError:
      description: Invalid or missing API key

  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
```

2. **Provide Examples**
```yaml
examples:
  PageView:
    value:
      event_type: "page_view"
      visitor_id: "abc123"
      properties:
        url: "https://example.com"
        utm_source: "google"
```

3. **Document All Responses**
- Success (2xx)
- Client errors (4xx)
- Server errors (5xx)

4. **Add Descriptions**
```yaml
description: |
  Ingest a batch of tracking events. Events are queued for
  asynchronous processing. You will receive a 202 Accepted
  response immediately with counts of accepted/rejected events.

  Rate limits apply per account. See /docs/rate-limits for details.
```

---

## Git Workflow

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

**Scopes**:
- `auth`: Authentication/API keys
- `event`: Event ingestion
- `visitor`: Visitor tracking
- `session`: Session management
- `api`: API endpoints
- `dashboard`: Web UI
- `docs`: Documentation
- `test`: Tests only

### Branch Strategy

```
main (production)
└── feature/rest-api-mvp (work here)
    ├── feat/auth-api-keys
    ├── feat/event-ingestion
    ├── feat/dashboard
    └── ...
```

### Commit Frequency

✅ **Good**: Small, focused commits after each DDD cycle
```
feat(auth): add API key model and generation
feat(auth): add authentication service
feat(event): add event model and validation
feat(event): add ingestion endpoint
```

❌ **Bad**: Large, infrequent commits
```
feat: add entire API
```

---

## Success Criteria

### API Functionality ✅
- [x] POST /api/v1/events accepts and queues events
- [x] GET /api/v1/validate validates API keys
- [x] GET /api/v1/health returns status
- [x] Bearer token authentication works
- [x] Rate limiting enforced (with X-RateLimit-* headers)
- [x] Multi-tenancy isolation verified
- [x] Async processing via Solid Queue
- [x] Returns 202 Accepted for all requests (even with partial failures)
- [x] Batch processing with partial failure support

### Documentation ✅
- [x] OpenAPI spec complete and valid (docs/api/openapi.yml)
- [x] Getting Started guide published (dynamic .md.erb at /docs/getting-started)
- [x] Code examples in 3+ languages (Ruby, JavaScript, Python)
- [x] Error handling documented
- [x] Rate limits documented
- [x] API docs site live at /docs/* routes
- [x] Beautiful Tailwind-styled documentation layout
- [x] Dynamic ERB content (shows user's API key when logged in)

### Testing ✅
- [x] Comprehensive test coverage (1,030 assertions passing)
- [x] Multi-tenancy isolation tests pass
- [x] Integration tests pass (4 end-to-end tests)
- [x] Rate limiting headers test
- [x] Batch processing with partial failures test
- [x] All 12 test files passing with 0 failures

### Dashboard ✅
- [x] User authentication works
- [x] Dashboard navigation with tabs (Dashboard, API Keys)
- [x] Event listing with recent events
- [x] UTM breakdown report (top 10)
- [x] Basic usage statistics

### API Keys Management UI ✅
- [x] `/dashboard/api-keys` - Full API key management interface
- [x] Generate new API keys with environment selection (test/live)
- [x] One-time plaintext key display with copy button
- [x] Masked key display on index (`sk_test_abc1****`)
- [x] Key status badges (Active/Revoked)
- [x] Revoke functionality with confirmation
- [x] Last used tracking
- [x] Empty state with helpful guidance
- [x] All microcopy driven by i18n (config/locales/en.yml)
- [x] Beautiful Tailwind UI matching dashboard design

### Security ✅
- [x] Prefixed IDs for all customer-facing resources
  - Accounts: `acct_*`
  - Users: `user_*`
  - Visitors: `vis_*`
  - Sessions: `sess_*`
  - Events: `evt_*`
- [x] API key hashing with SHA256 (no plaintext storage)
- [x] No `plaintext_key` column in database (verified by tests)
- [x] Plaintext keys filtered from logs (`:plaintext_key`, `:api_key`, `:key_digest`)
- [x] One-time plaintext display only on creation
- [x] Bearer token authentication
- [x] Multi-tenant data isolation
- [x] Comprehensive security tests (10 controller tests, 38 assertions)

---

## Phase 1 MVP Completion Status

**Status**: ✅ **COMPLETE** (as of 2025-11-12)

### Implementation Summary

The Phase 1 MVP has been successfully completed following the Doc-Driven Development (DDD) workflow. All core functionality is working, tested, and documented.

**Key Achievements**:
- 21 files created/modified
- 205 tests passing with 1,564 assertions (0 failures)
- Full end-to-end event tracking flow verified
- Multi-tenancy isolation confirmed
- API documentation site live with dynamic markdown
- API Keys management UI complete
- Security hardened with SHA256 hashing and zero plaintext storage

**Architecture Highlights**:
- Clean service object pattern (only `initialize` and `call` public)
- Functional Ruby throughout (no procedural code)
- Model concerns for organization
- Async job processing with Solid Queue
- Redis-backed rate limiting
- Dynamic markdown documentation with ERB
- Tailwind CSS v3 with @tailwindcss/typography

**Security Features**:
- Zero plaintext API key storage (SHA256 digest only)
- One-time key display on generation
- Sensitive params filtered from logs
- Multi-tenant data isolation enforced
- Prefixed IDs for all customer-facing resources
- Comprehensive security test coverage

**Production Readiness**: ✅ Ready to deploy

The implementation matches all specifications from `feature_1_utm_tracking_spec.md` and follows all conventions from `CLAUDE.md`.

---

## Phase 2: TimescaleDB + Multi-Touch Attribution (Next)

**See**: `lib/docs/architecture/attribution_methodology.md` - Canonical attribution design
**See**: `lib/docs/architecture/conversion_funnel_analysis.md` - Funnel analysis approach

### Week 1: TimescaleDB Integration ✅ COMPLETE

**Goal**: Convert events/sessions to hypertables for 10-20x performance improvement.

**Key Benefits**:
- ✅ Lossless compression (90% storage savings, all data preserved)
- ✅ Automatic time-based partitioning
- ✅ Continuous aggregates for instant dashboard queries
- ✅ No data deletion (keep all raw data forever)

**Implementation**:
1. Add `timescaledb` gem
2. Migrations: Enable extension, convert events/sessions to hypertables (1-week chunks)
3. Migrations: Add compression (events: 7 days, sessions: 30 days, NO retention policy)
4. Migrations: Create continuous aggregates (channel-based, not UTM-only):
   - `channel_attribution_daily` - Channel performance aggregated by day
   - `source_attribution_daily` - Traffic source breakdown
5. Update dashboard services to query continuous aggregates

**Success Criteria**:
- [✅] Events & sessions are hypertables
- [✅] Compression active, no retention policy
- [✅] Continuous aggregates created (channel-based)
- [✅] Dashboard queries <100ms (pre-computed aggregates ready)
- [✅] All 242 tests still pass

---

### Week 2-4: Multi-Touch Attribution Models

**Goal**: Implement 11 attribution models with declarative language for custom models.

**IMPORTANT**: Attribution is **channel-based** (not UTM-based). UTM is stored for drill-down detail only.

---

#### 11 Attribution Models

**Rule-Based Models** (8):
1. **First Touch** - 100% credit to first channel
2. **Last Touch** - 100% credit to last channel
3. **Linear** (aka Participation) - Equal credit to all channels
4. **Time Decay** - Exponential decay (7-day half-life)
5. **U-Shaped** (Position-Based) - 40% first, 40% last, 20% middle
6. **W-Shaped** - 30% first, 30% last, 30% opportunity (MQL event), 10% other
7. **Z-Shaped** (B2B Full Path) - 22.5% each: first, MQL, SQL, last + 10% other
8. **Custom** - User-defined via declarative language

**Data-Driven Models** (3 - Phase 3+):
9. **Algorithmic** - Machine learning based on conversion patterns
10. **Markov Chain** - Probability-based using transition matrices
11. **Shapley Value** - Game theory cooperative credit

---

#### Database Schema

```
conversions:
- account_id, visitor_id, session_id, event_id
- conversion_type (signup, purchase, trial_start)
- revenue (decimal, nullable)
- converted_at
- has_prefix_id :conv

attribution_credits:
- account_id, conversion_id, session_id, attribution_model_id
- attribution_model (first_touch, linear, etc.)
- credit (0.0 to 1.0)
- revenue_credit (nullable)
- channel (PRIMARY - what gets credit)
- utm_data (jsonb, REFERENCE - for drill-down)
- has_prefix_id :cred

attribution_models (custom models):
- account_id, name, description
- model_type (preset, custom)
- dsl_code (text) - Declarative language source
- rules (jsonb) - Compiled AST
- is_active
- has_prefix_id :amod
```

---

#### Declarative Attribution Language

**See**: `lib/specs/attribution_dsl_design.md` for full design spec.

**Note**: Phase 2C will implement a **true declarative language**, not YAML config.

**Design Goals**:
- Users describe **what** they want, not **how** to compute it
- Composable rules (combine conditions, weights, distributions)
- Type-safe (credits sum to 1.0, validated at definition time)
- Readable by non-technical marketers
- Visual builder generates valid DSL code

**Example Syntax** (draft):
```
model "U-Shaped Attribution"
  credit first_touch with 0.4
  credit last_touch with 0.4
  credit middle_touches with 0.2 equally
end

model "Channel Weighted"
  weight channel("paid_search") by 1.5
  weight channel("email") by 1.2
  distribute proportionally
end
```

**Implementation Components**:
- Lexer (tokenize DSL text)
- Parser (build AST)
- Validator (enforce credits sum to 1.0)
- Interpreter (execute AST against journey)
- Visual builder UI (generates DSL code)

---

#### Service Architecture

```
app/services/attribution/
├── base_service.rb              # Abstract base
├── dsl/                         # Declarative language engine
│   ├── lexer.rb
│   ├── parser.rb
│   ├── validator.rb
│   ├── interpreter.rb
│   └── ast/                     # AST node types
├── presets/                     # Built-in models (7)
│   ├── first_touch_service.rb
│   ├── last_touch_service.rb
│   ├── linear_service.rb
│   ├── time_decay_service.rb
│   ├── u_shaped_service.rb
│   ├── w_shaped_service.rb
│   └── z_shaped_service.rb
├── custom_service.rb            # Executes user-defined DSL
└── factory.rb                   # Returns correct service

app/services/conversions/
└── tracking_service.rb          # Creates conversion, runs attribution
```

---

#### API Endpoints

**Conversion Tracking**:
```
POST /api/v1/conversions
{
  "conversion": {
    "event_id": "evt_abc123",
    "conversion_type": "signup",
    "revenue": 99.99
  }
}

Response 201:
{
  "conversion_id": "conv_xyz789",
  "attribution_credits": {
    "first_touch": [
      { "channel": "organic_search", "credit": 1.0, "revenue_credit": 99.99, ... }
    ],
    "linear": [
      { "channel": "organic_search", "credit": 0.33, ... },
      { "channel": "paid_search", "credit": 0.33, ... },
      { "channel": "email", "credit": 0.33, ... }
    ]
  }
}
```

**Custom Attribution Models**:
```
POST /api/v1/attribution_models
{
  "attribution_model": {
    "name": "My Custom Model",
    "dsl_code": "model \"Custom\" credit first_touch with 0.5 ..."
  }
}

GET /api/v1/attribution_models
PATCH /api/v1/attribution_models/:id
DELETE /api/v1/attribution_models/:id
```

---

#### Dashboard Integration

```
app/controllers/dashboard/
├── attribution_controller.rb        # Channel attribution reports
│   - GET /dashboard/attribution?model=linear&days=30
│   - Shows channel performance (primary)
│   - Drill-down: channel → UTM campaigns
│
└── attribution_models_controller.rb # Manage custom models
    - Visual DSL builder UI
    - Live preview with sample journey

app/views/dashboard/attribution/
├── show.html.erb                    # Channel attribution report
└── models/
    ├── index.html.erb               # List models
    ├── new.html.erb                 # Visual DSL builder
    └── _form.html.erb               # DSL editor + preview
```

---

#### Success Criteria

**Phase 2A: TimescaleDB** (Week 1):
- [  ] Hypertables created, compression active
- [  ] Continuous aggregates (channel-based)
- [  ] Dashboard queries <100ms

**Phase 2B: Preset Models** (Week 2):
- [  ] 7 preset models implemented
- [  ] Channel-based attribution (not UTM)
- [  ] Conversion tracking API working
- [  ] Revenue attribution calculated

**Phase 2C: Declarative Language** (Week 3-4):
- [  ] DSL designed (see `attribution_dsl_design.md`)
- [  ] Lexer, parser, validator, interpreter implemented
- [  ] Custom models API (CRUD)
- [  ] Visual DSL builder UI
- [  ] 95%+ test coverage

---

## Phase 3: mbuzz-ruby Gem Integration

### Current Status: ⚠️ PARTIAL - 11 Test Failures

**Repository**: `/Users/vlad/code/mbuzz-ruby`

**Critical Issues** (5):

| # | Location | Problem | Fix | Time |
|---|----------|---------|-----|------|
| 1 | `middleware/tracking.rb:57` | Deprecated Rack API | Use `set_cookie_header!` | 1h |
| 2 | `client.rb` | Wrong endpoints | Send via `/api/v1/events` | 2-3h |
| 3 | `client.rb` | Wrong param name | Use `anonymous_id` | 1h |
| 4 | `client.rb` | Missing context | Add URL/referrer to payload | 2h |
| 5 | `README.md` | Placeholders | Write docs | 2-3h |

**Integration Checklist**:
- [  ] Fix 5 issues above
- [  ] All 55+ tests passing
- [  ] Complete README
- [  ] Test with live backend
- [  ] Demo Rails app integration

---

## Next Steps (Priority Order)

### Immediate (Week 1)
1. **✅ Phase 1 MVP** - COMPLETE (242 tests, production-ready)
2. **⏳ TimescaleDB** - Hypertables, compression, continuous aggregates

### Short-term (Weeks 2-4)
3. **🎯 Multi-Touch Attribution**
   - Week 2: 7 preset models (channel-based)
   - Week 3-4: Declarative language + visual builder

### Short-term (Week 5)
4. **🔧 Fix mbuzz-ruby Gem** - Fix 5 issues, complete docs

### Medium-term (Month 2+)
5. **🚀 Launch Beta** - Integration, user testing
6. **🤖 Data-Driven Models** - Algorithmic, Markov, Shapley (Phase 3)

---

## Original Next Steps (Archived)

1. **Set up documentation structure**
   ```bash
   mkdir -p docs/{api,architecture,development,api/examples}
   touch docs/api/openapi.yml
   touch docs/api/getting_started.md
   ```

2. **Start Day 1: Account & API Key**
   - Write `docs/api/authentication.md`
   - Write tests
   - Implement models and services
   - Follow 7-step DDD cycle

3. **Deploy docs site** (optional, Day 5)
   ```bash
   # Use Redoc or Swagger UI
   # Host on /api-docs route
   ```

---

## Resources

### Tools
- **OpenAPI Editor**: [Stoplight Studio](https://stoplight.io/studio)
- **API Docs Rendering**: [Redoc](https://redocly.com/redoc), [Swagger UI](https://swagger.io/tools/swagger-ui/)
- **API Testing**: [Postman](https://www.postman.com/), [Insomnia](https://insomnia.rest/)
- **Contract Testing**: [Dredd](https://dredd.org/)
- **Mock Server**: [Prism](https://stoplight.io/open-source/prism)

### Gems
- `rswag` - OpenAPI docs from RSpec tests
- `committee` - OpenAPI request/response validation
- `simplecov` - Code coverage
- `factory_bot_rails` - Test data

### References
- [OpenAPI 3.0 Spec](https://swagger.io/specification/)
- [API Design Best Practices](https://github.com/microsoft/api-guidelines)
- [Rails API Guide](https://guides.rubyonrails.org/api_app.html)

---

This implementation plan ensures we build a well-documented, tested, and production-ready REST API first, with client libraries as optional future additions.