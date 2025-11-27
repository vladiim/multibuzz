# Multi-Touch Attribution Methodology

**Status**: Design Standard - MUST follow for all attribution features
**Last Updated**: 2025-11-27
**Research Sources**: GA4, Amplitude, Mixpanel, Adobe Analytics, Google Research (2024)

---

## Purpose

This document defines the canonical approach for multi-touch attribution in mbuzz, based on academic research and industry best practices from leading analytics platforms.

**Key principle**: Attribution credits **sessions** (touchpoints), not individual events.

---

## 1. Core Concepts

### 1.1 Touchpoint

**Definition**: A single channel interaction within a session.

**Rules**:
- One touchpoint per channel per session
- Multiple sessions with same channel = multiple touchpoints
- Touchpoints are ordered by session start time

**Example**:
```
Session 1 (Day 1, Google Organic):
  - page_view
  - add_to_cart
  - page_view
  → ONE touchpoint: Google Organic

Session 2 (Day 3, Facebook Ad):
  - page_view
  - checkout_started
  → ONE touchpoint: Facebook Ad

Session 3 (Day 5, Google Organic):
  - purchase [CONVERSION]
  → ONE touchpoint: Google Organic

Total Journey: 3 touchpoints [Google Organic, Facebook Ad, Google Organic]
```

### 1.2 Journey

**Definition**: Ordered sequence of touchpoints leading to a conversion, within the lookback window.

**Components**:
- **Touchpoints**: Array of sessions with channel attribution
- **Conversion event**: Final business outcome
- **Lookback window**: Time period considered (default 30 days)

**Journey construction**:
1. Identify conversion event
2. Query all sessions for visitor within lookback window before conversion
3. Order sessions by started_at (ascending)
4. Deduplicate: one touchpoint per session
5. Extract channel from each session

### 1.3 Attribution Credit

**Definition**: Fractional value (0.0 to 1.0) assigned to a touchpoint based on attribution model.

**Mathematical constraint**: Sum of all credits for a conversion MUST equal 1.0

**Components**:
- **Credit**: Percentage of conversion attributed (0.0-1.0)
- **Revenue credit**: If conversion has revenue, credit × revenue
- **Channel**: Marketing channel receiving credit
- **UTM data**: Stored for drill-down, not primary attribution dimension

### 1.4 Conversion Event

**Definition**: Business outcome event that represents measurable value.

**Characteristics**:
- Explicitly marked (not inferred)
- Represents final outcome (not intermediate funnel step)
- Can have associated revenue
- Triggers attribution calculation

**Examples**:
- ✅ Conversion events: `purchase_completed`, `subscription_created`, `trial_started`
- ❌ Not conversions: `page_view`, `add_to_cart`, `checkout_started` (funnel events)

### 1.5 Lookback Window

**Definition**: Time period before conversion in which touchpoints are considered for attribution.

**Default**: 30 days (industry standard)

**Configurable by business model**:
- Quick-converting products: 7-14 days
- B2C e-commerce: 30 days
- B2B SaaS: 60-90 days

**Start**: First touchpoint within window
**End**: Conversion event timestamp

---

## 2. Attribution Models

### 2.1 Model Categories

**Preset Models** (7 standard models):
1. **First Touch**: 100% credit to first touchpoint
2. **Last Touch**: 100% credit to last touchpoint
3. **Linear**: Equal credit to all touchpoints (1/n each)
4. **Time Decay**: Exponential decay (7-day half-life default)
5. **U-Shaped**: 40% first, 40% last, 20% middle (equally distributed)
6. **W-Shaped**: 30% first, 30% conversion session, 30% last, 10% others
7. **Participation**: 100% credit to all unique channels (sum > 1.0)

**Custom Models** (Phase 2C):
- Defined via declarative DSL
- Validated to ensure credits sum to 1.0 (except Participation)
- Compiled to AST for execution

### 2.2 Model Execution

**Strategy Pattern**:
- Each model implements credit distribution algorithm
- Input: Journey (ordered touchpoints)
- Output: Array of credits (one per touchpoint)
- Constraint: Credits sum to 1.0 (enforced by validator)

**Formulas**:

**First Touch**:
```
credit = 1.0 for first touchpoint only
```

**Last Touch**:
```
credit = 1.0 for last touchpoint only
```

**Linear**:
```
credit_per_touchpoint = 1.0 / touchpoint_count
```

**Time Decay** (exponential, 7-day half-life):
```
weight(t) = 2^(-days_before_conversion / half_life_days)
credit(t) = weight(t) / sum_of_all_weights
```
- Default half-life: 7 days (configurable)
- Touchpoint at conversion: weight = 1.0
- Touchpoint 7 days before: weight = 0.5
- Touchpoint 14 days before: weight = 0.25

