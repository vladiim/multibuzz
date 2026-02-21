# Codebase Audit & Quality Hardening Specification

**Date:** 2026-02-21
**Priority:** P1
**Status:** Ready
**Branch:** `feature/codebase-audit`

---

## Summary

A deep audit of the mbuzz codebase to map functionality, assess architecture against SOLID/DRY/GoF principles, identify security gaps, and define the tooling + refactoring work needed to maintain code quality as the product scales. The codebase is architecturally sound with excellent separation of concerns, but has three multi-tenancy scoping bugs, missing quality tooling, and one large service ripe for extraction.

---

## Current State

### System Architecture (Verified)

mbuzz is a server-side marketing attribution platform. SDKs call four API endpoints; the server handles all session resolution, channel classification, and attribution calculation.

```
SDK Call            Controller                       Service Layer                              Database
--------            ----------                       -------------                              --------
POST /sessions  --> SessionsController#create    --> Sessions::CreationService                --> Visitor, Session
POST /events    --> EventsController#create      --> Events::IngestionService                 --> Event
POST /conversions-> ConversionsController#create --> Conversions::TrackingService             --> Conversion
POST /identify  --> IdentifyController#create    --> Identities::IdentificationService        --> Identity
                                                     |
                                                     v (after_create_commit on Conversion)
                                                 Attribution::Calculator / CrossDeviceCalculator
                                                     |
                                                     v
                                                 Attribution::Algorithms::{FirstTouch, LastTouch, Linear, ...}
                                                     |
                                                     v
                                                 AttributionCredit records
```

### Core Data Flow: Ingestion to Attribution

**1. Session Creation** (`POST /api/v1/sessions`)
- `Sessions::CreationService` (~342 lines) handles:
  - Visitor find/create with fingerprint matching (`SHA256(ip|user_agent)[0:32]`)
  - 30-min sliding window session reuse (`last_activity_at > 30.minutes.ago`)
  - UTM capture via `Sessions::UtmCaptureService`
  - Channel classification via `Sessions::ChannelAttributionService`
  - Click ID capture via `Sessions::ClickIdCaptureService`
  - Bot detection via `Sessions::BotClassifier` (UA pattern + no-signals heuristic)
  - New session only if new traffic source detected (UTM/click_id/external referrer)

**2. Channel Classification** (`Sessions::ChannelAttributionService`)
- GA4-aligned hierarchy (most reliable signal wins):
  1. **Click identifiers** (gclid, fbclid, etc.) -> `ClickIdentifiers::CHANNEL_MAP`
  2. **Google Places** (plcid in utm_term) -> organic_search
  3. **UTM medium** -> regex-matched against `UTM_MEDIUM_PATTERNS`
  4. **UTM source only** -> inferred from domain patterns (google->organic_search)
  5. **Internal/self referrer** -> direct
  6. **Referrer domain** -> `ReferrerSources::LookupService` (synced from Matomo/Snowplow) or pattern match
  7. **Fallback** -> direct

- 12 channels defined in `app/constants/channels.rb`: paid_search, organic_search, paid_social, organic_social, email, display, affiliate, referral, video, ai, direct, other
- 18 click identifiers in `app/constants/click_identifiers.rb` (Google, Meta, Microsoft, TikTok, LinkedIn, Twitter, Pinterest, Snapchat, Reddit, Quora, Yahoo, Yandex, Seznam)

