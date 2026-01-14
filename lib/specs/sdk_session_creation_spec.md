# SDK Session Creation Specification

## Overview

This specification addresses the SDK requirements for the **server-side session resolution** architecture:

1. **Middleware must call `POST /api/v1/sessions`** to create visitors for new visitors
2. **Session resolution is SERVER-SIDE** - SDKs should NOT manage session cookies
3. **Return structured errors** instead of just `false` for better debugging

**Last Updated**: 2026-01-15
**Status**: In Progress

---

## Architecture Summary

### Key Principle: Server-Side Session Resolution

Per `lib/specs/1_visitor_session_tracking_spec.md` requirement R4 (SDK Simplification):

> **Remove from SDKs:**
> - Session cookie (`_mbuzz_sid`)
> - Session ID generation
> - Time-bucket calculations
>
> **Keep in SDKs:**
> - Visitor cookie (`_mbuzz_vid`) only
> - Add ip/user_agent/identifier to all API calls for server-side resolution

The server resolves sessions using:
- `device_fingerprint` = SHA256(ip|user_agent)[0:32]
- True 30-minute sliding window via `last_activity_at`
- Finds existing session OR creates new one automatically

### What SDKs MUST Do

1. **Generate and persist visitor_id** (64-char hex in `_mbuzz_vid` cookie)
2. **Call POST /api/v1/sessions for NEW visitors** (first request only)
3. **Include ip/user_agent in API calls** for server-side session resolution
4. **Return structured errors** instead of just `false`

### What SDKs MUST NOT Do

1. ~~Manage session cookies (`_mbuzz_sid`)~~ - Server handles this
2. ~~Generate session_id for events/conversions~~ - Server generates from fingerprint
3. ~~Calculate time buckets~~ - Server uses true sliding window

---

## Problem Statement

### The Visitor Creation Gap

After the `require_existing_visitor` specification was implemented, the server no longer creates visitors implicitly when processing events. This was intentional to prevent "orphan visitors" with corrupted attribution.

Most SDKs generate visitor IDs locally but never register them via `POST /api/v1/sessions`. This causes:

```
BROKEN Flow (most SDKs):
┌──────────────────────────────────────────────────────────────────┐
│ User visits site                                                  │
│     ↓                                                             │
│ SDK middleware generates visitor_id cookie                        │
│     ↓                                                             │
│ NO API call to create visitor ← GAP                               │
│     ↓                                                             │
│ User triggers event/conversion                                    │
│     ↓                                                             │
│ SDK sends to /api/v1/events or /api/v1/conversions               │
│     ↓                                                             │
│ Server: require_existing_visitor check                            │
│     - find_by(visitor_id) → nil (never created!)                 │
│     - Returns "Visitor not found" error                          │
│     ↓                                                             │
│ Event/Conversion REJECTED                                         │
└──────────────────────────────────────────────────────────────────┘
```

### Correct Flow

```
┌──────────────────────────────────────────────────────────────────┐
│ User visits site (first time)                                     │
│     ↓                                                             │
│ SDK middleware generates visitor_id, sets _mbuzz_vid cookie       │
│     ↓                                                             │
│ SDK calls POST /api/v1/sessions (async, non-blocking)            │
│     - Creates Visitor record                                      │
│     - Creates Session record with UTM/channel attribution         │
│     ↓                                                             │
│ User triggers event/conversion                                    │
│     ↓                                                             │
│ SDK sends to /api/v1/events (with ip + user_agent)               │
│     ↓                                                             │
│ Server: Visitors::LookupService                                   │
│     - find_by(visitor_id) → FOUND                                │
│     - Session resolved via device_fingerprint (server-side)      │
│     ↓                                                             │
│ Event/Conversion ACCEPTED                                         │
└──────────────────────────────────────────────────────────────────┘
```

---

## SDK Analysis Summary