**U-Shaped** (Position-Based):
```
1 touchpoint:  100% to that touchpoint
2 touchpoints: 50% each
3+ touchpoints:
  first_credit = 0.4 (40%)
  last_credit = 0.4 (40%)
  middle_credit_each = 0.2 / middle_count (20% split equally)
```

**W-Shaped**:
```
1 touchpoint:  100% to that touchpoint
2 touchpoints: 50% each
3 touchpoints: 33.33% each
4+ touchpoints:
  first_credit = 0.3 (30%)
  middle_credit = 0.3 (30%) - touchpoint at index n/2
  last_credit = 0.3 (30%)
  other_credit_each = 0.1 / other_count (10% split equally)
```

**Participation**:
```
credit = 1.0 for each unique channel
```
- Deduplicates by channel (not session)
- Sum CAN exceed 1.0 (by design)
- Uses first session_id for each channel

### 2.3 Multi-Model Execution

**All active models run for each conversion**:
- Parallel execution (background job)
- Credits stored separately per model
- Enables instant model comparison in UI

**Benefit**: Users can switch attribution models instantly without recalculation.

---

## 3. Conversion Counting

### 3.1 Counting Modes

**Three modes supported** (GA4 2024 standard):

1. **Once per user** (default):
   - Only first/earliest conversion per user
   - Use case: Customer Acquisition Cost (CAC)
   - Denominator: Unique users

2. **Once per session**:
   - One conversion per session max
   - Use case: Legacy GA compatibility
   - Denominator: Unique sessions

3. **All events**:
   - Every conversion event counts
   - Use case: Repeat purchases, LTV analysis
   - Denominator: Total conversion events

**Configuration**: Account-level setting, overridable per conversion type.

### 3.2 Conversion Rate Calculation

**Formula**:
```
Conversion Rate (Channel X, Model Y) =
  Sum of attribution credits to Channel X under Model Y /
  Total users who had Channel X as touchpoint
```

**Example**:
```
100 users had Paid Search touchpoint
Under Linear model: Paid Search received 32.5 total credits
Conversion rate: 32.5 / 100 = 32.5%

Under First Touch model: Paid Search received 45 total credits
Conversion rate: 45 / 100 = 45%
```

**Key insight**: Conversion rates vary by model because credit distribution changes, not underlying conversion count.

---

## 4. Data Architecture

### 4.1 Storage Schema

**Events** (Bronze - raw data):
- All user actions tracked
- Immutable, never deleted
- Fields: visitor_id, session_id, event_type, occurred_at, properties (JSONB)

**Sessions** (Silver - enriched):
- Aggregated from events
- 30-minute timeout (configurable)
- Fields: visitor_id, session_id, started_at, channel, initial_utm (JSONB)
- One touchpoint per session

**Conversions** (Gold - business outcomes):
- Subset of events marked as conversions
- Fields: visitor_id, session_id, event_id, conversion_type, revenue, converted_at
- Triggers attribution calculation

**Attribution Credits** (Gold - calculated):
- Distributed credit per touchpoint
- Fields: conversion_id, attribution_model_id, session_id, channel, credit, revenue_credit
- One record per touchpoint per model per conversion

### 4.2 Continuous Aggregates (TimescaleDB)

**Pre-computed for dashboard performance**:

**channel_attribution_daily**:
- Aggregates by: account_id, channel, day, attribution_model_id
- Metrics: total_credits, total_revenue_credits, session_count, unique_visitors
- Refresh: Hourly, last 7 days

**model_comparison_daily**:
- Side-by-side model results
- Aggregates by: account_id, day, attribution_model_id, channel
- Enables instant model switching in UI

---

## 5. Service Architecture

### 5.1 Component Separation

**Data Collection Tier**:
- `Event::IngestionService` - Receives events from API
- `Session::ResolutionService` - Determines session boundaries (30-min timeout)
- `Channel::ClassificationService` - Maps UTM parameters + referrer to channel
- `Visitor::IdentityService` - Links anonymous visitors to known users

**Journey Construction Tier**:
- `Conversion::DetectionService` - Identifies conversion events
- `Attribution::JourneyBuilder` - Constructs touchpoint sequence from sessions
- `Attribution::TouchpointDeduplicator` - Ensures one per session
- `Attribution::LookbackFilter` - Applies 30-day window

**Attribution Calculation Tier**:
- `Attribution::ModelRegistry` - Manages preset + custom models
- `Attribution::ModelExecutor` - Applies algorithm to journey
- `Attribution::CreditDistributor` - Ensures sum = 1.0
- `Attribution::MultiModelRunner` - Parallel execution for comparison

