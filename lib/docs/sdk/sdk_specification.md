# Multibuzz SDK Specification

Version: 1.1.0
Last Updated: 2025-11-28
Status: **IMPLEMENTED**

This document defines the requirements for any Multibuzz SDK implementation. All SDKs (Ruby, JavaScript, Python, PHP, etc.) MUST implement this specification to be considered valid.

---

## Overview

VM: note - the idea is the SDK is a simple wrapper around the API. The API does all the context capture etc - think about this. The SDK implementation should be an extension of the REST API implementation.

Multibuzz SDKs enable customer applications to track visitor behavior, sessions, and conversions for marketing attribution. SDKs must handle:

1. **Visitor identification** - Persistent anonymous visitor tracking
2. **Session management** - Group events into browsing sessions
3. **Event tracking** - Page views, custom events
4. **Conversion tracking** - Revenue events with attribution
5. **User identification** - Link visitors to known users
6. **Context capture** - URL, referrer, UTM parameters

---

## SDK Types

### Server-Side SDK (e.g., Ruby, Python, PHP, Node.js)

Runs on the customer's server. Must:
- Manage cookies via middleware or helpers
- Extract request context (URL, referrer, user agent)
- Make server-to-server API calls to Multibuzz

### Client-Side SDK (e.g., JavaScript)

Runs in the browser. Must:
- Manage cookies directly in browser
- Capture page URL, referrer automatically
- Make API calls directly to Multibuzz (CORS)

---

## API Endpoints

All SDKs communicate with the Multibuzz API:

| Method | Endpoint | Purpose | Status |
|--------|----------|---------|--------|
| POST | `/api/v1/sessions` | Create session with acquisition context | **NEW** |
| POST | `/api/v1/events` | Track events (page views, custom events) | Implemented |
| POST | `/api/v1/conversions` | Track conversions with revenue | Implemented |
| POST | `/api/v1/identify` | Associate visitor with user ID | Implemented |
| POST | `/api/v1/alias` | Link visitor ID to user ID | Implemented |
| GET | `/api/v1/validate` | Validate API key | Implemented |
| GET | `/api/v1/health` | Health check | Implemented |

### Authentication

All requests must include the API key in the `Authorization` header:

```
Authorization: Bearer sk_live_abc123...
```

Or:

```
Authorization: Bearer sk_test_abc123...
```

Test keys (`sk_test_*`) create records with `is_test: true` for isolated testing.

---

## Core Identifiers

### Visitor ID

- **Purpose**: Anonymous identifier persisting across sessions
- **Format**: 64-character hex string (32 bytes)
- **Generation**: `SecureRandom.hex(32)` or equivalent
- **Storage**: Cookie named `_mbuzz_vid` (or SDK-specific prefix)
- **Expiry**: 2 years
- **Cookie attributes**: `HttpOnly; SameSite=Lax; Secure (in production); Path=/`

### Session ID

- **Purpose**: Group events within a browsing session
- **Format**: 64-character hex string (32 bytes)
- **Generation**: New session on first visit or after 30-minute inactivity
- **Storage**: Cookie named `_mbuzz_sid` (or SDK-specific prefix)
- **Expiry**: 30 minutes (sliding)
- **Cookie attributes**: `HttpOnly; SameSite=Lax; Secure (in production); Path=/`

### User ID

- **Purpose**: Customer-provided identifier for logged-in users
- **Format**: Any string (customer-defined)
- **Storage**: Application session (not managed by SDK)

---

## Required Methods

Every SDK MUST implement these methods:

### 1. `track(event_type, properties: {})`

Track a custom event.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `event_type` | string | Yes | Event name (e.g., `page_view`, `add_to_cart`) |
| `properties` | object | No | Custom event properties |

**Automatic enrichment (SDK must add):**
| Property | Source | Required |
|----------|--------|----------|
| `url` | Current page URL | Yes |
| `referrer` | Document referrer | Yes (if available) |
| `visitor_id` | Cookie | Yes |
| `session_id` | Cookie | Yes |
| `timestamp` | Current time (ISO8601) | Yes |