| SDK | Calls /sessions? | Has session_id? | Has session cookie? | Returns errors? | Status |
|-----|------------------|-----------------|---------------------|-----------------|--------|
| **mbuzz-ruby** | ✅ YES | ✅ YES | ⚠️ YES (remove!) | ❌ Returns `false` | NEEDS CLEANUP |
| **mbuzz-node** | ❌ NO | ❌ NO | ✅ None | ❌ Returns `false` | BROKEN |
| **mbuzz-python** | ❌ NO | ❌ NO | ✅ None | ✅ Structured results | BROKEN |
| **mbuzz-php** | ❌ NO | ❌ NO | ✅ None | ❌ Returns `false` | BROKEN |
| **mbuzz-shopify** | ⚠️ YES | ❌ MISSING! | N/A (client-side) | ❌ Silent failures | BROKEN |

### Detailed Findings

#### mbuzz-ruby ✅ Mostly Working
- **Location**: `/Users/vlad/code/m/mbuzz-ruby/lib/mbuzz/`
- **Status**: Calls /sessions for new visitors, but has legacy session cookies
- **What's Working**:
  - `Client::SessionRequest` exists and calls POST /sessions
  - Middleware calls session creation asynchronously for new visitors
  - Generates session_id (required by Sessions::CreationService)
- **Issues**:
  - Has session cookie (`_mbuzz_sid`) that should be REMOVED per R4
  - Returns `false` on failure instead of structured error
  - `identify()` missing ip/user_agent for server-side resolution
- **Fix Required**:
  - Remove session cookie handling from middleware
  - Return structured errors with error codes
  - Add ip/user_agent to identify() calls

#### mbuzz-node ❌ Missing Session Creation
- **Location**: `/Users/vlad/code/m/mbuzz-node/src/`
- **Status**: BROKEN - no session creation
- **What's Working**:
  - Middleware generates visitor_id cookie
  - Session cookie correctly removed (comment: "Session cookie removed in 0.7.0")
- **Issues**:
  - No `POST /sessions` call - visitors never created!
  - Returns `false` on failure
  - `identify()` missing ip/user_agent
- **Fix Required**:
  - Add session creation call in middleware for new visitors
  - Return structured errors
  - Add ip/user_agent to all API calls

#### mbuzz-python ❌ Missing Session Creation (Good Error Handling)
- **Location**: `/Users/vlad/code/m/mbuzz-python/src/mbuzz/`
- **Status**: BROKEN - no session creation, but good error structure
- **What's Working**:
  - Middleware generates visitor_id
  - Session cookie correctly removed
  - Returns `TrackResult`/`ConversionResult` with structured data ✅
- **Issues**:
  - No `POST /sessions` call - visitors never created!
  - `identify()` missing ip/user_agent
- **Fix Required**:
  - Add session creation call in middleware for new visitors
  - Add `SessionResult` return type
  - Add ip/user_agent to identify()

#### mbuzz-php ❌ Missing Session Creation
- **Location**: `/Users/vlad/code/m/mbuzz-php/src/Mbuzz/`
- **Status**: BROKEN - no session creation
- **What's Working**:
  - Has middleware for Symfony/Laravel
  - No session cookies (correct)
- **Issues**:
  - No `POST /sessions` call - visitors never created!
  - Returns `false` on failure
  - `identify()` missing ip/user_agent
  - Context returns `null` for visitor_id if cookie missing (should generate!)
- **Fix Required**:
  - Add session creation call in middleware
  - Generate visitor_id if missing
  - Return structured errors
  - Add ip/user_agent to identify()

#### mbuzz-shopify ⚠️ Broken Session Creation
- **Location**: `/Users/vlad/code/m/mbuzz-shopify/extensions/mbuzz-tracking/assets/mbuzz-shopify.js`
- **Status**: BROKEN - calls /sessions but missing required session_id
- **What's Working**:
  - DOES call `POST /sessions`
  - Generates visitor_id
- **Issues**:
  - Missing `session_id` parameter - server returns 422 error!
  - Sessions::CreationService requires: visitor_id, session_id, url
  - SDK sends: visitor_id, url, referrer, user_agent (no session_id!)
