# Session Rate Limiting & Bot Rejection

**Date:** 2026-03-27
**Priority:** P0
**Status:** In Progress
**Branch:** `feature/session-bot-detection`

---

## Summary

Bot traffic flooding `POST /api/v1/sessions` caused a production outage on 2026-03-27. A vulnerability scanner sent rapid-fire requests (5+/sec from a single fingerprint, probing paths like `/.secrets`, `/credentials.json`, `/var/log/nginx/error.log`), saturating both Puma workers. Response times degraded from 7ms to 2,100ms, starving legitimate traffic.

Bot detection (Phase 1-3 of `session_bot_detection_spec`) already classifies these sessions as `known_bot` — but still processes them fully (24 DB queries, 400-2000ms each). This spec adds two layers of defense: IP-based rate limiting and early rejection of known bots before any DB work.

---

## Current State

### Data Flow (Current)

```
SDK POST /api/v1/sessions
  → BaseController#authenticate_api_key (DB: find account)
  → SessionsController#create
  → Sessions::CreationService#run
    → validation (visitor_id, session_id, url present?)
    → idempotency check (find by request_id)
    → pg_advisory_xact_lock
    → find_or_create visitor (multiple queries)
    → find_or_initialize session
    → BotClassifier.call → sets suspect/suspect_reason
    → session.save! (with all attributes)
    → Billing::UsageCounter.increment!
  → 202 Accepted (always, even for bots)
```

**Problem:** Known bots hit the full pipeline — advisory lock, visitor resolution, session creation, billing increment — before being classified. Every bot request costs 11-24 DB queries.

### Key Files

| File | Current Role |
|------|-------------|
| `app/controllers/api/v1/sessions_controller.rb` | Delegates to CreationService, no rate limiting |
| `app/controllers/api/v1/base_controller.rb` | Rate limiting disabled (commented out) |
| `app/services/sessions/creation_service.rb` | Full processing pipeline, bot classification at save time |
| `app/services/sessions/bot_classifier.rb` | Classifies UA but result only used for column values |
| `app/services/api_keys/rate_limiter_service.rb` | Per-account rate limiter (disabled, cache-based) |

---

## Proposed Solution

Two layers, both cheap and stateless:

### Layer 1: Rails 8 `rate_limit` on Sessions Controller

Rails 8 ships `ActionController::RateLimiting` — built-in, uses `ActiveSupport::Cache` (SolidCache), zero dependencies. Throttle per-IP on the sessions endpoint.

```
POST /api/v1/sessions (IP: 172.69.23.140)
  → rate_limit check (cache read, ~1ms)
  → if exceeded: 429 Too Many Requests (zero DB work)
  → if allowed: proceed to authenticate + create
```

### Layer 2: Early Bot Rejection in CreationService

Move bot classification **before** the heavy DB work. When UA matches a known bot, return success immediately with `suspect: true` — no visitor, no session, no billing, no advisory lock.

```
Sessions::CreationService#run
  → validation
  → idempotency check
  → **classify UA** ← moved here
  → if known_bot: return success (fake session_id, no DB writes)
  → pg_advisory_xact_lock
  → find_or_create visitor
  → find_or_initialize session
  → session.save!
  → 202 Accepted
```

### Data Flow (Proposed)

```
SDK POST /api/v1/sessions
  → Rails rate_limit (per-IP, cache-only)         ← NEW: Layer 1
    → 429 if exceeded
  → BaseController#authenticate_api_key
  → SessionsController#create
  → Sessions::CreationService#run
    → validation
    → idempotency check
    → BotClassifier.call                           ← MOVED: before DB work
    → if known_bot: return success (no DB writes)  ← NEW: Layer 2
    → pg_advisory_xact_lock
    → process_visitor
    → process_session (classification already done)
    → 202 Accepted
```

### Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Rate limit scope | Per real client IP, sessions endpoint only | All traffic proxied through Cloudflare. `request.remote_ip` returns Cloudflare edge IPs, not real clients. Use `CF-Connecting-IP` header for true client IP. Per-account would penalise legitimate high-volume customers. |
| Rate limit threshold | 10 requests per 3 seconds | Legitimate SDKs send 1 session per page load. 10/3s is generous for real traffic, blocks sustained floods. |
| IP source | `CF-Connecting-IP` header | Cloudflare sets this to the real client IP. Falls back to `request.remote_ip` if header absent (non-Cloudflare environments like dev). |
| Bot rejection response | 202 with fake success | SDKs don't retry on 202. A 4xx would trigger SDK retry logic, making the flood worse. |
| Bot rejection — skip billing? | Yes, skip | Bots shouldn't consume usage quota. No visitor/session created = no billable record. |
| Spam referrer / no_signals | Still process fully | Only `known_bot` (UA-matched) gets early rejection. Spam referrers and no-signal sessions may be real users and need full processing for data integrity. |
| Rate limit backing store | SolidCache (default) | Already configured. Rails 8 `rate_limit` uses `ActiveSupport::Cache` which maps to SolidCache in production. |

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Normal traffic | < 10 req/3s per IP | 202 Accepted, full processing |
| Rate limited | > 10 req/3s per IP | 429 Too Many Requests, `Retry-After` header, zero DB work |
| Known bot, under rate limit | UA matches bot pattern | 202 Accepted, no DB writes, no billing |
| Known bot, over rate limit | UA matches + flood | 429 (rate limit fires first, before auth) |
| Spam referrer | IP referrer or known spam domain | Full processing, `suspect_reason: "spam_referrer"` (unchanged) |
| No signals | No referrer, UTMs, or click_ids | Full processing, `suspect_reason: "no_signals"` (unchanged) |
| Legitimate burst | Real user with fast navigations | Under 10/3s threshold; session continuity handles reuse |
| Bot patterns not loaded | Cache empty, sync failed | `BotPatterns::Matcher.bot?` returns false — degrades to full processing (safe default) |

---

## Implementation

### Phase 1: Rate Limiting

- [x] **1.1** Add `rate_limit to: 10, within: 3.seconds, by: -> { real_client_ip }` to `Api::V1::SessionsController`
- [x] **1.2** Add `real_client_ip` helper to `Api::V1::BaseController` — reads `CF-Connecting-IP` header, falls back to `request.remote_ip`
- [x] **1.3** Override `rate_limit_exceeded` to return JSON `{ error: "Rate limit exceeded" }` with 429 status (via `with:` lambda)
- [x] **1.4** Write tests: 3 tests — under limit (202), over limit (429 JSON), CF-Connecting-IP keying

### Phase 2: Early Bot Rejection

- [x] **2.1** Add `known_bot?` check before DB work in `CreationService#run`
- [x] **2.2** When `known_bot?`, return `success_result` immediately with passed-through `visitor_id`, `session_id`, `channel: "bot"` — no visitor/session/billing
- [x] **2.3** Non-bot classification still handled by `BotClassifier` at save time (unchanged)
- [x] **2.4** Write tests: 6 tests — bot skips DB, bot skips billing, bot passthrough IDs, bot channel="bot", spam referrer still processes, graceful degradation when patterns unavailable

### Phase 3: Deploy + Validate

- [ ] **3.1** Deploy to production
- [ ] **3.2** Monitor rate limit 429s in logs (should only hit during bot floods)
- [ ] **3.3** Verify legitimate SDK traffic unaffected (all 202s)
- [ ] **3.4** Update `session_bot_detection_spec` Phase 4 as complete

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Rate limit allows normal traffic | `test/controllers/api/v1/sessions_controller_test.rb` | 10 requests in 3s all return 202 |
| Rate limit blocks floods | `test/controllers/api/v1/sessions_controller_test.rb` | 11th request in 3s returns 429 JSON |
| Rate limit uses real client IP | `test/controllers/api/v1/sessions_controller_test.rb` | `CF-Connecting-IP` header used over `remote_ip` |
| Bot UA skips DB work | `test/services/sessions/creation_service_test.rb` | No Visitor/Session created, returns success |
| Bot UA skips billing | `test/services/sessions/creation_service_test.rb` | `Billing::UsageCounter` not called |
| Non-bot still processes | `test/services/sessions/creation_service_test.rb` | Visitor + Session created, classification applied |
| Spam referrer still processes | `test/services/sessions/creation_service_test.rb` | Full pipeline, `suspect_reason: "spam_referrer"` |
| Bot patterns unavailable | `test/services/sessions/creation_service_test.rb` | Degrades to full processing |

### Manual QA

1. Deploy to production
2. `curl` sessions endpoint 15 times rapidly from same IP — verify 429 after 10th
3. Check logs for bot sessions — should see no DB queries after classification
4. Verify dashboard session counts — bot sessions should not appear

---

## Definition of Done

- [ ] Rate limiting active on sessions endpoint
- [ ] Known bots rejected before DB work
- [ ] Tests pass (unit + existing suite)
- [ ] No regressions in session creation for legitimate traffic
- [ ] Spec updated with final state
- [ ] `session_bot_detection_spec` Phase 4 marked complete

---

## Out of Scope

- **Rate limiting on other endpoints** (events, conversions, identify) — can be added later with same pattern
- **Per-account rate limiting** — existing `RateLimiterService` handles this; re-enable separately
- **Cloudflare WAF rules** — complementary but outside the Rails app
- **Behavioral bot detection** — post-hoc reclassification, separate spec
- **Datacenter IP detection** — separate spec per bot detection roadmap
