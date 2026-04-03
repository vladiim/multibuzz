# API Contract for SDK Developers

**Purpose**: Define the exact API behavior that all SDKs must implement to remain compatible with the mbuzz backend.

**Last Updated**: 2026-01-09
**Backend Version**: 1.4.0

---

## Base URL

**Production**: `https://mbuzz.co/api/v1`
**Staging**: `https://staging.mbuzz.co/api/v1` (if available)

All endpoints are relative to this base URL.

---

## Identity Model

Understanding the identity model is essential for correct SDK implementation.

### Core Entities

| Entity | Description | Identifier |
|--------|-------------|------------|
| **Visitor** | Anonymous browser/device | `visitor_id` (SDK-generated, stored in cookie) |
| **Identity** | Known, identified individual | `user_id` (customer-provided, stored as `external_id`) |
| **Session** | A single visit with acquisition context | `session_id` (SDK-generated, stored in cookie) |

**Note**: The API accepts `user_id` in requests for SDK compatibility, but internally stores this as `Identity.external_id`. The term "Identity" avoids confusion with dashboard admin Users.

### Identity Resolution

A single person may have multiple visitors (multiple devices). When a user is identified (signup, login), the visitor is linked to the user:

```
Visitor (desktop) ──┐
                    ├──→ User (jane@example.com)
Visitor (mobile) ───┘
```

This link is **bidirectional in time**:
- **Backward**: All past sessions from the visitor are attributed to the user
- **Forward**: All future sessions from the visitor are attributed to the user

### Attribution Flow

When a conversion occurs:
1. Find the converting visitor/user
2. Find ALL visitors linked to that user
3. Find ALL sessions from those visitors (within lookback window)
4. Apply attribution models across all sessions

---

## Authentication

### API Key Format

**Test Keys**: `sk_test_{32_char_hex}`
**Live Keys**: `sk_live_{32_char_hex}`

**Example**:
```
sk_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
```

### Request Header

**Required header**:
```
Authorization: Bearer {api_key}
```

**Example**:
```http
POST /api/v1/events HTTP/1.1
Host: mbuzz.co
Authorization: Bearer sk_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
Content-Type: application/json
```

---

## Endpoints

### POST /api/v1/sessions

**Purpose**: Create a session when a visitor lands on the site. This is the foundation of attribution tracking.

**When to call**: SDK middleware should call this on every new session triggered by a **real page navigation**. Do NOT call for sub-requests (Turbo frames, htmx partials, fetch/XHR, prefetch, iframes).

> **Navigation Detection (v0.7.3+)**: SDKs MUST implement `Sec-Fetch-*` header checking before calling this endpoint. The API does not validate whether the request was a real navigation — this is the SDK's responsibility. Failing to implement navigation detection will inflate visit counts by the number of concurrent sub-requests per page load (typically 3-5x). See [Navigation Detection Reference](./navigation_detection.md) for the full algorithm.

**Request Headers**:
```
Authorization: Bearer {api_key}
Content-Type: application/json
User-Agent: mbuzz-ruby/1.0.0 (Ruby/3.2.0)
X-Forwarded-For: 1.2.3.4          # Visitor's real IP (for server-side SDKs)
X-Mbuzz-User-Agent: Mozilla/5.0... # Visitor's real UA (for server-side SDKs)
```

**Request Body**:
```json
{
  "session": {
    "visitor_id": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
    "session_id": "x1y2z3a4b5c6d7e8f9g0h1i2j3k4l5m6x1y2z3a4b5c6d7e8f9g0h1i2j3k4l5m6",
    "url": "https://example.com/landing?utm_source=google&utm_medium=cpc&utm_campaign=q4",
    "referrer": "https://www.google.com/search?q=analytics",
    "device_fingerprint": "ea687534a507e203bdef87cee3cc60c5",
    "started_at": "2025-11-28T10:30:00Z"
  }
}
```

**Required Fields**:
- `visitor_id` (String, 64 hex chars) - SDK-generated visitor identifier
- `session_id` (String, UUID v4 or 64 hex chars) - SDK-generated session identifier
- `url` (String) - Full landing page URL including query parameters

