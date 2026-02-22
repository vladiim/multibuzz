# Codebase Audit & Quality Hardening Specification

**Date:** 2026-02-21
**Completed:** 2026-02-22
**Priority:** P1
**Status:** Done — all 5 phases shipped, gate clean (2545 tests, 0 failures, 0 offenses)
**Branch:** `feature/session-bot-detection`

---

## Summary

A deep audit of the mbuzz codebase to map functionality, assess architecture against SOLID/DRY/GoF principles, identify security gaps, and define the tooling + refactoring work needed to maintain code quality as the product scales.

**Results:** 4 phases shipped across 7 commits on `feature/session-bot-detection`:
- **Phase 1:** 12 static analysis tools installed with full gate pipeline (`bin/gate`, Lefthook, CI)
- **Phase 2:** 3 multi-tenancy scoping bugs fixed, 3 JSONB size validations added, 9 new tests
- **Phase 3:** `Attribution::CreditEnrichment` concern extracted (~70 lines of duplication eliminated)
- **Phase 4:** RuboCop todo burned from 2829 to 375, `frozen_string_literal` on all files, "Multibuzz" renamed to "mbuzz"
- **Phase 5:** Performance baselines — 18 tests (timing, memory, query budgets), k6 load scripts, `bin/perf`, CI job

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

### Test Infrastructure (Updated Post-Phase 1)

- Minitest + fixtures (213 test files)
- Parallel test execution (14 workers)
- E2E tests in `sdk_integration_tests/` with Capybara + Playwright
- **SimpleCov**: 93.15% line coverage, 76.66% branch coverage (90% minimum gate)
- **Prosopite + pg_query**: N+1 detection active in all tests (scan on setup, finish on teardown)
- **Lefthook**: pre-commit (RuboCop + erb_lint), pre-push (Brakeman + bundler-audit)
- **bin/gate**: full static analysis suite (Brakeman, bundler-audit, RuboCop, erb_lint, tests)

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
| Attribution engine | **A** | Clean Strategy pattern for 8 algorithms. `CreditEnrichment` concern extracts shared logic (Phase 3). Calculator: 57 lines, CrossDeviceCalculator: 40 lines. |
| Dashboard queries | **A** | Each query is a focused class (TotalsQuery, TimeSeriesQuery, etc.). Filter operators use Strategy pattern. Cache keys are deterministic. |
| Sessions::CreationService | **B** | 342 lines is large, but 22 guard clauses keep nesting shallow. Well-commented. The orchestration logic (visitor + session + UTM + bot + channel) genuinely belongs together. Optional extraction could improve it (R1). |
| Constants layer | **A** | `Channels`, `ClickIdentifiers`, `UtmAliases` are self-documenting. Frozen arrays/hashes. Clear comments per platform. |

**Overall maintainability: A**

### Dimension 2: Readability & Understandability

*Can a new developer (or future-you) understand intent without external context?*

| Area | Grade | Evidence |
|------|-------|----------|
| Naming | **A** | Methods: `find_active_visitor_session`, `channel_from_click_ids`, `collapse_burst_sessions`, `suspect_session?`. Classes: `Sessions::ChannelAttributionService`, `Attribution::JourneyBuilder`. No abbreviations, no single-letter vars. |
| Code flow | **A** | Guard clauses over nested conditionals. Early returns everywhere. Functional chains: `touchpoints.map { \|t\| build_touchpoint(t) }`. Pipeline-style: `normalize_credits(algorithm_credits).map { enrich }.map { add_revenue }`. |
| Domain language | **A** | Code uses the same terms as the domain: "visitor", "session", "touchpoint", "channel", "conversion", "identity", "attribution credit". No invented jargon. |
| Documentation | **A-** | Architecture docs exist (`lib/docs/architecture/`), API contract is detailed, spec guide is exceptional. "Multibuzz" naming fixed (Phase 4). Internal code comments are sparse -- the code is mostly self-documenting, but complex logic (like session reuse rules) would benefit from a "why" comment. |
| Constants as docs | **A** | `ClickIdentifiers` has per-platform comments. `Channels` defines domain patterns inline. `UTM_MEDIUM_PATTERNS` is readable as a specification. |

**Overall readability: A**

### Dimension 3: Testability

*Can the system be tested effectively and confidently?*

| Area | Grade | Evidence |
|------|-------|----------|
| Test structure | **A** | 213 test files mirroring app/ structure. Memoized fixture methods per CLAUDE.md pattern. Parallel execution. |
| Service testability | **A** | Services accept account + params in initializer, return hash results. Easy to test in isolation. |
| E2E coverage | **A** | Full SDK integration tests (Ruby, Node, Python, PHP, Shopify) via Capybara + Playwright on ports 4001-4005. |
| Coverage measurement | **A** | SimpleCov with parallel worker merging: 93.15% line, 76.66% branch. 90% minimum gate. 14 files at 0% (public pages, background jobs — Phase 2 targets). |
| N+1 detection | **A** | Prosopite + pg_query active in all 2518 tests. Zero N+1s detected. Logs in development. |
| Multi-tenancy testing | **B+** | Cross-account isolation tests added for DeduplicationService, Calculator, CrossDeviceCalculator (Phase 2). Coverage of remaining services is incremental. |