**Persistence Tier**:
- `Attribution::CreditRepository` - Stores attribution credits
- `Attribution::AggregationService` - Updates continuous aggregates

### 5.2 Data Flow

**Event Tracking**:
```
User Action
  ↓
Event::IngestionService (validate, enrich)
  ↓
Session::ResolutionService (attach to session or create new)
  ↓
Channel::ClassificationService (determine marketing channel)
  ↓
Storage (events table, sessions table updated)
```

**Conversion Attribution** (background job):
```
Conversion Event Detected
  ↓
Attribution::JourneyBuilder (query last 30 days of sessions)
  ↓
Attribution::TouchpointDeduplicator (one per session)
  ↓
For each active AttributionModel:
  ↓
  Attribution::ModelExecutor (run algorithm)
    ↓
  Attribution::CreditDistributor (calculate credits)
    ↓
  Attribution::CreditRepository (persist)
  ↓
Attribution::AggregationService (update continuous aggregates)
```

---

## 6. Design Patterns

### 6.1 Strategy Pattern (Attribution Models)

**Interface**: `Attribution::BaseModel`
- Method: `calculate_credits(journey) -> Array<Credit>`
- Implementations: `FirstTouchModel`, `LinearModel`, `UShapedModel`, etc.
- Factory: `Attribution::ModelFactory.create(model_type)`

### 6.2 Builder Pattern (Journey Construction)

**Builder**: `Attribution::JourneyBuilder`
- Accumulates sessions within lookback window
- Validates completeness (has conversion event)
- Deduplicates touchpoints by session
- Produces immutable `Journey` object

### 6.3 Repository Pattern (Data Access)

**Repositories**:
- `EventRepository` - Query events by visitor, timeframe, filters
- `SessionRepository` - Retrieve sessions with channel data
- `ConversionRepository` - Find conversions and journey data
- `AttributionCreditRepository` - Store and query credits

### 6.4 Observer Pattern (Conversion Triggers)

**Flow**:
- `Conversion::DetectionService` publishes conversion event
- `Attribution::CalculationJob` observes and triggers
- Multiple models execute in parallel (async)
- Results aggregated for unified reporting

---

## 7. Implementation Guidelines

### 7.1 Session-Based Touchpoint Deduplication

**Rule**: One touchpoint per channel per session

**Implementation**:
```
Journey Construction:
1. Query sessions for visitor within lookback window
2. Order by started_at ASC
3. For each session:
   - Extract channel (already determined at session creation)
   - Add to touchpoints array
4. Result: Array of {session_id, channel, started_at}
```

**Why not event-level?**:
- Multiple events within session don't add attribution value
- Aligns with industry standards (GA4, Amplitude, Mixpanel)
- Prevents over-crediting channels with high page view counts

### 7.2 Channel Classification Priority

**Precedence** (highest to lowest):
1. UTM parameters (if present)
2. Referrer domain mapping
3. Direct (no referrer, no UTM)

**Channel taxonomy**:
- `paid_search` - Paid search ads (utm_medium=cpc/ppc)
- `organic_search` - Organic search traffic
- `paid_social` - Paid social ads (utm_medium=social, utm_source=facebook/instagram/linkedin/twitter)
- `organic_social` - Organic social referrals
- `email` - Email campaigns (utm_medium=email)
- `display` - Display advertising (utm_medium=display/banner)
- `referral` - Other website referrals
- `direct` - Direct traffic (no referrer, no UTM)

### 7.3 Attribution Credit Constraints

**Mathematical validation** (enforced):
- Sum of credits per conversion MUST equal 1.0
- Exception: Participation model (credits can sum > 1.0)
- Each credit value: 0.0 ≤ credit ≤ 1.0
- Precision: Round to 4 decimal places (0.3333)

### 7.4 Multi-Model Comparison

**Storage strategy**:
- Calculate credits for ALL active models per conversion
- Store separately: `attribution_credits.attribution_model_id`
- Dashboard filters by model_id for instant switching

**Performance**:
- Continuous aggregates pre-compute by model
- Query time: <100ms (vs 1-5 seconds for raw data)
- Trade-off: Storage for speed

---

## 8. Testing Requirements

### 8.1 Attribution Calculation Tests

**Test cases** (minimum):
1. Single touchpoint journey (credit = 1.0)
2. Two touchpoints (various models)
3. Many touchpoints (100+)
4. Credit sum validation (must equal 1.0)
5. Edge cases (same channel multiple sessions)
6. Lookback window boundaries
7. Multi-tenancy isolation

