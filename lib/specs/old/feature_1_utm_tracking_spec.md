# Feature 1: UTM-Based Page View Tracking - Architecture Spec

## Overview
Build framework-agnostic page view tracking with UTM attribution. Start with Rails, design for Django/Laravel expansion.

**Timeline**: 1-1.5 weeks | **Pattern**: API-first, framework adapters

---

## 1. Domain Model & Ubiquitous Language

### Core Entities

```
Account (Tenant)
├── has many ApiKeys
├── has many Visitors
├── has many Sessions
└── has many Events

Visitor (Anonymous User)
├── belongs to Account
├── has many Sessions
├── has many Events
└── identified by: visitor_id (SHA256 hash)

Session (Visit Journey)
├── belongs to Account, Visitor
├── has many Events
├── captures: initial_utm (first-touch attribution)
└── identified by: session_id (random hex)

Event (Tracked Action)
├── belongs to Account, Visitor, Session
├── types: page_view, signup, purchase, etc.
└── properties: JSONB (url, utm_*, custom data)

ApiKey (Client Credential)
├── belongs to Account
├── format: sk_{environment}_{random32}
└── scoped to: environment (test|live)
```

### Bounded Contexts

```
┌─────────────────────────────────────────────────────┐
│ INGESTION CONTEXT                                   │
│ - Receives events from client libs                  │
│ - Validates, batches, queues                        │
│ - Concerns: Rate limiting, auth, resilience         │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ TRACKING CONTEXT                                    │
│ - Stores events, visitors, sessions                 │
│ - Manages visitor identity                          │
│ - Concerns: Multi-tenancy, data integrity           │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ ATTRIBUTION CONTEXT (Phase 2)                       │
│ - Computes attribution models                       │
│ - Revenue tracking                                  │
│ - Concerns: Model accuracy, performance             │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ REPORTING CONTEXT                                   │
│ - Dashboard views                                   │
│ - Exports (CSV, API)                                │
│ - Concerns: Query performance, UX                   │
└─────────────────────────────────────────────────────┘
```

---

## 2. System Architecture

### 2.1 Framework-Agnostic Design

```
┌──────────────────────────────────────────────────────────────┐
│                    CLIENT APPLICATIONS                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │   Rails     │  │   Django    │  │   Laravel   │          │
│  │   App       │  │   App       │  │   App       │          │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘          │
│         │                 │                 │                 │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐          │
│  │ mbuzz-      │  │ multibuzz-  │  │ mbuzz-      │          │
│  │   rails     │  │   django    │  │   laravel   │          │
│  │  (gem)      │  │  (package)  │  │  (package)  │          │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘          │
└─────────┼─────────────────┼─────────────────┼────────────────┘
          │                 │                 │
          └─────────────────┼─────────────────┘
                            │ HTTP/JSON
                            ▼
┌──────────────────────────────────────────────────────────────┐
│                      MBUZZ SAAS API                           │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  API Layer (Rails)                                     │  │
│  │  - POST /api/v1/events (batch ingestion)              │  │
│  │  - GET  /api/v1/validate                              │  │
│  │  - GET  /api/v1/health                                │  │
│  └────────────────────────────────────────────────────────┘  │
│                            │                                  │
│  ┌────────────────────────▼────────────────────────────────┐ │
│  │  Service Layer (Namespaced)                            │ │
│  │  - Event::IngestionService                             │ │
│  │  - Event::ProcessingService                            │ │
│  │  - Visitor::IdentificationService                      │ │
│  │  - Session::TrackingService                            │ │
│  │  - ApiKey::AuthenticationService                       │ │
│  └────────────────────────────────────────────────────────┘  │
│                            │                                  │
│  ┌────────────────────────▼────────────────────────────────┐ │
│  │  Background Jobs (Solid Queue)                          │ │
│  │  - Event::ProcessingJob                                │ │
│  │  - Session::CleanupJob (Phase 2)                       │ │
│  └────────────────────────────────────────────────────────┘  │
│                            │                                  │
│  ┌────────────────────────▼────────────────────────────────┐ │
│  │  Data Layer (PostgreSQL)                                │ │
│  │  - accounts, api_keys, visitors, sessions, events      │ │
│  │  - Multi-tenant with account_id scoping                │ │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Cache Layer (Redis + Solid Cache)                     │  │
│  │  - Rate limiting counters                              │  │
│  │  - Dashboard query cache                               │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### 2.2 Client Library Architecture (Framework Adapters)

```
┌─────────────────────────────────────────────────────────────┐
│  MBUZZ CLIENT LIBRARY (Framework-Specific)                  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Framework Adapter Layer                             │   │
│  │  - Middleware/Hook integration                       │   │
│  │  - Request/Response abstraction                      │   │
│  │  - Cookie management                                 │   │
│  │  - Session access                                    │   │
│  └────────────────┬─────────────────────────────────────┘   │
│                   │                                          │
│  ┌────────────────▼─────────────────────────────────────┐   │
│  │  Core Tracking Library (Shared)                      │   │
│  │  - Visitor::Identifier                               │   │
│  │  - Event::Builder                                    │   │
│  │  - Event::Queue                                      │   │
│  │  - Api::Client                                       │   │
│  │  - Configuration                                     │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Service Object Structure (Nested Namespaces)