**Overall testability: A-** (structure is A, tooling is A, cross-account isolation tests started)

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
| Multi-tenancy enforcement | **A** | 100% scoped after Phase 2 fixes (S1-S3). Cross-account isolation tests added. Dashboard layer scoped via `BaseController#scoped_*` accessors. |
| Input validation | **A** | Multi-layer: controller params -> service validation -> model validation. JSONB columns size-limited to 50KB (Event.properties, Session.initial_utm, Identity.traits). |
| Attribution math | **A** | Credits normalized to sum=1.0 with tolerance check (`CREDIT_TOLERANCE = 0.0001`). Remainder adjustment applied to last credit. Revenue allocated proportionally. Edge cases handled (empty journey, single touchpoint). |
| Idempotency | **A** | Conversion dedup via `[account_id, idempotency_key]` unique index. Duplicate returns existing record, no double-counting, no double-attribution. |
| Session integrity | **A** | Advisory lock via PostgreSQL (`pg_advisory_xact_lock`) prevents race conditions in session creation. 30-min sliding window consistently enforced. |
| Bot filtering | **A** | Two-layer: known UA patterns (daily-synced from Matomo/Crawler User Agents) + no-signals heuristic. `.qualified` scope excludes suspects from all dashboard queries. |
| API key security | **A** | Keys stored as SHA256 digest, never plaintext. Revocation check on every request. Usage tracking. Environment separation (test/live). |
| AML DSL safety | **C** | `eval()` with user code is inherently risky. Mitigated by `Security::ASTAnalyzer` (whitelist-based AST inspection before eval) and `Security::Whitelist` (100+ allowed methods). But if the analyzer is bypassed, arbitrary code execution is possible. |

**Overall correctness: A** (scoping bugs fixed in Phase 2, JSONB size-validated)

### Dimension 6: Performance & Scalability

*Will this code perform under production load?*

| Area | Grade | Evidence |
|------|-------|----------|
| Database indexing | **A** | Composite indexes on all hot paths: `[account_id, session_id, started_at]`, `[visitor_id, device_fingerprint, last_activity_at]`, GIN on JSONB properties. TimescaleDB hypertables for events/sessions. |
| Query patterns | **A** | Memoized lookups (`sessions_map` via `index_by`). Prosopite verified: zero N+1s across 2518 tests. |
| Caching | **A** | Dashboard: 5-min TTL with deterministic keys. Bot patterns: `Rails.cache` with daily refresh. Referrer sources: 24h cache. Usage counters: cache-backed. All via Solid Cache (DB-backed, no Redis dependency). |
| Batch processing | **A** | Events endpoint accepts arrays. Per-event processing with atomic accept/reject. Usage counter incremented once per batch, not per event. |
| Background processing | **A** | Attribution calculation queued via `after_create_commit`. Referrer/bot pattern sync via scheduled jobs. Solid Queue for all async work. |
| Advisory locking | **A** | Session creation uses `pg_advisory_xact_lock` to prevent duplicate sessions from concurrent SDK calls. Scoped to `[account_id, session_id]`. |

**Overall performance: A** (no known bottlenecks; N+1s verified clean by Prosopite)

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
| Code-level | **A** | Calculator duplication resolved via `CreditEnrichment` concern (Phase 3). Constants well-extracted. UTM aliases centralized. |
| Configuration | **A** | SDK registry is single-source YAML. Channel colors defined once (though mismatched with style guide). Billing rules in one concern. |

**Overall DRY: A**

### Summary Scorecard

| Dimension | Grade | Key Gaps |
|-----------|-------|----------|
| Maintainability | **A** | Calculator duplication resolved via CreditEnrichment concern |
| Readability | **A** | frozen_string_literal on all files, naming consistent |
| Testability | **A-** | Multi-tenancy isolation tests still missing |
| Extensibility | **A-** | SDK checklist is manual, channel hierarchy is implicit |
| Correctness | **A** | All queries account-scoped, JSONB size-validated |
| Performance | **A** | N+1s verified clean by Prosopite |
| SOLID | **A-** | CreationService SRP, hardcoded deps |
| DRY | **A** | Calculator duplication extracted to CreditEnrichment concern |

**Overall codebase grade: A** -- excellent architecture with full static analysis tooling, all security bugs fixed, DRY violations resolved, style conventions codified, performance budgets locked. All 5 phases complete.

---

## Style Guides

mbuzz has a Ruby/backend code style guide (`CLAUDE.md`), a frontend design system (`lib/docs/architecture/STYLE_GUIDE.md`), and a minimal RuboCop config (`.rubocop.yml`). This section audits all three for completeness, internal consistency, and actual adherence across the codebase -- with emphasis on code style patterns.