**API Request:**
```json
POST /api/v1/events
{
  "events": [
    {
      "event_type": "page_view",
      "visitor_id": "abc123...",
      "session_id": "def456...",
      "timestamp": "2025-11-28T12:00:00Z",
      "properties": {
        "url": "https://example.com/pricing?utm_source=google",
        "referrer": "https://google.com/search",
        "custom_prop": "value"
      }
    }
  ]
}
```

**API Response:**
```json
{
  "accepted": 1,
  "rejected": [],
  "events": [
    {
      "id": "evt_abc123",
      "event_type": "page_view",
      "visitor_id": "abc123...",
      "session_id": "def456...",
      "status": "accepted"
    }
  ]
}
```

### 2. `page_view(properties: {})`

Convenience method for tracking page views. MUST call `track("page_view", properties)`.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `properties` | object | No | Additional properties |

### 3. `conversion(conversion_type, revenue: nil, properties: {})`

Track a conversion event for attribution.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `conversion_type` | string | Yes | Conversion name (e.g., `purchase`, `signup`) |
| `revenue` | number | No | Revenue amount (default currency USD) |
| `properties` | object | No | Custom properties |

**API Request:**
```json
POST /api/v1/conversions
{
  "conversion": {
    "conversion_type": "purchase",
    "visitor_id": "abc123...",
    "revenue": 99.99,
    "currency": "USD",
    "timestamp": "2025-11-28T12:00:00Z",
    "properties": {
      "order_id": "ORD-123"
    }
  }
}
```

**API Response:**
```json
{
  "conversion": {
    "id": "conv_abc123",
    "conversion_type": "purchase",
    "revenue": 99.99
  },
  "attribution": {
    "model": "last_touch",
    "touchpoints": [
      {
        "session_id": "sess_abc123",
        "channel": "paid_search",
        "utm_source": "google",
        "credit": 1.0
      }
    ]
  }
}
```

### 4. `identify(user_id, traits: {})`

Associate the current visitor with a known user ID.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `user_id` | string | Yes | Customer's user identifier |
| `traits` | object | No | User properties (name, email, etc.) |

**Behavior:**
1. Store `user_id` in session for subsequent events
2. Send identify call to API
3. Future events include `user_id`

**API Request:**
```json
POST /api/v1/identify
{
  "user_id": "user_123",
  "visitor_id": "abc123...",
  "traits": {
    "email": "user@example.com",
    "name": "John Doe"
  }
}
```

### 5. `alias(user_id)`

Explicitly link current visitor to a user ID. Called after login to merge anonymous and authenticated activity.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `user_id` | string | Yes | User identifier to link |

**API Request:**
```json
POST /api/v1/alias
{
  "user_id": "user_123",
  "visitor_id": "abc123..."
}
```

---

## Context Capture

SDKs MUST capture and send the following context with every event:

### URL (Required)

The full URL of the current page, including query parameters.

**Server-side:** `request.url` or `request.original_url`
**Client-side:** `window.location.href`

The server extracts from URL:
- `host` - Domain
- `path` - URL path
- `query_params` - All query parameters
- `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term` - UTM parameters

### Referrer (Required if available)

The referring URL.

**Server-side:** `request.referrer`
**Client-side:** `document.referrer`

### User Agent

**Server-side:** `request.user_agent`
**Client-side:** `navigator.userAgent`

Note: Server enriches `request_metadata` from HTTP headers, so client-side SDKs don't need to send explicitly.

---

## Configuration

SDKs MUST support these configuration options:

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `api_key` | string | Yes | - | API key (`sk_live_*` or `sk_test_*`) |
| `api_url` | string | No | `https://api.multibuzz.io` | API base URL |
| `enabled` | boolean | No | `true` | Enable/disable tracking |
| `debug` | boolean | No | `false` | Enable debug logging |
| `cookie_domain` | string | No | (auto) | Cookie domain scope |

### Example Configuration (Ruby)

```ruby
Mbuzz.configure do |config|
  config.api_key = ENV["MBUZZ_API_KEY"]
  config.api_url = "https://api.multibuzz.io"
  config.enabled = Rails.env.production? || Rails.env.staging?
  config.debug = Rails.env.development?
end
```