### 3.1 Backend Service Organization

```ruby
app/services/
├── event/
│   ├── ingestion_service.rb       # Validate & queue incoming events
│   ├── processing_service.rb      # Persist events to database
│   ├── validation_service.rb      # Schema validation
│   └── query_service.rb           # Read-side queries (Phase 2)
│
├── visitor/
│   ├── identification_service.rb  # Generate/validate visitor IDs
│   ├── lookup_service.rb          # Find or create visitors
│   └── merge_service.rb           # Merge duplicate visitors (Phase 2)
│
├── session/
│   ├── tracking_service.rb        # Create/update sessions
│   ├── utm_capture_service.rb     # Extract & store UTM params
│   └── timeout_service.rb         # End stale sessions (Phase 2)
│
├── api_key/
│   ├── authentication_service.rb  # Verify API keys
│   ├── generation_service.rb      # Create new keys
│   └── rate_limiter_service.rb    # Enforce rate limits
│
└── attribution/                   # Phase 2
    ├── first_touch_service.rb
    ├── last_touch_service.rb
    └── linear_service.rb
```

### 3.2 Service Naming Conventions

**Pattern**: `<Entity>::<Action>Service`

| Service | Responsibility | Returns |
|---------|---------------|---------|
| `Event::IngestionService` | Accept batch, validate, enqueue | `{ accepted: n, rejected: [...] }` |
| `Event::ProcessingService` | Persist single event to DB | `Event` record |
| `Visitor::IdentificationService` | Generate visitor_id from request | `String` (visitor_id) |
| `Visitor::LookupService` | Find or create visitor by ID | `Visitor` record |
| `Session::TrackingService` | Find or create session | `Session` record |
| `Session::UtmCaptureService` | Extract UTM params from properties | `Hash` (utm_data) |
| `ApiKey::AuthenticationService` | Verify API key, return account | `Account` or `nil` |
| `ApiKey::GenerationService` | Create new API key | `[ApiKey, plaintext_key]` |
| `ApiKey::RateLimiterService` | Check/increment rate limit | `{ allowed: bool, remaining: n }` |

### 3.3 Service Interface Pattern

All services follow this pattern:

```ruby
module Event
  class IngestionService
    # Dependency injection
    def initialize(account, **options)
      @account = account
      @options = options
    end

    # Primary public method (call or execute)
    def call(events_data)
      # Business logic
    end

    private

    # Private helper methods
  end
end

# Usage:
Event::IngestionService.new(account).call(events_data)
```

### 3.4 Job Naming (Matches Services)

```ruby
app/jobs/
├── event/
│   └── processing_job.rb          # Calls Event::ProcessingService
├── session/
│   └── cleanup_job.rb             # Calls Session::TimeoutService
└── attribution/
    └── compute_job.rb             # Phase 2
```

**Pattern**: `<Entity>::<Action>Job` wraps `<Entity>::<Action>Service`

---

## 4. Design Patterns & Principles

### 4.1 Backend Patterns

| Pattern | Application | Example |
|---------|-------------|---------|
| **Service Object** | Business logic outside models/controllers | `Event::IngestionService` |
| **Namespace Organization** | Group related services by entity | `Event::*`, `Visitor::*`, `Session::*` |
| **Dependency Injection** | Pass dependencies to services | `Service.new(account, logger: custom)` |
| **Strategy** | Phase 2: Pluggable attribution models | `Attribution::FirstTouchService` |
| **Adapter** | Framework-specific client libraries | Rails gem, Django package |
| **Queue/Worker** | Async processing | `Event::ProcessingJob` |
| **Multi-tenancy** | Account-scoped queries | `@account.events.where(...)` |
| **Repository** | Phase 2: Abstract data access | `Event::Repository` |

### 4.2 Client Library Patterns

