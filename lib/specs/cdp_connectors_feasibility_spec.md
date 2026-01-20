# CDP Connectors Feasibility Analysis

Connectors for Segment/Rudderstack/mParticle that apply attribution models to produce consistent insights regardless of the underlying event structure.

**Status**: Research / Feasibility
**Created**: 2026-01-21

---

## Executive Summary

| Aspect | Assessment |
|--------|------------|
| **Complexity** | Moderate (~100-150 hours for first connector) |
| **Core Changes Required** | None - architecture already source-agnostic |
| **Main Work** | Transformation layer + session reconstruction |
| **Extensibility** | High - adapter pattern enables additional CDPs easily |

---

## Current Architecture Alignment

### Why This Is Feasible

The existing architecture is **already decoupled from event sources**:

| Component | Location | Source-Agnostic? |
|-----------|----------|------------------|
| Channel Attribution | `Sessions::ChannelAttributionService` | Yes - accepts raw UTM/referrer |
| Attribution Algorithms | `Attribution::Algorithms::*` | Yes - operates on touchpoints |
| Journey Builder | `Attribution::JourneyBuilder` | Yes - queries sessions, not events |
| Session Resolution | `Sessions::CreationService` | Yes - uses device fingerprint |

### Data Flow (Unchanged)

```
[CDP Events] → Connector Adapter → Multibuzz Schema
                                        ↓
              Session Resolution → Channel Attribution
                                        ↓
              Conversion Tracking → Attribution Calculator
                                        ↓
                              8 models → Credits persisted
```

---

## Domain Model

### New Bounded Contexts

```
Connectors (new)
├── Adapters         # CDP-specific transformations
├── Mappings         # Customer-defined event→conversion rules
├── Importers        # Historical data pipelines
└── SessionBuilders  # Reconstruct sessions from event streams
```

### Entity Relationships

```
Account
├── ConnectorConfiguration (new)
│   ├── connector_type: enum (segment, rudderstack, mparticle)
│   ├── api_credentials: encrypted
│   ├── webhook_secret: encrypted
│   └── enabled: boolean
│
├── ConversionMapping (new)
│   ├── source_event: string ("Order Completed")
│   ├── conversion_type: string ("purchase")
│   ├── revenue_path: string ("properties.total")
│   └── acquisition_rule: string (optional)
│
└── ImportJob (new)
    ├── connector_type: enum
    ├── status: enum (pending, running, completed, failed)
    ├── progress: jsonb
    └── error_details: text
```

---

## Design Patterns

### 1. Adapter Pattern (Core)

Each CDP gets its own adapter implementing a common interface.

```
Connectors::Adapters::Base (abstract)
├── Connectors::Adapters::Segment
├── Connectors::Adapters::Rudderstack
├── Connectors::Adapters::MParticle
└── Connectors::Adapters::Amplitude
```

**Interface Contract**:
- `#transform_track(payload) → normalized_event`
- `#transform_identify(payload) → normalized_identity`
- `#transform_page(payload) → normalized_event`
- `#extract_context(payload) → { ip:, user_agent:, utm:, referrer:, click_ids: }`

**Why**: Isolates CDP-specific quirks. Adding a new CDP = adding one adapter class.

### 2. Strategy Pattern (Session Reconstruction)

Different CDPs may need different session reconstruction strategies.

```
Connectors::SessionBuilders::Base
├── Connectors::SessionBuilders::TimeWindow (default, 30-min gaps)
├── Connectors::SessionBuilders::ExplicitSession (if CDP provides session_id)
└── Connectors::SessionBuilders::PageSequence (group by referrer changes)
```

**Why**: Segment has no sessions; Amplitude has session_id; Rudderstack varies by source.

### 3. Registry Pattern (Connector Discovery)

```
Connectors::Registry
  .register(:segment, Connectors::Adapters::Segment)
  .register(:rudderstack, Connectors::Adapters::Rudderstack)

Connectors::Registry.adapter_for(:segment) # → Segment adapter instance
```