---

## Server-Side SDK Requirements

Server-side SDKs have additional requirements:

### 1. Middleware Integration

MUST provide middleware that:
1. Extracts or generates `visitor_id` from cookie
2. Extracts or generates `session_id` from cookie
3. Sets cookies in response
4. Makes request context available to application code

**Example (Ruby/Rack):**

```ruby
class Mbuzz::Middleware::Tracking
  def call(env)
    request = Rack::Request.new(env)

    # Extract or generate IDs
    visitor_id = request.cookies["_mbuzz_vid"] || generate_id
    session_id = request.cookies["_mbuzz_sid"] || generate_id

    # Store in env for application access
    env["mbuzz.visitor_id"] = visitor_id
    env["mbuzz.session_id"] = session_id

    # Store request context in thread-local
    Mbuzz::RequestContext.set(request)

    status, headers, body = @app.call(env)

    # Set cookies in response
    set_visitor_cookie(headers, visitor_id)
    set_session_cookie(headers, session_id)

    [status, headers, body]
  ensure
    Mbuzz::RequestContext.clear
  end
end
```

### 2. Controller Helpers

MUST provide helpers for controllers:

```ruby
module Mbuzz::ControllerHelpers
  def mbuzz_visitor_id
    request.env["mbuzz.visitor_id"]
  end

  def mbuzz_session_id
    request.env["mbuzz.session_id"]
  end

  def mbuzz_track(event_type, properties: {})
    Mbuzz.track(event_type, properties: properties)
  end

  def mbuzz_page_view(properties: {})
    Mbuzz.page_view(properties: properties)
  end

  def mbuzz_conversion(conversion_type, revenue: nil, properties: {})
    Mbuzz.conversion(conversion_type, revenue: revenue, properties: properties)
  end
end
```

### 3. Request Context

MUST maintain request context in thread-local storage:

```ruby
module Mbuzz::RequestContext
  def self.set(request)
    Thread.current[:mbuzz_request] = request
  end

  def self.current
    Thread.current[:mbuzz_request]
  end

  def self.clear
    Thread.current[:mbuzz_request] = nil
  end

  def self.url
    current&.url
  end

  def self.referrer
    current&.referrer
  end
end
```

### 4. Automatic Context Enrichment

When `track` or `conversion` is called, SDK MUST automatically add:

```ruby
def track(event_type, properties: {})
  enriched_properties = properties.merge(
    url: RequestContext.url,
    referrer: RequestContext.referrer
  ).compact

  Client.track(
    visitor_id: visitor_id,
    session_id: session_id,
    event_type: event_type,
    properties: enriched_properties,
    timestamp: Time.now.utc.iso8601
  )
end
```

---

## Client-Side SDK Requirements

Client-side SDKs have additional requirements:

### 1. Automatic Page View Tracking

SHOULD support automatic page view tracking on page load:

```javascript
mbuzz.init({
  apiKey: 'sk_live_...',
  capturePageView: true  // Auto-track on init
});
```

### 2. SPA Support

MUST support single-page applications:

```javascript
// Manual page view for SPA navigation
mbuzz.page_view({
  url: window.location.href
});
```

### 3. Cookie Management

MUST handle cookies directly:

```javascript
function getOrCreateVisitorId() {
  let vid = getCookie('_mbuzz_vid');
  if (!vid) {
    vid = generateId();
    setCookie('_mbuzz_vid', vid, { maxAge: 63072000 }); // 2 years
  }
  return vid;
}
```

---

## Error Handling

SDKs MUST handle errors gracefully:

1. **Network errors**: Log and continue (don't crash application)
2. **Invalid API key**: Log error, disable tracking
3. **Rate limiting (429)**: Implement exponential backoff
4. **Server errors (5xx)**: Retry with backoff

```ruby
def call
  run
rescue NetworkError => e
  log_error("Network error: #{e.message}")
  { success: false, errors: ["Network error"] }
rescue => e
  log_error("Unexpected error: #{e.message}")
  { success: false, errors: ["Internal error"] }
end
```

---

## Testing Support

SDKs SHOULD provide testing utilities:

### 1. Disable in Tests

```ruby
# config/environments/test.rb
Mbuzz.configure do |config|
  config.enabled = false
end
```

### 2. Test Mode

Using `sk_test_*` API keys creates `is_test: true` records, isolated from production data.

### 3. Mock/Stub Support

```ruby
# In tests
allow(Mbuzz).to receive(:track).and_return({ success: true })
```

---

## Validation Checklist

An SDK is valid if it passes all these checks:

### Core Functionality
- [ ] Generates and persists visitor ID in cookie
- [ ] Generates and manages session ID with 30-minute timeout
- [ ] Sends `visitor_id` with all API requests
- [ ] Sends `session_id` with all API requests
- [ ] Sends `timestamp` (ISO8601) with all requests
- [ ] Sends `url` in event properties
- [ ] Sends `referrer` in event properties (if available)

### API Integration
- [ ] Implements `track(event_type, properties)`
- [ ] Implements `page_view(properties)`
- [ ] Implements `conversion(conversion_type, revenue, properties)`
- [ ] Implements `identify(user_id, traits)`
- [ ] Implements `alias(user_id)`
- [ ] Sends correct Authorization header
- [ ] Handles API errors gracefully

### Configuration
- [ ] Supports `api_key` configuration
- [ ] Supports `api_url` configuration
- [ ] Supports `enabled` flag
- [ ] Supports `debug` flag

### Server-Side Specific
- [ ] Provides middleware for cookie management
- [ ] Provides controller helpers
- [ ] Maintains request context in thread-local storage
- [ ] Auto-enriches events with URL/referrer from request

### Client-Side Specific
- [ ] Manages cookies in browser
- [ ] Supports automatic page view on init
- [ ] Supports SPA navigation tracking

---

## Appendix: Cookie Specification

### Visitor Cookie

```
Name: _mbuzz_vid
Value: [64 hex chars]
Expires: [2 years from now]
Path: /
HttpOnly: true
Secure: true (production only)
SameSite: Lax
```

### Session Cookie

```
Name: _mbuzz_sid
Value: [64 hex chars]
Max-Age: 1800 (30 minutes)
Path: /
HttpOnly: true
Secure: true (production only)
SameSite: Lax
```

---

## Appendix: Example Event Payload

Complete example of what an SDK should send:

```json
POST /api/v1/events
Authorization: Bearer sk_live_abc123...
Content-Type: application/json

{
  "events": [
    {
      "event_type": "page_view",
      "visitor_id": "a1b2c3d4e5f6...",
      "session_id": "x1y2z3a4b5c6...",
      "timestamp": "2025-11-28T12:34:56Z",
      "properties": {
        "url": "https://example.com/pricing?utm_source=google&utm_medium=cpc&utm_campaign=q4",
        "referrer": "https://www.google.com/search?q=analytics",
        "page_title": "Pricing - Example"
      }
    }
  ]
}
```

The server will enrich this to:

```json
{
  "event_type": "page_view",
  "visitor_id": "a1b2c3d4e5f6...",
  "session_id": "x1y2z3a4b5c6...",
  "occurred_at": "2025-11-28T12:34:56Z",
  "properties": {
    "url": "https://example.com/pricing?utm_source=google&utm_medium=cpc&utm_campaign=q4",
    "host": "example.com",
    "path": "/pricing",
    "query_params": {
      "utm_source": "google",
      "utm_medium": "cpc",
      "utm_campaign": "q4"
    },
    "utm_source": "google",
    "utm_medium": "cpc",
    "utm_campaign": "q4",
    "referrer": "https://www.google.com/search?q=analytics",
    "referrer_host": "www.google.com",
    "referrer_path": "/search",
    "channel": "paid_search",
    "page_title": "Pricing - Example",
    "request_metadata": {
      "ip_address": "192.168.1.0",
      "user_agent": "Mozilla/5.0...",
      "language": "en-US",
      "dnt": null
    }
  }
}
```