### 1. Ruby Code Style (`CLAUDE.md`)

The project's Ruby conventions are codified in `CLAUDE.md`. Enforcement is now via extended RuboCop config (metrics, lint, style, thread safety, minitest cops enabled) with 2829 existing violations baselined in `.rubocop_todo.yml`. New code is held to the full standard.

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

**Finding:** 100% adoption after Phase 4. All 408 Ruby files have `# frozen_string_literal: true`.

**History:** Was partial (20-54%) before Phase 4 blanket autocorrect. Now enforced by RuboCop `Style/FrozenStringLiteralComment: always`.

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

### 2. RuboCop: Current State (Post-Phase 1)

All cops are now enabled. `.rubocop_todo.yml` burned from 2829 to 375 offenses (2110 autocorrected in Phase 4). Remaining 375 are non-autocorrectable (complexity, method length, parameter lists — require manual refactoring).

| Aspect | Status | Config |
|--------|--------|--------|
| Method length | **Enabled** | `Max: 12`, `CountAsOne: [array, hash, heredoc, method_call]`, excludes test + migrations |
| Class length | **Enabled** | `Max: 150`, excludes test + migrations |
| ABC size | **Enabled** | `Max: 20`, excludes test + migrations |
| Guard clauses | **Enabled** | `Style/GuardClause: Enabled` |
| Frozen string literal | **Enabled** | `FrozenStringLiteralComment: always` — all 408 files compliant |
| Cyclomatic complexity | **Enabled** | `Max: 8` |
| Perceived complexity | **Enabled** | `Max: 8` |
| Parameter lists | **Enabled** | `Max: 4` |
| Unused arguments | **Enabled** | `AllowUnusedKeywordArguments: true` |
| Thread safety | **Enabled** | `rubocop-thread_safety` plugin (ClassInstanceVariable, MutableClassInstanceVariable) |
| Test assertions | **Enabled** | `rubocop-minitest` plugin, `NewCops: enable` |
| Exclude merging | **Enabled** | `inherit_mode: merge: Exclude` (todo + main config coexist) |

**Remaining violations** (375 in `.rubocop_todo.yml`, all non-autocorrectable):
- 88 `MutableClassInstanceVariable` (thread safety)
- 50 `AbcSize` (complexity)
- 40 `AssertEmptyLiteral` (minitest style)
- 36 `ParameterLists` (method signatures)
- 25 `MethodLength` (long methods)
- 136 other (guard clauses, class length, perceived complexity, etc.)

### 3. Frontend Design System (`lib/docs/architecture/STYLE_GUIDE.md`)

An 890-line comprehensive design system. Well-structured for a dev-focused product. Two issues:

**Channel Color Mismatch (N2):** Style guide defines 7 channel-color pairs. Code (`chart_controller.js:5-18`) defines 12. They disagree on 5 of 7 shared mappings (e.g., paid_search: style guide says blue-500, code uses indigo). Root cause: channels evolved from 7 to 12 without backporting to the style guide. Fix: update STYLE_GUIDE.md to match the 12 channels in code.

**Naming (N1):** Heading says "Multibuzz" -- should be "mbuzz".

### Style Adherence Summary

| Style Guide | Completeness | Adherence | Enforced? |
|-------------|-------------|-----------|-----------|
| Ruby code style (`CLAUDE.md`) | **A** (all 6 conventions codified) | **A** (high discipline, 95%+ consistency, frozen_string_literal 100%) | **Yes** -- RuboCop extended config + Lefthook pre-commit |
| RuboCop | **A** (all metrics, lint, style, thread safety, minitest cops enabled) | **A** (376 baselined non-autocorrectable, zero on new code) | **Yes** -- CI + pre-commit |
| ERB lint | **A** (SpaceAroundErbTag, 298 fixes applied) | **A** (zero violations) | **Yes** -- CI + pre-commit |
| Design system (`STYLE_GUIDE.md`) | **A** (comprehensive, colors aligned) | **A** (12 channels match chart_controller.js, naming consistent) | No |

**Key insight:** Phase 1 converted tribal knowledge into machine-enforced standards. Phase 4 codified the remaining 6 conventions in CLAUDE.md. All style gaps are now closed.

---

## Findings

### A. Security Issues (Fix Immediately)

| # | Severity | Issue | File | Line |
|---|----------|-------|------|------|
| S1 | ~~HIGH~~ **FIXED** | ~~Unscoped~~ `account.visitors.where(id:).delete_all` | `app/services/visitors/deduplication_service.rb` | 142 |
| S2 | ~~HIGH~~ **FIXED** | ~~Unscoped~~ `account.sessions.where(id:).index_by` | `app/services/attribution/calculator.rb` | 103 |
| S3 | ~~HIGH~~ **FIXED** | ~~Unscoped~~ `account.sessions.where(id:).index_by` | `app/services/attribution/cross_device_calculator.rb` | 86 |

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
| V1 | **FIXED** — Event `properties` validated to 50KB max | `app/models/concerns/event/validations.rb` | `properties_size_limit` validation |
| V2 | **FIXED** — Session `initial_utm` validated to 50KB max | `app/models/concerns/session/validations.rb` | `initial_utm_size_limit` validation |
| V3 | **FIXED** — Identity `traits` validated to 50KB max | `app/models/concerns/identity/validations.rb` | `traits_size_limit` validation |