### 8.2 Journey Construction Tests

**Test cases**:
1. Sessions within lookback window
2. Sessions outside lookback window (excluded)
3. Session-based deduplication
4. Touchpoint ordering (chronological)
5. Missing conversion event (validation error)

---

## 9. Performance Considerations

### 9.1 Query Optimization

**Indexed fields**:
- `sessions.visitor_id` - Journey construction
- `sessions.started_at` - Lookback window filter
- `sessions.channel` - Aggregation
- `attribution_credits.attribution_model_id` - Model comparison
- `attribution_credits.conversion_id` - Credit lookup

### 9.2 Background Processing

**Async attribution calculation**:
- Conversion API responds immediately (creates conversion record)
- Attribution runs in background (Solid Queue)
- Credits appear in dashboard within seconds
- Webhooks triggered after attribution complete

---

## 10. Migration from Other Platforms

### 10.1 Google Analytics (UA/GA4)

**Mapping**:
- GA4 "key events" → mbuzz "conversions"
- GA4 "session source" → mbuzz "session.channel"
- GA4 attribution models → mbuzz preset models
- GA4 data-driven attribution → mbuzz custom models (Phase 2C)

**Differences**:
- mbuzz uses explicit conversion marking (vs GA4 automatic)
- mbuzz supports unlimited conversion types (vs GA4 30 limit)
- mbuzz allows retroactive model comparison (stored credits)

### 10.2 Segment/Mixpanel

**Mapping**:
- Segment "track" → mbuzz `POST /api/v1/events`
- Mixpanel "conversion event" → mbuzz conversion with `is_conversion: true`
- Mixpanel touchpoints → mbuzz sessions with channel

---

## 11. References

### 11.1 Academic Sources

1. **"A Time To Event Framework For Multi-touch Attribution"**
   Google Research, 2024 | Journal of Data Science, Volume 22, Issue 1
   arXiv:2009.08432

2. **"Shapley Value Methods for Attribution Modeling in Online Advertising"**
   arXiv:1804.05327

3. **"Shapley Meets Uniform: An Axiomatic Framework for Attribution"**
   WWW Conference | DOI:10.1145/3308558.3313731

### 11.2 Industry Documentation

1. **Google Analytics 4**: Attribution Overview, Conversion Counting Methods (2024)
2. **Amplitude**: Attribution Credit, Funnel Conversion Computation
3. **Mixpanel**: Multi-Touch Attribution Guide, Funnel Best Practices
4. **Adobe Analytics**: Attribution Panel Documentation
5. **Segment**: Event Tracking Best Practices

---

## 12. Implementation Status

### Implemented Algorithms

All 7 preset models are fully implemented:

| Model | Class | Status |
|-------|-------|--------|
| First Touch | `Attribution::Algorithms::FirstTouch` | ✅ Complete |
| Last Touch | `Attribution::Algorithms::LastTouch` | ✅ Complete |
| Linear | `Attribution::Algorithms::Linear` | ✅ Complete |
| Time Decay | `Attribution::Algorithms::TimeDecay` | ✅ Complete |
| U-Shaped | `Attribution::Algorithms::UShaped` | ✅ Complete |
| W-Shaped | `Attribution::Algorithms::WShaped` | ✅ Complete |
| Participation | `Attribution::Algorithms::Participation` | ✅ Complete |

### File Locations

```
app/services/attribution/algorithms/
├── first_touch.rb
├── last_touch.rb
├── linear.rb
├── time_decay.rb
├── u_shaped.rb
├── w_shaped.rb
└── participation.rb
```

### Not Yet Implemented

- **Custom Models (DSL)**: Phase 2C - see `lib/specs/attribution_dsl_design.md`
- **Data-Driven Models**: Markov chains, Shapley values (requires ML infrastructure)

---

## 13. Version History

- **v1.1** (2025-11-27): All 7 preset models implemented
  - Added Time Decay algorithm (configurable half-life)
  - Added U-Shaped algorithm (40/40/20 distribution)
  - Added W-Shaped algorithm (30/30/30/10 distribution)
  - Added Participation algorithm (100% per unique channel)
  - Complete test coverage (44 algorithm tests)

- **v1.0** (2025-11-19): Initial design based on research
  - Session-based touchpoint attribution
  - 30-day lookback window default
  - Multi-model execution strategy
  - Channel-primary, UTM-secondary approach

---

**See also**:
- `lib/specs/attribution_dsl_design.md` - Custom model DSL specification
- `lib/specs/implementation_plan_rest_api_first.md` - Phase 2 implementation plan
- `CLAUDE.md` - Code style and service object patterns