**Optional Fields**:
- `referrer` (String) - Referring URL
- `device_fingerprint` (String, 32 hex chars) - `SHA256(ip|user_agent)[0:32]` — enables server-side advisory lock serialization for concurrent requests from the same device
- `started_at` (String, ISO8601) - Session start time (defaults to now)

**What the API does**:
1. Creates Visitor record (if new visitor_id)
2. Creates Session record with:
   - UTM parameters extracted from URL
   - Referrer host/path extracted
   - Channel derived (paid_search, organic, email, etc.)
   - Landing page stored
3. Queues processing to background job (fast response)

**Success Response** (202 Accepted):
```json
{
  "status": "accepted",
  "visitor_id": "a1b2c3d4...",
  "session_id": "x1y2z3a4...",
  "channel": "paid_search"
}
```

**SDK Behavior**:
- Call asynchronously (fire and forget)
- Do NOT block the customer's page render
- Log errors but don't raise exceptions

---

### POST /api/v1/events

**Purpose**: Track events (custom actions, conversions, etc.)

**Request Headers**:
```
Authorization: Bearer {api_key}
Content-Type: application/json
User-Agent: Mozilla/5.0...  # Browser's User-Agent (for server-side session resolution)
```

**Request Body** (batch format - preferred):
```json
{
  "events": [
    {
      "event_type": "add_to_cart",
      "visitor_id": "a1b2c3d4e5f6...",
      "ip": "192.168.1.100",
      "user_agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)...",
      "properties": {
        "url": "https://example.com/product/123",
        "referrer": "https://example.com/catalog",
        "product_id": "SKU-123",
        "price": 49.99
      },
      "timestamp": "2025-11-28T10:35:00Z"
    }
  ]
}
```

**Required Fields**:
- `event_type` (String) - Name of the event
- `visitor_id` OR `user_id` (String) - At least one required

**Server-Side Session Resolution Fields** (v1.3.0+):
- `ip` (String) - Client's IP address (for device fingerprinting)
- `user_agent` (String) - Client's User-Agent string (for device fingerprinting)
- `identifier` (Object, optional) - Cross-device identity resolution (e.g., `{ "email": "user@example.com" }`)

When both `ip` and `user_agent` are provided, the API resolves sessions server-side using a true 30-minute sliding window. This is the **preferred method** for server-side SDKs (Ruby, Python, PHP, Node).

When `identifier` is provided, the API can resolve sessions across devices by finding other visitors linked to the same identity.

For browser-based SDKs (JavaScript), these values are captured from HTTP request headers automatically.

**Legacy Fields** (deprecated, but still supported):
- `session_id` (String) - Client-generated session ID. Ignored when `ip` and `user_agent` are present.

**Recommended Fields**:
- `properties.url` (String) - Current page URL
- `properties.referrer` (String) - Referring URL

**Optional Fields**:
- `properties` (Object) - Custom event metadata
- `timestamp` (String, ISO8601) - When event occurred (defaults to now)

**Success Response** (202 Accepted):
```json
{
  "accepted": 1,
  "rejected": [],
  "events": [
    {
      "id": "evt_abc123",
      "event_type": "add_to_cart",
      "visitor_id": "a1b2c3d4...",
      "session_id": "x1y2z3a4...",
      "status": "accepted"
    }
  ]
}
```

**Billing Blocked Response** (202 Accepted):

When the account cannot accept events due to billing issues (exceeded quota, payment failed, etc.):

```json
{
  "accepted": 0,
  "rejected": [],
  "events": [],
  "billing_blocked": true,
  "billing_error": "Account cannot accept events"
}
```

---

### POST /api/v1/conversions

**Purpose**: Track conversions and calculate attribution

**Request Body**:
```json
{
  "conversion": {
    "visitor_id": "a1b2c3d4e5f6...",
    "conversion_type": "purchase",
    "revenue": 99.99,
    "currency": "USD",
    "properties": {
      "order_id": "ORD-123"
    }
  }
}
```

**Required Fields**:
- `conversion_type` (String) - e.g., "purchase", "signup", "trial_start"
- `visitor_id` OR `event_id` (String) - At least one required

