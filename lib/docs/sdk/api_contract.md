# API Contract for SDK Developers

**Purpose**: Define the exact API behavior that all SDKs must implement to remain compatible with the mbuzz backend.

**Last Updated**: 2025-11-25
**Backend Version**: 1.0.0

---

## Base URL

**Production**: `https://mbuzz.co/api/v1`
**Staging**: `https://staging.mbuzz.co/api/v1` (if available)

All endpoints are relative to this base URL.

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

**Validation**:
- Backend extracts key from `Authorization: Bearer {key}`
- Validates key exists and belongs to an active account
- Sets `@current_account` for request scope
- All data operations are scoped to this account

---

## Endpoints

### POST /api/v1/events

**Purpose**: Track events (page views, signups, purchases, etc.)

**Request Headers**:
```
Authorization: Bearer {api_key}
Content-Type: application/json
User-Agent: mbuzz-ruby/0.2.0 (Ruby/3.2.0)  # Include SDK version
```

**Request Body** (single event):
```json
{
  "event_type": "Signup",
  "user_id": "user_123",
  "visitor_id": "vis_a1b2c3d4e5f6g7h8",
  "properties": {
    "plan": "pro",
    "trial_days": 14,
    "source": "homepage"
  },
  "timestamp": "2025-11-25T10:30:00Z"
}
```

**Request Body** (batch events):
```json
{
  "events": [
    {
      "event_type": "Page View",
      "visitor_id": "vis_a1b2c3d4e5f6g7h8",
      "properties": { "url": "/pricing" },
      "timestamp": "2025-11-25T10:29:00Z"
    },
    {
      "event_type": "Signup",
      "user_id": "user_123",
      "visitor_id": "vis_a1b2c3d4e5f6g7h8",
      "properties": { "plan": "pro" },
      "timestamp": "2025-11-25T10:30:00Z"
    }
  ]
}
```

**Required Fields**:
- `event_type` (String) - Name of the event
- `user_id` OR `visitor_id` (String) - At least one required

**Optional Fields**:
- `properties` (Object) - Custom event metadata
- `timestamp` (String, ISO8601) - When event occurred (defaults to now if omitted)

**Validation Rules**:
- `event_type` must be present and non-empty
- Either `user_id` OR `visitor_id` must be present
- `timestamp` must be valid ISO8601 format if provided
- `properties` must be a valid JSON object (not array, not null)
- Total request size < 1MB

**Success Response** (200 OK):
```json
{
  "accepted": 1,
  "rejected": []
}
```

**Validation Error** (422 Unprocessable Entity):
```json
{
  "accepted": 0,
  "rejected": [
    {
      "event": {
        "event_type": "Invalid",
        "properties": {}
      },
      "errors": ["user_id or visitor_id required"]
    }
  ]
}
```

**Auth Error** (401 Unauthorized):
```json
{
  "error": "Invalid API key"
}
```

**Rate Limit** (429 Too Many Requests):
```json
{
  "error": "Rate limit exceeded",
  "retry_after": 3600
}
```

**Response Headers**:
```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1732554000
```

---

### POST /api/v1/identify

**Status**: 🚧 Planned (not yet implemented)

**Purpose**: Associate traits with a user ID

**Request Body**:
```json
{
  "user_id": "user_123",
  "visitor_id": "vis_a1b2c3d4e5f6g7h8",
  "traits": {
    "email": "user@example.com",
    "name": "Jane Doe",
    "plan": "pro",
    "company": "Acme Inc"
  }
}
```

**Required Fields**:
- `user_id` (String)

**Optional Fields**:
- `visitor_id` (String) - Links anonymous visitor to user
- `traits` (Object) - User attributes

**Success Response** (200 OK):
```json
{
  "success": true
}
```

---

### POST /api/v1/alias

**Status**: 🚧 Planned (not yet implemented)

**Purpose**: Link a visitor ID to a user ID (for cross-device tracking)

**Request Body**:
```json
{
  "visitor_id": "vis_a1b2c3d4e5f6g7h8",
  "user_id": "user_123"
}
```

**Required Fields**:
- `visitor_id` (String)
- `user_id` (String)

**Success Response** (200 OK):
```json
{
  "success": true
}
```

---

### GET /api/v1/validate

**Purpose**: Validate an API key

**Request Headers**:
```
Authorization: Bearer {api_key}
```

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

**Auth Error** (401 Unauthorized):
```json
{
  "valid": false,
  "error": "Invalid API key"
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

### Timestamps

**Format**: ISO8601 with timezone
**Required**: UTC timezone (Z suffix)

**Valid**:
```
2025-11-25T10:30:00Z
2025-11-25T10:30:00.123Z
2025-11-25T10:30:00+00:00
```

**Invalid**:
```
1732550400                    # Unix timestamp (integer)
2025-11-25 10:30:00          # Missing T separator
2025-11-25T10:30:00          # Missing timezone
2025-11-25T10:30:00-05:00    # Non-UTC timezone (will work but discouraged)
```

**SDK Implementation**:
```ruby
# Ruby
Time.now.utc.iso8601
# => "2025-11-25T10:30:00Z"

# Python
from datetime import datetime, timezone
datetime.now(timezone.utc).isoformat()
# => "2025-11-25T10:30:00+00:00"

