# Navigation-Aware Session Creation — Fix 5x Visit Inflation

**Date:** 2026-01-29 | **Status:** Phases 1-8 Complete (full implementation done, data cleanup pending execution) | **Severity:** Critical (client-facing data integrity)
**Branch:** fix/navigation-aware-session-creation

---

## Problem

The UAT client dashboard shows **58,258–63,055 visits** in the last 7 days when the expected count is **~12,000**. This is a ~5x inflation factor. The funnel shows ~2% Add to Cart and ~0.4% Purchase conversion rates when real rates are ~5x higher.

This is a **recurrence** of the Turbo frame visitor inflation bug (`lib/specs/old/turbo_session_deduplication_spec.md`). The previous fix (canonical visitor resolution via fingerprint/session_id within 30 seconds) reduced inflation from 72,000x to 5x but did not eliminate it.

**Who's affected:** Every client using a server-side SDK with a framework that fires sub-requests (Turbo/Hotwire, htmx, Unpoly, SSR prefetching, etc.). This is not a pet_resorts-specific problem — it's an architectural gap in all SDKs.

---

## Root Cause

### The Mechanism

On a user's **first page load**, the browser sends multiple concurrent HTTP requests — one for the main page and one per lazy-loaded Turbo frame. Since no cookies exist yet, each request generates a **different random visitor_id** and **different random session_id**. The server-side deduplication fails because concurrent transactions can't see each other's uncommitted data.

### Why the Existing Server-Side Fix Fails

The advisory lock in `Sessions::CreationService` is keyed on `session_id`:

```ruby
# app/services/sessions/creation_service.rb:34-40
lock_key = Digest::MD5.hexdigest("#{account.id}:#{session_id}").to_i(16) % (2**31)
```

Concurrent requests have **different random session_ids** (`SecureRandom.uuid` at `mbuzz-ruby/lib/mbuzz/middleware/tracking.rb:94`) → they acquire **different locks** → they run **in parallel transactions** → PostgreSQL READ COMMITTED isolation means Transaction B cannot see Session S1 created by Transaction A → both create new visitors.

The canonical visitor detection (`find_canonical_by_fingerprint`) queries for sessions with the same fingerprint created in the last 30 seconds — but the first request's session hasn't been committed yet when the second request runs its query.

### Why Exactly 5x?

The pet_resorts app has a **lazy-loaded order banner in the navbar** (`app/views/application/_order_banner.html.erb`) that renders on **every page**, plus additional lazy frames on specific pages. A typical first page load fires ~5 concurrent requests. 12,000 real visitors × 5 concurrent requests ≈ 60,000 visitor records.

### The SDK's Role

Three SDK behaviors combine to create the problem:

| Behavior | Code Location | Impact |
|----------|---------------|--------|
| Random session_id | `mbuzz-ruby: tracking.rb:94` — `SecureRandom.uuid` | Concurrent requests get different session_ids, defeating server-side dedup |
| Session cookie still managed | `tracking.rb:31,139-145` — `set_session_cookie` | Cookie only helps AFTER first response — too late for concurrent requests |
| No sub-request detection | `skip_request?` only checks path/extension (line 40-52) | Turbo frames, htmx, fetch() all trigger full session creation |

### Documentation vs Reality

The SDK registry (`lib/docs/sdk/sdk_registry.md`) claims v0.7.0 **removed** session cookies. The actual Ruby SDK at v0.7.2 still:
- Defines `SESSION_COOKIE_NAME` and `SESSION_COOKIE_MAX_AGE` (`mbuzz-ruby/lib/mbuzz.rb:30-31`)
- Calls `set_session_cookie` on every response (`tracking.rb:31`)
- Generates random session_ids (`tracking.rb:94`)

This must be reconciled.

---

## Solution: Navigation-Aware Session Creation (Whitelist Approach)

### Why Whitelist, Not Blacklist

Blacklisting specific framework headers (`Turbo-Frame`, `HX-Request`, etc.) is fragile. When the next partial-page framework emerges, we'd miss it and the inflation returns.

