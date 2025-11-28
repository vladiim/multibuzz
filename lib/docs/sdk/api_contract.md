# API Contract for SDK Developers

**Purpose**: Define the exact API behavior that all SDKs must implement to remain compatible with the mbuzz backend.

**Last Updated**: 2025-11-28
**Backend Version**: 1.1.0

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

**When to call**: SDK middleware should call this on every new session (no session cookie, or session expired).

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
    "started_at": "2025-11-28T10:30:00Z"
  }
}
```

**Required Fields**:
- `visitor_id` (String, 64 hex chars) - SDK-generated visitor identifier
- `session_id` (String, 64 hex chars) - SDK-generated session identifier
- `url` (String) - Full landing page URL including query parameters

**Optional Fields**:
- `referrer` (String) - Referring URL
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
User-Agent: mbuzz-ruby/1.0.0 (Ruby/3.2.0)
```

**Request Body** (batch format - preferred):
```json
{
  "events": [
    {
      "event_type": "add_to_cart",
      "visitor_id": "a1b2c3d4e5f6...",
      "session_id": "x1y2z3a4b5c6...",
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

**Recommended Fields**:
- `session_id` (String) - Links event to session for attribution
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

**Success Response** (201 Created):
```json
{
  "conversion": {
    "id": "conv_xyz789",
    "conversion_type": "purchase",
    "revenue": "99.99"
  },
  "attribution": {
    "lookback_days": 30,
    "sessions_analyzed": 3,
    "models": {
      "first_touch": [
        { "channel": "paid_search", "credit": 1.0, "revenue_credit": "99.99" }
      ],
      "last_touch": [
        { "channel": "email", "credit": 1.0, "revenue_credit": "99.99" }
      ],
      "linear": [
        { "channel": "paid_search", "credit": 0.33, "revenue_credit": "33.00" },
        { "channel": "organic_social", "credit": 0.33, "revenue_credit": "33.00" },
        { "channel": "email", "credit": 0.34, "revenue_credit": "33.99" }
      ]
    }
  }
}
```

---

### POST /api/v1/identify

**Purpose**: Associate traits with a user ID and optionally link to a visitor

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
- `visitor_id` (String) - Links this visitor to the user (creates alias)
- `traits` (Object) - User attributes

**What happens when visitor_id is provided**:
- Creates Visitor → User link
- All past sessions from this visitor attributed to user
- All future sessions from this visitor attributed to user

**Success Response** (200 OK):
```json
{
  "success": true
}
```

---

### POST /api/v1/alias

**Purpose**: Explicitly link a visitor to a user (for cross-device tracking)

**When to call**: After login, when you want to link anonymous browsing to a known user

**Request Body**:
```json
{
  "visitor_id": "a1b2c3d4e5f6...",
  "user_id": "user_123"
}
```

**Required Fields**:
- `visitor_id` (String) - The anonymous visitor ID
- `user_id` (String) - The known user ID

**What happens**:
- Creates Visitor → User link
- **Backward**: All past sessions from visitor now attributed to user
- **Forward**: All future sessions from visitor attributed to user
- Enables cross-device attribution when user logs in on new device

**Success Response** (200 OK):
```json
{
  "success": true
}
```

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
**Generation**: `SecureRandom.hex(32)` or equivalent
**Lifetime**: 30 minutes (sliding expiry)
**Storage**: Cookie named `_mbuzz_sid`

**Cookie attributes**:
```
_mbuzz_sid=<64 hex chars>; Max-Age=1800; Path=/; HttpOnly; SameSite=Lax; Secure
```

**New session when**:
- No session cookie exists
- Session cookie expired (30+ minutes since last activity)

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

- ✅ Session creation (`POST /sessions`) - async, on new session
- ✅ Event tracking (`POST /events`)
- ✅ Visitor ID generation and cookie management
- ✅ Session ID generation and cookie management
- ✅ Authentication (Bearer token)
- ✅ Error handling (never raise exceptions)

### Standard (Recommended)

- ✅ User identification (`POST /identify`)
- ✅ Visitor aliasing (`POST /alias`)
- ✅ Include URL and referrer in event properties
- ✅ Conversion tracking (`POST /conversions`)

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
