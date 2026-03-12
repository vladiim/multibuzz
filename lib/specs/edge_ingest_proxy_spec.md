# Edge Ingest Proxy Specification

**Date:** 2026-03-12
**Priority:** P0
**Status:** In Progress
**Branch:** `feature/edge-ingest-proxy`

---

## Summary

When mbuzz goes down, customer data is lost. Sessions, events, conversions sent during an outage vanish. Pre-revenue this is embarrassing; post-revenue it's catastrophic. The fix is an edge ingest proxy — a Cloudflare Worker on `api.mbuzz.co` that accepts SDK payloads, durably stores them in R2, and replays them to the Rails API with infinite retry. The proxy is the only endpoint SDKs talk to. The Rails app becomes a processing backend that can go down without losing a single event.

---

## Current State

### Data Flow (Current)

```
SDK → POST mbuzz.co/api/v1/{endpoint} → Rails app → PostgreSQL
                                              ↓
                                         (app down = data lost)
```

SDKs send HTTP requests directly to the Rails app. If the app is unreachable (deploy, crash, DB issue, OOM), the request fails and the SDK drops it. There is no retry, no buffer, no fallback. Every outage is a data gap.

### Evidence of the Problem

- Multiple production outages have caused data loss (Kamal deploys, PG saturation, Puma crashes)
- Single-server architecture (`68.183.173.51`) — zero redundancy
- `SOLID_QUEUE_IN_PUMA=true` — job processing shares the same process as HTTP serving
- No CDN or edge layer in front of the API
- SDKs are fire-and-forget — no client-side retry or local buffering

### Current API Surface

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/sessions` | POST | Create session (visitor + UTM + channel) |
| `/api/v1/events` | POST | Track events (batch) |
| `/api/v1/conversions` | POST | Track conversions + trigger attribution |
| `/api/v1/identify` | POST | Link visitor to user identity |
| `/api/v1/validate` | GET | Validate API key |
| `/api/v1/health` | GET | Health check |

Authentication: `Authorization: Bearer sk_{env}_{32hex}` on every request. Session creation also requires `X-Forwarded-For` and `X-Mbuzz-User-Agent` headers.

---

## Proposed Solution

### Architecture

A Cloudflare Worker sits at the edge on `api.mbuzz.co`. It accepts the exact same requests SDKs already send, stores each payload durably in Cloudflare R2, and immediately attempts to forward it to the Rails API. A cron-triggered replay worker catches anything that didn't forward successfully.

### Data Flow (Proposed — Option A + Y, decided 2026-03-13)

```
SDK → POST api.mbuzz.co/api/v1/{endpoint}
        ↓
  Cloudflare Worker (edge, 300+ PoPs, ~0ms cold start)
        ↓
  1. Store raw request to R2 (durable, pending/)
  2. Attempt synchronous forward to mbuzz.co (5s timeout)
        ↓
  Forward succeeds (99% of time):
    → Return full Rails response to SDK (channel, event_ids, attribution — identical to direct)
    → Move R2 object to archive/{api_key}/... (permanent record)
  Forward fails (Rails down):
    → Return simplified 202: { "status": "accepted", "request_id": "req_..." }
    → Object stays in pending/ for replay
        ↓
  Replay Worker (CF cron, every 1 min)
        ↓
  Process pending/ in DEPENDENCY ORDER: sessions → events → conversions → identify
  On success → move to archive/
  On permanent 4xx → move to failed/
  On retryable error (5xx, 429, "Visitor not found") → leave in pending/
```

**SDK fallback (Option Y):** If proxy is unreachable (CF outage), SDKs fall back to `mbuzz.co/api/v1` directly. Configurable, enabled by default. The degraded 202 (no channel/event_ids) only appears when Rails is down AND the SDK has no fallback — effectively never.

### Why Cloudflare Workers + R2

DigitalOcean Functions was the initial idea, but research rules it out:

| Criterion | DO Functions | CF Workers + R2 |
|-----------|-------------|-----------------|
| **SLA** | None published | **99.9%** |
| **Cold start** | 400-600ms | **~0ms** (V8 isolates) |
| **Rate limit** | 600/min (~10 req/s) | **Effectively unlimited** |
| **Concurrency** | 120 per namespace | **Unlimited** |
| **Object storage binding** | SDK call over network | **Native binding (no network hop)** |
| **Edge PoPs** | 0 (single region) | **300+** |
| **DDoS protection** | None | **Built-in** |
| **Egress fees** | $0.01/GB | **Free forever** |

DO Functions' 600 invocations/minute hard cap is a dealbreaker. A single busy customer could exhaust it. CF Workers has no meaningful limit for our scale.

**Provider independence is a feature.** The proxy runs on Cloudflare. The app runs on DigitalOcean. If either provider has an outage, the other still functions — data is captured on CF, processed when DO recovers.

### Industry Precedent

This is the same pattern used by Segment, Snowplow, and RudderStack:

- **Segment**: SDK → Custom domain proxy → Tracking API → Internal queues → Destinations
- **Snowplow**: Collector → Kinesis stream → S3 archive → Enrich → Warehouse
- **RudderStack**: Collector → Internal buffer → Warehouse loader

All separate the "accept and durably store" step from the "process and persist" step. The ingest layer is a simple, highly available proxy. The processing layer is a complex, sometimes-failing application.

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Platform | Cloudflare Workers + R2 | No cold starts, 300+ PoPs, 99.9% SLA, native R2 binding, ~$50/mo at 10M events. DO Functions has no SLA and caps at 10 req/s. |
| Proxy behavior | Store-first, forward-optimistically | R2 write completes before 202 is returned (durability guarantee). Forward to Rails attempted async via `waitUntil()` — near-real-time when app is up, graceful degradation when down. |
| Replay worker location | CF Worker cron trigger | Independent of Rails — replays even if we're mid-deploy or recovering from a crash. Cron runs every 1 minute. |
| Retry strategy | Infinite retry with full jitter backoff | Never give up on customer data. Full jitter minimizes thundering herd on recovery. Dead letter only for permanent 4xx validation errors. |
| SDK change | New default base URL | SDKs already support configurable base URL. Change default from `mbuzz.co` to `api.mbuzz.co`. Same request format, same auth. Backwards-compatible. |
| Delivery guarantee | At-least-once with idempotent processing | Replay may forward a payload that was already processed (race between immediate forward and replay). Rails API handles duplicates via idempotency keys. |
| Custom domain | `api.mbuzz.co` | Industry standard (`api.` used by Stripe, Segment, Twilio). First-party subdomain, no ad-blocker issues. Clean separation from the app domain. |
| Response format | **Option A: Synchronous pass-through** (decided 2026-03-13) | Proxy forwards synchronously to Rails and returns the full Rails response (channel, event_ids, attribution). Falls back to simplified 202 only when Rails is unreachable. See "Decisions Made" section for full analysis. |
| SDK fallback | **Option Y: Configurable fallback** (decided 2026-03-13) | SDKs try `api.mbuzz.co` first, fall back to `mbuzz.co/api/v1` on timeout/5xx. Enabled by default, configurable. See "Decisions Made" section. |
| Archive | **Archive all payloads** (decided 2026-03-13) | On success, move R2 objects to `archive/{api_key}/...` instead of deleting. Permanent immutable event log for disaster recovery + reconciliation. |

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| **Happy path (app up)** | R2 write succeeds, sync forward succeeds | SDK gets full Rails response (channel, event_ids, etc.). R2 object moved to `archive/`. ~150ms total. |
| **App down** | R2 write succeeds, sync forward fails (5xx/timeout) | SDK gets simplified 202 receipt. Data safe in R2 `pending/`. Replay worker retries every minute until app recovers. |
| **App slow** | R2 write succeeds, forward times out (>5s) | Same as app down. Object stays in `pending/`, replay worker handles it. |
| **CF down, app up** | SDK can't reach proxy | SDK falls back to `mbuzz.co/api/v1` directly (Option Y). Full Rails response. No R2 involvement. |
| **Both down** | SDK can't reach proxy or Rails | SDK returns false. Data lost. Same as today — but requires simultaneous CF + DO outage. |
| **Partial outage** | Some forwards succeed, some fail | Each request independent. Successful ones archived, failed ones retried. |
| **R2 write fails** | Cloudflare internal error | Worker returns 503 to SDK. SDK falls back to direct Rails (Option Y). Extremely rare — R2 has 99.999999999% durability. |
| **Invalid API key format** | Key doesn't match `sk_{env}_{hex}` | Worker returns 401 immediately. No R2 write (saves storage on garbage requests). |
| **Replay processes duplicate** | Sync forward succeeded but R2 object not yet archived | Rails API receives duplicate. Idempotency key prevents double-processing. |
| **Retryable validation error** | Rails returns 422 "Visitor not found" | Replay worker leaves in `pending/` for retry. Session hasn't been replayed yet — will succeed on next run after sessions are processed. |
| **Permanent validation error** | Rails returns 400/422 (not "Visitor not found") | Replay worker moves to `failed/` prefix (dead letter). Never retried. |
| **Rate limited** | Rails returns 429 | Replay worker stops batch, retries next run. |
| **Large backlog after outage** | Hours of accumulated payloads | Replay worker processes in dependency order (sessions → events → conversions → identify), 100 per endpoint per run. |
| **Malformed request** | Non-JSON body, missing Content-Type | Worker returns 400. No R2 write. |

---

## Technical Design

### Ingest Worker (HTTP Trigger)

The edge worker handling SDK requests.

```
Routes:
  POST /api/v1/sessions     → store + forward
  POST /api/v1/events       → store + forward
  POST /api/v1/conversions  → store + forward
  POST /api/v1/identify     → store + forward
  GET  /api/v1/health       → { "status": "ok" } (proxy health, no forwarding)
  *    *                     → 404
