# Edge Ingest Proxy

**Last updated:** 2026-03-13
**Spec:** `lib/specs/edge_ingest_proxy_spec.md`
**Repo:** `../mbuzz-ingest-proxy/` (Cloudflare Worker)
**Domain:** `api.mbuzz.co`

---

## Purpose

The edge ingest proxy sits between SDKs and the Rails API. It durably stores every ingest payload in Cloudflare R2 before forwarding to Rails. If Rails is down, payloads accumulate and replay automatically when it recovers. Zero data loss.

---

## Request Flow

### Happy Path (Rails up — 99%+ of time)

```
SDK → POST api.mbuzz.co/api/v1/{endpoint}
  ↓
Cloudflare Worker (edge, 300+ PoPs)
  ↓
1. Validate request (method, path, auth format, JSON, <1MB)
2. Store raw request to R2 pending/{endpoint}/{date}/{timestamp}-{uuid}.json
3. Forward synchronously to mbuzz.co/api/v1/{endpoint} (5s timeout)
4. Rails returns full response (channel, event_ids, attribution)
  ↓
5. Return Rails response verbatim to SDK
6. Move R2 object to archive/{api_key}/{endpoint}/{date}/{timestamp}-{uuid}.json (async)
```

**SDK sees:** Full Rails response — identical to calling Rails directly. ~150ms total.

### Rails Down

```
SDK → POST api.mbuzz.co/api/v1/{endpoint}
  ↓
Cloudflare Worker
  ↓
1. Validate + store to R2 pending/
2. Forward to Rails → timeout/5xx
3. Return simplified 202: { "status": "accepted", "request_id": "req_..." }
4. Object stays in pending/ for replay
  ↓
Replay Worker (cron, every 1 min)
  ↓
5. Lists pending/ in dependency order: sessions → events → conversions → identify
6. Forwards each to Rails
7. On success → move to archive/
8. On retryable error → leave in pending/
9. On permanent error → move to failed/ (dead letter)
```

**SDK sees:** Simplified 202 (no channel/event_ids). Data is safe. If SDK has fallback enabled (default), it retries directly to `mbuzz.co/api/v1` and gets the full response.

### Cloudflare Down

```
SDK → POST api.mbuzz.co/api/v1/{endpoint} → timeout
  ↓ (SDK fallback, Option Y)
SDK → POST mbuzz.co/api/v1/{endpoint} → Rails directly
```

**SDK sees:** Full Rails response via fallback. No R2 involvement.

---

## Entity Dependency Chain

Understanding this is critical for replay ordering.

```
Sessions create Visitors
  ↓
Events need Visitors to exist (require_existing_visitor enforced)
  ↓
Conversions need Visitors + Events
  ↓
Identify needs Visitors
```

**Device fingerprinting:** `SHA256(ip|user_agent)[0:32]`. The proxy preserves `x-forwarded-for` and `x-mbuzz-user-agent` headers. The SDK also sends `device_fingerprint` pre-computed in the session body. Fingerprinting works identically through the proxy.

**SDK independence:** SDKs don't depend on session response data for subsequent calls. `visitor_id` and `session_id` come from cookies, not API responses. So even when the proxy returns a degraded 202 for sessions, subsequent event/conversion calls work fine.

---

## Replay Worker — Dependency Ordering

R2 lists objects lexicographically. Without ordering:
`conversions/` → `events/` → `identify/` → `sessions/` (alphabetical).

Sessions create Visitors. Events need Visitors. If events replay before sessions → "Visitor not found" → dead letter → **data loss**.

**Fix:** 4 separate `R2.list()` calls in dependency order:

```
1. pending/sessions/   → creates Visitors (must be first)
2. pending/events/     → needs Visitors
3. pending/conversions/ → needs Visitors + Events
4. pending/identify/   → needs Visitors
```

100 objects per endpoint per run. FIFO within each endpoint (oldest first).

### Retryable vs Permanent Errors

Not all 422s are permanent:

| Rails 422 Response | Action | Why |
|-------------------|--------|-----|
| "Visitor not found" | Leave in `pending/` | Session hasn't been replayed yet |
| "Billing blocked" | Leave in `pending/` | May succeed when billing resolved |
| "event_type is required" | Move to `failed/` | Permanent validation error |
| "Invalid API key" | Move to `failed/` | Will never succeed |

The replay worker checks the response body for known retryable error messages before dead-lettering.

---

## R2 Bucket Layout

**Bucket:** `mbuzz-ingest-buffer`

```
pending/{endpoint}/{YYYY}/{MM}/{DD}/{HH}/{timestamp_ms}-{uuid}.json
  → Awaiting processing

archive/{api_key}/{endpoint}/{YYYY}/{MM}/{DD}/{HH}/{timestamp_ms}-{uuid}.json
  → Successfully processed, permanent record

failed/{endpoint}/{YYYY}/{MM}/{DD}/{HH}/{timestamp_ms}-{uuid}.json
  → Dead letter (permanent 4xx from Rails)

_meta/circuit_breaker.json
  → Circuit breaker state
```

**Lifecycle rules:**
- `archive/` → Infrequent Access after 30 days
- `archive/` → Auto-delete after 25 months (CNIL recommendation)
- `failed/` → Auto-delete after 90 days

**Archive is account-scoped** by API key prefix. Enables per-account operations:
`R2.list({ prefix: "archive/sk_live_your_api_key..." })`.

---

## Stored Payload Format

Every request stored as a single JSON file:

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

The `request_id` is also sent as `X-Idempotency-Key` when forwarding to Rails.