**Optional Fields**:
- `revenue` (Number) - Conversion value
- `currency` (String) - Currency code (default: USD)
- `properties` (Object) - Custom metadata
- `user_id` (String) - Links conversion to an Identity (required for acquisition features)
- `is_acquisition` (Boolean) - Mark this as the acquisition conversion for this user (default: false)
- `inherit_acquisition` (Boolean) - Inherit attribution from user's acquisition conversion (default: false)
- `ip` (String) - Client's IP address (for visitor fallback via fingerprint)
- `user_agent` (String) - Client's User-Agent string (for visitor fallback via fingerprint)
- `identifier` (Object) - Cross-device identity resolution (e.g., `{ "email": "user@example.com" }`)

**Recurring Revenue Attribution**:

For SaaS/subscription businesses, use `is_acquisition` and `inherit_acquisition` to link recurring payments back to original customer acquisition:

```json
// Step 1: Mark signup as acquisition conversion
{
  "conversion": {
    "user_id": "user_123",
    "conversion_type": "signup",
    "is_acquisition": true
  }
}

// Step 2: Track payment with inherited attribution
{
  "conversion": {
    "user_id": "user_123",
    "conversion_type": "payment",
    "revenue": 49.00,
    "inherit_acquisition": true
  }
}
```

When `inherit_acquisition: true`:
1. Finds the user's acquisition conversion (where `is_acquisition: true`)
2. Copies attribution credits from that conversion
3. Recalculates `revenue_credit` based on THIS conversion's revenue

This enables LTV by acquisition channel, CAC payback analysis, and retention by source reporting.

**Success Response** (201 Created):
```json
{
  "conversion": {
    "id": "conv_xyz789",
    "conversion_type": "purchase",
    "revenue": "99.99",
    "converted_at": "2025-11-28T10:35:00Z",
    "visitor_id": "vis_abc123"
  },
  "attribution": {
    "status": "pending"
  }
}
```

**Note**: Attribution is calculated asynchronously. The initial response returns `"status": "pending"`. Attribution credits can be retrieved via the dashboard or API once processing completes (typically within seconds).

---

### POST /api/v1/identify

**Purpose**: Associate traits with a user ID and optionally link to a visitor. This endpoint also handles cross-device attribution by linking anonymous visitors to known users.

**When to call**: On signup, login, or when user attributes change

**Request Body**:
```json
{
  "user_id": "user_123",
  "visitor_id": "a1b2c3d4e5f6...",
  "traits": {
    "email": "jane@example.com",
    "name": "Jane Doe",
    "plan": "pro",
    "company": "Acme Inc"
  }
}
```

**Required Fields**:
- `user_id` (String) - Your application's user identifier

**Optional Fields**:
- `visitor_id` (String) - Links this visitor to the user (enables cross-device attribution)
- `traits` (Object) - User attributes

**What happens when visitor_id is provided**:
- Creates Visitor → Identity link
- **Backward**: All past sessions from this visitor attributed to user
- **Forward**: All future sessions from this visitor attributed to user
- **Retroactive Attribution**: If the identity has other linked visitors with existing conversions, and the newly-linked visitor has sessions within those conversions' lookback windows, attribution is automatically recalculated to include the new touchpoints

**Success Response** (200 OK):
```json
{
  "success": true,
  "identity_id": "idt_abc123def456",
  "visitor_linked": true
}
```

**Response Fields**:
- `success` (Boolean) - Whether the operation succeeded
- `identity_id` (String) - The prefixed ID of the identity record
- `visitor_linked` (Boolean) - Whether a visitor was linked to the identity (false if visitor_id not provided or not found)

**Note**: The `/api/v1/alias` endpoint has been deprecated. Use `identify` with `visitor_id` for cross-device linking.

---

### GET /api/v1/validate

**Purpose**: Validate an API key

**Success Response** (200 OK):
```json
{
  "valid": true,
  "account": {
    "id": "acct_abc123",
    "name": "Acme Inc"
  }
}
```

---

### GET /api/v1/health

**Purpose**: Check API health (no auth required)

**Success Response** (200 OK):
```json
{
  "status": "ok",
  "version": "1.0.0"
}
```

---

## Data Types & Formats

### Visitor ID

**Format**: 64-character hex string
**Generation**: `SecureRandom.hex(32)` or equivalent
**Lifetime**: 2 years
**Storage**: Cookie named `_mbuzz_vid`

**Cookie attributes**:
```
_mbuzz_vid=<64 hex chars>; Max-Age=63072000; Path=/; HttpOnly; SameSite=Lax; Secure
```