**Why**: Clean lookup, easy to add new connectors without modifying existing code.

### 4. Pipeline Pattern (Import Processing)

```
ImportPipeline
  .fetch(source)           # Extract from warehouse/API
  .transform(adapter)      # Normalize to Multibuzz schema
  .reconstruct_sessions    # Build sessions from events
  .persist                 # Write to database
  .calculate_attribution   # Trigger attribution for conversions
```

**Why**: Each step is testable in isolation; steps can be retried independently.

### 5. Builder Pattern (Conversion Mapping)

Customer-defined rules for mapping CDP events to conversions.

```
ConversionMapping::Builder
  .for_event("Order Completed")
  .maps_to_conversion("purchase")
  .with_revenue_from("properties.total")
  .acquisition_when("properties.is_first_order == true")
  .build
```

**Why**: Complex mapping rules expressed declaratively; validates at build time.

---

## File Structure

```
app/
├── models/
│   └── connectors/
│       ├── configuration.rb        # ConnectorConfiguration model
│       ├── conversion_mapping.rb   # ConversionMapping model
│       └── import_job.rb           # ImportJob model
│
├── services/
│   └── connectors/
│       ├── adapters/
│       │   ├── base.rb             # Abstract adapter interface
│       │   ├── segment.rb          # Segment-specific transforms
│       │   ├── rudderstack.rb      # Rudderstack-specific transforms
│       │   └── mparticle.rb        # mParticle-specific transforms
│       │
│       ├── session_builders/
│       │   ├── base.rb             # Abstract session builder
│       │   ├── time_window.rb      # 30-min gap detection
│       │   └── explicit_session.rb # Use CDP's session_id if present
│       │
│       ├── importers/
│       │   ├── base.rb             # Abstract importer
│       │   ├── webhook_importer.rb # Real-time webhook processing
│       │   └── warehouse_importer.rb # Batch historical import
│       │
│       ├── registry.rb             # Adapter/builder registration
│       ├── webhook_handler.rb      # Unified webhook entry point
│       ├── conversion_resolver.rb  # Apply conversion mappings
│       └── click_id_extractor.rb   # Parse click IDs from URLs
│
├── controllers/
│   └── webhooks/
│       └── connectors_controller.rb # Single endpoint, routes by type
│
└── jobs/
    └── connectors/
        ├── process_webhook_job.rb   # Async webhook processing
        └── historical_import_job.rb # Background import
```

---

## Schema Mapping Reference

### Segment → Multibuzz

| Segment Path | Multibuzz Field | Notes |
|--------------|-----------------|-------|
| `anonymousId` | `visitor_id` | Direct |
| `userId` | `identity.external_id` | Direct |
| `context.campaign.source` | `session.initial_utm.utm_source` | Direct |
| `context.campaign.medium` | `session.initial_utm.utm_medium` | Direct |
| `context.campaign.name` | `session.initial_utm.utm_campaign` | Direct |
| `context.referrer.url` | `session.initial_referrer` | Direct |
| `context.ip` | Device fingerprint input | Existing logic |
| `context.userAgent` | Device fingerprint input | Existing logic |
| `context.page.url` | Click ID extraction source | Parse query params |
| `event` | `event.event_type` | Direct |
| `properties` | `event.properties` | Direct |
| `timestamp` | `event.occurred_at` | ISO8601 parse |

### Rudderstack Differences

- Uses `anonymousId` and `userId` (same as Segment)
- Campaign context may be at `context.campaign` or `context.traits.campaign`
- Some sources include `sessionId` - use if present

### mParticle Differences

- Uses `mpid` (mParticle ID) instead of `anonymousId`
- User identities in `user_identities` object
- Session info in `session_uuid` and `session_start_unixtime_ms`

---

## Extensibility Points

### Adding a New CDP