**Whitelist approach:** Only create sessions when browser-enforced headers confirm this is a **real page navigation**. Every sub-request type — regardless of framework — gets filtered out automatically.

### The Sec-Fetch-\* Headers

Modern browsers send `Sec-Fetch-*` headers on every request. These are **forbidden headers** — JavaScript cannot forge them. They tell the server exactly what type of request this is.

| Request Type | Sec-Fetch-Mode | Sec-Fetch-Dest | Should Track? |
|---|---|---|---|
| User clicks link → full page load | `navigate` | `document` | **Yes** |
| Turbo Frame lazy load | `same-origin` | `empty` | No |
| htmx partial update | `same-origin` | `empty` | No |
| Unpoly fragment | `same-origin` | `empty` | No |
| fetch() / XHR | `cors`/`same-origin` | `empty` | No |
| Prefetch (hover) | `navigate` | `document` | No (`Sec-Purpose: prefetch`) |
| Prerender | `navigate` | `document` | No (`Sec-Purpose: prefetch`) |
| Service worker | `same-origin` | `empty` | No |
| WebSocket upgrade | `websocket` | `empty` | No |
| Image/script/font | `no-cors` | varies | No |
| Bot/crawler | **absent** | **absent** | Fallback needed |

**The rule:** `Sec-Fetch-Mode: navigate` AND `Sec-Fetch-Dest: document` AND `Sec-Purpose` absent = real page navigation.

### Browser Support

| Browser | Support Since |
|---------|-------------|
| Chrome | 76 (July 2019) |
| Edge | 79 (January 2020) |
| Firefox | 90 (July 2021) |
| Safari | 16.4 (March 2023) |

Essentially universal for current browser versions. For the small percentage of old browsers that don't send these headers, we fall back to the current behavior with a framework-specific blacklist as defense-in-depth.

### Complete Detection Logic

```ruby
# Pseudocode — applies to ALL server-side SDKs (Ruby, Node, Python, PHP)

def should_create_session?(env)
  mode = env["HTTP_SEC_FETCH_MODE"]
  dest = env["HTTP_SEC_FETCH_DEST"]

  if mode.present?
    # Modern browser: whitelist real navigations only
    return mode == "navigate" &&
           dest == "document" &&
           env["HTTP_SEC_PURPOSE"].blank?
  end

  # Fallback for old browsers / bots: blacklist known sub-requests
  env["HTTP_TURBO_FRAME"].blank? &&
    env["HTTP_HX_REQUEST"].blank? &&
    env["HTTP_X_UP_VERSION"].blank? &&
    env["HTTP_X_REQUESTED_WITH"] != "XMLHttpRequest"
end
```

**Key design:** The middleware still sets visitor cookies on ALL responses (so subsequent requests have them). It only gates **session creation** (the async API call). This means:

1. Main page request → `navigate` + `document` → creates session, sets cookies
2. Turbo frame request → `empty` → skips session creation, still gets cookies from response
3. Next page navigation → has cookies → existing session, no new session created

---

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| Whitelist vs blacklist | Whitelist (`Sec-Fetch-*`) with blacklist fallback | Future-proof — new frameworks automatically handled |
| Where to implement | SDK middleware (all SDKs) | Prevents bad data at source; no server changes needed for core fix |
| Server-side defense-in-depth? | Yes — fingerprint-based advisory lock | Belt and suspenders; catches edge cases |
| Remove session cookie? | Yes — complete the v0.7.0 migration | Registry claims it's removed; code still has it |
| Pet_resorts immediate fix? | Yes — add `skip_paths` to initializer | Stops inflation while SDK update ships |

---

## Acceptance Criteria

### SDK Changes (All Server-Side SDKs)
- [ ] Session creation gated by `should_create_session?` navigation detection
- [ ] Modern browsers: only `Sec-Fetch-Mode: navigate` + `Sec-Fetch-Dest: document` + no `Sec-Purpose` triggers session creation
- [ ] Old browsers (no `Sec-Fetch-*`): blacklist fallback skips `Turbo-Frame`, `HX-Request`, `X-Up-Version`, `X-Requested-With: XMLHttpRequest`
- [ ] Visitor cookie still set on ALL responses (not gated)
- [ ] Session cookie (`_mbuzz_sid`) fully removed from Ruby SDK (complete v0.7.0 migration)
- [ ] Session cookie removed from Node, Python, PHP SDKs (verify)
- [ ] Tests cover: real navigation → creates session; turbo frame → skips; htmx → skips; fetch → skips; old browser → fallback blacklist; prefetch → skips