### Session ID

**Format**: 64-character hex string
**Lifetime**: 30 minutes (sliding expiry)

**Resolution Methods**:

| Method | When Used | How It Works |
|--------|-----------|--------------|
| Server-side (preferred) | `ip` and `user_agent` provided in event | API resolves session using device fingerprint + 30-min sliding window |
| Client-side (legacy) | `session_id` provided, no `ip`/`user_agent` | SDK generates and manages session ID |

**Server-side resolution** (v1.3.0+):
- API generates `device_fingerprint = SHA256(ip\|user_agent)[0:32]`
- Finds existing session for visitor + device fingerprint with activity < 30 min ago
- Creates new session if no active session found
- Uses deterministic ID generation for concurrent request handling

**Client-side resolution** (legacy - deprecated in SDK v0.7.0):
- **Storage**: Cookie named `_mbuzz_sid` (no longer used in v0.7.0+ SDKs)
- **Generation**: `SecureRandom.hex(32)` or equivalent
- **Cookie attributes**: `_mbuzz_sid=<64 hex chars>; Max-Age=1800; Path=/; HttpOnly; SameSite=Lax; Secure`
- **New session when**: No session cookie exists OR session cookie expired (30+ minutes since last activity)

**Migration path**: SDKs v0.7.0+ use server-side resolution exclusively. The `_mbuzz_sid` cookie is no longer set or read. All SDKs now send `ip` and `user_agent` with events, and the server handles session resolution with a true 30-minute sliding window.

### User ID

**Format**: Any string (max 255 characters)
**Examples**: `"user_123"`, `"12345"`, `"usr_a1b2c3"`, `"jane@example.com"`

### Timestamps

**Format**: ISO8601 with timezone (UTC preferred)

**Valid**:
```
2025-11-28T10:30:00Z
2025-11-28T10:30:00.123Z
2025-11-28T10:30:00+00:00
```

### Properties Object

**Type**: JSON object (hash/dictionary)
**Max Size**: 64KB
**Max Depth**: 5 levels of nesting

**Reserved property keys** (SDK should populate):
- `url` - Current page URL (for UTM extraction)
- `referrer` - Referring URL (for channel attribution)

---

## Error Handling

### HTTP Status Codes

| Code | Meaning | SDK Action |
|------|---------|------------|
| 200 | Success | Return true |
| 201 | Created | Return true |
| 202 | Accepted | Return true (processing async) |
| 401 | Invalid API key | Log error, return false |
| 422 | Validation error | Log error, return false |
| 429 | Rate limit | Log error, return false |
| 500 | Server error | Log error, may retry |

### SDK Behavior on Errors

**MUST NOT**:
- Raise exceptions to application code
- Block application execution
- Crash the customer's app

**MUST**:
- Return `false` on any error
- Log error if debug mode enabled
- Continue application execution

---

## SDK Feature Requirements

### Core (Required)

- ✅ Event tracking (`POST /events`)
- ✅ Visitor ID generation and cookie management
- ✅ Authentication (Bearer token)
- ✅ Error handling (never raise exceptions)

### Standard (Recommended)

- ✅ Server-side session resolution (include `ip` and `user_agent` in events) - v1.3.0+
- ✅ User identification with cross-device linking (`POST /identify`)
- ✅ Include URL and referrer in event properties
- ✅ Conversion tracking (`POST /conversions`)
- ✅ Session creation (`POST /sessions`) - async, on real page navigations only
- ✅ Navigation detection (`Sec-Fetch-*` whitelist + framework blacklist fallback) - v0.7.3+
- ✅ Device fingerprint (`SHA256(ip|user_agent)[0:32]`) in session creation - v0.7.3+

### Legacy (Deprecated)

- ⚠️ Client-side session ID generation - replaced by server-side resolution
- ⚠️ Session ID cookie management (`_mbuzz_sid`) - no longer needed with server-side resolution

### Advanced (Optional)

- Batch event sending
- Offline queueing
- Custom HTTP client
- Event sampling

---

## Related Documentation

- [Identity & Sessions Spec](../../specs/identity_and_sessions_spec.md) - Core concepts
- [SDK Registry](./sdk_registry.md) - List of all SDKs
- [Event Properties](../architecture/event_properties.md) - Property extraction details
