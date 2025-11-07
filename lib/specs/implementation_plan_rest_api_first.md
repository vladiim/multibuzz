# Multibuzz REST API - Doc-Driven Implementation Plan

## Overview

This document outlines the REST API-first implementation approach for Multibuzz, replacing the original gem-first strategy. We'll build a production-ready REST API that any client (any language/framework) can consume.

**Domain**: multibuzz.io
**API Base URL**: https://api.multibuzz.io/v1

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
curl -X POST https://multibuzz.com/api/v1/events \
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
# Host at https://docs.multibuzz.io or https://multibuzz.io/docs
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
- [ ] POST /api/v1/events accepts and queues events
- [ ] GET /api/v1/validate validates API keys
- [ ] GET /api/v1/health returns status
- [ ] Bearer token authentication works
- [ ] Rate limiting enforced
- [ ] Multi-tenancy isolation verified
- [ ] Async processing via Solid Queue

### Documentation ✅
- [ ] OpenAPI spec complete and valid
- [ ] Getting Started guide published
- [ ] Code examples in 3+ languages
- [ ] Error handling documented
- [ ] Rate limits documented
- [ ] API docs site deployed

### Testing ✅
- [ ] 95%+ code coverage
- [ ] Multi-tenancy isolation tests pass
- [ ] Integration tests pass
- [ ] No N+1 queries
- [ ] Performance benchmarks met

### Dashboard ✅
- [ ] User authentication works
- [ ] API key CRUD operations
- [ ] Event listing with pagination
- [ ] UTM breakdown report
- [ ] Basic usage statistics

---

## Next Steps

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