- **Fix Required**:
  - Generate session_id (64-char hex)
  - Include session_id in /sessions payload

---

## Requirements

### R1: Middleware Must Call Sessions Endpoint for New Visitors

**When**: New visitor detected (no existing `_mbuzz_vid` cookie)
**Do**: Call `POST /api/v1/sessions` to create visitor + session
**How**: Async, non-blocking (fire and forget)

```
NEW VISITOR FLOW:
┌─────────────────────────────────────────────────────────────┐
│ Request arrives                                              │
│     ↓                                                        │
│ Check for _mbuzz_vid cookie                                  │
│     ↓                                                        │
│ Cookie missing? → Generate visitor_id + session_id          │
│     ↓                                                        │
│ Call POST /api/v1/sessions (async)                          │
│     ↓                                                        │
│ Set _mbuzz_vid cookie (2 years)                             │
│     ↓                                                        │
│ Continue with request                                        │
└─────────────────────────────────────────────────────────────┘

RETURNING VISITOR FLOW:
┌─────────────────────────────────────────────────────────────┐
│ Request arrives                                              │
│     ↓                                                        │
│ Check for _mbuzz_vid cookie                                  │
│     ↓                                                        │
│ Cookie exists? → Use existing visitor_id                    │
│     ↓                                                        │
│ NO session creation call (server handles session resolution)│
│     ↓                                                        │
│ Continue with request                                        │
└─────────────────────────────────────────────────────────────┘
```

### R2: Session Payload Requirements

All session creation calls must include:

```json
{
  "session": {
    "visitor_id": "64-char-hex-string",
    "session_id": "64-char-hex-string",
    "url": "https://example.com/page?utm_source=google",
    "referrer": "https://google.com/search",
    "started_at": "2026-01-14T20:00:00Z",
    "device_fingerprint": "32-char-hex-string"
  }
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `visitor_id` | YES | SDK-generated, stored in `_mbuzz_vid` cookie |
| `session_id` | YES | SDK-generated (for this initial call only) |
| `url` | YES | Current page URL with query params (captures UTM) |
| `referrer` | NO | HTTP referrer |
| `started_at` | NO | ISO8601 timestamp (defaults to now) |
| `device_fingerprint` | NO | SHA256(ip\|user_agent)[0:32] |

**Note**: `session_id` is only generated for the initial /sessions call. Subsequent events/conversions do NOT need session_id - the server resolves sessions via device_fingerprint.

### R3: NO Session Cookies in SDK

Per R4 of `1_visitor_session_tracking_spec.md`:

**REMOVE from SDKs:**
- Session cookie (`_mbuzz_sid`) - DELETE THIS
- Session ID generation for events/conversions
- Time-bucket calculations

**KEEP in SDKs:**
- Visitor cookie (`_mbuzz_vid`) only
- Session ID generation ONLY for initial /sessions call

### R4: Return Structured Errors

SDKs must return structured results instead of just `false`:

```ruby
# ✅ GOOD - Structured result
{
  success: false,
  error_code: "visitor_not_found",
  error_message: "Visitor vis_abc123 not found. Ensure session was created."
}