| Pattern | Application | Example |
|---------|-------------|---------|
| **Namespace Organization** | Group tracking logic | `Visitor::Identifier`, `Event::Builder` |
| **Middleware/Hook** | Transparent request interception | Rails Rack, Django Middleware |
| **Builder** | Construct complex event payloads | `Event::Builder.page_view(request).with_utm().build()` |
| **Singleton** | Global config, shared queue | `Mbuzz.configuration` |
| **Template Method** | Reusable core, framework variations | Base `Tracker`, Rails `RackTracker` |
| **Circuit Breaker** | Phase 2: Resilience to API failures | Disable tracking if API down |

### 4.3 Controller Organization

```ruby
# Match service namespaces
app/controllers/
├── api/
│   └── v1/
│       ├── events_controller.rb       # POST /api/v1/events
│       ├── health_controller.rb       # GET  /api/v1/health
│       └── validate_controller.rb     # GET  /api/v1/validate
│
└── dashboard/
    ├── events_controller.rb           # Web UI
    ├── sessions_controller.rb
    ├── visitors_controller.rb
    └── utm_reports_controller.rb
```

---

## 5. Data Architecture

### 5.1 Database Schema (Key Fields)

```sql
-- Multi-tenant root
accounts (id, name, slug, status, settings:jsonb)

-- Authentication
users (id, account_id, email, password_digest, role)
api_keys (id, account_id, key_digest, key_prefix, environment, last_used_at, revoked_at)

-- Core tracking
visitors (id, account_id, visitor_id, first_seen_at, last_seen_at, traits:jsonb)
sessions (id, account_id, visitor_id, session_id, started_at, ended_at,
          page_view_count, initial_utm:jsonb)
events (id, account_id, visitor_id, session_id, event_type, occurred_at,
        properties:jsonb)

-- Indexes
INDEX (account_id, visitor_id) UNIQUE
INDEX (account_id, session_id) UNIQUE
INDEX (account_id, event_type)
INDEX (account_id, occurred_at)
GIN INDEX (properties)
GIN INDEX ((properties -> 'utm_source'))
GIN INDEX ((properties -> 'utm_medium'))
GIN INDEX ((properties -> 'utm_campaign'))
```

### 5.2 Multi-Tenancy Strategy

**Approach**: Shared database, row-level isolation via `account_id`

**Implementation**:
```ruby
# All queries scoped
class Event < ApplicationRecord
  belongs_to :account

  # Default scope (optional, careful with this)
  # default_scope -> { where(account_id: Current.account_id) }
end

# Controller pattern
class Api::V1::EventsController < Api::V1::BaseController
  before_action :authenticate_api_key  # Sets @current_account

  def create
    Event::IngestionService.new(@current_account).call(event_params)
  end
end
```

**Safety**:
- Database constraints: `NOT NULL` + foreign keys
- Automated tests for cross-account leakage
- Code review checklist

### 5.3 Event Storage (JSONB)

```json
// events.properties
{
  "url": "https://example.com/page",
  "path": "/page",
  "referrer": "https://google.com",
  "user_agent": "Mozilla/5.0...",
  "utm_source": "google",
  "utm_medium": "cpc",
  "utm_campaign": "spring_sale",
  "utm_content": "ad_variant_a",
  "utm_term": "running shoes",
  "custom_field": "any_value"  // Extensibility
}

// sessions.initial_utm (first-touch attribution)
{
  "utm_source": "google",
  "utm_medium": "cpc",
  "utm_campaign": "spring_sale",
  "utm_content": "ad_variant_a",
  "utm_term": "running shoes"
}
```

---

## 6. API Contract

### 6.1 Authentication

```http
Authorization: Bearer sk_live_abc123xyz...
```

**Handled by**: `ApiKey::AuthenticationService`

### 6.2 Endpoints

```http
POST /api/v1/events
GET  /api/v1/validate
GET  /api/v1/health
```

### 6.3 Event Ingestion Request

```json
POST /api/v1/events

{
  "events": [
    {
      "event_type": "page_view",
      "visitor_id": "abc123...",
      "session_id": "xyz789...",
      "timestamp": "2025-11-06T10:30:45Z",
      "properties": {
        "url": "https://example.com/page",
        "utm_source": "google",
        "utm_medium": "cpc",
        "utm_campaign": "spring_sale"
      }
    }
  ]
}
```

**Responses**:
- `202 Accepted` → Success (queued)
- `400 Bad Request` → Invalid JSON/schema
- `401 Unauthorized` → Bad API key
- `422 Unprocessable` → Partial failure
- `429 Too Many Requests` → Rate limit