```

**R2 object key format:**
```
pending/{endpoint}/{YYYY}/{MM}/{DD}/{HH}/{timestamp_ms}-{uuid}.json
```

Example: `pending/events/2026/03/12/14/1741789200000-a1b2c3d4.json`

**Stored payload structure:**
```json
{
  "method": "POST",
  "path": "/api/v1/events",
  "headers": {
    "authorization": "Bearer sk_live_abc123...",
    "content-type": "application/json",
    "x-forwarded-for": "203.0.113.42",
    "x-mbuzz-user-agent": "Mozilla/5.0..."
  },
  "body": { "events": [{ "event_type": "page_view", ... }] },
  "received_at": "2026-03-12T14:00:00.000Z",
  "request_id": "req_a1b2c3d4e5f6"
}
```

**Validation before storage:**
- Method is POST (except health GET)
- Path matches known endpoints
- `Authorization` header present and matches `Bearer sk_(test|live)_[a-f0-9]{32}` format
- Body is valid JSON
- Body size < 1MB (CF Worker limit, also reasonable for analytics payloads)

**Response to SDK (Option A — synchronous pass-through):**

When Rails is up (99%+):
```
Proxy forwards synchronously → returns full Rails response verbatim
→ moves R2 object to archive/{api_key}/... (async via waitUntil)
```

When Rails is down:
```json
{
  "status": "accepted",
  "request_id": "req_a1b2c3d4e5f6"
}
```

**Proxy ingest flow (conceptual):**
```typescript
// 1. Store to R2 (durable — data is safe before we do anything else)
await env.INGEST_BUCKET.put(key, JSON.stringify(payload));