### Server-Side Defense (multibuzz)
- [ ] Advisory lock in `Sessions::CreationService` uses `device_fingerprint` instead of `session_id` when fingerprint is present
- [ ] Concurrent requests from same device serialize properly

### Documentation Updates
- [ ] `lib/docs/sdk/sdk_specification.md` — new "Navigation Detection" section added
- [ ] `lib/docs/sdk/api_contract.md` — session creation endpoint updated with navigation detection guidance
- [ ] `lib/docs/sdk/sdk_registry.md` — navigation detection added to release checklist, SDK features, and SDK development guidelines
- [ ] All SDK READMEs updated with navigation detection behavior

### Data Integrity
- [ ] Dashboard visits count matches real unique visitor count (within 5% margin)
- [ ] Conversion rates reflect true values

---

## Implementation Tasks

### Phase 0: Immediate Mitigation (pet_resorts)

- [ ] Add `skip_paths` to `config/initializers/mbuzz.rb` excluding turbo frame endpoints:
  ```ruby
  skip_paths: %w[/order_items /account/bookings/load_bookings /account/pets/load_pets /account/orders/load_my_orders]
  ```

### Phase 1: Ruby SDK (mbuzz-ruby) — COMPLETE ✅ (2026-02-02)

- [x] `should_create_session?` with `sec_fetch_headers?`, `page_navigation?`, `framework_sub_request?` methods
- [x] Session creation gated by Sec-Fetch-* whitelist + framework blacklist fallback
- [x] Session cookie (`_mbuzz_sid`) fully removed — constants and methods deleted
- [x] `build_request_context` simplified — no `new_session` key, no session cookie check
- [x] 13 navigation detection tests + integration tests in tracking_test.rb
- [x] Bump to v0.7.3, CHANGELOG updated

**Key files changed:**
| File | Change |
|------|--------|
| `lib/mbuzz/middleware/tracking.rb` | Added `should_create_session?`, `sec_fetch_headers?`, `page_navigation?`, `framework_sub_request?`; removed `set_session_cookie`, `session_cookie_options` |
| `lib/mbuzz.rb` | Removed `SESSION_COOKIE_NAME`, `SESSION_COOKIE_MAX_AGE` |
| `lib/mbuzz/version.rb` | Version `0.7.2` → `0.7.3` |
| `test/mbuzz/middleware/tracking_test.rb` | Navigation detection tests (lines 744-947) |
| `CHANGELOG.md` | v0.7.3 entry |

**E2E tests**: `sdk_integration_tests/scenarios/navigation_detection_test.rb` (19 tests, already written)

### Phase 2: Node SDK (mbuzz-node) — COMPLETE ✅ (2026-02-03)

- [x] `shouldCreateSession()` ported — Sec-Fetch-* whitelist + framework blacklist fallback
- [x] Adapted for Express middleware: `req.headers['sec-fetch-mode']`, `req.headers['turbo-frame']`
- [x] Session cookie fully removed (confirmed — not present in v0.7.3)
- [x] `deviceFingerprint()` utility — `SHA256(ip|user_agent)[0:32]` with Ruby parity
- [x] `createSessionAsync()` — fire-and-forget `POST /sessions`
- [x] 29 middleware tests + 4 fingerprint tests (all 135 tests passing)
- [x] Bump to v0.7.3, CHANGELOG updated

**Key files changed:**
| File | Change |
|------|--------|
| `src/middleware/express.ts` | Added `shouldCreateSession()`, `createSessionAsync()`, wired into middleware |
| `src/utils/fingerprint.ts` | NEW — `deviceFingerprint(ip, userAgent)` |
| `test/middleware/express.test.ts` | 29 navigation detection + session creation tests |
| `test/utils/fingerprint.test.ts` | 4 fingerprint utility tests |
| `package.json` | Version `0.7.0` → `0.7.3` |
| `CHANGELOG.md` | v0.7.3 entry |