# JavaScript
new Date().toISOString()
# => "2025-11-25T10:30:00.123Z"
```

### Properties Object

**Type**: JSON object (hash/dictionary)
**Max Size**: 64KB
**Max Depth**: 5 levels of nesting

**Valid**:
```json
{
  "plan": "pro",
  "amount": 99.99,
  "items": ["item1", "item2"],
  "metadata": {
    "source": "homepage",
    "campaign": "black-friday"
  }
}
```

**Invalid**:
```json
["array", "at", "root"]      # Must be object, not array
null                          # Must be object, not null
"string"                      # Must be object, not string
```

### Visitor ID

**Format**: 64-character hex string
**Generation**: `SecureRandom.hex(32)`
**Lifetime**: 2 years
**Storage**: Cookie named `mbuzz_visitor_id`

**Example**: `a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6`

**SDK Behavior**:
- Check for existing cookie
- Generate new ID if not present
- Set cookie with 2-year expiration
- Include in all tracking calls

### User ID

**Format**: Any string (max 255 characters)
**Examples**: `"user_123"`, `"12345"`, `"usr_a1b2c3"`

**SDK Behavior**:
- Accept any string provided by application
- Don't validate format (app decides ID structure)
- Include in tracking calls for identified users

---

## Error Handling

### SDK Behavior on Errors

**MUST NOT**:
- Raise exceptions to application code
- Block application execution
- Retry indefinitely

**MUST**:
- Return `false` on any error
- Log error if debug mode enabled
- Continue application execution

**Example**:
```ruby
# Ruby SDK
result = Mbuzz.track(event_type: 'Signup', user_id: 1)
if result
  # Success - event tracked
else
  # Failure - but app continues
end
```

### HTTP Status Codes

| Code | Meaning | SDK Action |
|------|---------|------------|
| 200 | Success | Return true |
| 401 | Invalid API key | Log error, return false |
| 422 | Validation error | Log error, return false |
| 429 | Rate limit | Log error, return false, don't retry |
| 500 | Server error | Log error, return false |
| 503 | Service unavailable | Log error, return false |

**SDK should NOT retry on**:
- 401 (auth won't fix itself)
- 422 (validation won't change)
- 429 (already rate limited)

**SDK MAY retry on** (with exponential backoff):
- 500 (server error might be transient)
- 503 (service might recover)
- Network timeout

---

## Rate Limiting

### Current Limits

**All accounts**: 1,000 events per hour

### Headers

Every response includes:
```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1732554000  # Unix timestamp
```

### SDK Behavior

**On 429 response**:
- Log warning if debug mode
- Return false
- Do NOT retry automatically
- Respect `retry_after` header if provided

**Example**:
```ruby
# Ruby SDK
response = api_call()
if response.status == 429
  retry_after = response.headers['Retry-After'] || 3600
  log_error("Rate limit exceeded. Retry after #{retry_after} seconds")
  return false
end
```

---

## Backwards Compatibility

### Breaking Changes

**Backend will maintain compatibility for**:
- Accepted parameter names (won't remove `user_id`, `event_type`, etc.)
- Response formats (won't change structure of success responses)
- Authentication method (Bearer token)

**Backend may add without notice**:
- New optional parameters
- New response fields
- New endpoints
- New HTTP headers

**SDK must**:
- Ignore unknown response fields
- Handle new optional parameters gracefully
- Not break if new headers added

### Deprecation Policy

**Process**:
1. Announce deprecation 6 months before removal
2. Add deprecation warnings to API responses
3. Update all SDKs with migration guide
4. Remove after 6 months

**Example deprecation header**:
```
X-Mbuzz-Deprecation: Parameter 'anonymous_id' is deprecated. Use 'visitor_id' instead.
```

---

## Testing Your SDK

### Manual Testing Checklist

- [ ] Install SDK in fresh app
- [ ] Configure with test API key
- [ ] Track a simple event
- [ ] Verify event appears in dashboard
- [ ] Test with invalid API key (should fail gracefully)
- [ ] Test with missing required fields (should return false)
- [ ] Test with malformed JSON (should return false)
- [ ] Test visitor ID generation and persistence
- [ ] Test batch event sending
- [ ] Test rate limiting behavior

### Integration Test Endpoints

**Staging API** (when available):
```
https://staging.mbuzz.co/api/v1
```

Use test API keys starting with `sk_test_` for all testing.

### Example cURL Commands

**Track Event**:
```bash
curl -X POST https://mbuzz.co/api/v1/events \
  -H "Authorization: Bearer sk_test_your_key_here" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Test Event",
    "user_id": "test_user_123",
    "properties": {
      "test": true
    },
    "timestamp": "2025-11-25T10:30:00Z"
  }'
```

**Validate Key**:
```bash
curl https://mbuzz.co/api/v1/validate \
  -H "Authorization: Bearer sk_test_your_key_here"
```

---

## SDK Feature Parity

All SDKs should eventually support:

**Core** (required):
- ✅ Track events
- ✅ Visitor identification
- ✅ Authentication
- ✅ Error handling (no exceptions)

**Standard** (recommended):
- ⏳ User identification
- ⏳ Visitor aliasing
- ⏳ Batch event sending
- ⏳ Automatic page view tracking

**Advanced** (optional):
- ❌ Offline queueing
- ❌ Event sampling
- ❌ Custom HTTP client
- ❌ Middleware/plugins

---

## Related Documentation

- [SDK Registry](./sdk_registry.md) - List of all SDKs
- [Documentation Strategy](../architecture/documentation_strategy.md) - Cross-linking guide
- [Bug Fixes](../../specs/bug_fixes_critical_inconsistencies.md) - Current issues
- [Event Properties](../architecture/event_properties.md) - Detailed property specs

---

## Questions?

**For SDK developers**:
- Email: dev@mbuzz.co
- GitHub Issues: https://github.com/multibuzz/mbuzz-ruby/issues

**For API changes**:
- Propose changes via GitHub issue
- Include use case and backwards compatibility plan
- Update this document when approved