# ❌ BAD - Just false
false
```

**Error codes to support:**
| Code | Description |
|------|-------------|
| `visitor_not_found` | Visitor doesn't exist (session not created) |
| `rate_limit_exceeded` | Account has exceeded rate limit |
| `invalid_api_key` | API key is invalid or missing |
| `validation_error` | Required fields missing |
| `network_error` | Failed to reach API |

### R5: Include IP/User-Agent in API Calls

All API calls (events, conversions, identify) must include:

```json
{
  "event": {
    "visitor_id": "...",
    "event_type": "page_view",
    "ip": "203.0.113.42",
    "user_agent": "Mozilla/5.0..."
  }
}
```

This enables server-side session resolution via device_fingerprint.

### R6: Error Handling Strategy

- Session creation failures must NOT block the application
- Log errors if debug mode enabled
- Continue with event tracking even if session creation fails
- Return structured error result (not exceptions)

---

## Development Workflow

For EACH SDK, follow this cycle:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        FEATURE DEVELOPMENT CYCLE                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. SDK INTEGRATION TEST (RED)                                              │
│     └─ Location: ./sdk_integration_tests/scenarios/                         │
│     └─ Write failing test that calls /sessions endpoint                     │
│     └─ Test proves the SDK doesn't call sessions yet                        │
│                                                                              │
│  2. UNIT TESTS (RED)                                                        │
│     └─ SDK: mbuzz-{lang}/test/* or tests/*                                  │
│     └─ Write failing unit tests for session creation                        │
│     └─ Test middleware calls session service                                │
│                                                                              │
│  3. IMPLEMENTATION                                                          │
│     └─ SDK: Add session creation service/request class                      │
│     └─ SDK: Update middleware to call sessions endpoint                     │
│     └─ Minimal code to pass tests                                           │
│                                                                              │
│  4. UNIT TESTS (GREEN)                                                      │
│     └─ Run SDK test suite, all tests pass                                   │
│                                                                              │
│  5. SDK INTEGRATION TEST (GREEN)                                            │
│     └─ Run ./sdk_integration_tests/ against local                           │
│     └─ Proves feature works end-to-end                                      │
│                                                                              │
│  6. UPDATE SPEC                                                             │
│     └─ Mark checkbox [x] complete in this spec                              │
│     └─ Add any learnings or changes                                         │
│                                                                              │
│  7. GIT COMMIT                                                              │
│     └─ Sydney time: 2026-01-14 20:00-23:59 +11:00                           │
│     └─ Format: feat(sdk): add session creation to middleware                │
│                                                                              │
│  8. NEXT SDK                                                                │
│     └─ Repeat steps 1-7 for next SDK                                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Commit Convention

All commits use **2026-01-14** between **8pm-midnight Sydney time** (AEDT +11:00):

```bash
GIT_AUTHOR_DATE="2026-01-14T20:XX:XX+11:00" \
GIT_COMMITTER_DATE="2026-01-14T20:XX:XX+11:00" \
git commit -m "feat(sdk): description"
```

### SDK Development Order

```
PHASE 1: mbuzz-ruby (highest priority - pet_resorts uses this)
  └─ ./sdk_integration_tests/scenarios/session_creation_test.rb
  └─ /Users/vlad/code/m/mbuzz-ruby/test/
  └─ /Users/vlad/code/m/mbuzz-ruby/lib/mbuzz/

PHASE 2: mbuzz-shopify (already calls sessions, just needs session_id fix)
  └─ ./sdk_integration_tests/scenarios/session_creation_test.rb (SDK=shopify)
  └─ /Users/vlad/code/m/mbuzz-shopify/extensions/

PHASE 3: mbuzz-node
  └─ ./sdk_integration_tests/scenarios/session_creation_test.rb (SDK=node)
  └─ /Users/vlad/code/m/mbuzz-node/test/
  └─ /Users/vlad/code/m/mbuzz-node/src/

PHASE 4: mbuzz-python
  └─ ./sdk_integration_tests/scenarios/session_creation_test.rb (SDK=python)
  └─ /Users/vlad/code/m/mbuzz-python/tests/
  └─ /Users/vlad/code/m/mbuzz-python/src/mbuzz/

PHASE 5: mbuzz-php
  └─ ./sdk_integration_tests/scenarios/session_creation_test.rb (SDK=php)
  └─ /Users/vlad/code/m/mbuzz-php/tests/
  └─ /Users/vlad/code/m/mbuzz-php/src/Mbuzz/
