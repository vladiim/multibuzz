# Multibuzz

Server-side multi-touch attribution tracking platform.

---

## Quick Links

**For Users**:
- 📖 [Getting Started](https://multibuzz.co/docs/getting-started) - Start tracking in 5 minutes
- 🔑 [Authentication](https://multibuzz.co/docs/authentication) - API keys and security
- 📚 [API Reference](https://multibuzz.co/docs/api-reference) - Complete API documentation
- 💡 [Examples](https://multibuzz.co/docs/examples) - Integration examples

**For Developers**:
- 🚀 [Setup Guide](lib/docs/SETUP.md) - Local development setup
- 🎨 [Style Guide](lib/docs/architecture/STYLE_GUIDE.md) - Visual design system
- 🤖 [Claude Guide](CLAUDE.md) - Coding standards for AI assistance
- 🚢 [Deployment](DEPLOYMENT.md) - Production deployment guide

---

## Technology Stack

**Framework**: Rails 8.0.2
**Ruby**: 3.4.3
**Database**: PostgreSQL 18 + TimescaleDB 2.23.1
**CSS**: Tailwind CSS 3.0
**JavaScript**: Hotwire (Turbo + Stimulus)
**Background Jobs**: Solid Queue
**Cache**: Solid Cache
**Deployment**: Kamal

---

## Project Structure

```
multibuzz/
├── app/                    # Rails application
│   ├── controllers/        # API and web controllers
│   ├── models/            # Domain models with concerns
│   ├── services/          # Business logic (Events::, Sessions::, etc.)
│   ├── views/             # HTML templates and docs
│   └── javascript/        # Stimulus controllers
│
├── lib/
│   ├── docs/              # Documentation
│   │   └── architecture/  # System design documents
│   └── specs/             # Feature specifications
│
├── CLAUDE.md              # Coding standards (for AI)
├── DEPLOYMENT.md          # Production deployment
└── README.md              # This file
```

---

## Documentation Index

### Architecture Documentation

**Core Design**:
- [Attribution Methodology](lib/docs/architecture/attribution_methodology.md) - Multi-touch attribution principles
- [Server-Side Attribution Architecture](lib/docs/architecture/server_side_attribution_architecture.md) - System design
- [Code Highlighting Implementation](lib/docs/architecture/code_highlighting_implementation.md) - Stripe-style docs

**Feature Documentation**:
- [Channel vs UTM Attribution](lib/docs/architecture/channel_vs_utm_attribution.md) - Channel derivation logic
- [Conversion Funnel Analysis](lib/docs/architecture/conversion_funnel_analysis.md) - Funnel tracking design
- [Event Properties](lib/docs/architecture/event_properties.md) - Event schema and properties

**Design System**:
- [Style Guide](lib/docs/architecture/STYLE_GUIDE.md) - Visual design system (colors, typography, components)

### Feature Specifications

**Implemented**:
- [UTM Tracking Spec](lib/specs/feature_1_utm_tracking_spec.md) - UTM extraction and session tracking
- [Implementation Roadmap](lib/specs/IMPLEMENTATION_ROADMAP.md) - Current status and next steps

**Planned**:
- [Epic 1: Server-Side Tracking](lib/specs/epic_1.md) - Vision document
- [Attribution DSL Design](lib/specs/attribution_dsl_design.md) - Custom attribution models
- [Event Debugging Interface](lib/specs/event_debugging_interface.md) - Debug tools
- [Mbuzz Gem Spec](lib/specs/mbuzz_gem_spec.md) - Ruby client library
- [Waitlist Feature](lib/specs/waitlist_feature_spec.md) - Pre-launch waitlist

**Research**:
- [Onboarding Best Practices](lib/specs/research_onboarding_best_practices.md) - User onboarding research

### Developer Guides

- [CLAUDE.md](CLAUDE.md) - Coding standards, patterns, and conventions
- [DEPLOYMENT.md](DEPLOYMENT.md) - TimescaleDB setup and production deployment
- [Setup Guide](lib/docs/SETUP.md) - Local development environment setup

---

## Key Features

### ✅ Implemented

**Event Tracking**:
- Multi-language client libraries (Ruby, Python, PHP)
- REST API for any platform
- Automatic page view tracking (Rails middleware)
- Custom event tracking
- Batch event ingestion

**Attribution**:
- Server-side visitor/session identification
- Cookie-based tracking (2-year visitor, 30-min session)
- Automatic UTM parameter extraction
- Channel attribution (UTM + referrer-based)
- Multi-touch attribution models (first-touch, last-touch, linear)
- Journey builder for visitor paths

**Data & Analytics**:
- TimescaleDB for time-series optimization
- Real-time event processing (Solid Queue)
- Session aggregation and metrics
- Conversion tracking
- Attribution credits

**Security & Infrastructure**:
- API key authentication with Bearer tokens
- Rate limiting per account
- Multi-tenancy with account isolation
- Prefixed IDs for customer-facing resources
- GDPR-compliant IP anonymization

### 🚧 In Progress

- Dashboard analytics views
- Attribution model DSL
- Event debugging interface
- Webhook notifications
- Data exports

---

## Models

**Core Models**:
- `Account` - Multi-tenant account (prefixed ID: `acct_*`)
- `User` - Dashboard user accounts
- `ApiKey` - API authentication (test/live environments)

**Tracking Models**:
- `Visitor` - Anonymous visitors (prefixed ID: `vis_*`, 2-year cookie)
- `Session` - User sessions (prefixed ID: `sess_*`, 30-min timeout)
- `Event` - Tracked events (prefixed ID: `evt_*`, TimescaleDB hypertable)

**Attribution Models**:
- `Conversion` - Conversion events
- `AttributionModel` - Attribution model configuration (prefixed ID: `attr_*`)
- `AttributionCredit` - Attribution credit assignments

**Lead Gen**:
- `FormSubmission` - Form submission tracking
- `WaitlistSubmission` - Pre-launch waitlist

All models use **concerns pattern** for organization:
- `ModelName::Validations`
- `ModelName::Relationships`
- `ModelName::Scopes`
- `ModelName::Callbacks`

---

## Services

**Namespace Pattern**: `ModuleName::ActionService` (plural modules)

**Event Services** (`Events::`):
- `IngestionService` - Batch event ingestion
- `ValidationService` - Event schema validation
- `ProcessingService` - Async event processing
- `EnrichmentService` - HTTP metadata enrichment

**Session Services** (`Sessions::`):
- `IdentificationService` - Cookie-based session management
- `TrackingService` - Session creation/updates
- `UtmCaptureService` - UTM parameter extraction
- `ChannelAttributionService` - Channel derivation

**Visitor Services** (`Visitors::`):
- `IdentificationService` - Cookie-based visitor tracking
- `LookupService` - Find or create visitors

**API Key Services** (`ApiKeys::`):
- `AuthenticationService` - Bearer token validation
- `GenerationService` - API key creation
- `RateLimiterService` - Rate limit enforcement

**Attribution Services** (`Attribution::`):
- `Calculator` - Multi-touch attribution calculation
- `JourneyBuilder` - Build visitor journey from sessions
- Various algorithm implementations (FirstTouch, LastTouch, Linear, etc.)

---

## Testing

**Test Suite**:
- 242 tests passing
- 1621 assertions
- Full coverage of services, models, and controllers

**Run Tests**:
```bash
bin/rails test                    # All tests
bin/rails test:models            # Model tests only
bin/rails test:services          # Service tests only
bin/rails test:controllers       # Controller tests only
```

**Test Conventions**:
- Use memoized fixture methods (see [CLAUDE.md](CLAUDE.md))
- Service objects test `initialize` and `call` only
- Multi-tenancy isolation tests required
- Follow doc-driven development (spec → test → code)

### SDK Integration Tests

End-to-end tests for mbuzz SDKs (Ruby, Node.js) live in `test/sdk_integration/`. These tests:
- Automatically create test accounts/API keys for each run
- Run minimal test apps with each SDK
- Use Capybara + Playwright for browser automation
- Verify data is correctly stored in the server

**Quick start:**
```bash
cd test/sdk_integration
bundle install
rake sdk:setup:all  # Install all dependencies
```

**Run tests:**
```bash
rake sdk:test      # All SDKs (Ruby + Node)
rake sdk:ruby      # Ruby SDK only
rake sdk:node      # Node SDK only
```

See [test/sdk_integration/README.md](test/sdk_integration/README.md) for detailed setup.

---

## Development Workflow

1. **Read the spec** - Check `lib/specs/` for feature specifications
2. **Write the test** - Red phase (failing test)
3. **Write the code** - Green phase (minimal implementation)
4. **Run all tests** - Ensure no regressions
5. **Refactor** - Improve while keeping tests green
6. **Update docs** - Keep specs and architecture docs current
7. **Commit** - Use conventional commit messages

**Commit Format**:
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`
**Scopes**: `auth`, `events`, `sessions`, `attribution`, `api`, `dashboard`, `docs`

---

## API Overview

**Base URL**: `https://multibuzz.co/api/v1`

**Authentication**: Bearer token in `Authorization` header

**Endpoints**:
- `POST /events` - Ingest events
- `POST /identify` - Identify users
- `POST /alias` - Link visitor to user
- `GET /validate` - Validate API key
- `GET /health` - Health check

**Client Libraries**:
- **Ruby**: `gem 'mbuzz'` (in production)
- **Python**: `pip install mbuzz` (planned)
- **PHP**: `composer require mbuzz/mbuzz-php` (planned)
- **REST API**: Direct HTTP calls

See [API Reference](https://multibuzz.co/docs/api-reference) for complete documentation.

---

## Database

**PostgreSQL 18** with **TimescaleDB 2.23.1** extension.

**Hypertables** (time-series optimized):
- `events` - Partitioned by `occurred_at`
- `sessions` - Partitioned by `started_at`

**Benefits**:
- 10-20x query performance for time-series data
- 90% storage savings with compression
- Automatic data retention policies
- Continuous aggregates for real-time metrics

**Continuous Aggregates**:
- `channel_attribution_daily` - Daily channel metrics
- `source_attribution_daily` - Daily source metrics

See [DEPLOYMENT.md](DEPLOYMENT.md) for setup instructions.

---

## Configuration

**Required Environment Variables**:
```bash
# Database
DATABASE_URL=postgresql://user:pass@localhost/multibuzz_production

# Secret Key
SECRET_KEY_BASE=your_secret_key_here

# Optional: Custom domain
RAILS_ENV=production
```

**Config Files**:
- `config/database.yml` - Database configuration
- `config/deploy.yml` - Kamal deployment
- `tailwind.config.js` - Tailwind CSS configuration

---

## Contributing

1. Read [CLAUDE.md](CLAUDE.md) for coding standards
2. Check `lib/specs/` for feature specifications
3. Follow the service object pattern (only `initialize` and `call` public)
4. Write tests using memoized fixtures
5. Keep models thin (extract to concerns)
6. Write functional, expressive Ruby (no procedural PHP-style)
7. All queries must be scoped to account (multi-tenancy)

---

## License

Proprietary - All rights reserved

---

## Support

- **Issues**: GitHub Issues
- **Docs**: https://multibuzz.co/docs
- **Dashboard**: https://multibuzz.co/dashboard

---

**Built with Rails 8, TimescaleDB, and Tailwind CSS**