### Phase 3: Python SDK (mbuzz-python) — COMPLETE ✅ (2026-02-03)

- [x] Port `should_create_session()` from Ruby reference implementation
- [x] Adapt for Flask middleware: `request.headers.get('Sec-Fetch-Mode')`, `request.headers.get('Turbo-Frame')`
- [x] Verify session cookie fully removed (was never added — Python SDK started at v0.7.0)
- [x] Tests matching Ruby test suite (11 navigation detection + 4 integration tests)
- [x] `device_fingerprint()` utility — `SHA256(ip|user_agent)[0:32]` with Ruby parity test
- [x] Async session creation via `threading.Thread(daemon=True)` — fire-and-forget `POST /sessions`
- [x] Bump to v0.7.3, CHANGELOG created

**Key files changed:**
| File | Change |
|------|--------|
| `src/mbuzz/utils/fingerprint.py` | NEW — `device_fingerprint(ip, user_agent)` |
| `src/mbuzz/utils/__init__.py` | Export `device_fingerprint` |
| `src/mbuzz/middleware/flask.py` | Added `should_create_session()`, `_create_session_async()`, wired into `before_request` |
| `tests/test_fingerprint.py` | NEW — 4 tests (Ruby parity, deterministic, unique, 32-char hex) |
| `tests/test_middleware.py` | Added `TestNavigationDetection` — 15 tests |
| `pyproject.toml` | Version `0.7.0` → `0.7.3` |
| `src/mbuzz/__init__.py` | `__version__` `0.7.0` → `0.7.3` |
| `CHANGELOG.md` | NEW |

### Phase 4: PHP SDK (mbuzz-php) — COMPLETE ✅ (2026-02-03)

- [x] Port `shouldCreateSession()` as `NavigationDetector::shouldCreateSession()` — reads `$_SERVER` headers
- [x] Accepts `$server` array parameter for testability (defaults to `$_SERVER`)
- [x] Verify session cookie fully removed (was never added — PHP SDK started at v0.7.0)
- [x] Tests matching Ruby test suite (11 navigation detection + 4 integration tests)
- [x] `Fingerprint::compute()` — `SHA256(ip|user_agent)[0:32]` with Ruby parity test
- [x] `IdGenerator::generateUuid()` — UUID v4 for session IDs
- [x] Synchronous session creation via `POST /sessions` in `Client::initFromRequest()` (PHP has no fire-and-forget)
- [x] Session only created when visitor cookie exists AND request is a real navigation
- [x] Bump to v0.7.3, CHANGELOG created

**Key files changed:**
| File | Change |
|------|--------|
| `src/Mbuzz/NavigationDetector.php` | NEW — `shouldCreateSession($server)` |
| `src/Mbuzz/Fingerprint.php` | NEW — `compute($ip, $userAgent)` |
| `src/Mbuzz/IdGenerator.php` | Added `generateUuid()` |
| `src/Mbuzz/Client.php` | Added `createSession()`, wired into `initFromRequest()` |
| `src/Mbuzz/Api.php` | User-Agent `0.1.0` → `0.7.3` |
| `tests/Unit/NavigationDetectorTest.php` | NEW — 15 tests |
| `tests/Unit/FingerprintTest.php` | NEW — 4 tests |
| `CHANGELOG.md` | NEW |

**Note:** PHP SDK does not auto-generate visitor IDs — reads from cookie only. Session creation requires an existing visitor cookie (set by a previous request or JS SDK). The e2e navigation detection test skips PHP (`SDKS_WITH_AUTO_VISITOR` excludes it).

### Phase 5: Shopify SDK (mbuzz-shopify) — EXEMPT ✅ (2026-02-05)

Shopify SDK is not affected by the navigation inflation bug:

