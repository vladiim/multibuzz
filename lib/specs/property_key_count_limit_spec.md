# Property Key Count Limit (Truncate-and-Warn)

**Date:** 2026-05-10
**Status:** Shipped (revised behavior)
**Branch:** `feat/property-key-count-limit`

## Problem

The four ingestion APIs (events, conversions, identify, sessions) accept arbitrary JSONB key/value blobs:

| Surface | Field | Byte cap | Key-count cap |
|---|---|---|---|
| `Event#properties` | `properties` | 50KB | none |
| `Identity#traits` | `traits` | 50KB | none |
| `Conversion#properties` | `properties` | **none** | none |
| `Visitor#traits` | `traits` | **none** | none |

The 50KB cap (where present) does not bound key count: 50KB / ~10 bytes per key = 5,000 keys. A misbehaving SDK or a hostile client can flood `Conversions::PropertyKeyDiscoveryService` with thousands of one-shot keys, polluting the dashboard filter UI (`Dashboard::ConversionDimensionsService` shows top 20 keys, but discovery and the prune cycle still process the long tail).

Two surfaces also lack the basic 50KB byte cap: `Conversion#properties` and `Visitor#traits`. Same JSONB bloat risk that the cap was added for elsewhere.

## Solution

Two layers, two rules:

1. **Hard byte cap (50KB) — reject with 422**. Applied at the model layer to all five JSONB fields. Backfilled to Conversion and Visitor.

2. **Soft key-count cap (25 custom keys) — truncate and warn**. Applied at the service layer. The server keeps the first 25 keys in insertion order, drops the rest, and surfaces a `warnings` array on the API response. The request still succeeds.

Truncation lives in service code, not in the model, because we need to detect the overflow *before* it disappears in order to surface a warning to the SDK. A `before_validation` callback would mutate silently and the warning hook would be awkward.

`PropertyKeyLimit` is a plain module with three pure functions:

- `PropertyKeyLimit::MAX_PROPERTY_KEYS = 25`
- `PropertyKeyLimit.truncate(hash, reserved: [])` — returns truncated hash
- `PropertyKeyLimit.overflow(hash, reserved: [])` — returns count of dropped keys
- `PropertyKeyLimit.truncated?(hash, reserved: [])` — boolean predicate

Each ingestion service calls `truncate` before persisting and uses `truncated?` to decide whether to add a warning.

| Service | Surface | Reserved keys |
|---|---|---|
| `Identities::IdentificationService` | `traits` | none |
| `Conversions::TrackingService` | `properties` | `url`, `referrer` |
| `Events::ProcessingService` | `properties` | none (URL / referrer are stored as part of `properties` but not given reserved-key treatment for the cap; the SDK rarely sends both URL and 25+ custom keys together) |

API response shape adds an optional `warnings` array. The field is omitted entirely when there's nothing to warn about.

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| Behavior on overflow | **Truncate and warn** (not reject) | Failing in production for a 26-key payload would break SDK callers for what is fundamentally an instrumentation mistake. Truncation lets the data flow while the warning gives developers the signal to fix instrumentation. |
| Truncation order | First 25 in insertion order | Predictable, language-agnostic. Hash key insertion order is preserved in Ruby and JSON parsers default to it. The SDK can choose which 25 keys to send first. |
| Warning location | Top-level `warnings` array on the response | Standard convention. SDKs can log it once per response without parsing nested structures. Events batch endpoint puts warnings on each accepted event entry (since each event is independent). |
| Per-call key limit | **25** | Matches GA4 (the strictest mainstream platform). 10 truncates normal B2B identify payloads (plan, mrr, role, signup_source, etc) and ecommerce conversion payloads (order_id, products, total, shipping, tax, coupon, segment, payment_method, currency). Mixpanel = 255, Segment = ~unlimited, Amplitude = 2,000/project. 25 is the safe defensible default. |
| Truncation layer | Service layer | Need to detect overflow before truncation in order to warn. Model `before_validation` could truncate silently but couldn't surface a warning to the API caller. Pure functions keep the logic testable without ActiveRecord ceremony. |
| 50KB byte cap | Stays at model layer | This is a hard reject — services don't need to do anything special. Backfilled to Conversion and Visitor concerns. |
| Reserved keys | Excluded from the 25-key count | System-captured keys (`url`, `referrer` for conversions) don't count toward the cap. The cap is on user-defined custom keys, which is what the cap is actually trying to bound. |
| Where reserved keys live | `Conversion::Validations::RESERVED_PROPERTY_KEYS` | `Conversions::PropertyKeyDiscoveryService` reads from this constant rather than redefining its own list. Single source of truth. |
| Warning message | `"properties: kept first 25 of N keys, dropped the rest"` | Echoes the actual count back so SDK authors can debug without grepping the source. |
| Direct AR calls | Not auto-truncated | `PropertyKeyLimit.truncate` is a pure function any caller can opt into. Internal jobs and Shopify webhook handlers should call it explicitly when ingesting user data. The 50KB hard cap still applies as a defensive lower bound. |