1. Create adapter: `app/services/connectors/adapters/new_cdp.rb`
2. Register: `Connectors::Registry.register(:new_cdp, Adapters::NewCdp)`
3. Add webhook route (optional): `config/routes.rb`
4. Add warehouse connector (optional): `Importers::NewCdpWarehouse`

**No changes to**: Attribution algorithms, channel derivation, session resolution, conversion tracking.

### Adding Custom Session Logic

1. Create builder: `app/services/connectors/session_builders/custom.rb`
2. Configure per-account: `ConnectorConfiguration.session_builder_type`

### Adding New Conversion Rules

1. Customer creates `ConversionMapping` via UI/API
2. `ConversionResolver` applies rules at import time
3. No code changes required

---

## Integration Points with Existing Code

### Reused Services (No Changes)

| Service | Purpose | Integration |
|---------|---------|-------------|
| `Sessions::ChannelAttributionService` | UTM → channel | Called with extracted UTM |
| `Sessions::ClickIdCaptureService` | Click ID handling | Called with parsed click IDs |
| `Visitors::IdentificationService` | Visitor creation | Called with visitor_id |
| `Identities::IdentificationService` | Identity linking | Called for identify events |
| `Events::ProcessingService` | Event persistence | Called with normalized events |
| `Conversions::TrackingService` | Conversion creation | Called when mapping matches |
| `Attribution::Calculator` | Attribution calculation | Triggered automatically |

### New Integration Hooks

| Hook | Location | Purpose |
|------|----------|---------|
| `after_connector_event` | `Connectors::WebhookHandler` | Custom post-processing |
| `before_session_create` | `SessionBuilders::Base` | Enrich session data |
| `on_import_progress` | `Importers::Base` | Progress callbacks |

---

## Architecture Options

### Option A: Webhook Destination

**Flow**: CDP → Webhook → Real-time processing

**Pros**: Simple, real-time, follows Shopify pattern
**Cons**: No historical data, depends on customer setup

### Option B: Warehouse Connector

**Flow**: CDP Warehouse → Batch import → Attribution

**Pros**: Full history, batch efficiency
**Cons**: Not real-time, requires warehouse access

### Option C: Hybrid (Recommended)

**Flow**: Webhook (real-time) + Warehouse (historical backfill)

**Implementation Phases**:
1. Webhook destination (MVP)
2. Warehouse connector (historical)
3. Configuration UI

---

## Challenges & Mitigations

| Challenge | Mitigation |
|-----------|------------|
| No session concept in CDPs | `SessionBuilders::TimeWindow` reconstructs from event gaps |
| Click IDs not in standard schema | `ClickIdExtractor` parses from `context.page.url` |
| Different event naming per customer | `ConversionMapping` allows custom rules |
| High event volume | Async processing via `Solid Queue`, batch imports |
| Historical data size | TimescaleDB hypertables, chunked imports |
| Schema variations between CDPs | Adapter pattern isolates differences |

---

## Effort Estimates

| Component | Hours | Dependencies |
|-----------|-------|--------------|
| Adapter framework + Segment | 30-40 | None |
| Session reconstruction | 20-30 | Adapter framework |
| Conversion mapping | 15-20 | None |
| Webhook handler | 10-15 | Adapter framework |
| Historical import pipeline | 25-35 | Session reconstruction |
| **Total (first connector)** | **100-150** | |
| Additional CDP adapter | 20-30 | Framework exists |

---

## Success Criteria

1. **Consistent attribution** regardless of event source (Segment vs native SDK)
2. **Zero changes** to attribution algorithms for new connectors
3. **< 30 hours** to add subsequent CDP adapters
4. **Session reconstruction accuracy** > 95% vs native tracking
5. **Historical import** handles 10M+ events without timeout

---

## Next Steps

1. Validate schema mapping with real Segment payloads
2. Prototype `Connectors::Adapters::Segment`
3. Test session reconstruction accuracy against known journeys
4. Design conversion mapping UI/API
5. Benchmark import performance with synthetic data