1. **Client-side only**: Runs as browser JavaScript in a Shopify theme app extension, not server-side middleware
2. **Single session creation**: `trackSession()` called once on initial page load — no concurrent sub-request issue
3. **Explicit API calls**: JavaScript explicitly calls `fetch()` for tracking, not intercepted HTTP requests
4. **No framework sub-requests**: Theme extensions don't use Turbo/htmx/Unpoly lazy-loaded frames
5. **Persistent visitor ID**: 2-year `_mbuzz_vid` cookie prevents duplicate visitor records
6. **Sec-Fetch not applicable**: Browser JS cannot read forbidden `Sec-Fetch-*` headers
7. **Session cookie already removed**: Confirmed removed in v0.7.0 — only visitor cookie set

**No action required.** Navigation detection is unnecessary for client-side JavaScript SDKs.

### Phase 6: Server-Side Defense (multibuzz) — COMPLETE ✅ (2026-02-05)

- [x] Advisory lock in `Sessions::CreationService` uses `device_fingerprint` when present, falls back to `session_id`
- [x] Concurrent requests with different session_ids but same fingerprint serialize via shared lock
- [x] 4 new tests: fingerprint dedup, burst dedup (3 requests), no-fingerprint fallback, cross-device isolation

**Key change:**
```ruby
# Before: lock on session_id — different random UUIDs = different locks = parallel
# After:  lock on device_fingerprint — same device = same lock = serialized
lock_value = device_fingerprint.presence || session_id
```

**Files changed:**
| File | Change |
|------|--------|
| `app/services/sessions/creation_service.rb` | `with_session_lock` uses fingerprint-based lock key |
| `test/services/sessions/creation_service_test.rb` | 4 new fingerprint advisory lock tests |

### Phase 7: Documentation Updates — COMPLETE ✅ (2026-02-05)

- [x] `lib/docs/sdk/sdk_specification.md` — added "Navigation Detection (Required)" section with algorithm, header reference, pseudocode; updated Validation Checklist
- [x] `lib/docs/sdk/api_contract.md` — updated `POST /sessions` "When to call" with navigation detection requirement; added `device_fingerprint` to request body; added navigation detection to SDK Feature Requirements
- [x] `lib/docs/sdk/sdk_registry.md` — all SDKs updated to v0.7.3; navigation detection + device fingerprint added to features; release checklist updated with 4 new items; version compatibility matrix updated; Shopify marked exempt
- [x] `lib/docs/sdk/navigation_detection.md` — **NEW** standalone reference document with algorithm, implementations in 4 languages, testing checklist (15 scenarios), edge cases, browser support, device fingerprint spec
- [x] Registry reconciled — v0.7.0 session cookie removal confirmed across all SDKs; Ruby v0.7.3 completed the cleanup (removed constants + methods)

### Phase 8: Data Cleanup — RAKE TASK READY ✅ (2026-02-05)

- [x] `Visitors::DeduplicationService` — finds duplicate visitors (same `device_fingerprint`, created within 30s burst window), merges by reassigning sessions/events/conversions to canonical (earliest) visitor, preserves identity links, deletes duplicates
- [x] `bin/rails visitors:deduplicate ACCOUNT_ID=N [DRY_RUN=true] [WINDOW=30]` — rake task with dry-run default
- [x] 14 unit tests covering: merge, reassignment, identity preservation, boundary conditions, dry run
- [ ] Run against UAT client account (`DRY_RUN=true` first, then `DRY_RUN=false`)
- [ ] Verify dashboard numbers correct after cleanup

**Files:**
| File | Purpose |
|------|---------|
| `app/services/visitors/deduplication_service.rb` | Core merge logic |
| `test/services/visitors/deduplication_service_test.rb` | 14 tests |
| `lib/tasks/visitors.rake` | CLI wrapper with dry-run |

---

## Discovery: Navigation Detection as Core SDK Feature

### Why This Was Missed

The SDK specification (`lib/docs/sdk/sdk_specification.md`) and API contract (`lib/docs/sdk/api_contract.md`) define **what to track** but not **when to track**. There is no guidance on filtering sub-requests vs real navigations. Every SDK was built to fire on every HTTP request that isn't a static asset, because the docs never said otherwise.

This is not a bug in any single SDK — it's a missing architectural concept across the entire SDK platform.