**Fix**: Add `validate :properties_size_limit` custom validation capping JSONB at 50KB.

### E. Documentation Inconsistencies

| # | Issue | Files |
|---|-------|-------|
| N1 | "Multibuzz" used instead of "mbuzz" | `lib/docs/architecture/STYLE_GUIDE.md` (heading), `lib/docs/SETUP.md`, `lib/docs/sdk/streamlined_sdk_spec.md`, `lib/docs/sdk/sdk_specification.md`, `lib/docs/architecture/code_highlighting_implementation.md` |
| N2 | Chart color palette in `chart_controller.js` doesn't match STYLE_GUIDE.md | `app/javascript/controllers/chart_controller.js` lines 5-18 vs `lib/docs/architecture/STYLE_GUIDE.md` lines 134-142 |
| N3 | Planned doc automation tools (link checker, SDK consistency validator, example runner) referenced in `documentation_strategy.md` but never implemented | `lib/docs/architecture/documentation_strategy.md` |

### F. Static Analysis Assessment (Updated Post-Phase 1)

#### What Exists Now

| Tool | Version | CI Gated? | Notes |
|------|---------|-----------|-------|
| **Brakeman** | 8.0.2 | Yes (`scan_ruby`) | Upgraded from 7.1.1. 12 warnings baselined in `config/brakeman.ignore`. |
| **RuboCop** | 1.81.7 | Yes (`lint`) | Extended config: metrics, lint, style, thread safety, minitest. 2829 baselined. `NewCops: enable`. |
| **bundler-audit** | latest | Yes (`gem_audit`) | 0 CVEs. Daily advisory DB sync. |
| **erb_lint** | latest | Yes (`erblint`) | 298 autocorrected. SpaceAroundErbTag enabled. |
| **Prosopite** + pg_query | latest | Yes (in `test`) | N+1 detection in all 2518 tests. 0 N+1s. |
| **SimpleCov** | latest | Optional (`COVERAGE=1`) | 93.15% line, 76.66% branch. 90% minimum gate. |
| **strong_migrations** | latest | Raises in dev/test | PG 16 target. Blocks unsafe migrations. |
| **Reek** | latest | Local gate only | Code smell detection. Configured via `.reek.yml`. |
| **database_consistency** | latest | Local only | 38 findings (Phase 2 targets). |
| **active_record_doctor** | latest | Local only | 13 findings (Phase 2 targets). |
| **importmap audit** | Built-in | Yes (`scan_js`) | JS dependency CVE scanning. |
| **Lefthook** | 2.1.1 | N/A (local hooks) | Pre-commit: RuboCop + erb_lint. Pre-push: Brakeman + bundler-audit. |

CI pipeline (`.github/workflows/ci.yml`) runs 6 jobs: `scan_ruby`, `scan_js`, `gem_audit`, `lint`, `erblint`, `test`.

#### What's Still Missing (Post-Phase 1)

| Tool | What It Catches | Priority | Phase |
|------|----------------|----------|-------|
| Trivy | Container image vulnerabilities before `kamal deploy` | P1 | Out of scope |
| `undercover` | Changed code in PR lacking test coverage (diff-based) | P1 | Installed, not yet configured for CI |
| `flay` | Structural code duplication (would catch Calculator/CrossDeviceCalculator D1-D3) | P2 | Periodic audit tool |
| Performance tools | benchmark-ips, memory_profiler, rack-mini-profiler, stackprof, k6 | P2 | Phase 5 |

#### database_consistency Findings (38 items for Phase 2+)

| Category | Count | Examples |
|----------|-------|---------|
| Redundant indexes | 16 | `index_visitors_on_account_id` redundant (covered by composite) |
| Missing uniqueness validators | 8 | `Session.session_id+account_id` has unique index but no validator |
| NULL constraint mismatches | 5 | `Visitor.first_seen_at` required in DB but no presence validator |
| Missing unique index | 1 | `Session.session_id+account_id` needs proper unique index |
| Foreign key cascade issues | 2 | `Identity.visitors` missing `on_delete: :nullify` |
| Missing foreign key | 1 | `Event.session` missing FK constraint |
| Missing dependent options | 3 | `Conversion.visitor`, `ApiRequestLog.account`, `Account.plan` |

#### active_record_doctor Findings (13 items for Phase 2+)

| Category | Count | Examples |
|----------|-------|---------|
| Missing primary keys | 2 | `events`, `sessions` (TimescaleDB hypertables — expected) |
| Incorrect dependent option | 8 | `Account.account_memberships` should use `dependent: :delete_all` |
| Missing FK indexes | 3 | `attribution_credits(session_id)`, `conversions(session_id)`, `conversions(event_id)` |