## Acceptance Criteria

- [x] `PropertyKeyLimit` module exists and exposes `MAX_PROPERTY_KEYS = 25`, `truncate(hash, reserved: [])`, `overflow(hash, reserved: [])`, `truncated?(hash, reserved: [])` as pure functions.
- [x] `Identities::IdentificationService` truncates `traits` to 25 keys before persisting; surfaces a `warnings` array on the result when truncation fired.
- [x] `Conversions::TrackingService` truncates `properties` to 25 custom keys before persisting; preserves `url` and `referrer` outside the cap; surfaces `warnings`.
- [x] `Events::ProcessingService` truncates `properties` to 25 keys before persisting; surfaces `warnings` per event.
- [x] `Events::IngestionService` plumbs warnings up so each accepted event in the batch response carries a `warnings` array when applicable.
- [x] `Api::V1::IdentifyController` includes top-level `warnings` in the success response when present; omits the field entirely otherwise.
- [x] `Conversions::ResponseBuilder` includes top-level `warnings` in the success response when present; omits otherwise.
- [x] `Api::V1::EventsController` returns each accepted event with a `warnings` field when applicable.
- [x] Conversions backfill the 50KB byte cap (`Conversion::Validations#properties_size_limit`).
- [x] Visitor backfills the 50KB byte cap on `traits` (`Visitor::Validations#traits_size_limit`).
- [x] `Conversions::PropertyKeyDiscoveryService` reads `Conversion::Validations::RESERVED_PROPERTY_KEYS` instead of defining its own list.
- [x] `lib/docs/BUSINESS_RULES.md` § 12 updated to describe the truncate-and-warn rule (PK1–PK8).
- [x] `lib/docs/sdk/api_contract.md` updated: properties section describes the cap, each endpoint documents the optional `warnings` field.
- [x] Full test suite green (2716 tests across models, services, controllers).

## Out of Scope

- Per-account total key cap (currently effectively bounded by `PropertyKeyDiscoveryService` 90-day prune; a hard cap is a separate spec).
- Per-key value-length cap. The 50KB byte cap is the only value-size guard for now.
- Property key naming validation (alphanumeric/underscore enforcement). Sanitization on read in `Dashboard::Scopes::Operators::Base` is sufficient for the dashboard filter path.
- Backfill / cleanup of existing rows in production that exceed the cap. Truncation is applied on `create` and `update` via the service layer; existing rows stay readable.
- Fix 3 from `spend_dashboard_bugfixes_spec.md` ("user properties cannot be tested because the app is blocked from this state"). Still awaiting clarification on the blocked-state surface.

## References

- [GA4 event collection limits](https://support.google.com/analytics/answer/9267744) — 25 event params, 25 user properties
- [Mixpanel property reference](https://docs.mixpanel.com/docs/data-structure/property-reference) — 255 per event
- [Segment schema limits](https://segment.com/docs/connections/sources/schema/schema-unique-limits/) — display cap 300
- [Amplitude limits](https://amplitude.com/docs/faq/limits) — 2,000/project, no per-call cap