### What Needs to Change in SDK Documentation

#### 1. `lib/docs/sdk/sdk_specification.md`

Add a new top-level section: **"Navigation Detection (Required)"**

Content must cover:
- **The problem**: Server-side middleware intercepts ALL HTTP requests, but only real page navigations should create sessions. Sub-requests (Turbo frames, htmx partials, fetch/XHR, prefetch, service workers) inflate visit counts.
- **The solution**: Whitelist approach using browser-enforced `Sec-Fetch-*` headers with framework-specific blacklist fallback.
- **The detection algorithm**: Full pseudocode of `should_create_session?` with both paths (modern browser whitelist, old browser blacklist).
- **What to gate vs what to allow**: Session creation is gated. Visitor cookie setting is NOT gated (all responses get cookies).
- **Complete header reference table**: Every `Sec-Fetch-Mode` / `Sec-Fetch-Dest` / `Sec-Purpose` combination and what it means.
- **Framework-specific headers**: `Turbo-Frame`, `HX-Request`, `X-Up-Version`, `X-Requested-With` for fallback blacklist.
- **Edge cases**: Old browsers (no headers → fallback), bots (no headers → consider skipping), HTTPS required (Sec-Fetch only sent over HTTPS), prefetch/prerender (navigate+document but with Sec-Purpose).

Add to the **Validation Checklist**:
- [ ] Only creates sessions for real page navigations (`Sec-Fetch-Mode: navigate` + `Sec-Fetch-Dest: document`)
- [ ] Skips session creation for sub-requests (Turbo frames, htmx, fetch, XHR, prefetch)
- [ ] Falls back to framework-specific blacklist when `Sec-Fetch-*` headers are absent
- [ ] Visitor cookie set on ALL responses (not gated by navigation detection)

#### 2. `lib/docs/sdk/api_contract.md`

Update the `POST /api/v1/sessions` section:

- **When to call**: Change from "on every new session" to "on every new session triggered by a **real page navigation**. Do NOT call for sub-requests (Turbo frames, htmx, fetch/XHR, prefetch)."
- Add a **"Navigation Detection"** subsection explaining that SDKs must implement `Sec-Fetch-*` header checking before calling this endpoint.
- Add guidance: "The API does not validate whether the request was a real navigation. This is the SDK's responsibility. Failing to implement navigation detection will inflate visit counts by the number of concurrent sub-requests per page load."

#### 3. `lib/docs/sdk/sdk_registry.md`

Update **SDK Development Guidelines / Required Behavior (v0.7.0+)** to add:
- `Navigation detection: Only create sessions for requests where Sec-Fetch-Mode: navigate AND Sec-Fetch-Dest: document (with framework blacklist fallback)`

Update **SDK Release Checklist / Code** to add:
- [ ] Navigation detection implemented (Sec-Fetch-* whitelist + framework blacklist fallback)
- [ ] Session creation only fires for real page navigations
- [ ] Tests verify sub-requests (Turbo, htmx, fetch, XHR, prefetch) do NOT create sessions

Update **SDK Features** table for each SDK to add:
- `✅ Navigation-aware session creation (Sec-Fetch-* whitelist)` — once implemented

Update **Version Compatibility Matrix** to add v0.8.0 row.

#### 4. New Document: `lib/docs/sdk/navigation_detection.md`

Create a standalone reference document that any SDK developer (internal or third-party) can follow to implement navigation detection. This becomes the canonical reference that the specification and registry point to.

Structure:
1. **Why** — The inflation problem, with concrete examples
2. **How browsers signal request type** — `Sec-Fetch-*` header reference
3. **The detection algorithm** — Full pseudocode with comments
4. **Implementation by language** — Ruby (Rack env), Node (Express req.headers), Python (Flask request.headers), PHP (PSR-7 getHeaderLine)
5. **Testing checklist** — Every scenario that must be tested
6. **Edge cases** — Old browsers, bots, HTTPS, prefetch, redirects
7. **Framework reference** — Every known framework and its identifying headers

### What This Means for New SDK Development