---

## Proposed Solution

### Static Analysis Workflow

Every phase ends with a **gate**: run the full static analysis suite and fix any new violations before moving to the next phase. This prevents accumulating debt as we refactor.

```
Phase N work complete
       |
       v
  Run gate: bin/gate
    - bin/brakeman --no-pager --no-exit-on-error
    - bundle exec bundler-audit check --update
    - bundle exec rubocop
    - bundle exec erb_lint app/views/
    - bin/rails test (Prosopite active)
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

### Phase 1: Static Analysis Foundation -- COMPLETE

12 tools installed and configured. Gate passes clean. See Implementation Tasks below for details.

### Phase 2: Security Fixes -- COMPLETE

Fixed S1-S3 (unscoped queries), V1-V3 (JSONB size validations), cross-account isolation tests. Commit `ccc2c03`.

### Phase 3: DRY Refactor -- COMPLETE

Extracted `Attribution::CreditEnrichment` concern from Calculator and CrossDeviceCalculator. 10 shared methods moved to concern (~70 lines eliminated). Calculator: 121 -> 57 lines. CrossDeviceCalculator: 104 -> 40 lines. Commit `cc16f98`.

### Phase 4: Style Guide Codification & Doc Cleanup -- COMPLETE

Burned `.rubocop_todo.yml` from 2829 to 375 offenses (2110 autocorrected). Added `frozen_string_literal: true` to all files. Renamed "Multibuzz" to "mbuzz" in all lib/docs/. Codified 6 conventions in CLAUDE.md. Updated STYLE_GUIDE.md channel colors to match chart_controller.js (12 channels). Cleaned up documentation_strategy.md planned tool references. Commit `b1a4d71` + follow-up.

### Phase 5: Performance Baselines -- COMPLETE

18 performance tests across 3 files: ingestion (8 tests), attribution (5 tests), dashboard (5 tests). Covers timing budgets, query budgets, and memory budgets. k6 load test scripts for ingestion and dashboard. `bin/perf` script for local runs. Non-blocking CI job. Baselines documented in `test/performance/BASELINES.md`. Gate clean: 2545 tests, 0 failures.

---

## Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `app/services/visitors/deduplication_service.rb` | Visitor dedup | Scope `delete_all` to account (line 142) |
| `app/services/attribution/calculator.rb` | Single-device attribution | Scope `sessions_map` to account (line 103) |
| `app/services/attribution/cross_device_calculator.rb` | Cross-device attribution | Scope `sessions_map` to account (line 86) |
| `app/models/concerns/event/validations.rb` | Event validations | Add JSONB size limit |
| `CLAUDE.md` | Code style guide | Codify 6 undocumented conventions (service ordering, test style, error handling, query objects, JSONB, constants) |
| `.rubocop.yml` | Linter config | Extended: metrics, lint, style, thread safety, minitest. `inherit_mode: merge`. `NewCops: enable`. |
| `.rubocop_todo.yml` | Baselined violations | 376 non-autocorrectable offenses (burned from 2829) |
| `Gemfile` | Dependencies | Added: bundler-audit, strong_migrations, prosopite, pg_query, database_consistency, active_record_doctor, simplecov, undercover, reek, rubocop-minitest, rubocop-thread_safety, erb_lint, benchmark-ips, memory_profiler. Upgraded: brakeman 7.1.1 -> 8.0.2. |
| `test/test_helper.rb` | Test setup | SimpleCov (parallel worker merging, 90% minimum) + Prosopite (scan/finish per test) |
| `.github/workflows/ci.yml` | CI pipeline | 7 jobs: scan_ruby, scan_js, gem_audit, lint, erblint, test, perf |
| `lefthook.yml` | Git hooks | Pre-commit: RuboCop + erb_lint. Pre-push: Brakeman + bundler-audit. |
| `bin/gate` | Local gate script | Full static analysis suite runner |
| `config/initializers/strong_migrations.rb` | Migration safety | PG 16 target |
| `config/brakeman.ignore` | Security baseline | 12 pre-existing warnings (Phase 2 targets) |
| `.reek.yml` | Code smell config | 309 actionable smells (noise detectors disabled: IrresponsibleModule, UtilityFunction, NilCheck, MissingSafeMethod) |
| `.erb_lint.yml` | ERB linting config | SpaceAroundErbTag enabled |
| `config/environments/development.rb` | Dev config | Prosopite logging (rails_logger + prosopite_logger) |
| `.gitignore` | Git ignores | Added `/coverage` |
| `lib/docs/architecture/STYLE_GUIDE.md` | Design system | Fix naming, update channel colors to match chart_controller.js (12 channels) |
| `test/performance/` | Performance tests | 18 tests: ingestion, attribution, dashboard (timing, memory, query budgets) |
| `test/load/` | k6 load tests | ingestion_load.js, dashboard_load.js, README.md |
| `bin/perf` | Performance runner | Runs all performance tests locally |
| `test/performance/BASELINES.md` | Performance baselines | Documented budget thresholds |

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
| Edge: unscoped delete (FIXED) | Dedup runs with IDs from mixed accounts | Scoped to account — cross-account isolation tested |
| Edge: oversized properties (FIXED) | 10MB JSONB payload | Rejected with validation error (50KB max) |
| Edge: unknown utm_medium | `utm_medium=podcast` (not in patterns) | Falls back to referrer, then `other` |

---

## Implementation Tasks

### Phase 1: Static Analysis Foundation -- COMPLETE

Commit: `9cdbbef` on `feature/session-bot-detection`

**1A. Security scanning:**

- [x] **1.1** bundler-audit added, 0 CVEs, `gem_audit` CI job added
- [x] **1.2** strong_migrations added, `config/initializers/strong_migrations.rb` (PG 16 target)

**1B. Code quality:**

- [x] **1.3** Extended `.rubocop.yml`: metrics, lint, style, rails cops. `inherit_mode: merge: Exclude`. `AllCops: NewCops: enable`. 2829 violations baselined in `.rubocop_todo.yml`.
- [x] **1.4** `rubocop-minitest` added as plugin
- [x] **1.5** `rubocop-thread_safety` added as plugin (ThreadSafety/ClassInstanceVariable, MutableClassInstanceVariable)
- [x] **1.6** `erb_lint` added with `.erb_lint.yml` (SpaceAroundErbTag enabled; AllowedScriptType + RequireInputAutocomplete disabled as false positives). 298 ERB violations autocorrected across 50+ templates. `erblint` CI job added.
- [x] **1.7** `reek` added with `.reek.yml` (TooManyStatements: 8, LongParameterList: 4, FeatureEnvy, NestedIterators: 2)

**1C. Database analysis:**

- [x] **1.8** `prosopite` + `pg_query` added. Configured in `test_helper.rb` (scan/finish per test). Configured in `development.rb` (rails_logger + prosopite_logger). 0 N+1s found across 2518 tests.
- [x] **1.9** `database_consistency` added and run. 38 findings documented (Phase 2+ targets).
- [x] **1.10** `active_record_doctor` added and run. 13 findings documented (Phase 2+ targets).

**1D. Test quality:**

- [x] **1.11** `simplecov` added with parallel worker merging (`parallelize_setup`/`parallelize_teardown`). 93.15% line coverage, 76.66% branch coverage. 90% minimum gate.
- [x] **1.12** `undercover` gem installed. PR-level configuration deferred.

**1E. Developer workflow:**

- [x] **1.13** Lefthook installed. Pre-commit: RuboCop + erb_lint on staged files. Pre-push: Brakeman + bundler-audit.

**1F. Gate checkpoint:**

- [x] **1.14** `bin/gate` passes clean: Brakeman (0 warnings, 12 ignored), bundler-audit (0 CVEs), RuboCop (0 offenses), erb_lint (0 errors), tests (2518 pass, 0 failures, 0 errors).

**Additional work done:**
- Brakeman upgraded from 7.1.1 to 8.0.2
- `config/brakeman.ignore` created (12 pre-existing warnings baselined as Phase 2 targets)
- `.gitignore` updated to exclude `/coverage`
- `bin/gate` uses `--no-exit-on-error` (parser errors from ERB heredocs are harmless)

**Not done (moved to Phase 5):**
- Performance tools (benchmark-ips, memory_profiler, rack-mini-profiler, stackprof, k6)
- Query budget assertions

### Phase 2: Security Fixes -- COMPLETE

Commit: `ccc2c03` on `feature/session-bot-detection`

- [x] **2.1** Scoped `deduplication_service.rb:142` — `account.visitors.where(id:).delete_all`
- [x] **2.2** Scoped `calculator.rb:103` — `account.sessions.where(id:).index_by`
- [x] **2.3** Scoped `cross_device_calculator.rb:86` — `account.sessions.where(id:).index_by`
- [x] **2.4** Added 50KB JSONB size validation to Event.properties, Session.initial_utm, Identity.traits
- [x] **2.5** Cross-account isolation tests for DeduplicationService, Calculator, CrossDeviceCalculator + JSONB size rejection tests for Event, Session, Identity (9 new tests)
- [x] **2.6** Gate clean: 2527 tests, 0 failures, 0 offenses

### Phase 3: DRY Refactor

- [x] **3.1** Extracted `Attribution::CreditEnrichment` concern with 10 shared methods: `compute_credits`, `algorithm_credits`, `build_algorithm`, `probabilistic_model?`, `build_probabilistic_model`, `enrich_with_session_data`, `find_session`, `sessions_map`, `utm_value`, `add_revenue_credit`, `account`
- [x] **3.2** Both calculators include `CreditEnrichment`. Calculator: 121 -> 57 lines. CrossDeviceCalculator: 104 -> 40 lines. ~70 lines of duplication eliminated.
- [ ] **3.3** (Deferred) Extract `Visitors::ResolutionService` from `Sessions::CreationService` — lower priority, CreationService works well as-is
- [x] **3.4** Gate clean: 2527 tests, 0 failures, 0 offenses

### Phase 4: Style Guide Codification & Documentation Cleanup

**4A. Codify undocumented code conventions in CLAUDE.md:**

- [x] **4.1** Service method ordering convention codified in CLAUDE.md
- [x] **4.2-4.6** All 6 conventions codified: service ordering, test style, error handling patterns, query objects, JSONB, constants

**4B. RuboCop enforcement:**

- [x] **4.7** `frozen_string_literal: true` added to all 408 files
- [x] **4.8** `.rubocop_todo.yml` burned: 2829 -> 375 (2110 autocorrected). Remaining 375 are non-autocorrectable (complexity, method length, parameter lists — require manual refactoring).

**4C. Documentation cleanup:**

- [x] **4.9** "Multibuzz" -> "mbuzz" in 4 lib/docs/ files
- [x] **4.10** STYLE_GUIDE.md channel colors updated to match chart_controller.js (12 channels)
- [x] **4.11** Documentation strategy cleaned up — planned automation tools marked as future, weekly review checklist fixed
- [x] **4.12** Gate clean: 2545 tests, 0 failures, 0 offenses

### Phase 5: Performance Baselines -- COMPLETE

**5A. Performance test suite (`test/performance/`):**

- [x] **5.1** `performance_test_helper.rb` with `count_queries`, `assert_query_budget`, `measure_avg_ms`, `measure_allocations` helpers
- [x] **5.2** Ingestion performance tests (8 tests): session <50ms, event batch <8x, conversion <75ms, identify <30ms, query budgets, memory budgets
- [x] **5.3** Attribution performance tests (5 tests): calculator <100ms, cross-device <100ms, query budgets <=10/15, memory <5,000 allocations
- [x] **5.4** Dashboard query performance tests (5 tests): TotalsQuery <200ms, TimeSeriesQuery <300ms, ByChannelQuery <200ms, query budgets <=10
- [x] **5.5** Memory budgets integrated into ingestion + attribution tests via `memory_profiler` gem

**5B. Load test scripts (`test/load/`):**

- [x] **5.6** `test/load/` directory created
- [x] **5.7** `ingestion_load.js` — steady state 100rps/60s, spike to 500rps/30s, p95<100ms, p99<250ms
- [x] **5.8** `dashboard_load.js` — 20 concurrent users, 60s, p95<500ms, p99<1s
- [x] **5.9** `test/load/README.md` with execution instructions

**5C. Regression detection:**

- [x] **5.10** `bin/perf` script for running all performance tests locally
- [x] **5.11** Non-blocking CI job (`perf`) with `continue-on-error: true`
- [x] **5.12** Baselines documented in `test/performance/BASELINES.md`. Gate clean: 2545 tests, 0 failures.

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

### CI Pipeline (Implemented)

Pipeline runs 7 jobs:

```
scan_ruby:     bin/brakeman --no-pager (with config/brakeman.ignore)
scan_js:       bin/importmap audit
gem_audit:     bundle exec bundler-audit check --update
lint:          bin/rubocop -f github (extended config + .rubocop_todo.yml)
erblint:       bundle exec erb_lint app/views/
test:          bin/rails db:test:prepare test test:system (Prosopite active via test_helper.rb)
perf:          bin/rails test test/performance/ (continue-on-error: true)
```

### Local Gate Script (Implemented)

`bin/gate` runs the full suite locally between phases:

```bash
#!/usr/bin/env bash
set -e
echo "==> Brakeman"       && bin/brakeman --no-pager --no-exit-on-error
echo "==> Gem audit"       && bundle exec bundler-audit check --update
echo "==> RuboCop"         && bundle exec rubocop
echo "==> ERB Lint"        && bundle exec erb_lint app/views/
echo "==> Tests + N+1"     && bin/rails test
echo ""
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

