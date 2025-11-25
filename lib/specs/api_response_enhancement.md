# API Response Enhancement Specification

## Overview

Enhance API responses to return resource IDs for created entities. This enables SDKs and REST API consumers to:
- Create conversions linked to specific events
- Reference sessions and visitors in subsequent calls
- Build complete attribution journeys programmatically

## Security Analysis

**Prefixed IDs are safe to return.** They are references, not credentials.

| Concern | Mitigation |
|---------|------------|
| Brute force enumeration | 128-bit entropy (32 hex chars) = 2^128 attempts required |
| Cross-account access | All queries scoped to authenticated account |
| Unauthenticated access | API key required for every request |
| Bulk enumeration | Rate limiting (10,000 req/day) |

The API key is the security boundary. Resource IDs follow the same pattern as Stripe (`ch_...`), Segment, and other production APIs.

---

## Current State

### Events Endpoint

**Request:**
```bash
POST /api/v1/events
Authorization: Bearer sk_test_xxx

{
  "events": [
    {
      "event_type": "page_view",
      "visitor_id": "vis_abc123",
      "session_id": "sess_xyz789",
      "timestamp": "2025-01-15T10:00:00Z",
      "properties": { "url": "/pricing" }
    }
  ]
}
```

**Current Response:**
```json
{
  "accepted": 1,
  "rejected": []
}
```

**Problem:** No event IDs returned. Cannot create conversions for specific events.

---

## Proposed Enhancement

### Events Endpoint

**Enhanced Response:**
```json
{
  "accepted": 1,
  "rejected": [],
  "events": [
    {
      "id": "evt_a1b2c3d4e5f6",
      "event_type": "page_view",
      "visitor_id": "vis_abc123",
      "session_id": "sess_xyz789",
      "status": "accepted"
    }
  ]
}
```

**For rejected events:**
```json
{
  "accepted": 0,
  "rejected": [
    {
      "index": 0,
      "event_type": "page_view",
      "errors": ["visitor_id is required"],
      "status": "rejected"
    }
  ],
  "events": []
}
```

### Sessions Endpoint

**Current Response:**
```json
{
  "success": true
}
```

**Enhanced Response:**
```json
{
  "success": true,
  "session": {
    "id": "sess_xyz789",
    "visitor_id": "vis_abc123",
    "started_at": "2025-01-15T10:00:00Z",
    "channel": "organic_search",
    "initial_utm": {
      "source": "google",
      "medium": "organic"
    }
  }
}
```

### Visitors Endpoint

**Current Response:**
```json
{
  "success": true
}
```

**Enhanced Response:**
```json
{
  "success": true,
  "visitor": {
    "id": "vis_abc123",
    "created_at": "2025-01-15T10:00:00Z",
    "is_new": true
  }
}
```

### Conversions Endpoint

**Current Response:**
```json
{
  "success": true
}
```

**Enhanced Response:**
```json
{
  "success": true,
  "conversion": {
    "id": "conv_m1n2o3p4",
    "event_id": "evt_a1b2c3d4e5f6",
    "visitor_id": "vis_abc123",
    "value": 99.00,
    "attribution": {
      "model": "linear",
      "touchpoints": 3,
      "calculated_at": "2025-01-15T10:00:05Z"
    }
  }
}
```

---

## Implementation Requirements

### 1. Switch Events to Synchronous Processing

**Current:** Events queued via Solid Queue (async)
**Required:** Process inline to return IDs immediately

```ruby
# app/services/events/ingestion_service.rb

def run
  return error_result(["events array is required"]) unless events_data.is_a?(Array)

  results = events_data.map.with_index do |event_data, index|
    process_event(event_data, index)
  end

  accepted = results.select { |r| r[:status] == "accepted" }
  rejected = results.select { |r| r[:status] == "rejected" }

  success_result(
    accepted: accepted.count,
    rejected: rejected,
    events: accepted
  )
end

private

def process_event(event_data, index)
  validation = validate_event(event_data)
  return { index: index, errors: validation.errors, status: "rejected" } unless validation.valid?

  event = persist_event(event_data)  # Sync, not queued

  {
    id: event.prefix_id,
    event_type: event.event_type,
    visitor_id: event.visitor&.prefix_id,
    session_id: event.session&.prefix_id,
    status: "accepted"
  }
end
```