**3. Event Ingestion** (`POST /api/v1/events`)
- Batch processing (array of events)
- Per-event: validate -> enrich (IP, UA, URL components, UTM, referrer) -> process
- Server-side resolution: `Sessions::ResolutionService` generates deterministic session_id from fingerprint if ip+ua present
- `require_existing_visitor` = ENABLED (events rejected if visitor doesn't exist)

**4. Conversion Tracking** (`POST /api/v1/conversions`)
- Resolution chain: event lookup -> visitor by ID -> fingerprint fallback (30-sec window)
- Idempotency via `[account_id, idempotency_key]` unique index
- `after_create_commit` triggers `Attribution::CalculationJob`

**5. Identity Linking** (`POST /api/v1/identify`)
- Find/create Identity by `external_id` (user_id)
- Deep-merge traits
- Link visitor to identity
- Queue reattribution if identity now has multiple visitors

**6. Attribution Calculation** (`Attribution::Calculator`)
- `JourneyBuilder` collects sessions in lookback window (default 90 days)
- `BurstDeduplication` collapses direct sessions within 5-min window
- 8 algorithms: first_touch, last_touch, linear, time_decay, u_shaped, participation, markov_chain, shapley_value
- `CrossDeviceCalculator` spans all visitors linked to an identity
- Credits normalized to sum=1.0, revenue allocated proportionally

### Model Layer (Verified Good)

Models are thin (4-12 lines) with concerns properly extracted:

| Model | Lines | Concerns |
|-------|-------|----------|
| `Account` | 12 | Billing, Relationships, Validations, Scopes, Callbacks, Onboarding, Search |
| `Event` | 13 | Validations, Relationships, Scopes, PropertyAccess, Broadcasts |
| `Visitor` | 9 | Validations, Relationships, Scopes, Tracking, Callbacks |
| `Session` | 12 | Validations, Relationships, Scopes, Tracking, Callbacks |
| `Conversion` | 16 | Relationships, Validations, Scopes, Callbacks |
| `Identity` | 8 | Relationships, Validations, Scopes |
| `AttributionModel` | 10 | Enums, Relationships, Validations, Scopes, Callbacks, AlgorithmMapping |

### Service Layer (Verified Good)

`ApplicationService` pattern with `#call` -> `#run` and `success_result`/`error_result`. Error handling wraps `RecordInvalid`, `RecordNotFound`, `StandardError` with `Rails.error.report`. Services that return domain-specific structures (not success/fail) correctly skip `ApplicationService` (e.g., `Events::IngestionService`, `ApiKeys::AuthenticationService`).

### Dashboard/Reporting Layer (Verified Good)

- Query objects in `dashboard/queries/` (TotalsQuery, TimeSeriesQuery, ByChannelQuery, etc.)
- Scope objects with Strategy pattern for filter operators (`Equals`, `Contains`, `GreaterThan`, etc.)
- 5-minute cache TTL with deterministic keys (account + model + dates + channels + filters)
- Turbo Frames for lazy-loading, Turbo Streams for real-time event feed
- Highcharts via Stimulus `chart_controller.js` (606 lines, 4 chart types)

### Test Infrastructure (Verified)

- Minitest + fixtures (213 test files)
- Parallel test execution
- E2E tests in `sdk_integration_tests/` with Capybara + Playwright
- No test coverage measurement
- No N+1 detection

---

## Business Logic Map

Every business capability mbuzz provides, where it lives, and what it depends on.

### Domain 1: Visitor & Session Resolution

**What it does:** Resolves anonymous web traffic into persistent visitors and time-bounded sessions. The foundation everything else builds on.

| Capability | Key Files | Pattern |
|-----------|-----------|---------|
| Visitor creation/dedup | `visitors/identification_service.rb`, `visitors/lookup_service.rb`, `visitors/deduplication_service.rb` | Cookie-based (`_mbuzz_vid`) + fingerprint fallback |
| Session lifecycle | `sessions/creation_service.rb`, `sessions/tracking_service.rb`, `sessions/identification_service.rb` | 30-min sliding window, new session on new traffic source |
| Server-side resolution | `sessions/resolution_service.rb` | Deterministic session_id from `SHA256(ip\|ua)[0:32]` for server-side SDKs |
| Cross-device linking | `identities/identification_service.rb` | Identity links multiple visitors, triggers reattribution |
| Device fingerprinting | Computed in 4 services | `SHA256(ip\|user_agent)[0:32]` -- consistent across services |

**Dependencies:** `Visitor`, `Session`, `Identity` models. `Account` for multi-tenancy scoping.

### Domain 2: Channel Classification

**What it does:** Classifies every session into one of 12 marketing channels using a GA4-aligned signal hierarchy. This is the "source of truth" for all downstream attribution.

| Capability | Key Files | Pattern |
|-----------|-----------|---------|
| Channel classification | `sessions/channel_attribution_service.rb` | 7-tier priority cascade (click_ids > UTM > referrer > direct) |
| Click ID detection | `constants/click_identifiers.rb`, `sessions/click_id_capture_service.rb` | 18 platform-specific click IDs with source/channel maps |
| UTM capture + normalization | `sessions/utm_capture_service.rb`, `constants/utm_aliases.rb` | URL + properties extraction, alias normalization (fb->facebook) |
| Referrer classification | `referrer_sources/lookup_service.rb`, `referrer_sources/sync_service.rb` | DB-backed lookup (Matomo/Snowplow synced daily) with regex fallback |
| Bot filtering | `sessions/bot_classifier.rb`, `bot_patterns/matcher.rb` | UA regex match (daily-synced patterns) + no-signals heuristic |
| Channel taxonomy | `constants/channels.rb` | 12 channels, domain regex patterns for search/social/video/AI |

**Dependencies:** `ReferrerSource` model (synced upstream data), `BotPatterns::Matcher` (cached regex).

### Domain 3: Event & Conversion Tracking

**What it does:** Ingests behavioral events and conversion signals from SDKs. Events are enriched server-side. Conversions trigger attribution.

| Capability | Key Files | Pattern |
|-----------|-----------|---------|
| Event ingestion (batch) | `events/ingestion_service.rb`, `events/validation_service.rb` | Batch array processing, per-event validate/enrich/process |
| Event enrichment | `events/enrichment_service.rb` | Server-side: IP anonymization, URL parsing, UTM extraction, referrer parsing |
| Event processing | `events/processing_service.rb` | Visitor lookup -> session tracking -> server-side resolution -> persist |
| Conversion tracking | `conversions/tracking_service.rb`, `conversions/response_builder.rb` | Resolution chain (event->visitor->fingerprint), idempotency, identity linking |
| Billing gating | `billing/usage_counter.rb`, `account/billing.rb` | Usage incremented per session/event/conversion, 402 when over limit |

**Dependencies:** Visitor + Session must exist. `require_existing_visitor` = ENABLED.

### Domain 4: Attribution Engine

**What it does:** After a conversion, calculates how much credit each marketing touchpoint deserves. The core value proposition of mbuzz.

| Capability | Key Files | Pattern |
|-----------|-----------|---------|
| Journey construction | `attribution/journey_builder.rb`, `attribution/cross_device_journey_builder.rb` | Session-based touchpoints in lookback window (default 90 days), ordered chronologically |
| Burst deduplication | `attribution/burst_deduplication.rb` | Collapses direct sessions within 5-min window |
| Credit calculation | `attribution/calculator.rb`, `attribution/cross_device_calculator.rb` | Algorithm -> normalize credits (sum=1.0) -> enrich with UTM -> allocate revenue |
| 8 algorithms | `attribution/algorithms/{first_touch,last_touch,linear,time_decay,u_shaped,participation,markov_chain,shapley_value}.rb` | Strategy pattern via `AttributionModel#algorithm_class` |
| Algorithm mapping | `concerns/attribution_model/algorithm_mapping.rb` | Hash lookup: algorithm name -> class |
| Probabilistic models | `attribution/markov/conversion_paths_query.rb`, `attribution/markov/removal_effect_calculator.rb` | Markov chain removal effects, Shapley value subsets |
| Reattribution | `attribution/rerun_service.rb`, `attribution/rerun_initiation_service.rb` | Triggered on identity linking or model change |
| Data readiness | `attribution/data_readiness_checker.rb` | Validates sufficient data for probabilistic models (500+ conversions) |

**Dependencies:** `Conversion`, `Session`, `Visitor`, `Identity`, `AttributionModel`, `AttributionCredit` models.

### Domain 5: Dashboard & Reporting

**What it does:** Aggregates attribution data into actionable charts, KPIs, and exports for marketers.

| Capability | Key Files | Pattern |
|-----------|-----------|---------|
| Data aggregation | `dashboard/conversions_data_service.rb`, `dashboard/clv_data_service.rb` | Service delegates to query objects, 5-min cache TTL |
| Query objects | `dashboard/queries/{totals,time_series,by_channel,cohort_analysis,smiling_curve,funnel_stages}_query.rb` | Each query returns one data shape, composable |
| Filter system | `dashboard/scopes/filtered_credits_scope.rb`, `dashboard/scopes/operators/*.rb` | Strategy pattern for operators (Equals, Contains, GreaterThan, etc.) |
| Date parsing | `dashboard/date_range_parser.rb` | Preset ("7d", "30d") or custom ranges, prior period comparison |
| Chart rendering | `app/javascript/controllers/chart_controller.js` | Stimulus + Highcharts, 4 chart types, drilldown, channel colors |
| Real-time feed | Turbo Streams via Solid Cable | Live event feed on Events tab, connection status indicator |
| CSV export | `dashboard/exports_controller.rb` | Export attribution data as CSV |
| CLV analysis | `dashboard/clv_data_service.rb` | Cohort analysis, smiling curve (repeat purchase), coverage % |
| Funnel analysis | `dashboard/funnel_controller.rb`, `dashboard/queries/funnel_stages_query.rb` | Stage conversion rates |

**Dependencies:** `AttributionCredit`, `Conversion`, `Session`. All scoped to `current_account`.

### Domain 6: Platform & Infrastructure

**What it does:** Authentication, billing, SDK management, onboarding, and operational tooling.

| Capability | Key Files | Pattern |
|-----------|-----------|---------|
| API authentication | `api_keys/authentication_service.rb`, `api/v1/base_controller.rb` | `Bearer sk_{env}_{key}` -> SHA256 digest lookup -> account resolution |
| SDK registry | `config/sdk_registry.yml`, `app/models/sdk_registry.rb` | `Data.define` structs loaded from YAML, `SdkCategories` constants |
| Onboarding | `app/controllers/onboarding/`, partials per SDK | Step-by-step install flow, Turbo Frames |
| Billing/Stripe | `billing/checkout_service.rb`, `account/billing.rb` | Stripe integration, usage counters, plan limits, grace periods |
| Data integrity | `data_integrity/checks/*.rb` | Attribution mismatch, self-referral rate, ghost session cleanup |
| API request logging | `api_request_logs/record_service.rb` | Structured logging: endpoint, status, error details, SDK version, response time |
| AML DSL | `aml/executor.rb`, `aml/security/whitelist.rb`, `aml/security/ast_analyzer.rb` | User-defined attribution rules with AST-level security sandboxing |

---

## Quality Scorecard

Assessment of each functional area against key software quality dimensions.

**Rating scale:** A (excellent) / B (good) / C (adequate) / D (needs work) / F (broken)

### Dimension 1: Maintainability

*Can a developer understand and safely modify this code?*

| Area | Grade | Evidence |
|------|-------|----------|
| Model layer | **A** | 4-12 line models, 70 concerns properly segregated by responsibility (Validations, Relationships, Scopes, etc.). Adding a field or scope requires touching exactly one concern file. |
| Service layer | **A** | Consistent `ApplicationService` base with `#call`/`#run`. Private `attr_reader`. Memoization via `@var \|\|=`. Services namespaced by domain (`Sessions::`, `Events::`, `Attribution::`, etc.). |
| Controller layer | **A** | Thin controllers delegate to services. Memoized results. Consistent error handling in `BaseController`. No business logic in controllers. |
| Attribution engine | **B** | Clean Strategy pattern for 8 algorithms. But `Calculator` and `CrossDeviceCalculator` duplicate ~60% of their code (D1-D3), meaning changes must be applied twice. |
| Dashboard queries | **A** | Each query is a focused class (TotalsQuery, TimeSeriesQuery, etc.). Filter operators use Strategy pattern. Cache keys are deterministic. |
| Sessions::CreationService | **B** | 342 lines is large, but 22 guard clauses keep nesting shallow. Well-commented. The orchestration logic (visitor + session + UTM + bot + channel) genuinely belongs together. Optional extraction could improve it (R1). |
| Constants layer | **A** | `Channels`, `ClickIdentifiers`, `UtmAliases` are self-documenting. Frozen arrays/hashes. Clear comments per platform. |

**Overall maintainability: A-**

### Dimension 2: Readability & Understandability

*Can a new developer (or future-you) understand intent without external context?*

| Area | Grade | Evidence |
|------|-------|----------|
| Naming | **A** | Methods: `find_active_visitor_session`, `channel_from_click_ids`, `collapse_burst_sessions`, `suspect_session?`. Classes: `Sessions::ChannelAttributionService`, `Attribution::JourneyBuilder`. No abbreviations, no single-letter vars. |
| Code flow | **A** | Guard clauses over nested conditionals. Early returns everywhere. Functional chains: `touchpoints.map { \|t\| build_touchpoint(t) }`. Pipeline-style: `normalize_credits(algorithm_credits).map { enrich }.map { add_revenue }`. |
| Domain language | **A** | Code uses the same terms as the domain: "visitor", "session", "touchpoint", "channel", "conversion", "identity", "attribution credit". No invented jargon. |
| Documentation | **B** | Architecture docs exist (`lib/docs/architecture/`), API contract is detailed, spec guide is exceptional. But "Multibuzz" naming creep (N1) and missing doc index reduce discoverability. Internal code comments are sparse -- the code is mostly self-documenting, but complex logic (like session reuse rules) would benefit from a "why" comment. |
| Constants as docs | **A** | `ClickIdentifiers` has per-platform comments. `Channels` defines domain patterns inline. `UTM_MEDIUM_PATTERNS` is readable as a specification. |

**Overall readability: A-**

### Dimension 3: Testability

*Can the system be tested effectively and confidently?*

| Area | Grade | Evidence |
|------|-------|----------|
| Test structure | **A** | 213 test files mirroring app/ structure. Memoized fixture methods per CLAUDE.md pattern. Parallel execution. |
| Service testability | **A** | Services accept account + params in initializer, return hash results. Easy to test in isolation. |
| E2E coverage | **A** | Full SDK integration tests (Ruby, Node, Python, PHP, Shopify) via Capybara + Playwright on ports 4001-4005. |
| Coverage measurement | **D** | No SimpleCov. No branch coverage data. Unknown which code paths are actually exercised. Flying blind. |
| N+1 detection | **D** | No Bullet or Prosopite. N+1s could exist undetected, especially in dashboard queries that traverse attribution_credits -> sessions -> visitors. |
| Multi-tenancy testing | **C** | Services are properly scoped, but no explicit "account A can't see account B's data" tests. The 3 unscoped queries (S1-S3) were found by code review, not by tests. |

**Overall testability: B-** (structure is A, tooling is D)

### Dimension 4: Extensibility

*How easy is it to add new features without breaking existing ones?*

| Area | Grade | Evidence |
|------|-------|----------|
| Adding a new channel | **A** | Add constant to `Channels`, add pattern to `ChannelAttributionService`, done. No model changes needed. Channel is a string column, not an enum. |
| Adding a new click ID | **A** | Add to `ClickIdentifiers::ALL`, `SOURCE_MAP`, `CHANNEL_MAP`. Three hash entries. |
| Adding an attribution algorithm | **A** | Create class in `attribution/algorithms/`, add to `ALGORITHM_CLASSES` hash. Strategy pattern makes this a single-file addition. |
| Adding an SDK | **B** | Documented 11-touchpoint checklist in `GUIDE.md`. Comprehensive but manual -- no automation validates completeness. |
| Adding a dashboard metric | **B** | Add query object in `dashboard/queries/`, reference in data service. Pattern is clear but requires understanding the scope/filter chain. |
| Adding a filter operator | **A** | Create operator class in `dashboard/scopes/operators/`, register it. Strategy pattern makes this trivial. |
| Adding a new API endpoint | **A** | Inherit from `Api::V1::BaseController` (auth + error handling for free), create service, create test. Pattern is well-established. |
| Modifying channel classification rules | **B** | Rules are in hash constants (readable), but changing priority order requires understanding the cascade in `#call`. The 7-tier hierarchy is implicit in method ordering, not explicitly configured. |

**Overall extensibility: A-**

### Dimension 5: Correctness & Safety

*Does the code do what it claims? Are there bugs or safety gaps?*

| Area | Grade | Evidence |
|------|-------|----------|
| Multi-tenancy enforcement | **B** | Correctly scoped in 99% of queries. Three exceptions found (S1-S3). Pattern is right; execution has gaps. Dashboard layer is 100% scoped via `BaseController#scoped_*` accessors. |
| Input validation | **B** | Multi-layer: controller params -> service validation -> model validation. But JSONB columns have no size limits (V1-V3), allowing unbounded storage. |
| Attribution math | **A** | Credits normalized to sum=1.0 with tolerance check (`CREDIT_TOLERANCE = 0.0001`). Remainder adjustment applied to last credit. Revenue allocated proportionally. Edge cases handled (empty journey, single touchpoint). |
| Idempotency | **A** | Conversion dedup via `[account_id, idempotency_key]` unique index. Duplicate returns existing record, no double-counting, no double-attribution. |
| Session integrity | **A** | Advisory lock via PostgreSQL (`pg_advisory_xact_lock`) prevents race conditions in session creation. 30-min sliding window consistently enforced. |
| Bot filtering | **A** | Two-layer: known UA patterns (daily-synced from Matomo/Crawler User Agents) + no-signals heuristic. `.qualified` scope excludes suspects from all dashboard queries. |
| API key security | **A** | Keys stored as SHA256 digest, never plaintext. Revocation check on every request. Usage tracking. Environment separation (test/live). |
| AML DSL safety | **C** | `eval()` with user code is inherently risky. Mitigated by `Security::ASTAnalyzer` (whitelist-based AST inspection before eval) and `Security::Whitelist` (100+ allowed methods). But if the analyzer is bypassed, arbitrary code execution is possible. |

**Overall correctness: B+** (A except for the scoping bugs and unbounded JSONB)

### Dimension 6: Performance & Scalability

*Will this code perform under production load?*

| Area | Grade | Evidence |
|------|-------|----------|
| Database indexing | **A** | Composite indexes on all hot paths: `[account_id, session_id, started_at]`, `[visitor_id, device_fingerprint, last_activity_at]`, GIN on JSONB properties. TimescaleDB hypertables for events/sessions. |
| Query patterns | **B** | Memoized lookups (`sessions_map` via `index_by`). No obvious N+1s in core ingestion. But no Bullet/Prosopite to verify -- hidden N+1s possible in dashboard traversals. |
| Caching | **A** | Dashboard: 5-min TTL with deterministic keys. Bot patterns: `Rails.cache` with daily refresh. Referrer sources: 24h cache. Usage counters: cache-backed. All via Solid Cache (DB-backed, no Redis dependency). |
| Batch processing | **A** | Events endpoint accepts arrays. Per-event processing with atomic accept/reject. Usage counter incremented once per batch, not per event. |
| Background processing | **A** | Attribution calculation queued via `after_create_commit`. Referrer/bot pattern sync via scheduled jobs. Solid Queue for all async work. |
| Advisory locking | **A** | Session creation uses `pg_advisory_xact_lock` to prevent duplicate sessions from concurrent SDK calls. Scoped to `[account_id, session_id]`. |

**Overall performance: A-** (no known bottlenecks; needs N+1 verification)

### Dimension 7: SOLID Principle Adherence

| Principle | Grade | Evidence |
|-----------|-------|----------|
| **SRP** (Single Responsibility) | **B+** | Models are thin. Services are focused. Two exceptions: `CreationService` (342 lines, 6 responsibilities) and `Account::Billing` (40 methods). Both are well-organized internally but could be split. |
| **OCP** (Open/Closed) | **A** | Attribution algorithms extend behavior via Strategy pattern -- add a new class, register in hash. Channel classification uses hash-based pattern matching -- add a regex, done. Filter operators same. |
| **LSP** (Liskov Substitution) | **A** | All attribution algorithms implement `#call` returning `[{session_id:, channel:, credit:}]`. All service objects implement `#call` returning result hashes. Substitutable. |
| **ISP** (Interface Segregation) | **A** | Concerns split model interfaces by responsibility. No model forced to implement methods it doesn't need. |
| **DIP** (Dependency Inversion) | **B** | Services receive dependencies via initializer (good). `AttributionModel#algorithm_class` returns the class (good inversion). But some services hardcode class references (`BotPatterns::Matcher`, `ReferrerSources::LookupService`) rather than injecting them. Acceptable at this scale. |

**Overall SOLID: A-**

### Dimension 8: DRY (Don't Repeat Yourself)

| Area | Grade | Evidence |
|------|-------|----------|
| Business rules | **A** | "30-min session window" defined once in `CreationService`. "12 channels" defined once in `Channels::ALL`. Device fingerprint algorithm consistent across 4 services. |
| Code-level | **B** | One significant violation: `Calculator` / `CrossDeviceCalculator` share ~60% code (D1-D3). Constants are well-extracted. UTM aliases centralized. |
| Configuration | **A** | SDK registry is single-source YAML. Channel colors defined once (though mismatched with style guide). Billing rules in one concern. |

**Overall DRY: B+**

### Summary Scorecard

| Dimension | Grade | Key Gaps |
|-----------|-------|----------|
| Maintainability | **A-** | Attribution calculator duplication |
| Readability | **A-** | Missing doc index, sparse "why" comments |
| Testability | **B-** | No coverage tool, no N+1 detection, no isolation tests |
| Extensibility | **A-** | SDK checklist is manual, channel hierarchy is implicit |
| Correctness | **B+** | 3 unscoped queries, unbounded JSONB |
| Performance | **A-** | Needs N+1 verification |
| SOLID | **A-** | CreationService SRP, hardcoded deps |
| DRY | **B+** | Calculator duplication |

**Overall codebase grade: B+/A-** -- excellent architecture with targeted gaps in tooling and three specific bugs.

---

## Style Guides

mbuzz has a Ruby/backend code style guide (`CLAUDE.md`), a frontend design system (`lib/docs/architecture/STYLE_GUIDE.md`), and a minimal RuboCop config (`.rubocop.yml`). This section audits all three for completeness, internal consistency, and actual adherence across the codebase -- with emphasis on code style patterns.

### 1. Ruby Code Style (`CLAUDE.md`)

The project's Ruby conventions are codified in `CLAUDE.md`. Enforcement is via developer discipline + omakase RuboCop (which disables most metrics cops).

#### Documented Conventions -- Adherence Audit

| Convention | Rule | Grade | Evidence |
|-----------|------|-------|----------|
| **Functional over procedural** | Chains, early returns, enumerables, no if/else chains | **A** | `ChannelAttributionService#call`: 7 early returns, zero nesting. `JourneyBuilder#touchpoints`: chain of `.where.not.order.map`. Pattern used in all 174 service files. |
| **Method length < 10 lines** | Explicit rule | **B** | ~85% comply. ~15 methods exceed 10 lines. `CreationService#run` (22 lines), `FunnelStagesQuery#call` (15 lines). Not machine-enforced -- omakase disables `Metrics/MethodLength`. |
| **Descriptive naming** | `exceeded_rate_limit?` not `check`. No abbreviations. | **A** | `find_active_visitor_session`, `channel_from_click_ids`, `collapse_burst_sessions`, `suspect_session?`. Consistent across 70+ service files. Zero single-letter vars outside blocks. |
| **`then` pipelines** | Use for chained transformations | **B** | `channel_from_patterns` uses `.then`. Not widespread -- most services use sequential method calls instead. |
| **`fetch` over `[]`** | Fail-fast hash access | **B** | `MEDIUM_TO_CHANNEL.fetch(medium, Channels::REFERRAL)` in ChannelAttributionService. Some services use `[]` where nil is valid. Acceptable pragmatism. |
| **Private `attr_reader`** | All ivars via `attr_reader` after `private` | **A** | 100% of services. Zero direct `@var` reads outside initializers. |
| **Memoization `@var \|\|=`** | Standard pattern | **A** | Consistent: `sessions_map`, `referrer_lookup`, `lookback_window_start`, etc. Controllers memoize service results: `@result \|\|= Service.new.call`. |
| **`.freeze` constants** | All arrays/hashes frozen | **A** | 100% of constants files. `UTM_MEDIUM_PATTERNS.freeze`, `CHANNEL_MAP.freeze`, `ALL.freeze`. |
| **2-space indent** | For continuations and nested HTML/ERB | **A** | Consistent across all Ruby and ERB files. |

#### Service Object Structure -- Ordering Convention

**Finding:** 98% of 46 `ApplicationService` subclasses follow an identical structure:

```
initialize(params)      # public
                        # blank line
private                 # access modifier
  attr_reader :a, :b    # attribute readers (first thing after private)
                        #
  def run               # implementation
    ...
  end
                        #
  def helper_method     # private helpers
    ...
  end
```

**Evidence (sampled):**

| Service | Follows Pattern? |
|---------|-----------------|
| `Billing::CheckoutService` (102 lines) | Yes -- init:5-12, private:14, attr_reader:16, run:18-23 |
| `Team::InvitationService` (129 lines) | Yes -- init:5-11, private:13, attr_reader:15, run:17-21 |
| `Accounts::CreationService` (58 lines) | Yes -- init:5-8, private:10, attr_reader:12, run:14-18 |
| `Events::ValidationService` (79 lines) | Yes -- init:3-5, private:7, attr_reader:9, run:11-22 |
| `ApiKeys::GenerationService` (43 lines) | Yes -- init:3-7, private:9, attr_reader:11, run:13-20 |

**Deviations (3, all intentional per CLAUDE.md):**
- `ApiKeys::RateLimiterService` -- returns `{ allowed:, remaining:, reset_at: }`, not success/fail
- `Dashboard::DateRangeParser` -- value object with public `attr_reader`
- `Sessions::MediumNormalizer` -- `self.call` class method wrapper

**Gap:** This ordering convention is followed religiously but **not documented in CLAUDE.md**. Should be codified.

#### Concern Extraction -- Naming Convention

**Finding:** 100% consistent. All 62 concerns follow `Model::ResponsibilityName`:

| Responsibility | Examples | Count |
|---------------|----------|-------|
| `Validations` | `Account::Validations`, `Event::Validations`, `Session::Validations` | 8 |
| `Relationships` | `Account::Relationships`, `Event::Relationships`, `Visitor::Relationships` | 7 |
| `Callbacks` | `Account::Callbacks`, `Session::Callbacks`, `Visitor::Callbacks` | 5 |
| `Scopes` | `Account::Scopes`, `Event::Scopes`, `Conversion::Scopes` | 6 |
| `Tracking` | `Session::Tracking`, `Visitor::Tracking` | 2 |
| Domain-specific | `Account::Billing`, `Account::Onboarding`, `User::Authentication`, `ApiKey::KeyManagement`, `AttributionModel::AlgorithmMapping` | 34 |

All use `extend ActiveSupport::Concern` + `included do` block. Zero deviations.

#### Controller Pattern

**Finding:** 100% thin. All 56 controllers delegate to services via memoized private methods.

| Controller | Lines | Public Logic | Evidence |
|-----------|-------|-------------|----------|
| `DashboardController` | 15 | 3 lines | Single `show` action, private helper |
| `AccountsController` | 37 | 5 lines | Memoized `creation_result` |
| `SignupController` | 59 | 8 lines | Memoized `signup_result` |
| `Dashboard::ConversionsController` | 79 | 10 lines | Memoized service calls |
| `Api::V1::EventsController` | 154 | 29 lines | **Longest** -- still thin; 125 lines are private helpers |

**Memoization pattern (consistent across all controllers):**
```ruby
def service_result
  @service_result ||= MyService.new(current_account, params).call
end
```

#### Error Handling Patterns

**Finding:** Three patterns exist, all valid per CLAUDE.md, but the choice criteria aren't documented.

| Pattern | Usage | When to Use |
|---------|-------|-------------|
| **ApplicationService rescue** (46 services) | `run` raises, `call` rescues `RecordInvalid`, `RecordNotFound`, `StandardError` | Default for any service returning success/fail |
| **Explicit error collection** (5 services) | `errors = []; errors.concat(validate_x); return error_result(errors) if errors.any?` | Validation services that collect multiple errors |
| **Custom return types** (3 services) | No ApplicationService. Returns domain hash (`{ allowed:, remaining: }`) | Services returning domain-specific structures per CLAUDE.md guidance |

**Example of explicit error collection** (`Events::ValidationService`):
```ruby
def run
  errors = []
  errors.concat(validate_event_type)
  errors.concat(validate_identity)
  return error_result(errors) if errors.any?
  { valid: true, errors: [] }
end
```

**Gap:** CLAUDE.md documents *when NOT to use* ApplicationService but doesn't document the error collection pattern or when to choose it over letting exceptions bubble.

#### Predicate Methods

**Finding:** 100% consistent. All `?` methods return booleans. Private in services, public in models.

**Models:** `Article#published?`, `Conversion#inherit_acquisition?`, `SdkRegistry#live?`, `ApiKey#active?`, `User#member_of?(account)`, `FeedItem#event?`

**Services:** `BotPatterns::Matcher#bot?(user_agent)`, `RateLimiterService#rate_limited?`, `AuthenticationService#header_valid?`

#### Test Patterns

**Finding:** Two patterns coexist -- memoized helpers (73%) and `setup` blocks (27%).

| Pattern | Usage | Example |
|---------|-------|---------|
| **Memoized fixture methods** (73% -- 153/210 files) | `def account = @account \|\|= accounts(:one)` | Preferred per CLAUDE.md |
| **`setup do` blocks** (27% -- 57/210 files) | `setup { Rails.cache.clear }` | Used for cache clearing, global state reset |

**Test naming** is consistent: action-based strings.
- `test "should authenticate valid API key"`
- `test "returns 422 with invalid event_id"`
- `test "prevents cross-account event access"`

**Gap:** No documented convention for when `setup` is acceptable vs memoized helpers. The split is pragmatic (setup for side-effectful resets, memoized for fixtures), but undocumented.

#### Frozen String Literal Adoption

**Finding:** Partial adoption, trending up with newer code.

| Directory | With Pragma | Total | % |
|-----------|------------|-------|---|
| `app/services/` | 94 | 174 | **54%** |
| `app/constants/` | 5 | 15 | **33%** |
| `app/models/` | 30 | 100 | **30%** |
| `app/controllers/` | 11 | 56 | **20%** |

**Gap:** Omakase disables `Style/FrozenStringLiteralComment`. Enabling it + running `rubocop --auto-correct` would fix all files in one pass.

#### Query Object Patterns

**Finding:** All query objects in `dashboard/queries/` use consistent interface -- `initialize(scope, ...)` + `call` returning domain-specific structures (not success/fail). They correctly do NOT inherit from `ApplicationService`.

```ruby
# FunnelStagesQuery returns Array of stage hashes
# TopCampaignsQuery returns Hash mapping channels to campaign arrays
```

**Gap:** This pattern is not documented. New developers might mistakenly inherit from ApplicationService.

#### Autoloading Compliance

**Finding:** 100% compliant. Zero manual `require` statements for application code. Only exceptions:
- `require "ostruct"` in `Billing::CheckoutService` (stdlib, not Rails-autoloaded)
- `require "test_helper"` in all test files (Rails convention)

#### Constants Organization

**Finding:** 100% consistent across all 15 files in `app/constants/`:
- Module wrapping (`module Channels`, `module Billing`)
- Section headers (`# --- Plan Slugs ---`, `# --- Domain ---`)
- SCREAMING_SNAKE_CASE naming
- `.freeze` on all collections
- Inline comments explaining purpose

#### Conventions Documented But Not Machine-Enforced

| Convention | CLAUDE.md Rule | Enforcement Gap |
|-----------|---------------|-----------------|
| Methods < 10 lines | Explicit | `Metrics/MethodLength` disabled by omakase. ~15 violations. |
| Single responsibility | "One action per service" | No cop. `Account::Billing` has 40 methods. |
| No magic values | "Use constants" | No cop. Minor -- `30` (session window), `50` (dedup log interval) hardcoded but documented via constant names in primary usages. |
| `frozen_string_literal` | Implicit Ruby best practice | Disabled by omakase. 54% adoption in services, 20% in controllers. |
| Guard clause preference | "Early returns over nested conditionals" | `Style/GuardClause` disabled by omakase. |

#### Missing From Ruby Style Guide (CLAUDE.md)

| Gap | Impact | Recommendation |
|-----|--------|----------------|
| **No service method ordering convention** | New developers won't know the init -> private -> attr_reader -> run -> helpers pattern | Codify in CLAUDE.md. Already followed by 98% of services. |
| **No test style guide** | Split between memoized helpers (73%) and setup blocks (27%) is pragmatic but undocumented | Document: "Use memoized helpers for fixtures; `setup` only for side-effectful resets (cache clear, global state)." Add `rubocop-minitest` for assertion style. |
| **No error handling convention** | Three patterns exist without documented selection criteria | Document when to use each: ApplicationService rescue (default), error collection (multi-field validation), custom returns (domain structures). |
| **No JSONB convention** | Services write JSONB with different patterns (deep_merge vs shallow assign) | Document: max 50KB, validate via custom validator, prefer shallow assignment. |
| **No query object convention** | Query objects in `dashboard/queries/` return domain types but this isn't documented | Document: "Query objects return domain structures (not success/fail). Use `initialize(scope, ...)` + `call`. Do not inherit from `ApplicationService`." |
| **No constant organization convention** | Constants use section headers (`# --- Plan Slugs ---`) but this isn't documented | Document: "Constants use module wrapping, section headers, SCREAMING_SNAKE, `.freeze` on all collections." Already 100% consistent. |

### 2. RuboCop: Current vs Required

| Aspect | Current (omakase) | Required (per CLAUDE.md conventions) | Proposed Config |
|--------|-------------------|--------------------------------------|-----------------|
| Method length | **Disabled** | < 10 lines | `Max: 12` (allow 2-line buffer) |
| Class length | **Disabled** | Thin models (~10 lines) | `Max: 150` |
| Guard clauses | **Disabled** | "Early returns over nested conditionals" | `Style/GuardClause: Enabled` |
| Frozen string literal | **Disabled** | ~40% of files missing | `FrozenStringLiteralComment: always` |
| Cyclomatic complexity | **Disabled** | Implied by "single responsibility" | `Max: 8` |
| Parameter lists | **Disabled** | Implied by "dependency injection via init" | `Max: 4` |
| Unused arguments | **Disabled** | Clean code | `UnusedMethodArgument: Enabled` |
| Thread safety | **Not installed** | Puma + Solid Queue = threaded | Add `rubocop-thread_safety` |
| Test assertions | **Not installed** | Consistent test style | Add `rubocop-minitest` |

**The gap:** `CLAUDE.md` documents clear conventions. `.rubocop.yml` enforces almost none of them. Omakase intentionally disables the metrics cops that would catch violations. The extended config in the Appendix bridges this gap, with `--auto-gen-config` to baseline existing violations into `.rubocop_todo.yml` for incremental cleanup.

### 3. Frontend Design System (`lib/docs/architecture/STYLE_GUIDE.md`)

An 890-line comprehensive design system. Well-structured for a dev-focused product. Two issues:

**Channel Color Mismatch (N2):** Style guide defines 7 channel-color pairs. Code (`chart_controller.js:5-18`) defines 12. They disagree on 5 of 7 shared mappings (e.g., paid_search: style guide says blue-500, code uses indigo). Root cause: channels evolved from 7 to 12 without backporting to the style guide. Fix: update STYLE_GUIDE.md to match the 12 channels in code.

**Naming (N1):** Heading says "Multibuzz" -- should be "mbuzz".

### Style Adherence Summary

| Style Guide | Completeness | Adherence | Enforced? |
|-------------|-------------|-----------|-----------|
| Ruby code style (`CLAUDE.md`) | **B+** (missing 6 conventions documented above) | **A-** (high discipline, 95%+ consistency on documented rules) | **No** -- developer discipline only |
| RuboCop | **D** (omakase disables key cops) | N/A | Barely active |
| Design system (`STYLE_GUIDE.md`) | **A-** (comprehensive but colors diverged) | **B** (channel colors stale, naming inconsistency) | No |

**Key insight:** The codebase has *excellent* style consistency despite minimal tooling enforcement. The patterns are deeply internalized. The risk is that as the team scales, undocumented conventions and unenforced rules will drift. Codifying the 6 missing conventions in CLAUDE.md and enabling the RuboCop extended config converts tribal knowledge into machine-enforced standards.

---

## Findings

### A. Security Issues (Fix Immediately)

| # | Severity | Issue | File | Line |
|---|----------|-------|------|------|
| S1 | **HIGH** | Unscoped `Visitor.where(id:).delete_all` | `app/services/visitors/deduplication_service.rb` | 142 |
| S2 | **HIGH** | Unscoped `Session.where(id:).index_by` | `app/services/attribution/calculator.rb` | 103 |
| S3 | **HIGH** | Unscoped `Session.where(id:).index_by` | `app/services/attribution/cross_device_calculator.rb` | 86 |

**S1**: `delete_all` bypasses callbacks and operates globally. If `duplicate_ids` leaks cross-account, data is destroyed.
Fix: `account.visitors.where(id: duplicate_ids).delete_all`

**S2+S3**: Session lookup without account scoping. Journey touchpoints come from properly-scoped `JourneyBuilder`, so exploitation is unlikely, but defense-in-depth requires scoping.
Fix: `conversion.account.sessions.where(id: session_ids).index_by(&:id)`

### B. DRY Violations

| # | Issue | Files | Impact |
|---|-------|-------|--------|
| D1 | `Calculator` and `CrossDeviceCalculator` share ~60% identical code | `attribution/calculator.rb`, `attribution/cross_device_calculator.rb` | Divergence risk; bug fixes must be applied twice |
| D2 | `sessions_map` pattern duplicated verbatim | Same files, lines 100-105 and 83-88 | Copy-paste, both with the S2/S3 scoping bug |
| D3 | `enrich_with_session_data` + `add_revenue_credit` + `utm_value` duplicated verbatim | Same files | Same methods, same signatures |

**Fix**: Extract `Attribution::CreditEnricher` concern or shared module. Both calculators include it, eliminating duplication and centralizing the session lookup fix.

### C. SRP Concerns

| # | Issue | File | Lines | Recommendation |
|---|-------|------|-------|----------------|
| R1 | `Sessions::CreationService` handles visitor resolution, session management, UTM capture, bot detection, cookie setting, usage counting | `app/services/sessions/creation_service.rb` | 342 | Well-organized with guard clauses (22 early returns), but extracting visitor resolution into `Visitors::ResolutionService` would improve testability |
| R2 | `Account::Billing` concern has 40 methods across 262 lines | `app/models/concerns/account/billing.rb` | 262 | Methods are individually small (2-6 lines), but the concern is a knowledge magnet. Consider `Account::BillingStatus` for read-only queries vs `Account::BillingActions` for mutations |

### D. Missing Validations

| # | Issue | File | Risk |
|---|-------|------|------|
| V1 | Event `properties` JSONB has no size limit | `app/models/concerns/event/validations.rb` | Unbounded storage; a malicious SDK call with 10MB properties succeeds |
| V2 | Session `initial_utm` JSONB has no size limit | `app/models/session.rb` | Same risk |
| V3 | Identity `traits` JSONB has no size limit | `app/models/identity.rb` | Same risk |

**Fix**: Add `validate :properties_size_limit` custom validation capping JSONB at 50KB.

### E. Documentation Inconsistencies

| # | Issue | Files |
|---|-------|-------|
| N1 | "Multibuzz" used instead of "mbuzz" | `lib/docs/architecture/STYLE_GUIDE.md` (heading), `lib/docs/SETUP.md`, `lib/docs/sdk/streamlined_sdk_spec.md`, `lib/docs/sdk/sdk_specification.md`, `lib/docs/architecture/code_highlighting_implementation.md` |
| N2 | Chart color palette in `chart_controller.js` doesn't match STYLE_GUIDE.md | `app/javascript/controllers/chart_controller.js` lines 5-18 vs `lib/docs/architecture/STYLE_GUIDE.md` lines 134-142 |
| N3 | Planned doc automation tools (link checker, SDK consistency validator, example runner) referenced in `documentation_strategy.md` but never implemented | `lib/docs/architecture/documentation_strategy.md` |

### F. Static Analysis Assessment

#### What Exists Today

| Tool | Gem/Config | CI Gated? | Notes |
|------|-----------|-----------|-------|
| **Brakeman** 7.1.1 | `Gemfile` + `bin/brakeman` | Yes (`scan_ruby` job) | Enforces `--ensure-latest`. Working well. |
| **RuboCop** 1.81.7 | `rubocop-rails-omakase` + `rubocop-rails` + `rubocop-performance` | Yes (`lint` job) | Omakase disables Metrics/Naming/Lint cops. Minimal custom overrides. |
| **importmap audit** | Built-in Rails 8 | Yes (`scan_js` job) | JS dependency CVE scanning. |

CI pipeline (`.github/workflows/ci.yml`) runs 4 jobs: `scan_ruby`, `scan_js`, `lint`, `test`.

#### What's Missing

**Security:**

| Tool | What It Catches | Priority |
|------|----------------|----------|
| `bundler-audit` | Known CVEs in gem dependencies (`Gemfile.lock`) | **P0** -- not in CI despite being trivial to add |
| `strong_migrations` | Unsafe migrations (non-concurrent index, column with default on large table) | **P0** -- prevents production incidents |
| Trivy | Container image vulnerabilities before `kamal deploy` | **P1** -- scans OS packages + app dependencies in Docker image |

**Code Quality:**

| Tool | What It Catches | Priority |
|------|----------------|----------|
| Extended RuboCop | Method length, class length, complexity, guard clauses, frozen string literals | **P0** -- enforces CLAUDE.md conventions that omakase disables |
| `rubocop-minitest` | Test assertion best practices (`assert_equal` ordering, `refute` usage) | **P1** |
| `erb_lint` | ERB template issues (spacing, no JS tag helper, embedded Ruby style) | **P1** |
| `rubocop-thread_safety` | Mutable class instance variables, thread-unsafe patterns under Puma/Solid Queue | **P1** |
| `reek` | Code smells: Feature Envy, Data Clump, Too Many Statements, Nested Iterators | **P2** |
| `flay` | Structural code duplication (would have caught Calculator/CrossDeviceCalculator D1-D3) | **P2** |

**Database:**

| Tool | What It Catches | Priority |
|------|----------------|----------|
| `prosopite` | N+1 queries at runtime in tests (zero false positives, superior to Bullet) | **P0** -- no N+1 detection exists today |
| `database_consistency` | Schema/validation mismatches (e.g., `validates :name, presence: true` but column allows NULL) | **P1** |
| `active_record_doctor` | Missing foreign key indexes, extraneous indexes, unindexed WHERE columns | **P1** |

**Test Quality:**

| Tool | What It Catches | Priority |
|------|----------------|----------|
| `simplecov` | Overall test coverage with branch coverage | **P0** -- flying blind without it |
| `undercover` | Changed code in PR that lacks test coverage (diff-based) | **P1** -- more actionable than overall % |

**Developer Workflow:**

| Tool | What It Does | Priority |
|------|-------------|----------|
| Lefthook | Pre-commit hooks: run RuboCop + Brakeman on staged files before commit | **P1** -- catches issues before CI |

**Not Recommended (evaluated and rejected):**

| Tool | Why Not |
|------|---------|
| Bullet | Prosopite is superior (zero false positives, created to fix Bullet's issues) |
| Sorbet/Steep | High adoption cost for existing Rails 8 codebase. Gradual typing not justified at current team size. |
| Mutant | Computationally expensive. Commercial license required. Overkill for current scale. |
| rails_best_practices | Poorly maintained, lags behind Rails 8 conventions. |
| Fasterer | Micro-optimizations that rarely matter in a Rails app. |
| Dawnscanner | Minimal maintenance, superseded by Brakeman + Semgrep. |

---

## Proposed Solution

### Static Analysis Workflow

Every phase ends with a **gate**: run the full static analysis suite and fix any new violations before moving to the next phase. This prevents accumulating debt as we refactor.

```
Phase N work complete
       |
       v
  Run static checkers:
    bin/brakeman --no-pager
    bundle exec bundler-audit check --update
    bundle exec rubocop
    bundle exec erblint app/views/
    PROSOPITE=1 bin/rails test
    bundle exec database_consistency
       |
       v
  Fix violations introduced in Phase N
       |
       v
  Commit fixes
       |
       v
  Phase N+1
```

**Gate rules:**
- Zero new Brakeman warnings (security is non-negotiable)
- Zero new bundler-audit CVEs
- RuboCop: only pre-existing `.rubocop_todo.yml` violations allowed
- Prosopite: zero N+1 queries in test suite
- database_consistency: zero new mismatches
- erblint: zero warnings on changed views

### Phase 1: Static Analysis Foundation (Immediate)

Install all static analysis tools so they're available as gates for subsequent phases.

### Phase 2: Security Fixes

Fix the three unscoped queries, add JSONB size validations. Run gate.

### Phase 3: DRY Refactor

Extract shared attribution logic. Optionally extract visitor resolution from CreationService. Run gate.

### Phase 4: Style Guide Codification & Doc Cleanup

Codify undocumented code conventions in CLAUDE.md, enable RuboCop enforcement, fix naming inconsistencies. Run gate.

---

## Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `app/services/visitors/deduplication_service.rb` | Visitor dedup | Scope `delete_all` to account (line 142) |
| `app/services/attribution/calculator.rb` | Single-device attribution | Scope `sessions_map` to account (line 103) |
| `app/services/attribution/cross_device_calculator.rb` | Cross-device attribution | Scope `sessions_map` to account (line 86) |
| `app/models/concerns/event/validations.rb` | Event validations | Add JSONB size limit |
| `CLAUDE.md` | Code style guide | Codify 6 undocumented conventions (service ordering, test style, error handling, query objects, JSONB, constants) |
| `.rubocop.yml` | Linter config | Extend beyond omakase to enforce CLAUDE.md conventions |
| `Gemfile` | Dependencies | Add bundler-audit, strong_migrations, prosopite, database_consistency, active_record_doctor, simplecov, undercover, reek, rubocop-minitest, rubocop-thread_safety, erb_lint |
| `test/test_helper.rb` | Test setup | Add SimpleCov + Prosopite config |
| `.github/workflows/ci.yml` | CI pipeline | Add bundler-audit, erblint, database_consistency jobs |
| `lefthook.yml` | Pre-commit hooks | RuboCop + erblint on staged files |
| `config/initializers/strong_migrations.rb` | Migration safety | Block unsafe migrations |
| `.reek.yml` | Code smell config | Thresholds for TooManyStatements, LongParameterList, etc. |
| `.erb-lint.yml` | ERB linting config | SpaceAroundErbTag, NoJavascriptTagHelper |
| `lib/docs/architecture/STYLE_GUIDE.md` | Design system | Fix naming, update channel colors to match 12-channel taxonomy |

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Happy path: session ingestion | Valid SDK call with UTM + referrer | Session created, channel classified, visitor resolved |
| Happy path: attribution | Conversion with 3+ sessions in lookback | Credits distributed per algorithm, sum = 1.0 |
| Edge: cross-device | Identity with 2 visitors, conversion on visitor B | JourneyBuilder spans both visitors' sessions |
| Edge: burst dedup | 3 sessions within 5 min, middle one is direct | Middle session collapsed, 2 touchpoints remain |
| Edge: bot detection | UA matches known bot pattern + has real UTM | `suspect: true, suspect_reason: "known_bot"`, filtered from dashboard via `.qualified` scope |
| Edge: idempotent conversion | Same `idempotency_key` sent twice | Second call returns existing conversion, `duplicate: true`, no double-counting |
| Edge: unscoped delete (BUG) | Dedup runs with IDs from mixed accounts | **Currently**: deletes across accounts. **After fix**: scoped to account |
| Edge: oversized properties | 10MB JSONB payload | **Currently**: accepted. **After fix**: rejected with validation error |
| Edge: unknown utm_medium | `utm_medium=podcast` (not in patterns) | Falls back to referrer, then `other` |

---

## Implementation Tasks

### Phase 1: Static Analysis Foundation

Install all tools, configure them, baseline existing violations. After this phase, the full gate suite is available for all subsequent work.

**1A. Security scanning:**

- [ ] **1.1** Add `bundler-audit` to Gemfile (development group). Run `bundle audit check --update`, fix any CVEs. Add `bundler-audit` job to `.github/workflows/ci.yml`.
- [ ] **1.2** Add `strong_migrations` to Gemfile. Configure in `config/initializers/strong_migrations.rb` with `target_version` for PostgreSQL. Run all pending migrations to verify none are flagged.

**1B. Code quality:**

- [ ] **1.3** Extend `.rubocop.yml` with Metrics cops (MethodLength: 12, ClassLength: 150, CyclomaticComplexity: 8, ParameterLists: 4), Lint cops (UnusedMethodArgument, DuplicateMethods, ShadowingOuterLocalVariable), Style cops (FrozenStringLiteralComment, GuardClause), Rails cops (HasManyOrHasOneDependent, UniqueValidationWithoutIndex). Run `rubocop --auto-gen-config` to baseline existing violations into `.rubocop_todo.yml`.
- [ ] **1.4** Add `rubocop-minitest` for test assertion best practices. Add to `.rubocop.yml` plugins.
- [ ] **1.5** Add `rubocop-thread_safety` for Puma + Solid Queue thread safety. Add to `.rubocop.yml` plugins.
- [ ] **1.6** Add `erb_lint` with `.erb-lint.yml` -- SpaceAroundErbTag, NoJavascriptTagHelper, RuboCop integration. Add `erblint` job to CI.
- [ ] **1.7** Add `reek` with `.reek.yml` -- TooManyStatements: 8, LongParameterList: 4, FeatureEnvy, NestedIterators: 2. Exclude test/ and db/migrate/.

**1C. Database analysis:**

- [ ] **1.8** Add `prosopite` to Gemfile (development + test). Configure in `test_helper.rb`: `Prosopite.raise = true`. Configure in `config/environments/development.rb`: `Prosopite.rails_logger = true`. Fix any N+1s surfaced by test suite.
- [ ] **1.9** Add `database_consistency` to Gemfile (development). Run `bundle exec database_consistency`. Fix schema/validation mismatches or document exceptions in `.database_consistency.yml`.
- [ ] **1.10** Add `active_record_doctor` to Gemfile (development). Run `rake active_record_doctor` to find missing indexes. Add any missing foreign key indexes.

**1D. Test quality:**

- [ ] **1.11** Add `simplecov` to Gemfile (test). Configure in `test_helper.rb` behind `ENV["COVERAGE"]`, set `minimum_coverage 80`, enable branch coverage, add groups (Models/Controllers/Services/Jobs). Run `COVERAGE=1 bin/rails test` to establish baseline.
- [ ] **1.12** Add `undercover` to Gemfile (development). Configure for PR-level diff coverage checks.

**1E. Performance baselines:**

- [ ] **1.13** Add `benchmark-ips` and `memory_profiler` to Gemfile (development + test). These enable the Phase 5 performance test suite.
- [ ] **1.14** Add query budget assertions to existing hot-path controller tests using `assert_queries`. Measure current baselines, then lock them. Key budgets:

| Endpoint | Max Queries | Rationale |
|----------|------------|-----------|
| `POST /sessions` | ~12 | Every page load hits this |
| `POST /events` (batch 10) | ~18 | Must NOT scale linearly with batch size |
| `POST /conversions` | ~15 | Triggers async attribution |
| `POST /identify` | ~8 | Simple find-or-create |

- [ ] **1.15** Add `rack-mini-profiler` and `stackprof` to Gemfile (development only). Configure `rack-mini-profiler` in `config/environments/development.rb` behind `ENV["PROFILER"]` flag.

**1F. Developer workflow:**

- [ ] **1.16** Install Lefthook (`brew install lefthook`). Create `lefthook.yml` with pre-commit hooks: RuboCop on staged `.rb` files, erblint on staged `.erb` files, Brakeman quick scan. Run `lefthook install`.

**1G. Gate checkpoint:**

- [ ] **1.17** Run full gate suite. Fix all violations. Commit clean baseline.

### Phase 2: Security Fixes

- [ ] **2.1** Scope `deduplication_service.rb:142` -- change `Visitor.where(id: duplicate_ids).delete_all` to `account.visitors.where(id: duplicate_ids).delete_all`
- [ ] **2.2** Scope `calculator.rb:103` -- change `Session.where(id: session_ids)` to `conversion.account.sessions.where(id: session_ids)`
- [ ] **2.3** Scope `cross_device_calculator.rb:86` -- same fix as 2.2
- [ ] **2.4** Add JSONB size validation to Event, Session (initial_utm), Identity (traits) -- max 50KB
- [ ] **2.5** Write cross-account isolation tests for `DeduplicationService`, `Calculator`, `CrossDeviceCalculator`
- [ ] **2.6** **Gate checkpoint:** run full static analysis suite. Fix any new violations.

### Phase 3: DRY Refactor

- [ ] **3.1** Extract `Attribution::CreditEnricher` module from `Calculator` and `CrossDeviceCalculator` -- shared methods: `enrich_with_session_data`, `add_revenue_credit`, `find_session`, `sessions_map`, `utm_value`
- [ ] **3.2** Both calculators `include Attribution::CreditEnricher`, eliminating ~40 lines of duplication
- [ ] **3.3** (Optional) Extract `Visitors::ResolutionService` from `Sessions::CreationService` for the visitor find/create + fingerprint matching logic (~50 lines)
- [ ] **3.4** **Gate checkpoint:** run full static analysis suite. Verify `flay` would no longer flag Calculator duplication.

### Phase 4: Style Guide Codification & Documentation Cleanup

**4A. Codify undocumented code conventions in CLAUDE.md:**

- [ ] **4.1** Add service method ordering convention: `initialize` -> blank line -> `private` -> `attr_reader` -> `def run` -> private helpers
- [ ] **4.2** Add test style convention: "Memoized helpers for fixtures; `setup` only for side-effectful resets (cache clear, global state). Test names: action-based strings."
- [ ] **4.3** Add error handling convention: document when to use each pattern (ApplicationService rescue = default; error collection = multi-field validation; custom returns = domain structures)
- [ ] **4.4** Add query object convention: "Return domain structures, not success/fail. Use `initialize(scope, ...)` + `call`. Do not inherit from ApplicationService."
- [ ] **4.5** Add JSONB convention: "Max 50KB. Validate via custom validator. Prefer shallow assignment over deep_merge."
- [ ] **4.6** Add constant organization convention: "Module wrapping, section headers (`# --- Section ---`), SCREAMING_SNAKE, `.freeze` on all collections."

**4B. Enable RuboCop enforcement:**

- [ ] **4.7** Add `frozen_string_literal: true` pragma to all files missing it (enable cop + `rubocop --auto-correct`)
- [ ] **4.8** Burn down `.rubocop_todo.yml` -- fix remaining baselined violations or document permanent exceptions with `rubocop:disable` comments

**4C. Documentation cleanup:**

- [ ] **4.9** Find-and-replace "Multibuzz" -> "mbuzz" across all `lib/docs/**/*.md` files (including STYLE_GUIDE.md heading)
- [ ] **4.10** Update `STYLE_GUIDE.md` channel color mapping to match the 12 channels in `chart_controller.js`
- [ ] **4.11** Remove references to unimplemented automation tools from `documentation_strategy.md` or create issues to track them
- [ ] **4.12** **Final gate checkpoint:** run full static analysis suite. Zero violations.

### Phase 5: Performance Baselines

Establish measured performance baselines and regression detection. The codebase scored A- on performance by code review -- Phase 5 replaces opinions with numbers.

**5A. Performance test suite (`test/performance/`):**

- [ ] **5.1** Create `test/performance/` directory and `test/performance/performance_test_helper.rb` with shared benchmark utilities (timing helper, allocation counter, query counter).
- [ ] **5.2** Write ingestion performance tests:
  - Session creation completes in < 50ms average (100 iterations after warmup)
  - Event batch ingestion scales sub-linearly: 10 events < 3x single-event time
  - Conversion tracking completes in < 75ms average
  - Identity linking completes in < 30ms average
- [ ] **5.3** Write attribution performance tests:
  - `Attribution::Calculator` with 10-touchpoint journey: < 100ms
  - `Attribution::Calculator` with 50-touchpoint journey: < 500ms
  - Markov chain with 100 historical paths: < 1s
  - Shapley value with 8 channels: < 2s
  - Object allocations per attribution run: < 5,000
- [ ] **5.4** Write dashboard query performance tests:
  - `TotalsQuery` cold cache: < 200ms
  - `TimeSeriesQuery` (30 days): < 300ms
  - `ByChannelQuery`: < 200ms
  - All dashboard queries: zero N+1 (Prosopite covers this, but explicit assertions document intent)
- [ ] **5.5** Write memory budget tests using `memory_profiler`:
  - Single session creation: < 500 allocated objects
  - Single event ingestion: < 300 allocated objects
  - Event batch (10): < 2,000 allocated objects (not 10x single)
  - Attribution calculation: < 5,000 allocated objects

**5B. Load test scripts (`test/load/`):**

- [ ] **5.6** Install k6 (`brew install k6`). Create `test/load/` directory.
- [ ] **5.7** Write `test/load/ingestion_load.js` -- k6 script for steady-state and spike scenarios:
  - Steady state: 100 req/s for 60s
  - Spike: ramp to 500 req/s for 30s, recover
  - Thresholds: p95 < 100ms, p99 < 250ms, error rate < 1%
- [ ] **5.8** Write `test/load/dashboard_load.js` -- k6 script for dashboard queries under concurrent load:
  - 20 concurrent users, 60s duration
  - Thresholds: p95 < 500ms, p99 < 1s
- [ ] **5.9** Document load test execution in `test/load/README.md` -- not CI-gated, run manually before deploys.

**5C. Regression detection:**

- [ ] **5.10** Add `bin/perf` script for running performance tests locally:
  ```bash
  #!/usr/bin/env bash
  set -e
  echo "==> Query budgets"  && bin/rails test test/performance/ --name /query_budget/
  echo "==> Timing budgets" && bin/rails test test/performance/ --name /timing/
  echo "==> Memory budgets" && bin/rails test test/performance/ --name /memory/
  echo "==> All clear."
  ```
- [ ] **5.11** Add performance test job to CI (non-blocking, report-only -- failures produce warnings, not build failures):
  ```yaml
  perf:
    runs-on: ubuntu-latest
    continue-on-error: true
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { bundler-cache: true }
      - run: bin/rails test test/performance/
  ```
- [ ] **5.12** **Gate checkpoint:** all performance tests pass. Document baseline numbers in `test/performance/BASELINES.md`.

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Cross-account isolation: dedup | `test/services/visitors/deduplication_service_test.rb` | `delete_all` only affects current account's visitors |
| Cross-account isolation: calculator | `test/services/attribution/calculator_test.rb` | `sessions_map` only loads current account's sessions |
| Cross-account isolation: cross-device | `test/services/attribution/cross_device_calculator_test.rb` | Same as above |
| JSONB size limit: event | `test/models/event_test.rb` | Properties > 50KB rejected |
| JSONB size limit: session | `test/models/session_test.rb` | initial_utm > 50KB rejected |
| CreditEnricher module | `test/services/attribution/credit_enricher_test.rb` | Enrichment works with account-scoped session lookup |

### Performance Tests

| Test | File | Verifies |
|------|------|----------|
| Query budget: sessions | `test/performance/sessions_performance_test.rb` | Session creation stays within query budget |
| Query budget: events | `test/performance/events_performance_test.rb` | Batch ingestion queries don't scale linearly |
| Query budget: conversions | `test/performance/conversions_performance_test.rb` | Conversion tracking within query budget |
| Timing: ingestion | `test/performance/ingestion_timing_test.rb` | Session < 50ms, event batch < 100ms, conversion < 75ms |
| Timing: attribution | `test/performance/attribution_timing_test.rb` | Calculator < 100ms for 10 touchpoints |
| Memory: ingestion | `test/performance/ingestion_memory_test.rb` | Bounded object allocations per request |
| Memory: attribution | `test/performance/attribution_memory_test.rb` | < 5,000 objects per calculation |
| Sub-linear scaling | `test/performance/scaling_test.rb` | 10x batch != 10x cost |

### CI Pipeline (Updated)

Current pipeline has 4 jobs. After Phase 1, expands to 7:

```
Existing (keep):
  scan_ruby:     bin/brakeman --no-pager
  scan_js:       bin/importmap audit
  lint:          bin/rubocop -f github

New:
  gem_audit:     bundle exec bundler-audit check --update
  erblint:       bundle exec erblint app/views/
  db_check:      bundle exec database_consistency
  test:          COVERAGE=1 PROSOPITE=1 bin/rails test
                 (SimpleCov min 80% + Prosopite raises on N+1)
```

### Local Gate Script

Create `bin/gate` for running the full suite locally between phases:

```bash
#!/usr/bin/env bash
set -e
echo "==> Brakeman"      && bin/brakeman --no-pager
echo "==> Gem audit"      && bundle exec bundler-audit check --update
echo "==> RuboCop"        && bundle exec rubocop
echo "==> ERB Lint"       && bundle exec erblint app/views/
echo "==> DB Consistency"  && bundle exec database_consistency
echo "==> Tests + N+1"    && COVERAGE=1 bin/rails test
echo "==> Performance"    && bin/rails test test/performance/
echo "==> All clear."
```

### Manual QA

1. Run `bin/gate` -- all checks pass
2. Review SimpleCov HTML report (`coverage/index.html`) -- branch coverage >= 80%
3. Review `undercover` report -- no untested changes in diff
4. Verify dashboard renders with test data after attribution scoping fix
5. Run `bin/perf` -- all performance budgets pass
6. Run k6 load tests against local server -- p95 within thresholds

---

## Definition of Done

- [ ] Full static analysis suite installed and passing (`bin/gate` exits 0)
- [ ] All three unscoped queries fixed and tested
- [ ] JSONB size validations added for Event, Session, Identity
- [ ] RuboCop extended config with `.rubocop_todo.yml` baseline (then burned down)
- [ ] `Attribution::CreditEnricher` extracted, both calculators refactored
- [ ] 6 undocumented code conventions codified in CLAUDE.md
- [ ] `frozen_string_literal: true` added to all Ruby files
- [ ] "Multibuzz" references removed from `lib/docs/`
- [ ] STYLE_GUIDE.md channel colors aligned with `chart_controller.js` (12 channels)
- [ ] CI pipeline expanded: bundler-audit, erblint, database_consistency, Prosopite in tests
- [ ] Lefthook pre-commit hooks installed and configured
- [ ] All tests pass with zero N+1 queries (Prosopite) and >= 80% coverage (SimpleCov)
- [ ] Query budgets locked for all 4 ingestion endpoints
- [ ] Performance test suite (`test/performance/`) with timing, memory, and scaling tests
- [ ] Load test scripts (`test/load/`) with k6 for ingestion and dashboard
- [ ] `bin/perf` script for local performance regression checks
- [ ] Performance baselines documented in `test/performance/BASELINES.md`
- [ ] Spec updated with final state

---

## Out of Scope

- Sorbet/Steep type checking (high adoption cost for existing Rails 8 codebase; not justified at current team size)
- Mutant mutation testing (computationally expensive, commercial license)
- Packwerk module boundaries (not justified at current team size)
- Semgrep/Bearer (Brakeman is sufficient for Rails-specific SAST; revisit when team scales)
- Trivy container scanning (add when deployment pipeline matures; tracked separately)
- `rubycritic` / `debride` / `flay` / `flog` (useful for periodic audits, not CI-gated)
- `license_finder` (add when third-party compliance requirements arise)
- Refactoring `Sessions::CreationService` (342 lines but well-organized; optional extraction in Phase 3.3)
- Refactoring `Account::Billing` concern (40 methods but all small; monitor, don't split yet)
- Implementing planned doc automation tools (link checker, SDK validator)
- Chart controller refactoring (color fix only, not a rewrite)
- `AML::Executor#eval` sandboxing (mitigated by `Security::ASTAnalyzer`; tracked separately)
- Production APM (New Relic, Datadog) -- valuable but orthogonal to test-time performance budgets
- Premature caching optimization -- measure first with performance tests, then cache where data justifies it
- Database query plan analysis automation -- manual `EXPLAIN ANALYZE` is sufficient at current scale

---

## Appendix A: Complete Tooling Inventory

### What We're Adding (Phase 1)

**Category: Security**

| Tool | Gem | CI Job | What It Catches | Config File |
|------|-----|--------|----------------|-------------|
| Brakeman | Already installed | `scan_ruby` | SQL injection, XSS, command injection, Rails-specific vulns | `.brakeman.yml` (optional) |
| bundler-audit | `bundler-audit` | `gem_audit` (new) | Known CVEs in gem dependencies via RubySec advisory DB | None (reads `Gemfile.lock`) |
| strong_migrations | `strong_migrations` | Raises in dev/test | Unsafe migrations: non-concurrent index adds, column defaults on large tables, removing columns without ignore | `config/initializers/strong_migrations.rb` |

**Category: Code Quality**

| Tool | Gem | CI Job | What It Catches | Config File |
|------|-----|--------|----------------|-------------|
| RuboCop (extended) | `rubocop-rails-omakase` + `rubocop-minitest` + `rubocop-thread_safety` | `lint` (existing) | Method/class length, complexity, guard clauses, frozen strings, thread safety, test assertions | `.rubocop.yml` + `.rubocop_todo.yml` |
| erb_lint | `erb_lint` | `erblint` (new) | ERB template issues: spacing, no JS tag helper, embedded Ruby style | `.erb-lint.yml` |
| Reek | `reek` | Local gate only | Code smells: Feature Envy, Data Clump, Too Many Statements, Nested Iterators | `.reek.yml` |

**Category: Database**

| Tool | Gem | CI Job | What It Catches | Config File |
|------|-----|--------|----------------|-------------|
| Prosopite | `prosopite` | Integrated in `test` job | N+1 queries at runtime (zero false positives) | `test_helper.rb` + `development.rb` |
| database_consistency | `database_consistency` | `db_check` (new) | Schema/validation mismatches, missing NOT NULL constraints, orphaned indexes | `.database_consistency.yml` |
| active_record_doctor | `active_record_doctor` | Local only (rake tasks) | Missing foreign key indexes, extraneous indexes, unindexed WHERE columns | None |

**Category: Test Quality**

| Tool | Gem | CI Job | What It Catches | Config File |
|------|-----|--------|----------------|-------------|
| SimpleCov | `simplecov` | Integrated in `test` job | Line + branch coverage gaps. Minimum 80% gate. | `test_helper.rb` |
| Undercover | `undercover` | PR checks (optional) | Changed code in PR lacking test coverage | None (reads SimpleCov + git diff) |

**Category: Performance**

| Tool | Gem / Install | CI Job | What It Catches | Config File |
|------|--------------|--------|----------------|-------------|
| benchmark-ips | `benchmark-ips` | Integrated in `perf` job | Throughput regressions in hot paths (iterations/second) | None |
| memory_profiler | `memory_profiler` | Integrated in `perf` job | Object allocation regressions per request | None |
| rack-mini-profiler | `rack-mini-profiler` | Dev only (not CI) | Per-request SQL count, timing, memory in browser | `development.rb` |
| stackprof | `stackprof` | Dev only (not CI) | CPU flamegraphs for identifying bottlenecks | None |
| k6 | `brew install k6` | Not CI-gated (manual) | Load testing: latency percentiles, throughput floor, error rates under load | `test/load/*.js` |

**Category: Developer Workflow**

| Tool | Install | What It Does | Config File |
|------|---------|-------------|-------------|
| Lefthook | `brew install lefthook` | Pre-commit: RuboCop on staged `.rb`, erblint on staged `.erb`, Brakeman quick scan | `lefthook.yml` |

### What We Evaluated and Rejected

| Tool | Why Not | Revisit When |
|------|---------|-------------|
| **Bullet** | Prosopite has zero false positives; Bullet has known accuracy issues | Never (Prosopite is strictly superior) |
| **Sorbet / Steep** | High adoption cost for existing Rails 8 codebase. Tapioca helps but still significant ongoing maintenance. | Team grows to 3+ or starting a new service from scratch |
| **Mutant** | Computationally expensive mutation testing. Commercial license required for non-OSS. | Critical payment/attribution paths only, if ever |
| **Semgrep / Bearer** | Supplementary SAST beyond Brakeman. Adds value for polyglot repos but mbuzz is Rails-only. | Adding non-Ruby services |
| **Trivy** | Container image vulnerability scanning. Valuable but orthogonal to code quality. | Hardening Kamal deployment pipeline (separate spec) |
| **rails_best_practices** | Poorly maintained, lags behind Rails 8 conventions. RuboCop + Reek cover the same ground. | Never |
| **Fasterer** | Micro-optimizations (e.g., `detect` vs `select.first`) that rarely impact a Rails app. | Never |
| **derailed_benchmarks** | Boot time and per-request memory profiling. mbuzz boots fine; `memory_profiler` is more targeted. | Never |
| **test-prof** | Advanced test profiling (FactoryProf, EventProf). Useful for slow test suites; mbuzz tests are fast with fixtures. | Test suite exceeds 5 minutes |
| **New Relic / Datadog APM** | Production APM. Valuable but orthogonal to test-time performance budgets. | Production traffic exceeds 1M req/day |
| **Dawnscanner** | Minimal maintenance, superseded by Brakeman. | Never |
| **license_finder** | Dependency license compliance. Not needed until enterprise/regulated customers. | Enterprise sales or SOC 2 audit |
| **Flay** | Structural duplication detection. Useful for audits but too noisy for CI gating. | Periodic audits (quarterly) |
| **Flog** | ABC complexity scoring. RuboCop Metrics cops cover the same ground. | Never (RuboCop is enough) |
| **RubyCritic** | Wraps Reek + Flay + Flog into HTML report. Good for dashboards, not CI gates. | Monthly quality reviews |
| **Debride** | Dead method detection. Useful but high false-positive rate with Rails metaprogramming. | Periodic audits (quarterly) |
| **Packwerk** | Module boundary enforcement. Overkill for current team/codebase size. | 3+ developers or 50+ models |

### Recommended `.rubocop.yml`

```yaml
inherit_gem: { rubocop-rails-omakase: rubocop.yml }

plugins:
  - rubocop-minitest
  - rubocop-thread_safety

Metrics/MethodLength:
  Enabled: true
  Max: 12
  CountAsOne: ['array', 'hash', 'heredoc', 'method_call']
  Exclude: ['db/migrate/**/*', 'test/**/*']

Metrics/ClassLength:
  Enabled: true
  Max: 150
  Exclude: ['db/migrate/**/*', 'test/**/*']

Metrics/AbcSize:
  Enabled: true
  Max: 20
  Exclude: ['db/migrate/**/*']

Metrics/CyclomaticComplexity:
  Enabled: true
  Max: 8

Metrics/PerceivedComplexity:
  Enabled: true
  Max: 8

Metrics/ParameterLists:
  Enabled: true
  Max: 4

Lint/UnusedMethodArgument:
  Enabled: true
  AllowUnusedKeywordArguments: true

Lint/UnusedBlockArgument:
  Enabled: true

Lint/DuplicateMethods:
  Enabled: true

Lint/ShadowingOuterLocalVariable:
  Enabled: true

Style/FrozenStringLiteralComment:
  Enabled: true
  EnforcedStyle: always

Style/GuardClause:
  Enabled: true

Rails/HasManyOrHasOneDependent:
  Enabled: true

Rails/UniqueValidationWithoutIndex:
  Enabled: true

ThreadSafety/InstanceVariableInClassMethod:
  Enabled: true

ThreadSafety/MutableClassInstanceVariable:
  Enabled: true
```

### Recommended `.reek.yml`

```yaml
detectors:
  TooManyStatements:
    max_statements: 8
    exclude: ['initialize']
  LongParameterList:
    max_params: 4
  FeatureEnvy:
    enabled: true
  NestedIterators:
    max_allowed_nesting: 2
  DataClump:
    enabled: true

exclude_paths:
  - test/
  - db/migrate/
  - config/
```

### Recommended `.erb-lint.yml`

```yaml
linters:
  SpaceAroundErbTag:
    enabled: true
  NoJavascriptTagHelper:
    enabled: true
  Rubocop:
    enabled: true
    rubocop_config:
      inherit_from: .rubocop.yml
```

### Recommended `lefthook.yml`

```yaml
pre-commit:
  parallel: true
  commands:
    rubocop:
      glob: "*.rb"
      run: bundle exec rubocop --force-exclusion {staged_files}
    erblint:
      glob: "*.erb"
      run: bundle exec erblint {staged_files}

pre-push:
  commands:
    brakeman:
      run: bin/brakeman --no-pager --quiet
    bundler-audit:
      run: bundle exec bundler-audit check --update
```

### Recommended `config/initializers/strong_migrations.rb`

```ruby
StrongMigrations.target_postgresql_version = "16"

StrongMigrations.disable_check(:add_index)  # TimescaleDB hypertable indexes need special handling
```

### Recommended Prosopite config (`test_helper.rb` addition)

```ruby
require "prosopite"

class ActiveSupport::TestCase
  setup do
    Prosopite.scan
  end

  teardown do
    Prosopite.finish
  end
end
```

### Recommended SimpleCov config (`test_helper.rb` addition)

```ruby
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "rails" do
    minimum_coverage 80
    minimum_coverage_by_file 50
    enable_coverage :branch

    add_group "Models", "app/models"
    add_group "Controllers", "app/controllers"
    add_group "Services", "app/services"
    add_group "Constants", "app/constants"
    add_group "Jobs", "app/jobs"

    add_filter "/test/"
    add_filter "/db/"
    add_filter "/config/"
  end
end
```

---

## Appendix B: CI Pipeline Configuration

### Updated `.github/workflows/ci.yml`

The existing pipeline has 4 jobs. After Phase 1, it expands to 7:

```yaml
# New jobs to add alongside existing scan_ruby, scan_js, lint, test:

gem_audit:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: ruby/setup-ruby@v1
      with: { bundler-cache: true }
    - run: bundle exec bundler-audit check --update

erblint:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: ruby/setup-ruby@v1
      with: { bundler-cache: true }
    - run: bundle exec erblint app/views/

db_check:
  runs-on: ubuntu-latest
  services:
    postgres:
      image: postgres:16
      env:
        POSTGRES_PASSWORD: postgres
      ports: ["5432:5432"]
  steps:
    - uses: actions/checkout@v4
    - uses: ruby/setup-ruby@v1
      with: { bundler-cache: true }
    - run: bin/rails db:schema:load
      env:
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/mbuzz_test
        RAILS_ENV: test
    - run: bundle exec database_consistency
      env:
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/mbuzz_test
        RAILS_ENV: test

# Update existing test job to include coverage + N+1 detection:
test:
  # ... existing setup ...
  env:
    COVERAGE: "1"
  # Prosopite is enabled automatically via test_helper.rb

# New: Performance tests (non-blocking)
perf:
  runs-on: ubuntu-latest
  continue-on-error: true
  services:
    postgres:
      image: postgres:16
      env:
        POSTGRES_PASSWORD: postgres
      ports: ["5432:5432"]
  steps:
    - uses: actions/checkout@v4
    - uses: ruby/setup-ruby@v1
      with: { bundler-cache: true }
    - run: bin/rails db:schema:load
      env:
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/mbuzz_test
        RAILS_ENV: test
    - run: bin/rails test test/performance/
      env:
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/mbuzz_test
        RAILS_ENV: test
```

---

## Appendix C: Performance Test Examples

### Query Budget Test

```ruby
# test/performance/sessions_performance_test.rb
class SessionsPerformanceTest < ActionDispatch::IntegrationTest
  test "session creation stays within query budget" do
    assert_queries(count: 12) do
      post api_v1_sessions_url,
        params: { session: valid_session_params },
        headers: auth_headers
    end
  end

  test "session creation does not scale queries with concurrent visitors" do
    queries_for_one = count_queries do
      post api_v1_sessions_url,
        params: { session: valid_session_params },
        headers: auth_headers
    end

    # Second call for different visitor should use same query count
    queries_for_two = count_queries do
      post api_v1_sessions_url,
        params: { session: valid_session_params.merge(visitor_id: SecureRandom.hex(32)) },
        headers: auth_headers
    end

    assert_equal queries_for_one, queries_for_two,
      "Query count should be constant regardless of visitor"
  end
end
```

### Timing Budget Test

```ruby
# test/performance/ingestion_timing_test.rb
class IngestionTimingTest < ActiveSupport::TestCase
  test "timing: session creation completes under 50ms" do
    5.times { create_session } # warmup

    elapsed = Benchmark.realtime do
      50.times { create_session }
    end

    avg_ms = (elapsed / 50) * 1000
    assert avg_ms < 50,
      "Session creation averaged #{avg_ms.round(1)}ms (budget: 50ms)"
  end

  test "timing: event batch scales sub-linearly" do
    time_1  = Benchmark.realtime { ingest_events(count: 1) }
    time_10 = Benchmark.realtime { ingest_events(count: 10) }

    ratio = time_10 / time_1
    assert ratio < 3.0,
      "10 events took #{ratio.round(1)}x single event (budget: 3x)"
  end
end
```

### Memory Budget Test

```ruby
# test/performance/ingestion_memory_test.rb
require "memory_profiler"

class IngestionMemoryTest < ActiveSupport::TestCase
  test "memory: session creation allocates bounded objects" do
    create_session # warmup

    report = MemoryProfiler.report { create_session }

    assert report.total_allocated < 500,
      "Session creation allocated #{report.total_allocated} objects (budget: 500)"
  end

  test "memory: event batch does not allocate linearly" do
    ingest_events(count: 1) # warmup

    report_1  = MemoryProfiler.report { ingest_events(count: 1) }
    report_10 = MemoryProfiler.report { ingest_events(count: 10) }

    ratio = report_10.total_allocated.to_f / report_1.total_allocated
    assert ratio < 5.0,
      "10 events allocated #{ratio.round(1)}x single event (budget: 5x)"
  end
end
```

### k6 Load Test

```javascript
// test/load/ingestion_load.js
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const API_KEY  = __ENV.API_KEY  || 'sk_test_replaceme';

const headers = {
  'Authorization': `Bearer ${API_KEY}`,
  'Content-Type': 'application/json',
};

export const options = {
  scenarios: {
    steady_state: {
      executor: 'constant-arrival-rate',
      rate: 100,
      timeUnit: '1s',
      duration: '60s',
      preAllocatedVUs: 50,
    },
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: 100,
      timeUnit: '1s',
      stages: [
        { duration: '10s', target: 500 },
        { duration: '30s', target: 500 },
        { duration: '10s', target: 100 },
      ],
      preAllocatedVUs: 200,
      startTime: '70s',
    },
  },
  thresholds: {
    http_req_duration: ['p95<100', 'p99<250'],
    http_req_failed: ['rate<0.01'],
  },
};

function randomHex(len) {
  let result = '';
  const chars = '0123456789abcdef';
  for (let i = 0; i < len; i++) {
    result += chars.charAt(Math.floor(Math.random() * 16));
  }
  return result;
}

export default function () {
  const visitorId = randomHex(64);

  // Session creation
  const sessionRes = http.post(`${BASE_URL}/api/v1/sessions`, JSON.stringify({
    session: {
      visitor_id: visitorId,
      session_id: randomHex(64),
      url: 'https://example.com/landing?utm_source=google&utm_medium=cpc',
    }
  }), { headers });

  check(sessionRes, {
    'session status is 202': (r) => r.status === 202,
  });

  sleep(0.1);

  // Event tracking
  const eventRes = http.post(`${BASE_URL}/api/v1/events`, JSON.stringify({
    events: [{
      event_type: 'page_view',
      visitor_id: visitorId,
      properties: { url: 'https://example.com/product/123' },
    }]
  }), { headers });

  check(eventRes, {
    'event status is 202': (r) => r.status === 202,
  });
}
```