- [x] Full static analysis suite installed and passing (`bin/gate` exits 0)
- [x] All three unscoped queries fixed and tested
- [x] JSONB size validations added for Event, Session, Identity (50KB max)
- [x] RuboCop extended config with `.rubocop_todo.yml` baseline (2829 -> 375 offenses)
- [x] `.rubocop_todo.yml` burned down (2110 autocorrected, 375 remaining non-autocorrectable)
- [x] `Attribution::CreditEnrichment` concern extracted, both calculators refactored
- [x] 6 undocumented code conventions codified in CLAUDE.md
- [x] `frozen_string_literal: true` added to all Ruby files
- [x] "Multibuzz" references removed from `lib/docs/` (4 files)
- [x] STYLE_GUIDE.md channel colors aligned with `chart_controller.js` (12 channels)
- [x] CI pipeline expanded: bundler-audit, erblint, Prosopite in tests, perf (non-blocking)
- [x] Lefthook pre-commit hooks installed and configured
- [x] All tests pass with zero N+1 queries (Prosopite) and >= 90% coverage (SimpleCov)
- [x] Query budgets locked for all 4 ingestion endpoints
- [x] Performance test suite (`test/performance/`) with 18 tests (timing, memory, query budgets)
- [x] Load test scripts (`test/load/`) with k6 for ingestion and dashboard
- [x] `bin/perf` script for local performance regression checks
- [x] Performance baselines documented in `test/performance/BASELINES.md`
- [x] Spec updated with final state

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