---

## 7. Client Library Structure

### 7.1 Gem Organization (Rails)

```
lib/mbuzz/
├── version.rb
├── configuration.rb
├── railtie.rb
│
├── visitor/
│   └── identifier.rb              # Generate visitor_id, manage cookies
│
├── event/
│   ├── builder.rb                 # Construct event payloads
│   └── queue.rb                   # Batch, flush to API
│
├── api/
│   └── client.rb                  # HTTP transport
│
├── middleware/
│   └── tracking.rb                # Rack middleware for page views
│
└── adapters/                      # Phase 2: Other frameworks
    ├── rails.rb
    ├── django.rb
    └── laravel.rb
```

### 7.2 Usage Pattern

```ruby
# Installation
gem 'mbuzz'

# Configuration
Mbuzz.configure do |config|
  config.api_key = ENV['MBUZZ_API_KEY']
  config.api_url = ENV.fetch('MBUZZ_API_URL', 'https://mbuzz.co/api/v1')
  config.enabled = !Rails.env.test?
  config.batch_size = 50
  config.flush_interval = 30
end

# Automatic tracking via middleware (transparent)
# Manual tracking (Phase 2)
Mbuzz.track(:signup, properties: { plan: 'pro' })
```

### 7.3 Client Services (Match Backend Pattern)

```ruby
# In gem
module Mbuzz
  module Visitor
    class Identifier
      def self.identify(request, response)
        # Generate or retrieve visitor_id
      end
    end
  end

  module Event
    class Builder
      def self.page_view(request, visitor_id, session_id)
        # Construct event payload
      end
    end

    class Queue
      def push(event)
        # Batch and flush
      end
    end
  end

  module Api
    class Client
      def send_events(events)
        # HTTP POST to /api/v1/events
      end
    end
  end
end
```

---

## 8. Development Process

### 8.1 TDD Cycle

```
RED → GREEN → REFACTOR → DOCUMENT → COMMIT

1. RED: Write failing test
   test/services/event/ingestion_service_test.rb

2. GREEN: Implement service
   app/services/event/ingestion_service.rb

3. REFACTOR: Extract, optimize, follow patterns

4. DOCUMENT: YARD comments, update spec

5. COMMIT: Conventional commit message
```

### 8.2 Git Commit Convention

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

**Scopes**: Match service namespaces
- `event`: Event-related changes
- `visitor`: Visitor-related changes
- `session`: Session-related changes
- `api-key`: API key changes
- `api`: API endpoints
- `dashboard`: Web UI
- `gem`: Client library

**Examples**:
```
feat(event): add batch ingestion service

- Implement Event::IngestionService
- Validate event schema
- Queue for async processing
- Return accepted/rejected counts

Closes #12

---

refactor(visitor): extract identification service

Move visitor ID generation from middleware to
Visitor::IdentificationService for better testability.

---

test(session): add UTM capture specs

Test Session::UtmCaptureService extracts all 5 UTM parameters
```

### 8.3 Testing Strategy

**Test Organization**:
```ruby
test/
├── models/
│   ├── account_test.rb
│   ├── visitor_test.rb
│   ├── session_test.rb
│   └── event_test.rb
│
├── services/
│   ├── event/
│   │   ├── ingestion_service_test.rb
│   │   ├── processing_service_test.rb
│   │   └── validation_service_test.rb
│   ├── visitor/
│   │   ├── identification_service_test.rb
│   │   └── lookup_service_test.rb
│   ├── session/
│   │   ├── tracking_service_test.rb
│   │   └── utm_capture_service_test.rb
│   └── api_key/
│       ├── authentication_service_test.rb
│       └── rate_limiter_service_test.rb
│
├── controllers/
│   └── api/
│       └── v1/
│           ├── events_controller_test.rb
│           └── validate_controller_test.rb
│
├── jobs/
│   └── event/
│       └── processing_job_test.rb
│
└── integration/
    └── tracking_flow_test.rb  # E2E: gem → API → DB
```

**Key Test Cases**:
1. ✅ Multi-tenancy isolation (critical)
2. ✅ API key authentication & revocation
3. ✅ Event validation (required fields, types)
4. ✅ Rate limiting enforcement
5. ✅ Visitor ID generation & persistence
6. ✅ UTM parameter extraction
7. ✅ Batch processing & async jobs
8. ✅ Dashboard queries (performance, no N+1)

---

## 9. Framework Extensibility

### 9.1 Shared Core (Language-Agnostic Concepts)