Anyone creating a new SDK (e.g., the planned Magento extension, or a Go/Rust/Java SDK) must implement navigation detection from day one. The spec and API contract now make this explicit. Without it, any server-side SDK deployed on a modern web framework will inflate visit counts.

---

## Diagnostic SQL Queries

### Confirm Inflation Source

```sql
-- Visitors created in bursts (confirms concurrent request inflation)
SELECT
  date_trunc('second', created_at) as second,
  COUNT(*) as visitors_created
FROM visitors
WHERE account_id = 2
  AND created_at > NOW() - INTERVAL '1 day'
GROUP BY 1
HAVING COUNT(*) > 3
ORDER BY visitors_created DESC
LIMIT 20;
```

### True vs Inflated Count

```sql
SELECT
  COUNT(DISTINCT visitor_id) as current_visits_count,
  COUNT(DISTINCT device_fingerprint) as true_unique_devices,
  ROUND(
    COUNT(DISTINCT visitor_id)::numeric /
    NULLIF(COUNT(DISTINCT device_fingerprint), 0), 1
  ) as inflation_factor
FROM sessions
WHERE account_id = 2
  AND started_at > NOW() - INTERVAL '7 days'
  AND is_test = false;
```

---

## Out of Scope

- Rewriting the session resolution architecture (server-side approach is sound once SDKs send clean data)
- Client-side JavaScript SDK changes (browser JS doesn't have access to Sec-Fetch headers and doesn't fire sub-requests the same way)
- Historical data backfill beyond the deduplication cleanup
- Changing how the dashboard counts visits (COUNT DISTINCT visitor_id is correct once visitor records are accurate)
- Card-vs-chart discrepancy (58k vs 63k) — this is correct behavior: a visitor with sessions in multiple channels appears once in card, once-per-channel in chart

---

## Key Code References

| File | Lines | What |
|------|-------|------|
| `mbuzz-ruby: lib/mbuzz/middleware/tracking.rb` | 40-52 | `skip_request?` — missing navigation detection |
| `mbuzz-ruby: lib/mbuzz/middleware/tracking.rb` | 93-95 | `generate_session_id` — random UUID (should be removed) |
| `mbuzz-ruby: lib/mbuzz/middleware/tracking.rb` | 139-145 | `set_session_cookie` — should be removed (v0.7.0 migration incomplete) |
| `mbuzz-ruby: lib/mbuzz.rb` | 30-31 | `SESSION_COOKIE_NAME`, `SESSION_COOKIE_MAX_AGE` — should be removed |
| `mbuzz-node: src/middleware/express.ts` | skip logic | Same missing navigation detection |
| `mbuzz-python: src/mbuzz/middleware/flask.py` | `_should_skip()` | Same missing navigation detection |
| `mbuzz-php: src/Mbuzz/Client.php` | `initFromRequest()` | Same missing navigation detection |
| `multibuzz: app/services/sessions/creation_service.rb` | 34-40 | Advisory lock keyed on session_id (should use fingerprint) |
| `multibuzz: app/services/sessions/creation_service.rb` | 108-126 | Canonical visitor detection (30s window — fails under concurrent txns) |
| `multibuzz: app/services/dashboard/queries/funnel_stages_query.rb` | 50-56 | Visits = `COUNT(DISTINCT visitor_id)` — correct once data is clean |
| `pet_resorts: config/initializers/mbuzz.rb` | 1-5 | Missing `skip_paths` (immediate mitigation) |
| `pet_resorts: app/views/application/_order_banner.html.erb` | 59-63 | Lazy turbo frame on every page (trigger) |
| `lib/docs/sdk/sdk_specification.md` | — | Missing navigation detection section |
| `lib/docs/sdk/api_contract.md` | 88-148 | Session creation — no navigation detection guidance |
| `lib/docs/sdk/sdk_registry.md` | 219-253 | Release checklist — missing navigation detection check |

---

## Code Review Findings (2026-02-02)

### Verified Against Codebase

All code references in the spec have been verified against the current codebase:

**Sessions::CreationService** — confirmed:
- Advisory lock keyed on `session_id` (line 34-40) — this is the core server-side issue
- `device_fingerprint` is received from SDK params (line 13-15), NOT computed server-side
- `find_canonical_by_fingerprint` queries sessions created within 30s (lines 114-126) — fails under concurrent transactions because the first txn hasn't committed
- Race condition handler (lines 164-182) catches `RecordNotUnique`/`RecordInvalid` and adopts the winning session's visitor — but this only helps when the same `session_id` collides, not different random ones

**Ruby SDK (`/Users/vlad/code/m/mbuzz-ruby/`)** — confirmed:
- `SESSION_COOKIE_NAME = "_mbuzz_sid"` still defined at `lib/mbuzz.rb:30`
- `SESSION_COOKIE_MAX_AGE = 30 * 60` still defined at `lib/mbuzz.rb:31`
- `generate_session_id` returns `SecureRandom.uuid` at `tracking.rb:93-95`
- `set_session_cookie` at `tracking.rb:139-145` — sets cookie on every response
- `skip_request?` at `tracking.rb:40-52` — only checks path and extension, no header inspection
- `create_session_async` at `tracking.rb:105-111` — fires in background `Thread.new`, gated only by `context[:new_session]` (no session cookie present)
- `build_request_context` at `tracking.rb:60-79` — correctly freezes context for thread safety, computes `device_fingerprint` as `SHA256(ip|user_agent)[0:32]`
- Existing test suite at `test/mbuzz/middleware/tracking_test.rb` (773 lines) covers cookie behavior, path filtering, thread safety — but has zero navigation detection tests

**Other SDKs exist** at `/Users/vlad/code/m/`: `mbuzz-node`, `mbuzz-python`, `mbuzz-php`, `mbuzz-shopify`

### Dual Fingerprint Sources (Architectural Note)

The codebase has **two different sources** for `device_fingerprint`:
1. **SDK-computed** (in `build_request_context`): `SHA256(ip|user_agent)[0:32]` — sent as a param to the server
2. **Server-computed** (in `ResolutionService`, `Events::ProcessingService`, `Conversions::TrackingService`): Same formula `SHA256(ip|user_agent)[0:32]`

These produce identical values (same formula). The server-side computation exists as a fallback for when the SDK doesn't send a fingerprint. This dual-source approach is fine — the Phase 6 advisory lock change should work with either source.

### Best Practice Research Findings

Research into the W3C Fetch Metadata Request Headers spec and browser behavior confirms the spec's approach is sound, with these additional edge cases to document:

| Edge Case | Behavior | Implication |
|-----------|----------|-------------|
| **Form POST submissions** | Send `Sec-Fetch-Mode: navigate`, `Sec-Fetch-Dest: document` | Will create sessions — correct for analytics (form submit = real navigation) |
| **iframe navigations** | Send `Sec-Fetch-Mode: navigate`, `Sec-Fetch-Dest: iframe` | Filtered by `dest != document` — correct |
| **`window.open()` / `target="_blank"`** | Send `navigate` + `document` | Creates session — correct (real user navigation) |
| **Redirects (3xx)** | `Sec-Fetch-Mode` stays `navigate` through chain; `Sec-Fetch-Site` recalculated per hop | No impact — redirected navigations are real navigations |
| **Service worker cache hit** | Request never reaches server | No session created — acceptable (cached page = no server visibility) |
| **HTTPS requirement** | Sec-Fetch headers only sent over HTTPS | All SDKs should be deployed behind HTTPS already; HTTP fallback uses blacklist path |
| **Non-browser clients** (curl, Postman, bots) | Can forge Sec-Fetch headers | Not a security concern — these are analytics headers, not auth. Bots without headers hit the blacklist fallback path |

**Key validation**: The `nested-navigate` proposal for iframes was abandoned — all browsers use `Sec-Fetch-Dest: iframe` instead, so the spec's `dest == "document"` check is the correct and stable approach.

### Spec Accuracy: Confirmed

No corrections needed to the spec's technical approach. The whitelist + blacklist fallback design is the industry-recommended pattern per the W3C spec and web.dev guidance. The `Sec-Purpose: prefetch` check covers both `<link rel="prefetch">` and speculative prerendering.