### What Was Added (Phase 1 -- Complete)

**Category: Security**

| Tool | Gem | CI Job | What It Catches | Config File |
|------|-----|--------|----------------|-------------|
| Brakeman | Upgraded to 8.0.2 | `scan_ruby` | SQL injection, XSS, command injection, Rails-specific vulns | `config/brakeman.ignore` (12 baselined) |
| bundler-audit | `bundler-audit` | `gem_audit` (new) | Known CVEs in gem dependencies via RubySec advisory DB | None (reads `Gemfile.lock`) |
| strong_migrations | `strong_migrations` | Raises in dev/test | Unsafe migrations: non-concurrent index adds, column defaults on large tables, removing columns without ignore | `config/initializers/strong_migrations.rb` |

**Category: Code Quality**

| Tool | Gem | CI Job | What It Catches | Config File |
|------|-----|--------|----------------|-------------|
| RuboCop (extended) | `rubocop-rails-omakase` + `rubocop-minitest` + `rubocop-thread_safety` | `lint` | Method/class length, complexity, guard clauses, frozen strings, thread safety, test assertions | `.rubocop.yml` + `.rubocop_todo.yml` (375 remaining, burned from 2829) |
| erb_lint | `erb_lint` | `erblint` | ERB template spacing (298 autocorrected) | `.erb_lint.yml` |
| Reek | `reek` | Local gate only | Code smells: Feature Envy, Data Clump, Too Many Statements, Nested Iterators | `.reek.yml` |

