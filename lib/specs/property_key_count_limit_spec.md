# Property Key Count Limit (and JSONB Cap Backfill)

**Date:** 2026-05-10
**Status:** Shipped
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

Add `MAX_PROPERTY_KEYS = 25` as a shared constant in a new `Concerns::PropertyKeyLimit` module (mirrors the existing `MAX_JSONB_BYTES = 50.kilobytes` pattern in `Identity::Validations`, `Event::Validations`, `Session::Validations`). Validates that the JSONB hash has at most 25 top-level keys.

Apply both validations (key count + 50KB byte cap) to all four surfaces:

1. `Event::Validations` — already has 50KB cap, add key-count cap.
2. `Identity::Validations` — already has 50KB cap, add key-count cap.
3. `Conversion::Validations` — add **both** caps (currently has neither).
4. `Visitor::Validations` — add **both** caps for `traits` (currently has neither).

Validation lives at the model layer (per CLAUDE.md "JSONB Columns: Max 50KB per JSONB field. Validate via `validate :field_size_limit`"). Services raising `ActiveRecord::RecordInvalid` are caught by `ApplicationService` and surfaced as 422 to the API client.

The dashboard `ConversionDimensionsService.limit(20)` stays. Per-call cap (25) is independent from per-account discovery cap (20); customers may have long-tail keys in DB that don't surface in the filter UI.

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| Per-call key limit | **25** | Matches GA4 (the strictest mainstream platform). 10 rejects normal B2B identify payloads (plan, mrr, role, signup_source, etc) and ecommerce conversion payloads (order_id, products, total, shipping, tax, coupon, segment, payment_method, currency). Mixpanel = 255, Segment = ~unlimited, Amplitude = 2,000/project. 25 is the safe defensible default. |
| Validation layer | Model concern | Repo convention: 50KB cap already lives in model concerns. Service layer wraps in `ApplicationService` which converts `RecordInvalid` to 422. |
| Shared constant | New `Concerns::PropertyKeyLimit` module | Three concerns currently inline-define `MAX_JSONB_BYTES`. Extract once for `MAX_PROPERTY_KEYS` so it doesn't drift across surfaces. |
| Conversion 50KB cap | Backfill in same PR | Closing two known JSONB gaps in one change is cheaper than two PRs. |
| Visitor 50KB cap | Backfill in same PR | Same. |
| Key-count error message | `"cannot have more than 25 custom keys (got N)"` | Echoes count back so SDK authors can debug. "Custom" because reserved keys are excluded from the count. |
| Reserved keys count? | **No, excluded** | System-captured keys (`url`, `referrer` for conversions) don't count toward the 25-key cap. The cap is on user-defined custom keys, which is what the cap is actually trying to bound. Documented as "25 custom keys" in error messages and BUSINESS_RULES. |
| Where reserved keys live | Class constant on each model that has them | Conversion gets `RESERVED_PROPERTY_KEYS = %w[url referrer].freeze`; Event/Identity/Visitor define `RESERVED_PROPERTY_KEYS = [].freeze` (or omit and the concern defaults to `[]`). `Conversions::PropertyKeyDiscoveryService` reads from the model constant instead of redefining its own. |
| Dashboard top-20 limit | Unchanged | Independent of ingestion cap. Customers can send 25 keys per call; UI surfaces the 20 most-populated. |

## Acceptance Criteria

- [x] `Concerns::PropertyKeyLimit` module exists and is `extend`able. Defines `MAX_PROPERTY_KEYS = 25` and a `validate_property_key_count(field)` class macro.
- [x] `Event#properties` rejected when > 25 top-level keys (RED → GREEN test in `event_test.rb`).
- [x] `Identity#traits` rejected when > 25 top-level keys.
- [x] `Conversion#properties` rejected when > 25 top-level keys AND when > 50KB.
- [x] `Visitor#traits` rejected when > 25 top-level keys AND when > 50KB.
- [x] API surfaces (POST /events, /conversions, /identify, /sessions) return 422 with the count-cap error message when the cap is exceeded — service-level test for each.
- [x] Existing `MAX_JSONB_BYTES = 50.kilobytes` is moved into a single shared constant (or duplicated intentionally — pick during implementation; do not silently diverge).
- [x] Error message echoes the actual key count: `"properties cannot have more than 25 keys (got 47)"`.
- [x] Reserved keys (`url`, `referrer` on Conversion) are excluded from the 25-key count. A conversion with `{url, referrer, k1..k25}` is valid (27 total keys, 25 custom). A conversion with `{url, referrer, k1..k26}` is rejected (26 custom).
- [x] `Conversions::PropertyKeyDiscoveryService` reads `Conversion::RESERVED_PROPERTY_KEYS` instead of defining its own list. Existing discovery test still passes.
- [x] Documented in `lib/docs/BUSINESS_RULES.md` under a new section: "Property Key Limits".
- [x] No regression in 27 score-related tests, full ingestion test suite green.

## Out of Scope

- Per-account total key cap (currently effectively bounded by `PropertyKeyDiscoveryService` 90-day prune; a hard cap is a separate spec).
- Per-key value-length cap (the 50KB byte cap is the only value-size guard for now; GA4 caps individual values at 100 chars but our use case is freer).
- Property key naming validation (alphanumeric/underscore enforcement). Sanitization on read in `Dashboard::Scopes::Operators::Base` is sufficient for the dashboard filter path.
- Backfill / cleanup of existing rows in production that exceed the cap. Validation is applied on `create` and `update`; existing rows stay readable until they are touched.
- Fix 3 from `spend_dashboard_bugfixes_spec.md` ("user properties cannot be tested because the app is blocked from this state"). Still awaiting clarification on the blocked-state surface.

## References

- [GA4 event collection limits](https://support.google.com/analytics/answer/9267744) — 25 event params, 25 user properties
- [Mixpanel property reference](https://docs.mixpanel.com/docs/data-structure/property-reference) — 255 per event
- [Segment schema limits](https://segment.com/docs/connections/sources/schema/schema-unique-limits/) — display cap 300
- [Amplitude limits](https://amplitude.com/docs/faq/limits) — 2,000/project, no per-call cap