---

## Circuit Breaker

Prevents hammering Rails when it's down.

```
Closed (normal)
  → 5 consecutive full-batch failures
Open (skip processing)
  → wait 5 minutes
Half-open (probe)
  → process 1 object
  → success → Closed
  → failure → Open (another 5 min)
```

State stored in `_meta/circuit_breaker.json`.

---

## Idempotency

The store-and-forward pattern can send duplicates (race between sync forward and replay). Rails handles this:

1. Proxy generates `request_id` (UUID) per incoming request
2. Proxy sends `X-Idempotency-Key: {request_id}` when forwarding
3. Rails checks `request_id` column (unique index per account) before creating
4. Duplicate → return original response, no side effects

---

## Cloudflare Configuration

### Account

- Account ID: `ccff0b44171fa4416302a954764d756f`
- Plan: Workers Paid ($5/mo)

### DNS (mbuzz.co zone)

- `api.mbuzz.co` → Worker route (Custom Domain in CF dashboard)
- AAAA record `api` → `100::` (proxied)

### Worker Bindings

| Binding | Type | Value |
|---------|------|-------|
| `INGEST_BUCKET` | R2 | `mbuzz-ingest-buffer` |
| `ORIGIN_URL` | Env var | `https://mbuzz.co` |

### Cron Trigger

`* * * * *` — replay worker runs every minute.

### Zone-Level Settings (mbuzz.co)

Configured to prevent Cloudflare from interfering with the Rails app:

- **SSL/TLS:** Full (strict)
- **Caching:** Bypass all (cache rule applied to all requests)
- **Email Address Obfuscation:** Off
- **Auto Minify:** Off
- **Rocket Loader:** Off

---

## SDK Configuration

SDKs default to the proxy. Fallback enabled by default.

```ruby
# Ruby example
Mbuzz.init(
  api_key: ENV['MBUZZ_API_KEY'],
  # api_url: "https://api.mbuzz.co/api/v1"    # default (proxy)
  # fallback_url: "https://mbuzz.co/api/v1"   # default (direct), nil to disable
)
```

| SDK | Primary URL | Fallback URL | Config File |
|-----|-------------|-------------|-------------|
| Ruby | `https://api.mbuzz.co/api/v1` | `https://mbuzz.co/api/v1` | `lib/mbuzz/configuration.rb:29` |
| Node | `https://api.mbuzz.co/api/v1` | `https://mbuzz.co/api/v1` | `src/config.ts:11` |
| Python | `https://api.mbuzz.co/api/v1` | `https://mbuzz.co/api/v1` | `src/mbuzz/config.py:6` |
| PHP | `https://api.mbuzz.co/api/v1` | `https://mbuzz.co/api/v1` | `src/Mbuzz/Config.php:11` |
| Shopify | 3 files | N/A (client-side) | See spec Phase 3.5 |
| sGTM | `template.tpl` | N/A | See spec Phase 3.6 |

**Permanent dual-endpoint policy:** `mbuzz.co/api/v1` is a permanent, documented, supported direct endpoint. It is not deprecated. If Cloudflare has a global outage, customers flip one config value and bypass the proxy entirely.

---

## Runbook

### Check R2 pending count

```bash
# Via Cloudflare dashboard: R2 → mbuzz-ingest-buffer → Objects → filter by prefix "pending/"
# Or via wrangler:
cd ../mbuzz-ingest-proxy
npx wrangler r2 object list mbuzz-ingest-buffer --prefix "pending/" | head -20
```

If pending count is growing: Rails is likely down or the replay worker is stuck.

### Check dead letters

```bash
npx wrangler r2 object list mbuzz-ingest-buffer --prefix "failed/" | head -20
```

Dead letters are permanent 4xx errors. Investigate the payload to understand why Rails rejected it.

### Read a specific R2 object

```bash
npx wrangler r2 object get mbuzz-ingest-buffer "pending/events/2026/03/12/14/1741789200000-a1b2c3d4.json"
```

### Bypass proxy in an emergency

If the proxy itself is causing issues, point SDKs directly at Rails:

```ruby
Mbuzz.init(
  api_key: ENV['MBUZZ_API_KEY'],
  api_url: "https://mbuzz.co/api/v1",  # bypass proxy
  fallback_url: nil                      # no fallback needed
)
```

### Deploy Worker updates

```bash
cd ../mbuzz-ingest-proxy
npm run deploy    # wrangler deploy
```

### Check Worker logs

```bash
cd ../mbuzz-ingest-proxy
npx wrangler tail    # live stream of Worker logs
```

### Manually trigger replay

The replay worker runs automatically every minute via cron. To trigger it manually:

```bash
curl https://api.mbuzz.co/api/v1/health  # just check it's alive
# There's no manual replay trigger — wait for the next cron run (max 60s)
```

### Check circuit breaker state

```bash
npx wrangler r2 object get mbuzz-ingest-buffer "_meta/circuit_breaker.json"
```

If circuit is open, Rails has been down for a while. Check the Rails app. Once Rails is back, the circuit breaker will auto-close on the next probe (within 5 minutes).

---

## Cost

| Scale | Monthly Cost |
|-------|-------------|
| Current (low traffic) | ~$5 (Workers Paid minimum) |
| 10M events/month | ~$100 (Workers $5 + R2 PUTs ~$90 + R2 GETs ~$4 + storage ~$1) |

R2 egress is free. Archive storage grows ~10GB/month at scale but transitions to Infrequent Access after 30 days.