**Services** (conceptual, implement in each language):
- `Visitor::Identifier` → Generate/validate visitor IDs
- `Event::Builder` → Construct event payloads
- `Event::Queue` → Batch and flush logic
- `Api::Client` → HTTP transport

### 9.2 Framework Adapters

Each framework package provides:

**Request Abstraction**:
```ruby
# Rails
Multibuzz::Adapters::Rails::Request.new(rack_request)

# Django (Python)
Multibuzz.Adapters.Django.Request(django_request)

# Laravel (PHP)
Multibuzz\Adapters\Laravel\Request($request)
```

**Middleware/Hook**:
```ruby
# Rails: Rack Middleware
Multibuzz::Middleware::Tracking

# Django: Middleware class
Multibuzz.Middleware.Tracking

# Laravel: HTTP Middleware
Multibuzz\Middleware\Tracking
```

**Configuration**:
```ruby
# Rails: Initializer
Mbuzz.configure do |config|
  config.api_key = ENV['MBUZZ_API_KEY']
end

# Django: settings.py
MBUZZ = {
    'API_KEY': os.getenv('MBUZZ_API_KEY')
}

# Laravel: config/mbuzz.php
return [
    'api_key' => env('MBUZZ_API_KEY'),
];
```

---

## 10. Phase 1 Scope

### ✅ In Scope

**Backend**:
- Models: Account, User, ApiKey, Visitor, Session, Event
- Services: `Event::*`, `Visitor::*`, `Session::*`, `ApiKey::*`
- Jobs: `Event::ProcessingJob`
- API: POST /api/v1/events, GET /api/v1/validate, GET /api/v1/health
- Dashboard: Login, stats, UTM breakdown, recent events

**Client Library** (Rails Gem):
- Automatic page view tracking
- Services: `Visitor::Identifier`, `Event::Builder`, `Event::Queue`, `Api::Client`
- Middleware: `Multibuzz::Middleware::Tracking`
- Configuration

**DevOps**:
- PostgreSQL, Redis, Solid Queue
- Kamal deployment config

**Testing**:
- Unit (models, services)
- Integration (API endpoints)
- E2E (gem → API → DB)

### ❌ Out of Scope (Phase 2+)

- Custom event tracking
- User identification
- Attribution models
- Revenue tracking
- Exports
- Django/Laravel libraries
- Advanced dashboard features

---

## 11. Implementation Order

```
Week 1: Backend Foundation
Day 1-2: Models + Services
  - Account, User, ApiKey models
  - ApiKey::GenerationService
  - ApiKey::AuthenticationService
  - Visitor, Session, Event models
  - Visitor::IdentificationService
  - Visitor::LookupService
  - Session::TrackingService
  - Session::UtmCaptureService
  - Unit tests (TDD)

Day 3-4: API + Jobs
  - Api::V1::EventsController
  - Event::IngestionService
  - Event::ValidationService
  - Event::ProcessingService
  - Event::ProcessingJob
  - ApiKey::RateLimiterService
  - Integration tests

Day 5: Dashboard
  - Login/auth
  - Dashboard views
  - System tests

Week 2: Client Library + Integration
Day 1-2: Gem Core
  - Configuration
  - Visitor::Identifier
  - Event::Builder
  - Event::Queue
  - Api::Client
  - Unit tests (RSpec)

Day 3: Gem Middleware
  - Multibuzz::Middleware::Tracking
  - Page view tracking
  - UTM extraction
  - Integration tests

Day 4: E2E
  - Test Rails app
  - Full flow validation
  - Performance testing

Day 5: Deploy
  - Documentation
  - Kamal deploy
  - Beta invites
```

---

## 12. Key Architectural Decisions

1. **Namespaced service objects** (`Event::*`, `Visitor::*`) for organization
2. **Multi-tenant via account_id scoping** (simple, scalable)
3. **JSONB for event properties** (flexible, future-proof)
4. **Async processing via Solid Queue** (non-blocking)
5. **Framework adapters pattern** (Rails now, Django/Laravel later)
6. **Batch API ingestion** (reduce HTTP overhead)
7. **Cookie-based anonymous tracking** (GDPR-friendly)
8. **TDD + conventional commits** (quality)
9. **API versioning** (`/api/v1/*`)

---

## Summary

This spec defines a clean, namespaced architecture that:
- Groups services by domain entity
- Supports framework extensibility via adapters
- Follows TDD with conventional commits
- Enables multi-tenant SaaS tracking
- Provides foundation for attribution (Phase 2)

**Next**: Begin Day 1 implementation with TDD cycle.
