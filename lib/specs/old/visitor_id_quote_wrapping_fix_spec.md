# Visitor ID Quote-Wrapping Fix

**Date:** 2026-05-06
**Status:** Complete
**Branch:** `develop`

## Problem

Production error tracker is firing intermittent `ActiveRecord::RecordInvalid` warnings from `Sessions::CreationService`:

```
Validation failed: Visitor must contain only letters, numbers, underscores, hyphens, dots, and colons
```

Investigation via `api_request_logs` for `endpoint: "v1/sessions"`, `http_status: 422`, last 3 days:

```
visitor_id: """""""""""""""""""""dc8e02e6...7779a794"""""""""""""""""""""
visitor_id: """"""""""3238f62b...c23098df""""""""""
```

Both values are valid `SecureRandom.hex(32)` strings wrapped in matching pairs of `"`. Quote count grows by 2 per session call (19 pairs on one visitor, 10 on another). Both come from real customer sites. `session_id` is clean (fresh UUID per call), so the bug lives in the **client-side persistent storage read/write path**: a `JSON.stringify`-on-write without `JSON.parse`-on-read pattern, accumulating one quote pair per round trip.

Volume is small (2 events / 3 days, 2 sites), but consequences for affected visitors are severe:

- Sessions never persist (validation rejects every call).
- Events for those visitors fail with "Visitor not found" because the lookup string keeps mutating.
- Cookies grow unbounded until they exceed size limits and break tracking entirely.

`ApplicationService#call` rescues `RecordInvalid` but reports it via `Rails.error.report(handled: true)`, which is what's emailing the warnings.

## Solution

Server-side defensive normalization at the two service entry points that read `visitor_id`:

1. **Strip leading/trailing `"` characters** from incoming `visitor_id` before validation/lookup. Recovers affected visitors silently.
2. **Validate format upfront** in `Sessions::CreationService#validation_error` so genuinely-malformed values return a clean 422 without raising `RecordInvalid` (and without emailing a warning).

SDK fixes are explicitly out of scope (per user direction).

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Where to normalize | `Visitor.normalize_id` class method on the model | Single source of truth. Two service entry points share it. No new helper cluster. |
| Where to format-validate | `Sessions::CreationService#validation_error` (boundary) | Stops `Rails.error.report` noise for known input-validation failures. Model validation remains as safety net. |
| Strip scope | Leading/trailing `"` only | Targets the observed bug pattern. Other malformed input still fails cleanly via format check. |
| Also normalize in events flow | Yes — `Events::ProcessingService#event_visitor_id` | Otherwise affected visitors get a clean session row but their events still miss the lookup. |
| Touch `session_id` | No | All observed `session_id` values are clean UUIDs — no quote accumulation. Don't fix what isn't broken. |
| Spec format | Mini Spec | One-page bug fix with clear root cause. Per `lib/specs/GUIDE.md`. |

## Acceptance Criteria

- [x] `Sessions::CreationService` accepts `visitor_id: '""abc123""'` and creates the visitor with `visitor_id: "abc123"`.
- [x] `Sessions::CreationService` returns 422 with format error (not raised exception) when `visitor_id` contains invalid characters (e.g. `"foo bar"` after strip).
- [x] Format-validation failure does NOT trigger `Rails.error.report` (the noisy email path). Asserted indirectly: the 422 path returns the boundary message `"visitor_id format invalid"`, not the rescue path's `"Record invalid: ..."`. The rescue is the only `Rails.error.report` site in `ApplicationService`, so a boundary return implies no report.
- [x] `Events::ProcessingService` resolves `visitor_id: '""""abc123""""'` to an existing visitor with `visitor_id: "abc123"`.
- [x] Existing session/event tests still pass (458 tests, 978 assertions, 0 failures).
- [ ] Re-running the production diagnostic query 24h post-deploy shows zero new `Visitor must contain` 422s for visitors whose canonical hex form already exists. *(verify after deploy)*

## Implementation Tasks

- [x] **1.1** Promote regex to `Visitor::ID_FORMAT` constant in `app/models/concerns/visitor/validations.rb`.
- [x] **1.2** Add `Visitor.normalize_id(value)` class method in `app/models/visitor.rb`.
- [x] **1.3** Sessions::CreationService: normalize `visitor_id` reader; add format check in `validation_error`.
- [x] **1.4** Events::ProcessingService: normalize `event_visitor_id` reader.
- [x] **2.1** RED test — Sessions::CreationService accepts quote-wrapped visitor_id.
- [x] **2.2** RED test — Sessions::CreationService returns 422 (not raise) on malformed format.
- [x] **2.3** RED test — Events::ProcessingService resolves quote-wrapped visitor_id to existing visitor.
- [x] **3.1** Run full test suite, no regressions.
- [x] **3.2** Update spec status → Complete; move to `lib/specs/old/`.

## Out of Scope

- Fixing the SDK that double-wraps visitor_id on write. (User direction.)
- Silencing `Rails.error.report` globally for `RecordInvalid` in `ApplicationService`. The boundary fix is scoped; broader rescue policy is a separate decision.
- Normalizing `session_id` or `device_fingerprint` (not observed to have this issue).