```

---

## Implementation Checklist

### Phase 1: mbuzz-ruby (Cleanup - Already Works)

mbuzz-ruby already calls /sessions. It needs cleanup only:

- [x] **EXISTING**: SessionRequest class exists and works
  - File: `/Users/vlad/code/m/mbuzz-ruby/lib/mbuzz/client/session_request.rb`
  - Already calls POST /sessions with visitor_id, session_id, url

- [ ] **CLEANUP-001**: Remove session cookie handling
  - File: `/Users/vlad/code/m/mbuzz-ruby/lib/mbuzz/middleware/tracking.rb`
  - Remove `_mbuzz_sid` cookie setting
  - Keep `_mbuzz_vid` cookie only
  - Session_id only needed for initial /sessions call, not stored in cookie

- [ ] **CLEANUP-002**: Return structured errors
  - Files: `lib/mbuzz/client.rb`, `lib/mbuzz/client/*.rb`
  - Change `return false` to structured result hash
  - Include error_code and error_message

- [ ] **CLEANUP-003**: Add ip/user_agent to identify()
  - File: `/Users/vlad/code/m/mbuzz-ruby/lib/mbuzz.rb`
  - Pass ip/user_agent to Client.identify() for server-side resolution

- [ ] **COMMIT**: `fix(sdk-ruby): remove session cookie, add structured errors`

### Phase 2: mbuzz-shopify (Fix session_id)

- [ ] **FIX-001**: Add session_id to /sessions payload
  - File: `/Users/vlad/code/m/mbuzz-shopify/extensions/mbuzz-tracking/assets/mbuzz-shopify.js`
  - Generate session_id (64-char hex) using crypto.getRandomValues()
  - Include in session creation payload (one-time, not stored)
  - Note: session_id NOT needed for events/conversions (server-side resolution)

- [ ] **COMMIT**: `fix(sdk-shopify): add session_id to session creation`

### Phase 3: mbuzz-node (Add Session Creation)

- [ ] **IMPL-001**: Add session creation service
  - File: `/Users/vlad/code/m/mbuzz-node/src/client/session.ts`
  - POST /sessions with visitor_id, session_id, url, referrer, device_fingerprint

- [ ] **IMPL-002**: Update middleware to call /sessions for new visitors
  - File: `/Users/vlad/code/m/mbuzz-node/src/middleware/express.ts`
  - Detect new visitor (no _mbuzz_vid cookie)
  - Generate visitor_id + session_id
  - Call /sessions async (non-blocking)
  - Set _mbuzz_vid cookie only (NO session cookie)

- [ ] **IMPL-003**: Add structured error returns
  - Change `false` returns to `{ success: false, error_code: '...' }`

- [ ] **IMPL-004**: Add ip/user_agent to all API calls
  - Events, conversions, identify all need ip/user_agent for server-side session resolution

- [ ] **COMMIT**: `feat(sdk-node): add session creation with structured errors`

### Phase 4: mbuzz-python (Add Session Creation)

- [ ] **IMPL-005**: Add session creation service
  - File: `/Users/vlad/code/m/mbuzz-python/src/mbuzz/client/session.py`
  - Add `SessionResult` dataclass like existing `TrackResult`

- [ ] **IMPL-006**: Update Flask middleware
  - File: `/Users/vlad/code/m/mbuzz-python/src/mbuzz/middleware/flask.py`
  - Call /sessions for new visitors
  - Keep only _mbuzz_vid cookie (already correct)

- [ ] **IMPL-007**: Add ip/user_agent to identify()
  - Already has good error structure, just needs session creation

- [ ] **COMMIT**: `feat(sdk-python): add session creation`

### Phase 5: mbuzz-php (Add Session Creation + Visitor Generation)

- [ ] **IMPL-008**: Generate visitor_id when missing
  - File: `/Users/vlad/code/m/mbuzz-php/src/Mbuzz/Context.php`
  - Currently returns null; generate 64-char hex instead

- [ ] **IMPL-009**: Add session request class
  - File: `/Users/vlad/code/m/mbuzz-php/src/Mbuzz/Request/SessionRequest.php`

- [ ] **IMPL-010**: Update framework middleware
  - Files: `src/Mbuzz/Framework/SymfonySubscriber.php`, `LaravelMiddleware.php`
  - Call /sessions for new visitors
  - Set _mbuzz_vid cookie only

- [ ] **IMPL-011**: Return structured errors
  - Change `false` returns to arrays with error info

- [ ] **COMMIT**: `feat(sdk-php): add session creation with visitor generation`

---

## Phase 6: pet_resorts Integration

### Issues Found

Location: `/Users/vlad/code/pet_resorts/`

| Issue | Location | Fix | Status |
|-------|----------|-----|--------|
| ~~Using raw user.id~~ | Mta::Identify | Use user.prefix_id | ✅ FIXED |
| Missing visitor_id | Mta::Track, Convert | Auto-resolved by middleware | ✅ OK |
| Session creation | mbuzz-ruby railtie | Auto-installs middleware | ✅ OK |

### Analysis

**Good News**: The integration is mostly correct!

1. **mbuzz-ruby railtie** auto-installs `Mbuzz::Middleware::Tracking` in Rails apps
2. **All MTA calls** are from controllers (request context), so visitor_id is auto-resolved
3. **Mbuzz.event/conversion** fall back to `Mbuzz.visitor_id` which reads from request context

### Implementation

- [x] **PET-001**: Ensure mbuzz-ruby middleware is configured
  - ✅ Railtie auto-installs middleware: `app.middleware.use Mbuzz::Middleware::Tracking`
  - ✅ Mbuzz.init() called in `config/initializers/mbuzz.rb`

- [x] **PET-002**: Mta::Track service - NO CHANGE NEEDED
  - File: `/Users/vlad/code/pet_resorts/app/services/mta/track.rb`
  - `Mbuzz.event()` auto-resolves visitor_id from RequestContext
  - Called from controllers only, so middleware has set up context

- [x] **PET-003**: Mta::Convert service - NO CHANGE NEEDED
  - File: `/Users/vlad/code/pet_resorts/app/services/mta/convert.rb`
  - Same as Track - auto-resolved from RequestContext

- [x] **PET-004**: Update Mta::Identify service - FIXED
  - File: `/Users/vlad/code/pet_resorts/app/services/mta/identify.rb`
  - Changed `user.id` to `user.prefix_id` (security fix)

- [x] **PET-005**: Background jobs - NOT APPLICABLE
  - All MTA calls are from controllers
  - No background job MTA usage found

- [ ] **COMMIT**: `fix(pet_resorts): use prefix_id for identify service`

---

## Phase 7: Documentation Updates

All documentation must be updated to reflect the new architecture.

### SDK READMEs

- [ ] **DOC-001**: mbuzz-ruby README
  - File: `/Users/vlad/code/m/mbuzz-ruby/README.md`
  - Remove any session cookie references
  - Explain automatic visitor creation via middleware
  - Document structured error returns

- [ ] **DOC-002**: mbuzz-node README
  - File: `/Users/vlad/code/m/mbuzz-node/README.md`
  - Add session creation documentation
  - Document middleware setup

- [ ] **DOC-003**: mbuzz-python README
  - File: `/Users/vlad/code/m/mbuzz-python/README.md`
  - Add session creation documentation

- [ ] **DOC-004**: mbuzz-php README
  - File: `/Users/vlad/code/m/mbuzz-php/README.md`
  - Add visitor_id generation documentation
  - Add session creation documentation

- [ ] **DOC-005**: mbuzz-shopify README
  - File: `/Users/vlad/code/m/mbuzz-shopify/README.md`
  - Document session_id requirement fix

### Application Documentation (app/views/docs)

- [ ] **DOC-006**: SDK Installation Guide
  - File: `/Users/vlad/code/m/multibuzz/app/views/docs/` (find relevant file)
  - Explain middleware auto-creates visitors
  - Remove session cookie setup instructions
  - Add error handling examples

- [ ] **DOC-007**: API Reference - Sessions Endpoint
  - File: `/Users/vlad/code/m/multibuzz/app/views/docs/` (find relevant file)
  - Document POST /api/v1/sessions payload
  - Explain when SDK calls this automatically

- [ ] **DOC-008**: Troubleshooting Guide
  - Add "Visitor not found" error explanation
  - Add "Rate limit exceeded" explanation
  - Explain how to verify session creation is working

### Onboarding Documentation

- [ ] **DOC-009**: Quick Start Guide
  - Simplify: just install SDK + add middleware
  - Emphasize middleware handles visitor/session creation
  - Remove manual session setup steps

- [ ] **DOC-010**: Integration Checklist
  - Add verification step: check sessions being created
  - Add debugging tips for common errors

### Architecture Documentation

- [ ] **DOC-011**: Update lib/docs/architecture/
  - Document server-side session resolution
  - Document device_fingerprint calculation
  - Remove client-side session management references

### lib/specs Updates

- [ ] **DOC-012**: Update 1_visitor_session_tracking_spec.md
  - Mark R4 (SDK Simplification) as implemented
  - Add links to SDK implementations

---

## Technical Design Details

### Session Creation Payload (POST /api/v1/sessions)

```ruby
# Ruby example - called ONCE for new visitors
{
  session: {
    visitor_id: "a1b2c3d4...",        # 64-char hex, stored in _mbuzz_vid cookie
    session_id: "x1y2z3w4...",        # 64-char hex, generated for this call only
    url: request.url,                  # Full URL with query params (UTM capture)
    referrer: request.referrer,        # HTTP referrer
    started_at: Time.current.iso8601,  # ISO8601 timestamp
    device_fingerprint: fingerprint    # SHA256(ip|ua)[0:32] (optional)
  }
}
```

### Visitor Cookie Management (ONLY cookie in SDK)

```ruby
# Cookie settings - VISITOR COOKIE ONLY
VISITOR_COOKIE_NAME = "_mbuzz_vid"
VISITOR_COOKIE_MAX_AGE = 60 * 60 * 24 * 365 * 2  # 2 years

# NO SESSION COOKIE - Server handles session resolution!

# New visitor detection
def new_visitor?
  visitor_id_from_cookie.nil?
end

def visitor_id
  @visitor_id ||= visitor_id_from_cookie || generate_visitor_id
end

def generate_visitor_id
  SecureRandom.hex(32)  # 64-char hex
end
```

### Async Session Creation (Non-Blocking)

```ruby
# Ruby - Thread-based (only for NEW visitors)
def create_session_for_new_visitor
  return unless new_visitor?

  # Generate IDs
  vid = generate_visitor_id
  sid = SecureRandom.hex(32)  # session_id for this call only

  Thread.new do
    Mbuzz::Client::SessionRequest.new(
      visitor_id: vid,
      session_id: sid,
      url: request.url,
      referrer: request.referrer
    ).call
  rescue StandardError => e
    Mbuzz.config.logger&.error("[mbuzz] Session creation failed: #{e.message}")
  end

  vid  # Return visitor_id to set in cookie
end
```

```javascript
// JavaScript - Promise-based (only for NEW visitors)
function createSessionForNewVisitor(request) {
  const existingVisitorId = getCookie('_mbuzz_vid');
  if (existingVisitorId) return existingVisitorId;  // Not new

  // Generate IDs
  const visitorId = generateHex(32);  // 64-char
  const sessionId = generateHex(32);  // For this call only

  // Fire and forget - don't await
  fetch(`${apiUrl}/sessions`, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      session: {
        visitor_id: visitorId,
        session_id: sessionId,
        url: request.url,
        referrer: request.headers.referer
      }
    })
  }).catch(err => console.error('[mbuzz] Session creation failed:', err));

  return visitorId;  // Set in cookie
}
```

### Device Fingerprint Calculation (Server-Side)

The server calculates this from ip + user_agent passed in API calls:

```ruby
# Server-side (in Multibuzz)
def device_fingerprint(ip, user_agent)
  Digest::SHA256.hexdigest("#{ip}|#{user_agent}")[0, 32]
end
```

SDKs must pass ip/user_agent in all API calls to enable this:

```ruby
# SDK event call
Mbuzz.event("page_view",
  visitor_id: visitor_id,
  ip: request.ip,
  user_agent: request.user_agent,
  # ... other params
)
```

### Structured Error Response Format

```ruby
# Success
{
  success: true,
  visitor_id: "vis_abc123...",
  session_id: "sess_xyz789..."
}

# Failure
{
  success: false,
  error_code: "visitor_not_found",
  error_message: "Visitor not found. Ensure middleware created session on first visit."
}
```

---

## Verification Commands

```bash
# 1. SDK Integration Tests
cd /Users/vlad/code/m/multibuzz/sdk_integration_tests
SDK=ruby bundle exec ruby -Ilib scenarios/session_creation_test.rb
SDK=shopify bundle exec ruby -Ilib scenarios/session_creation_test.rb
SDK=node bundle exec ruby -Ilib scenarios/session_creation_test.rb
SDK=python bundle exec ruby -Ilib scenarios/session_creation_test.rb
SDK=php bundle exec ruby -Ilib scenarios/session_creation_test.rb

# 2. SDK Unit Tests
cd /Users/vlad/code/m/mbuzz-ruby && bundle exec rake test
cd /Users/vlad/code/m/mbuzz-node && npm test
cd /Users/vlad/code/m/mbuzz-python && python -m pytest
cd /Users/vlad/code/m/mbuzz-php && ./vendor/bin/phpunit

# 3. API Tests (ensure server accepts sessions)
cd /Users/vlad/code/m/multibuzz && bin/rails test
```

---

## Success Criteria

After implementation:

1. **New visitors** immediately create session via `/api/v1/sessions`
2. **Events and conversions** succeed because visitor exists
3. **Attribution is correct** because session captures UTM/referrer
4. **No duplicate sessions** for concurrent requests (server handles dedup)
5. **Backward compatible** - existing clients continue to work

### Metrics to Monitor

| Metric | Before Fix | After Fix |
|--------|------------|-----------|
| "Visitor not found" errors | High | Near zero |
| Sessions created via /sessions | Low | High |
| Conversion success rate | Low | Normal |
| Attribution accuracy | Corrupted | Correct |

---

## Rollback Plan

If issues arise:

1. **Server-side**: The `require_existing_visitor` change can be reverted to auto-create visitors (not recommended - brings back orphan problem)

2. **Client-side**: SDK releases can be rolled back to previous versions

3. **Graceful degradation**: Server fingerprint fallback continues to work for 30 seconds after session creation

---

## Related Documents

| Document | Relationship |
|----------|--------------|
| `lib/specs/require_existing_visitor_spec.md` | Root cause - server now requires existing visitors |
| `lib/specs/1_visitor_session_tracking_spec.md` | Parent spec for visitor/session architecture |
| `lib/docs/sdk/api_contract.md` | API contract for /sessions endpoint |
| `lib/docs/architecture/server_side_attribution_architecture.md` | Attribution flow documentation |
| `mbuzz-ruby/lib/specs/old/v2.0.0_sessions_upgrade.md` | Original (unimplemented) session upgrade spec |

---

## Progress Log

| Date | Item | Status |
|------|------|--------|
| 2026-01-14 | Spec created | Complete |
| 2026-01-14 | SDK analysis complete | Complete |
| 2026-01-15 | Spec updated with correct architecture | Complete |
| 2026-01-15 | Added pet_resorts integration section | Complete |
| 2026-01-15 | Added documentation updates section | Complete |
| 2026-01-15 | Phase 6: pet_resorts - Fixed user.id to prefix_id | Complete |
| - | Phase 1: mbuzz-ruby (cleanup) | Pending |
| - | Phase 2: mbuzz-shopify (fix session_id) | Pending |
| - | Phase 3: mbuzz-node (add session creation) | Pending |
| - | Phase 4: mbuzz-python (add session creation) | Pending |
| - | Phase 5: mbuzz-php (add session creation) | Pending |
| - | Phase 7: Documentation updates | Pending |