// 2. Try synchronous forward to Rails (5s timeout)
try {
  const response = await forwardToOrigin(env, payload);
  if (response.ok) {
    // 2xx — Rails processed it. Archive R2 object, return Rails response.
    ctx.waitUntil(moveToArchive(env.INGEST_BUCKET, key));
    return new Response(await response.text(), {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }
  if (response.status >= 400 && response.status < 500 && response.status !== 429) {
    // 4xx (client error) — pass through Rails error. Delete R2 (bad request, no value).
    ctx.waitUntil(env.INGEST_BUCKET.delete(key));
    return new Response(await response.text(), {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }
  // 5xx or 429 — Rails down or rate-limited, leave in pending for replay
} catch {
  // Forward failed (timeout/network) — leave in pending for replay
}

// 3. Rails unreachable — return receipt, replay worker will handle it
return jsonResponse({ status: "accepted", request_id: requestId }, 202);
```

### Replay Worker (Cron Trigger)

Runs every 1 minute. Processes pending objects in **dependency order** to prevent "Visitor not found" errors during outage recovery.

```
Every 1 minute:
  1. Process pending/sessions/  (limit 100, oldest first) — creates Visitors
  2. Process pending/events/    (limit 100, oldest first) — needs Visitors
  3. Process pending/conversions/ (limit 100, oldest first) — needs Visitors + Events
  4. Process pending/identify/  (limit 100, oldest first) — needs Visitors

  For each object:
     a. GET object from R2
     b. Forward request to https://mbuzz.co/api/v1/{path}
     c. On 2xx → MOVE to archive/{api_key}/... (permanent record)
     d. On 422 "Visitor not found" → LEAVE in pending/ (session not yet replayed, retry next run)
     e. On 4xx (not 429, not retryable 422) → MOVE to failed/ (dead letter)
     f. On 429 → stop processing this endpoint, move to next
     g. On 5xx/timeout → leave in pending/ (retry next run)

  Circuit breaker check before processing.
```

**Why dependency order matters:**

R2 lists objects lexicographically. Without ordering, replay processes:
`conversions/` → `events/` → `identify/` → `sessions/` (alphabetical).
Sessions create Visitors. Events/conversions/identify need Visitors to exist.
If events replay before sessions → "Visitor not found" → data loss.

The fix: 4 separate `R2.list()` calls in dependency order.

**Retryable vs permanent 422s:**

| Rails 422 Response | Action | Why |
|-------------------|--------|-----|
| "Visitor not found" | Leave in `pending/` | Session hasn't been replayed yet — will succeed next run |
| "event_type is required" | Move to `failed/` | Permanent validation error — will never succeed |
| "Billing blocked" | Leave in `pending/` | Temporary — may succeed when billing is resolved |

The replay worker checks the response body for known retryable error messages before deciding to dead-letter.

**Batch processing rules:**
- Max 100 objects per endpoint per run (prevent Worker timeout)
- 5-second timeout per forwarded request
- Process sequentially within a batch (respect rate limits)
- FIFO within each endpoint: oldest objects processed first

**Circuit breaker:**
- Track consecutive failures in a durable object (`_meta/circuit_breaker.json`)
- After 5 consecutive full-batch failures: enter open state
- Open state: skip processing for 5 minutes
- After 5 minutes: half-open, process 1 object as probe
- Probe success: close circuit, resume normal processing
- Probe failure: reopen for another 5 minutes

### Rails API Changes (Idempotency)

The Rails API must handle duplicate requests from the store-and-forward pattern.

**Idempotency key flow:**
1. Proxy generates `request_id` (UUID) for each incoming request
2. Proxy includes `X-Idempotency-Key: {request_id}` when forwarding to Rails
3. Rails checks if `request_id` was already processed
4. If duplicate: return original response, no side effects

**Implementation:**
- Add `request_id` column (string, indexed, nullable) to `events`, `sessions`, `conversions`
- `UNIQUE` index on `(account_id, request_id)` where `request_id IS NOT NULL`
- Service layer checks for existing record before creating
- Idempotency is optional — requests without the header are processed normally (backwards-compatible)

### SDK Changes

All SDKs need a new minor version (0.8.0):

1. **Default base URL**: `https://mbuzz.co/api/v1` → `https://api.mbuzz.co/api/v1`
2. **Fallback URL**: `https://mbuzz.co/api/v1` (default, configurable, set `nil` to disable)
3. **Fallback logic**: On proxy timeout (5s) or 5xx, retry once to `fallback_url`. Requires Phase 2 (idempotency) deployed first.
4. **Dual-response guard**: `track()` and `conversion()` must handle the degraded 202 gracefully — return `{ success: true }` with nil IDs instead of `false`. This only triggers when Rails is down AND fallback also fails (effectively never with A+Y).
5. **Configurable**: Users can override primary URL to point directly at `mbuzz.co` if they prefer

SDK version matrix:

| SDK | Repo | Current Version | New Version | Change |
|-----|------|----------------|-------------|--------|
| Ruby | `mbuzzco/mbuzz-ruby` | 0.7.5 | 0.8.0 | Default URL in `lib/mbuzz/configuration.rb` |
| Node.js | `mbuzzco/mbuzz-node` | 0.7.5 | 0.8.0 | Default URL in `src/config.ts` |
| Python | `mbuzzco/mbuzz-python` | 0.7.5 | 0.8.0 | Default URL in `src/mbuzz/config.py` |
| PHP | `mbuzzco/mbuzz-php` | 0.7.5 | 0.8.0 | Default URL in `src/Mbuzz/Config.php` |
| Shopify | (private) | live | — | 3 files: pixel `index.js`, tracking `mbuzz-shopify.js`, `tracking.liquid` |
| sGTM | `mbuzzco/mbuzz-sgtm` | live | — | 2 locations in `template.tpl` |
| REST API | N/A | N/A | N/A | Update curl examples in `sdk_registry.yml` + API docs |

### Cloudflare Configuration

**DNS:**
- `api.mbuzz.co` → Cloudflare Worker route (proxied, orange cloud)
- Managed in Cloudflare dashboard (mbuzz.co zone must be on Cloudflare)

**R2 Bucket:**
- Name: `mbuzz-ingest-buffer`
- Region: Auto (closest to origin for replay)
- Lifecycle rules:
  - `archive/` → Transition to Infrequent Access after 30 days
  - `archive/` → Auto-delete after 25 months (CNIL recommendation)
  - `failed/` → Auto-delete after 90 days

**Worker bindings:**
- `INGEST_BUCKET` → R2 bucket `mbuzz-ingest-buffer`
- `ORIGIN_URL` → `https://mbuzz.co` (env variable)

---

## Cost Estimate

At 10M events/month (growth target):

| Item | Cost |
|------|------|
| CF Workers (10M requests included in $5/mo plan) | $5/mo |
| R2 Class A ops — ingest PUTs (10M) | ~$45/mo |
| R2 Class A ops — archive PUTs (10M moves) | ~$45/mo |
| R2 Class B ops (archive GETs for move + rare replay) | ~$4/mo |
| R2 storage (archive grows ~10GB/mo, IA after 30d) | ~$1-2/mo |
| R2 egress | **Free** |
| **Total** | **~$100/mo** |

At current scale (pre-revenue, low traffic): effectively **$5/mo** (Worker plan minimum).

Comparable alternatives:
- AWS Lambda + S3: ~$55/mo (egress fees add up)
- DO App Platform + Spaces: ~$22/mo (but no edge, no SLA on Functions, 10 req/s cap on Functions)
- DO Functions: **Not viable** (600 invocations/min hard cap)

---

## Implementation Tasks

### Phase 1: Cloudflare Infrastructure ✅

- [x] **1.1** Add mbuzz.co domain to Cloudflare — DNS migrated from Namecheap, SSL Full (strict), cache bypass rule, email obfuscation off, auto minify off, rocket loader off
- [x] **1.2** Create R2 bucket `mbuzz-ingest-buffer` (lifecycle rules TODO — add via CF dashboard)
- [x] **1.3** Create Cloudflare Worker project (`mbuzz-ingest-proxy`) — repo at `../mbuzz-ingest-proxy/`, wrangler config with R2 binding + env vars
- [x] **1.4** Write ingest Worker: validate → store R2 → return 202 → forward via `waitUntil()` (constants-based, ~320 lines)
- [x] **1.5** Write replay Worker (cron `* * * * *`): list pending → forward → circuit breaker (5 failures → 5min cooldown → half-open probe)
- [x] **1.6** Configure `api.mbuzz.co` DNS: AAAA record `api` → `100::` (proxied) + Worker route `api.mbuzz.co/*`
- [x] **1.7** Deploy Worker, E2E verified: `curl` → proxy → R2 → forward → Rails → PostgreSQL (visitor 1244725, session 1482635, event 42086 created in prod)
- [x] **1.8** Write Worker tests (Vitest + `@cloudflare/vitest-pool-workers` — 29 tests covering validation, sync pass-through, archive, dependency ordering, retryable 422s, circuit breaker)

### Phase 1b: Proxy Code Updates ✅ (decided 2026-03-13, implemented 2026-03-12)

Updated the Worker to implement A+Y decisions. TDD: RED tests first, then GREEN implementation.

- [x] **1b.1** Sync pass-through: `handleIngest()` forwards synchronously (5s timeout), returns Rails response verbatim on success, falls back to 202 on failure
- [x] **1b.2** Archive on success: `moveToArchive()` copies to `archive/{api_key}/{endpoint}/{date}/{timestamp}-{uuid}.json`, deletes original from `pending/`
- [x] **1b.3** Dependency-ordered replay: `handleReplay()` makes 4 sequential `R2.list()` calls: `pending/sessions/`, `pending/events/`, `pending/conversions/`, `pending/identify/`
- [x] **1b.4** Retryable 422 handling: `isRetryableError()` checks response body for "Visitor not found" and "Billing blocked" → leaves in `pending/` instead of dead-lettering
- [x] **1b.5** `extractApiKey()` + `buildArchiveKey()` extract API key from `headers.authorization` for archive path
- [x] **1b.6** 32 tests: 7 validation, 5 sync pass-through, 3 4xx pass-through (client errors returned to SDK, R2 deleted), 4 archive, 3 dependency ordering, 2 replay archive, 6 retryable 422, 2 circuit breaker
- [ ] **1b.7** Deploy updated Worker, E2E verify: session → event → conversion → identify through proxy with full Rails responses

### Phase 2: Rails Idempotency Layer

- [ ] **2.1** Add migration: `request_id` column (string, nullable) to `sessions`, `events`, `conversions`
- [ ] **2.2** Add unique index: `(account_id, request_id)` where `request_id IS NOT NULL`
- [ ] **2.3** Update `Sessions::CreationService` — check for existing `request_id` before creating
- [ ] **2.4** Update `Events::IngestionService` — check for existing `request_id` before creating
- [ ] **2.5** Update `Conversions::TrackingService` — check for existing `request_id` before creating (note: conversions already have `idempotency_key` — wire `request_id` through same mechanism)
- [ ] **2.6** Update `Api::V1::BaseController` — extract `X-Idempotency-Key` header, pass to services
- [ ] **2.7** Write tests for idempotency: duplicate request returns original response, no double-counting
- [ ] **2.8** Write tests for backwards compatibility: requests without idempotency key still work

### Phase 3: SDK Updates

Each SDK change is the same: update the default base URL from `https://mbuzz.co/api/v1` to `https://api.mbuzz.co/api/v1`. The old URL remains a supported fallback — users can always override back to `mbuzz.co` via the existing config option.

#### 3.1 Ruby SDK (`mbuzz-ruby`) — 0.7.5 → 0.8.0

- [ ] Repo: `github.com/mbuzzco/mbuzz-ruby` (local: `../mbuzz-ruby/`)
- [ ] File: `lib/mbuzz/configuration.rb:29`
- [ ] Change: `@api_url = "https://mbuzz.co/api/v1"` → `@api_url = "https://api.mbuzz.co/api/v1"`
- [ ] Bump version in gemspec to `0.8.0`
- [ ] Update CHANGELOG
- [ ] `gem build && gem push`

#### 3.2 Node.js SDK (`mbuzz-node`) — 0.7.5 → 0.8.0

- [ ] Repo: `github.com/mbuzzco/mbuzz-node` (local: `../mbuzz-node/`)
- [ ] File: `src/config.ts:11`
- [ ] Change: `const DEFAULT_API_URL = 'https://mbuzz.co/api/v1'` → `const DEFAULT_API_URL = 'https://api.mbuzz.co/api/v1'`
- [ ] Bump version in `package.json` to `0.8.0`
- [ ] Update CHANGELOG
- [ ] `npm publish`

#### 3.3 Python SDK (`mbuzz-python`) — 0.7.5 → 0.8.0

- [ ] Repo: `github.com/mbuzzco/mbuzz-python` (local: `../mbuzz-python/`)
- [ ] File: `src/mbuzz/config.py:6`
- [ ] Change: `DEFAULT_API_URL = "https://mbuzz.co/api/v1"` → `DEFAULT_API_URL = "https://api.mbuzz.co/api/v1"`
- [ ] Bump version in `pyproject.toml` to `0.8.0`
- [ ] Update CHANGELOG
- [ ] `python -m build && twine upload dist/*`

#### 3.4 PHP SDK (`mbuzz-php`) — 0.7.5 → 0.8.0

- [ ] Repo: `github.com/mbuzzco/mbuzz-php` (local: `../mbuzz-php/`)
- [ ] File: `src/Mbuzz/Config.php:11`
- [ ] Change: `private const DEFAULT_API_URL = 'https://mbuzz.co/api/v1'` → `private const DEFAULT_API_URL = 'https://api.mbuzz.co/api/v1'`
- [ ] Bump version in `composer.json` to `0.8.0`
- [ ] Update CHANGELOG
- [ ] Tag release (Packagist auto-publishes from GitHub tags)

#### 3.5 Shopify App (`mbuzz-shopify`) — 3 files

- [ ] Repo: local `../mbuzz-shopify/` (no public GitHub repo)
- [ ] File 1: `extensions/mbuzz-pixel/src/index.js:8`
  - Change: `const API_URL = "https://mbuzz.co/api/v1"` → `const API_URL = "https://api.mbuzz.co/api/v1"`
- [ ] File 2: `extensions/mbuzz-tracking/assets/mbuzz-shopify.js:14`
  - Change: default fallback `'https://mbuzz.co/api/v1'` → `'https://api.mbuzz.co/api/v1'`
- [ ] File 3: `extensions/mbuzz-tracking/blocks/tracking.liquid:4` and `:38`
  - Change: default value `"https://mbuzz.co/api/v1"` → `"https://api.mbuzz.co/api/v1"` (both the Liquid default and the schema default)
- [ ] Deploy via `shopify app deploy`

#### 3.6 sGTM Tag (`mbuzz-sgtm`) — 2 locations in 1 file

- [ ] Repo: `github.com/mbuzzco/mbuzz-sgtm` (local: `../mbuzz-sgtm/`)
- [ ] File: `template.tpl`
  - Line 195: `var DEFAULT_API_URL = 'https://mbuzz.co/api/v1'` → `var DEFAULT_API_URL = 'https://api.mbuzz.co/api/v1'`
  - Line 140: `"defaultValue": "https://mbuzz.co/api/v1"` → `"defaultValue": "https://api.mbuzz.co/api/v1"`
- [ ] Push to GitHub (GTM Community Template Gallery auto-syncs)

#### 3.7 REST API Docs (mbuzz main repo)

- [ ] File: `config/sdk_registry.yml` — update `rest_api.event_code`, `rest_api.conversion_code`, `rest_api.identify_code` curl examples from `https://mbuzz.co/api/v1/` → `https://api.mbuzz.co/api/v1/`
- [ ] Update any API reference docs pages that hardcode the old URL

#### 3.8 Documentation

- [ ] Update `lib/docs/sdk/api_contract.md` — document proxy behavior, 202 response format, `X-Idempotency-Key` header, permanent dual-endpoint policy
- [ ] Update API docs pages — recommend `api.mbuzz.co` as primary, document `mbuzz.co` as permanent direct fallback

#### 3.9 Integration Testing

- [ ] Run E2E integration tests (`sdk_integration_tests/`) against `api.mbuzz.co` for each SDK
- [ ] Verify session → event → conversion → identify flow through proxy for at least Ruby + Node

### Phase 4: Monitoring + Observability

- [ ] **4.1** CF Worker analytics: track request count, latency, error rate (built-in CF dashboard)
- [ ] **4.2** R2 metrics: track pending object count (alert if > 1000 — indicates app is down or replay is stuck)
- [ ] **4.3** Dead letter alerting: alert when objects land in `failed/` prefix
- [ ] **4.4** Replay lag metric: track age of oldest pending object (alert if > 10 minutes)
- [ ] **4.5** Add proxy status to the existing `/api/v1/health` endpoint on Rails (or separate status page)

### Phase 5: Documentation

- [ ] **5.1** Document Cloudflare setup in `lib/docs/architecture/edge_ingest_proxy.md` — account details, DNS config, R2 bucket, Worker bindings, cron schedule, Cloudflare dashboard settings (SSL Full Strict, bypass cache, email obfuscation off, etc.)
- [ ] **5.2** Update `lib/docs/sdk/api_contract.md` — document `api.mbuzz.co` as primary endpoint, proxy 202 response format, `X-Idempotency-Key` header, direct `mbuzz.co/api/v1` as permanent fallback
- [ ] **5.3** Update `lib/docs/PRODUCT.md` — mention edge proxy as part of platform reliability
- [ ] **5.4** Update `lib/docs/BUSINESS_RULES.md` — dual-endpoint behavior, idempotency semantics
- [ ] **5.5** Update `README.md` — link to architecture doc, note Cloudflare dependency
- [ ] **5.6** Add runbook to `lib/docs/architecture/edge_ingest_proxy.md` — how to check R2 pending count, how to flush dead letters, how to bypass proxy in an emergency, how to deploy Worker updates

---

## Testing Strategy

### Worker Tests (Miniflare / Vitest)

| Test | Verifies |
|------|----------|
| POST to valid endpoint + Rails up → full Rails response returned | Sync pass-through |
| POST to valid endpoint + Rails 401 → 401 passed through to SDK | 4xx pass-through |
| POST to valid endpoint + Rails 422 → 422 passed through to SDK | 4xx pass-through |
| POST to valid endpoint + Rails 4xx → R2 object deleted (bad request) | 4xx cleanup |
| POST to valid endpoint + Rails down → 202 receipt | Graceful degradation |
| POST to valid endpoint → R2 object created in `pending/` | Durable storage |
| POST with invalid auth header → 401, no R2 write | Auth format validation |
| POST with non-JSON body → 400, no R2 write | Input validation |
| GET /api/v1/health → 200 | Proxy health (no R2 involvement) |
| POST to unknown path → 404 | Route validation |
| Stored object contains method, path, headers, body, request_id | Payload fidelity |
| Successful forward → R2 object moved to `archive/{api_key}/...` | Archive on success |
| Archive key contains correct API key, endpoint, date segments | Archive path format |
| Replay worker: processes sessions before events before conversions | Dependency ordering |
| Replay worker: pending object + 200 from origin → moved to `archive/` | Successful replay + archive |
| Replay worker: pending object + 500 from origin → object remains in `pending/` | Retry behavior |
| Replay worker: 422 "Visitor not found" → object remains in `pending/` | Retryable 422 |
| Replay worker: 422 "event_type is required" → moved to `failed/` | Permanent 422 → dead letter |
| Replay worker: 5 consecutive failures → circuit opens | Circuit breaker |
| Replay worker: circuit open + 5 min elapsed + probe succeeds → circuit closes | Circuit recovery |

### Rails Idempotency Tests

| Test | File | Verifies |
|------|------|----------|
| Session with `request_id` created once | `test/services/sessions/creation_service_test.rb` | No duplicate sessions |
| Same `request_id` returns original session | Same | Idempotent response |
| Event batch with `request_id` deduplicated | `test/services/events/ingestion_service_test.rb` | No duplicate events |
| Conversion with `request_id` deduplicated | `test/services/conversions/tracking_service_test.rb` | No duplicate conversions |
| Request without `X-Idempotency-Key` works normally | `test/controllers/api/v1/base_controller_test.rb` | Backwards compatibility |
| Cross-account: same `request_id` different accounts → both created | Service tests | Multi-tenancy isolation |

### E2E Tests

| Test | Verifies |
|------|----------|
| SDK → proxy → R2 → replay → Rails → PostgreSQL | Full pipeline |
| SDK → proxy (Rails down) → R2 → ... → (Rails up) → replay → PostgreSQL | Outage recovery |
| 100 events sent during "outage" → all 100 appear after recovery | Zero data loss |

### Manual QA

1. Deploy Worker to production
2. Send session + event + conversion via `curl` to `api.mbuzz.co`
3. Verify data appears in mbuzz dashboard within ~1 minute
4. Stop the Rails app (`kamal app stop`)
5. Send more events to the proxy — verify 202 responses
6. Check R2 bucket — pending objects accumulating
7. Start the Rails app (`kamal app boot`)
8. Wait 2-3 minutes — verify all pending events processed
9. Check R2 bucket — pending objects cleared
10. Check dashboard — no data gap

---

## Migration Plan

Rolling migration, no big bang:

1. **Deploy proxy** (Phase 1) — accepts traffic but SDKs still point to `mbuzz.co`
2. **Deploy idempotency** (Phase 2) — Rails handles duplicates, safe for dual traffic
3. **Update SDKs** (Phase 3) — gradual rollout, old SDK versions still work against `mbuzz.co`
4. **Monitor** (Phase 4) — verify proxy path stable
5. **Document** (Phase 5) — architecture docs, runbook, README

**Permanent dual-endpoint policy:** `mbuzz.co/api/v1` remains available forever as a direct fallback. If Cloudflare has a global outage, customers flip one SDK config value (`api_url: "https://mbuzz.co/api/v1"`) and bypass the proxy entirely. SDKs default to `api.mbuzz.co` but the direct path is a documented, supported, permanent option — not a deprecated legacy.

---

## Definition of Done

- [x] Cloudflare Worker deployed on `api.mbuzz.co`, accepting all 4 API endpoints
- [x] Proxy uses sync pass-through (full Rails response when up, 202 when down)
- [x] Proxy passes through 4xx client errors (401, 422) to SDK, deletes R2 object
- [x] Replay worker processes in dependency order (sessions → events → conversions → identify)
- [x] Replay worker handles retryable 422s (leaves in `pending/`, doesn't dead-letter)
- [x] R2 archive: successful payloads moved to `archive/{api_key}/...` (not deleted)
- [ ] R2 lifecycle rules: IA after 30d, delete archive after 25mo, delete failed after 90d
- [x] Circuit breaker preventing thundering herd on recovery
- [ ] Rails idempotency layer preventing duplicate processing
- [ ] All SDK defaults updated to `api.mbuzz.co` with configurable fallback to `mbuzz.co`
- [ ] SDKs handle degraded 202 gracefully (return `{ success: true }` with nil IDs, not `false`)
- [ ] E2E test: outage simulation with zero data loss
- [ ] E2E test: replay ordering verified (sessions before events before conversions)
- [ ] Monitoring: pending count, dead letters, replay lag
- [ ] API docs and `api_contract.md` updated
- [x] Architecture doc with full flow, Cloudflare setup, and runbook in `lib/docs/architecture/`
- [ ] Direct `mbuzz.co/api/v1` endpoint documented as permanent fallback
- [ ] Spec updated and moved to `old/`

---

## Decided: Response Contract & SDK Fallback (2026-03-13)

Two issues surfaced during implementation. Both resolved — Option A (sync pass-through) + Option Y (configurable fallback).

---

### Problem 1: Response Contract Mismatch

The proxy currently returns a simplified 202 for every request:

```json
{ "status": "accepted", "request_id": "req_a1b2c3d4e5f6" }
```

But the Rails API returns rich, endpoint-specific responses that the SDKs actively parse:

#### Rails Response Formats (Current)

**`POST /api/v1/sessions` → 202 Accepted:**
```json
{
  "status": "accepted",
  "visitor_id": "vis_...",
  "session_id": "sess_...",
  "channel": "paid_search"
}
```

**`POST /api/v1/events` → 202 Accepted:**
```json
{
  "accepted": 2,
  "rejected": [],
  "events": [
    { "id": "evt_...", "event_type": "page_view", "visitor_id": "vis_...", "session_id": "sess_...", "status": "accepted" }
  ]
}
```

**`POST /api/v1/conversions` → 201 Created:**
```json
{
  "conversion": { "id": "conv_...", "conversion_type": "signup", "revenue": "99.99", "converted_at": "...", "visitor_id": "vis_..." },
  "attribution": { "status": "pending" },
  "duplicate": false
}
```

**`POST /api/v1/identify` → 200 OK:**
```json
{
  "success": true,
  "identity_id": "idt_...",
  "visitor_linked": true
}
```

#### What Breaks in Each SDK

All 4 server-side SDKs have two HTTP methods: `post()` (fire-and-forget, returns bool) and `post_with_response()` (parses JSON, returns structured data). The track and conversion handlers use `post_with_response()`.

| SDK | File | What Breaks |
|-----|------|-------------|
| **Ruby** | `lib/mbuzz/session_request.rb` | `parse_response` checks `resp["status"] == "accepted"` then extracts `visitor_id`, `session_id`, `channel` — **`visitor_id` and `session_id` will be nil** |
| **Ruby** | `lib/mbuzz/track_request.rb` | Extracts `response.dig("events", 0, "id")` — **returns `false` (event not in proxy response)** |
| **Ruby** | `lib/mbuzz/conversion_request.rb` | Extracts `response.dig("conversion", "id")` — **returns `false`** |
| **Node** | `src/trackRequest.ts` | Checks `response?.events?.[0]?.id` — **returns `false`** |
| **Node** | `src/conversionRequest.ts` | Checks `response?.conversion?.id` — **returns `false`** |
| **Node** | `src/middleware/express.ts` | Session creation is fire-and-forget `void post()` — **safe** |
| **Python** | `src/mbuzz/client/track.py` | Checks `response.get("events")` — **returns `TrackResult(success=False)`** |
| **Python** | `src/mbuzz/client/conversion.py` | Checks `response` truthy then `response.get("conversion", {}).get("id")` — **returns `ConversionResult(success=False)`** |
| **Python** | `src/mbuzz/middleware/flask.py` | Session creation is fire-and-forget via `threading.Thread` — **safe** |
| **PHP** | `src/Mbuzz/Request/TrackRequest.php` | Checks `$response['events']` — **returns `false`** |
| **PHP** | `src/Mbuzz/Request/ConversionRequest.php` | Checks `$response` then `$response['conversion']['id']` — **returns `false`** |
| **PHP** | `src/Mbuzz/Client.php` | Session creation is fire-and-forget `$this->api->post()` — **safe** |

**Impact summary:**

| Call | Impact |
|------|--------|
| `session()` | Ruby: nil `visitor_id`/`session_id` returned. Node/Python/PHP: fire-and-forget, **safe**. |
| `track()` / `event()` | All SDKs: returns `false` despite data being accepted. Callers checking return value think it failed. |
| `conversion()` | All SDKs: returns `false`, no `conversion_id` or `attribution` data. |
| `identify()` | All SDKs: fire-and-forget `post()`, **safe**. |

**The data IS accepted and will be processed** — but the SDK tells the caller it failed. This is a silent contract violation. Most SDK users don't check return values (fire-and-forget pattern), but any customer who does will see false failures.

---

### Options for Fixing the Response Contract

#### Option A: Synchronous Pass-Through (Recommended)

Change the proxy to forward synchronously and return the Rails response when the app is up. Fall back to the simplified 202 only when Rails is unreachable.

```
Rails up (99% of time):
  SDK → proxy → store R2 → forward to Rails → return Rails response → delete R2
  (SDK sees full response: event_id, channel, attribution, etc.)

Rails down:
  SDK → proxy → store R2 → forward fails → return simplified 202
  (SDK sees { "status": "accepted", "request_id": "..." })
```

**Proxy changes:**
- Instead of `waitUntil(forward)` + return 202, the proxy attempts a synchronous forward first
- If forward succeeds within 5s: return the Rails response verbatim, delete R2 object
- If forward fails/times out: return the simplified 202 (data safe in R2 for replay)

**Pros:**
- Zero SDK changes for the happy path — response contract identical to direct Rails
- Graceful degradation — only returns simplified 202 during outages
- Callers who check return values still get full data 99% of the time

**Cons:**
- Adds ~50-100ms latency (proxy → Rails round-trip) vs current fire-and-forget 202
- Worker holds the connection open longer (but well within CF Worker limits)
- Two response shapes still exist — SDKs must handle the degraded 202

**Worker code change (conceptual):**
```typescript
// Current: store → return 202 → waitUntil(forward)
// New: store → try forward → return Rails response OR 202

const forwardResult = await tryForward(env, payload);

if (forwardResult.ok) {
  ctx.waitUntil(env.INGEST_BUCKET.delete(key));  // cleanup async
  return new Response(forwardResult.body, {
    status: forwardResult.status,
    headers: { "content-type": "application/json" },
  });
}

// Forward failed — data safe in R2, return simplified 202
return jsonResponse({ status: "accepted", request_id: requestId }, 202);
```

#### Option B: Fire-and-Forget SDKs

Change all SDKs to stop parsing response data. `track()` returns `true` on any 2xx, not a structured object.

**Pros:**
- Simple, permanent fix — no response shape ambiguity
- Matches the "analytics SDKs are fire-and-forget" philosophy

**Cons:**
- Breaking change for SDK users who check `result[:event_id]` or `result[:attribution]`
- Loses useful debugging info (event IDs, attribution status)
- Requires major version bump (1.0.0) since it changes the return type

#### Option C: SDKs Handle Both Response Shapes

Keep the proxy as-is (always returns simplified 202). Update SDKs to treat `{ "status": "accepted" }` as success.

```ruby
# Ruby example
def call
  return false unless valid?
  return { success: true } if proxy_response?(response)
  parse_full_response(response)
end

def proxy_response?(resp)
  resp&.dig("status") == "accepted" && resp&.key?("request_id")
end
```

**Pros:**
- No proxy changes needed
- SDKs work with both proxy and direct Rails endpoints

**Cons:**
- `track()` returns `{ success: true }` with no `event_id` — always, not just during outages
- Callers lose access to response data permanently when using the proxy
- Inconsistent behavior: same SDK returns different shapes depending on which endpoint it hits

#### Option D: Edge-Generated IDs (Industry Best Practice)

The proxy generates entity-specific IDs at the edge and returns them immediately. Rails adopts these IDs as the canonical dedup key. This is what Segment (`messageId`), Snowplow (`event_id`), and Mixpanel (`$insert_id`) all do.

**The principle:** Whoever first receives the event generates the canonical ID. For mbuzz, that's the proxy.

```
SDK → proxy → generate IDs + store R2 → return IDs immediately (fast 202)
                                           ↓
                                     Rails processes payload
                                     Uses proxy-generated ID for dedup
                                     Stores as external_id column
```

**Proxy response (events example):**
```json
{
  "status": "accepted",
  "request_id": "req_a1b2c3d4e5f6",
  "events": [
    { "id": "evt_7f3a9c2e1b4d", "event_type": "page_view", "status": "accepted" }
  ]
}
```

**Proxy response (conversions example):**
```json
{
  "status": "accepted",
  "request_id": "req_a1b2c3d4e5f6",
  "conversion": { "id": "conv_8e2b1d4f5a6c" }
}
```

**How it works:**

1. Proxy parses the request body (it already does this for validation)
2. For `/events`: generates an `evt_{12hex}` ID for each event in the batch
3. For `/conversions`: generates a `conv_{12hex}` ID
4. For `/sessions`: `visitor_id` and `session_id` are already in the request body (SDK-generated)
5. For `/identify`: fire-and-forget, no ID needed
6. IDs are injected into the R2 payload before storage
7. Response includes the IDs immediately
8. Rails receives the payload (via forward or replay) with the proxy-generated IDs
9. Rails stores the proxy ID in an `external_id` column (this pattern already exists — `Identity.external_id`)
10. Unique index on `(account_id, external_id)` provides dedup — this IS the idempotency layer

**Industry precedent:**

| Platform | Who Generates | ID Name | Used For |
|----------|---------------|---------|----------|
| **Segment** | Client SDK | `messageId` (UUIDv4) | Dedup key. IS the canonical ID. Server adds no second ID. |
| **Snowplow** | Client tracker | `event_id` / `eid` (UUIDv4) | Dedup key. IS the canonical ID throughout the pipeline. |
| **Mixpanel** | Client SDK | `$insert_id` | Composite dedup key: `(event_name, distinct_id, time, $insert_id)` |
| **Stripe** | Client | `Idempotency-Key` header | Dedup key. Server generates separate resource ID (`ch_`, `pi_`). |

Segment and Snowplow use the client-generated ID as the only ID. Stripe uses a dual-ID model (client key for dedup, server ID for the resource). mbuzz would use a variant: proxy-generated ID for dedup + SDK response, DB-generated `prefix_id` for internal use.

**What the proxy CAN generate (stateless):**

| Field | Source | Available at Edge? |
|-------|--------|-------------------|
| `event_id` (`evt_`) | UUID | Yes |
| `conversion_id` (`conv_`) | UUID | Yes |
| `visitor_id` (`vis_`) | Already in request body (SDK-generated) | Yes (echo back) |
| `session_id` (`sess_`) | Already in request body (SDK-generated) | Yes (echo back) |
| `request_id` (`req_`) | UUID | Yes (already generated) |

**What the proxy CANNOT generate (requires Rails processing):**

| Field | Why |
|-------|-----|
| `channel` | Requires UTM parsing + referrer classification logic |
| `attribution` | Requires full attribution pipeline |
| `accepted` / `rejected` counts | Requires event validation (visitor exists, valid event_type, etc.) |

**ID format:** UUIDv7 (RFC 9562) for time-ordering. Generated as `{prefix}_{12 hex chars from UUIDv7}`. Collision probability at 1M events/sec: ~1 in 10^11. Effectively zero.

**Rails changes:**
- Add `external_id` column (string, nullable) to `events`, `sessions`, `conversions`
- Unique index on `(account_id, external_id)` where `external_id IS NOT NULL`
- Services check `external_id` before creating — if found, return existing record (idempotent)
- This replaces the Phase 2 `request_id` approach — `external_id` IS the idempotency key
- The existing `prefix_id` (hashed from DB primary key) continues to work for internal use, dashboard URLs, etc.
- Pattern already proven in codebase: `Identity.external_id` does exactly this

**SDK changes:**
- SDKs handle the proxy response shape: extract `events[0].id`, `conversion.id` as before
- Session response: proxy echoes back `visitor_id` and `session_id` from the request body (SDK already has these) — `channel` is absent (nil) in proxy response, present when Rails responds
- Minor: SDKs treat missing `channel` as acceptable (it was informational, not functional)

**Pros:**
- **Matches industry best practice** — Segment and Snowplow do exactly this
- **Proxy stays fast** — no synchronous forward, immediate 202 with IDs
- **Solves idempotency for free** — the proxy-generated ID IS the dedup key, no separate Phase 2 needed
- **Consistent response shape** — SDK always gets IDs back, whether from proxy or direct Rails
- **No dual-response-shape problem** — proxy always returns the same structure

**Cons:**
- `channel` not available in proxy response (only in direct Rails response) — but SDKs don't use `channel` functionally, it's informational
- `attribution.status` not available — but it's always `"pending"` anyway (async processing)
- `accepted`/`rejected` event counts not available — proxy accepts everything that passes format validation, Rails does business validation later
- Two ID systems coexist: `external_id` (proxy-generated, used for dedup) and `prefix_id` (DB-generated, used for dashboard/internal)
- Proxy needs endpoint-aware response building (knows what `/events` vs `/conversions` returns)

#### Decision: Option A (sync pass-through) — decided 2026-03-13

**Option D rejected** after deep analysis of mbuzz's entity model:

1. **Proxy returns IDs before validation.** The proxy can't know if an event will be rejected (invalid visitor, billing blocked, duplicate). Returning `evt_xxx` for a rejected event is a false positive — the SDK thinks it succeeded.
2. **Can't return `channel`.** Channel resolution requires UTM parsing + referrer classification. This is mbuzz's core value proposition — stripping it from the response degrades the product.
3. **Can't return `attribution`.** Same issue. Even though attribution is always `"pending"`, it signals to the caller that the system is working.
4. **Dual-ID system.** `external_id` (proxy) vs `prefix_id` (DB) creates confusion. Which ID do you use in the dashboard? In API calls? In support tickets?
5. **Makes the proxy fat.** Proxy needs endpoint-aware response building — knows what `/events` vs `/conversions` returns. Violates our "thin proxy, thin SDK, max business logic on server" principle.

**Option A wins** because:
- 99%+ of the time, Rails is up → SDK gets the full response (channel, event_ids, attribution) — identical to direct
- The degraded 202 only appears during outages, and with Option Y fallback, effectively never
- Proxy stays dumb (forwards bytes, doesn't interpret them)
- Zero SDK response-parsing changes needed for the happy path
- +50-100ms latency is acceptable for server-side SDKs

Options B and C both permanently degrade the SDK contract for a problem that only exists during outages.

---

### Problem 2: SDK-Level Endpoint Fallback

Should SDKs automatically fall back to `mbuzz.co/api/v1` (direct) when `api.mbuzz.co` (proxy) fails?

```
POST api.mbuzz.co/api/v1/events     ← primary (proxy)
  ↓ timeout or 5xx?
POST mbuzz.co/api/v1/events          ← fallback (direct to Rails)
  ↓ also fails?
  drop (both endpoints down)
```

#### Industry Research

No major analytics vendor implements SDK-level endpoint failover:

| Vendor | Proxy Model | Failover? | Retry Strategy |
|--------|-------------|-----------|----------------|
| **Segment** | Custom proxy via `apiHost` config | No | localStorage queue, 10 retries, exponential backoff |
| **RudderStack** | Single `dataPlaneUrl` | No | localStorage/Redis persistence, exponential backoff with jitter |
| **PostHog** | Single `api_host` | No | Infinite retry with backoff |
| **LaunchDarkly** | Relay Proxy | **Explicitly no** — documented: "SDKs do not fall back to LaunchDarkly if Relay Proxy is unavailable" |
| **Snowplow** | Single collector URL | No | Configurable retry + `onRequestFailure` callback for custom logic |
| **Amplitude** | Dynamic config (vendor-managed) | Server-side redirect only | Incompatible with custom proxies |

**The unanimous industry pattern:** SDK → single endpoint → retry with backoff → drop. Availability is an infrastructure concern (load balancer, multi-AZ), not an SDK concern.

#### Why Vendors Don't Do It

1. **Exposes the origin.** The proxy's purpose (for client-side SDKs) is hiding the origin from ad-blockers. A hardcoded fallback URL in client code defeats this. *Note: this argument is weak for mbuzz — all SDKs are server-side.*
2. **Split-brain ingestion.** Events going two paths risk duplicates, ordering issues, and different data shapes if the proxy applies any transformation.
3. **Timeout penalty.** ~5s wait for proxy to fail before trying fallback = unacceptable latency on the failure path.
4. **Complexity.** Circuit breaker logic, health checks, retry state — all in every SDK, in every language.

#### Arguments For Doing It (mbuzz-specific)

1. **All SDKs are server-side.** No ad-blocker concern. The origin URL is already in server-side config — no exposure risk.
2. **Simple implementation.** One `try/catch` wrapper. No localStorage, no persistence layer.
3. **Real insurance.** Cloudflare's 99.9% SLA means ~43 minutes of downtime/month is within SLA. During those minutes, fallback saves data.
4. **Direct endpoint is permanent.** We've committed to keeping `mbuzz.co/api/v1` forever. The fallback is always available.

#### Options

**Option X: No fallback (match industry standard)**

SDKs hit `api.mbuzz.co` only. If proxy is down, data is lost (same as today when Rails is down — which is what we're fixing). Rely on Cloudflare's 99.9% SLA.

**Option Y: Configurable fallback (opt-in)**

```ruby
Mbuzz.init(
  api_key: ENV['MBUZZ_API_KEY'],
  # api_url: "https://api.mbuzz.co/api/v1"    # default
  # fallback_url: "https://mbuzz.co/api/v1"   # default, set nil to disable
)
```

SDK tries primary, falls back on timeout/5xx. Both URLs configurable. Fallback enabled by default but can be disabled.

**Pros:** Maximum data resilience. Customers can disable if they don't want it.
**Cons:** Adds ~5s latency on failure path. Potential duplicates if proxy accepted but SDK thinks it failed (timeout race). Need idempotency layer (Phase 2) deployed first.

**Option Z: Hooks-based (Snowplow pattern)**

Expose `on_request_failure` callback. Let customers implement their own fallback logic.

```ruby
Mbuzz.init(
  api_key: ENV['MBUZZ_API_KEY'],
  on_request_failure: ->(path, payload, error) {
    # Custom logic: retry, log, fallback, alert, etc.
  }
)
```

**Pros:** Maximum flexibility. No opinions baked into SDK. Customers who need compliance/data-residency controls aren't surprised by automatic failover.
**Cons:** Most customers won't implement it. Requires SDK-specific callback patterns across 4 languages.

#### Recommendation

**Option Y (configurable fallback, on by default)** is pragmatic for mbuzz:
- Server-side SDKs eliminate the main industry objection (origin exposure)
- Simple to implement — one try/catch per HTTP call
- Enabled by default = customers get resilience without thinking about it
- Requires Phase 2 (idempotency) to be deployed first to handle the duplicate race

**Dependency:** If we go with Option A (synchronous pass-through) for the response contract AND Option Y (fallback), the fallback path returns the full Rails response (since it hits Rails directly). This means the SDK always gets rich response data — either from the proxy-forwarded Rails response or from the direct fallback. The degraded 202 only appears when *both* endpoints are down, which is effectively never.

---

### Decision Matrix

| Combination | Response Contract | SDK Fallback | Complexity | Data Loss Risk | Latency Impact |
|-------------|-------------------|--------------|------------|----------------|----------------|
| **A + Y (decided)** | Pass-through when up, 202 when down | Try proxy, fall back to direct | Medium | Near-zero | +50-100ms (sync forward) |
| D + Y (rejected) | Edge-generated IDs, always fast 202 | Try proxy, fall back to direct | Medium | Near-zero | None (proxy stays async) |
| A + X | Pass-through when up, 202 when down | Proxy only | Low | Low (CF 99.9%) | +50-100ms (sync forward) |
| B + Y | Always fire-and-forget | Try proxy, fall back to direct | Medium | Near-zero | None, but no IDs ever |
| C + X | Always simplified 202 | Proxy only | Low | Low | None, but no IDs ever |

**Decided: A + Y** — synchronous pass-through preserves 100% of the existing response contract. SDKs get full Rails responses (channel, event_ids, attribution) 99%+ of the time. Configurable fallback ensures near-zero data loss. The +50-100ms latency is acceptable for server-side SDKs.

---

## Decided: Raw Event Archive (2026-03-13)

Keep every ingest payload permanently in R2 as an immutable event log. Same pattern as Snowplow (S3 archive) and Segment (unlimited event retention). R2 becomes the source of truth; PostgreSQL is a derived projection that can be rebuilt.

### Phase A: Archive on success (immediate)

Instead of deleting R2 objects after successful forward, move them to `archive/`:

```typescript
// Current: delete on success
await env.INGEST_BUCKET.delete(key);

// New: move to archive/ on success
await moveToArchive(env.INGEST_BUCKET, key);
```

**R2 prefixes:**
```
pending/   — awaiting processing (unchanged)
archive/   — successfully processed, permanent record (new)
failed/    — dead letter (unchanged)
_meta/     — circuit breaker state (unchanged)
```

**Archive key format (account-scoped):**
```
archive/{api_key}/{endpoint}/{YYYY}/{MM}/{DD}/{HH}/{timestamp_ms}-{uuid}.json
```

Example:
```
archive/sk_live_your_api_key_here/events/2026/03/12/14/1741789200000-a1b2c3d4.json
```

Account-scoped by API key so you can list a single customer's data with `R2.list({ prefix: "archive/sk_live_3ea1..." })`. The API key is already stored inside every payload — the path doesn't increase exposure. Enables per-account disaster recovery, GDPR erasure, and debugging without opening every file.

**Cost at 10M events/month:** ~$46/mo incremental (one extra R2 PUT per event for the move). Storage is negligible (~$1-2/mo). At current scale: ~$0 (within free tier).

### Phase B: Lifecycle rules (next)

- Transition `archive/` to R2 Infrequent Access after 30 days ($0.01/GB vs $0.015/GB)
- Auto-delete `archive/` after 25 months (CNIL recommendation for audience measurement data)
- Auto-delete `failed/` after 90 days

### Phase C: Reconciliation (later)

Hourly count check: compare R2 `archive/` object count vs `SELECT COUNT(*)` for same hour. Alert if delta > threshold. Auto-replay missing events from archive.

### Phase D: PII stripping + GDPR (later)

Strip raw IP addresses and API keys from archived payloads after 30 days (they've served their purpose by then — IP already resolved to `device_fingerprint`, API key already authenticated). Crypto-shredding for identify call PII (encrypt with per-visitor key, delete key on erasure request).

---

## Out of Scope

- **Request batching at the proxy** — Cloudflare Pipelines (currently in beta) can batch events, transform with SQL, and write Parquet to R2. Natural upgrade path, but not needed now.
- **Browser/JS SDK** — all current SDKs are server-side. CORS handling in the Worker is trivial to add when we build a client-side SDK.
- **Multi-region replay** — single replay worker is fine at current scale. R2 is globally distributed anyway.
- **Encryption at rest** — R2 encrypts at rest by default. Payloads contain API keys in headers, which is acceptable (same as HTTPS transport). If needed later, we can encrypt the stored payload body.
- **Real-time streaming** — the 1-minute replay interval is fine for attribution analytics. If we need sub-second processing, consider Cloudflare Queues (push-based) as a future upgrade.