### 2. Add prefix_id to Event Model

```ruby
# app/models/event.rb
class Event < ApplicationRecord
  has_prefix_id :evt
end
```

### 3. Update Controller Response

```ruby
# app/controllers/api/v1/events_controller.rb
def create
  result = Events::IngestionService.new(current_account, events_params).call

  if result[:success]
    render json: {
      accepted: result[:accepted],
      rejected: result[:rejected],
      events: result[:events]
    }, status: :accepted
  else
    render json: { errors: result[:errors] }, status: :unprocessable_entity
  end
end
```

---

## SDK Usage Examples

### Ruby SDK

```ruby
# Track event and get ID
response = Mbuzz.track("signup", visitor_id: "vis_abc", properties: { plan: "pro" })
event_id = response.events.first.id  # => "evt_a1b2c3d4"

# Create conversion from event
Mbuzz.conversion(event_id: event_id, value: 99.00)
```

### REST API

```bash
# 1. Track signup event
curl -X POST https://mbuzz.co/api/v1/events \
  -H "Authorization: Bearer sk_test_xxx" \
  -d '{"events": [{"event_type": "signup", "visitor_id": "vis_abc"}]}'

# Response: {"accepted": 1, "events": [{"id": "evt_a1b2c3d4", ...}]}

# 2. Create conversion
curl -X POST https://mbuzz.co/api/v1/conversions \
  -H "Authorization: Bearer sk_test_xxx" \
  -d '{"event_id": "evt_a1b2c3d4", "value": 99.00}'
```

---

## Migration Path

### Phase 1: Add IDs to Responses (Non-Breaking)
- Add `events` array to response
- Keep `accepted`/`rejected` counts for backwards compatibility
- Switch to sync processing

### Phase 2: SDK Updates
- Update Ruby SDK to use returned IDs
- Document in SDK UAT guide

---

## Testing Requirements

### Unit Tests

```ruby
test "events response includes event IDs" do
  result = service.call([valid_event_params])

  assert result[:success]
  assert_equal 1, result[:events].count
  assert_match /^evt_/, result[:events].first[:id]
end

test "rejected events include index and errors" do
  result = service.call([invalid_event_params])

  assert_equal 1, result[:rejected].count
  assert_equal 0, result[:rejected].first[:index]
  assert_includes result[:rejected].first[:errors], "visitor_id is required"
end
```

### Integration Tests

```ruby
test "POST /api/v1/events returns event IDs" do
  post api_v1_events_path,
    params: { events: [event_params] },
    headers: auth_headers

  assert_response :accepted
  json = JSON.parse(response.body)

  assert_equal 1, json["accepted"]
  assert_match /^evt_/, json["events"].first["id"]
end
```

---

## Performance Considerations

### Sync vs Async Trade-offs

| Aspect | Async (Current) | Sync (Proposed) |
|--------|-----------------|-----------------|
| Response time | ~50ms | ~100-200ms |
| IDs available | No | Yes |
| Throughput | Higher | Lower |
| SDK usability | Limited | Full |

**Recommendation:** Sync processing is acceptable for MVP. Typical SDK usage is 1-10 events per request. Can optimize later with:
- Batch inserts
- Connection pooling
- Optional `async: true` param for high-volume clients

---

## Acceptance Criteria

- [ ] Events endpoint returns `events` array with IDs for accepted events
- [ ] Events endpoint returns `rejected` array with index and errors
- [ ] Sessions endpoint returns session details including ID
- [ ] Visitors endpoint returns visitor details including ID
- [ ] Conversions endpoint returns conversion details including attribution summary
- [ ] All existing tests pass
- [ ] New tests cover ID responses
- [ ] SDK UAT T6 (Attribution Models) can complete end-to-end