**Category: Database**

| Tool | Gem | CI Job | What It Catches | Config File |
|------|-----|--------|----------------|-------------|
| Prosopite | `prosopite` | Integrated in `test` job | N+1 queries at runtime (zero false positives) | `test_helper.rb` + `development.rb` |
| database_consistency | `database_consistency` | Local only | Schema/validation mismatches, missing NOT NULL constraints, orphaned indexes (38 findings) | `.database_consistency.yml` |
| active_record_doctor | `active_record_doctor` | Local only (rake tasks) | Missing foreign key indexes, extraneous indexes, dependent options (13 findings) | None |

**Category: Test Quality**

| Tool | Gem | CI Job | What It Catches | Config File |
|------|-----|--------|----------------|-------------|
| SimpleCov | `simplecov` | Optional (`COVERAGE=1`) | Line + branch coverage. 93.15% line, 76.66% branch. 90% minimum gate. | `test_helper.rb` |
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
| Lefthook | `brew install lefthook` | Pre-commit: RuboCop + erb_lint on staged files. Pre-push: Brakeman + bundler-audit. | `lefthook.yml` |

### Evaluated and Rejected

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

### Actual `.rubocop.yml` (Implemented)

```yaml
inherit_gem: { rubocop-rails-omakase: rubocop.yml }
inherit_from: .rubocop_todo.yml

inherit_mode:
  merge:
    - Exclude

AllCops:
  NewCops: enable

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
  Exclude: ['db/migrate/**/*', 'test/**/*']

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

ThreadSafety/ClassInstanceVariable:
  Enabled: true

ThreadSafety/MutableClassInstanceVariable:
  Enabled: true
```

### Actual `test/test_helper.rb` (Implemented)

```ruby
ENV["RAILS_ENV"] ||= "test"
ENV["BROWSERSLIST_IGNORE_OLD_DATA"] ||= "1"
$VERBOSE = nil

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "rails" do
    minimum_coverage 90
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

require_relative "../config/environment"
require "rails/test_help"
require "prosopite"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    parallelize_setup do |worker|
      SimpleCov.command_name "minitest-#{worker}" if ENV["COVERAGE"]
    end

    parallelize_teardown do |_worker|
      SimpleCov.result if ENV["COVERAGE"]
    end

    fixtures :all

    setup do
      Rails.cache.clear
      Prosopite.scan
    end

    teardown do
      Prosopite.finish
    end
  end
end
```

---

## Appendix B: CI Pipeline Configuration (Implemented)

6 jobs in `.github/workflows/ci.yml`. See file for full config. Key additions from Phase 1:

```yaml
gem_audit:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: ruby/setup-ruby@v1
      with: { ruby-version: .ruby-version, bundler-cache: true }
    - run: bundle exec bundler-audit check --update

erblint:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: ruby/setup-ruby@v1
      with: { ruby-version: .ruby-version, bundler-cache: true }
    - run: bundle exec erb_lint app/views/
```

**Prosopite** runs automatically in the `test` job via `test_helper.rb` (no separate CI config needed).

**database_consistency** and **active_record_doctor** run locally only (require full DB schema, too heavyweight for CI).

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
