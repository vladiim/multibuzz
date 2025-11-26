# mbuzz SDK User Acceptance Testing (UAT) Guide

**Version**: 1.0
**Created**: 2025-11-26
**Status**: Active

---

## Overview

This guide provides a standardized UAT process for testing mbuzz SDKs across all supported languages and frameworks. Use this guide to verify SDK functionality before release or when integrating mbuzz into a new application.

### Supported SDKs

| SDK | Status | Framework Support |
|-----|--------|-------------------|
| **mbuzz-ruby** | Active | Rails, Sinatra, Rack |
| **REST API** | Active | Any (cURL, HTTP client) |
| **mbuzz-python** | Planned | Django, Flask, FastAPI |
| **mbuzz-php** | Planned | Laravel, Symfony |
| **mbuzz-node** | Planned | Express, Fastify, Next.js |

---

## Prerequisites

### 1. mbuzz Server Running

```bash
# Development (local)
cd /path/to/mbuzz
bin/rails server

# Verify server is running
curl http://localhost:3000/api/v1/health
# Expected: {"status":"ok"}
```

### 2. Test Account & API Key

```bash
# Create test account and API key via Rails console
bin/rails console

account = Account.create!(name: "UAT Test Account", slug: "uat-test")
api_key = ApiKeys::GenerationService.new(account, environment: "test").call
puts api_key[:raw_key]  # Save this! Only shown once
```

### 3. Attribution Model Setup

```bash
# Ensure attribution models exist (Rails console)
account = Account.find_by(slug: "uat-test")

# Create default attribution models if needed
AttributionModel.find_or_create_by!(
  account: account,
  name: "First Touch",
  model_type: :standard,
  algorithm: :first_touch,
  lookback_days: 30,
  is_active: true,
  is_default: true
)

AttributionModel.find_or_create_by!(
  account: account,
  name: "Last Touch",
  model_type: :standard,
  algorithm: :last_touch,
  lookback_days: 30,
  is_active: true
)

AttributionModel.find_or_create_by!(
  account: account,
  name: "Linear",
  model_type: :standard,
  algorithm: :linear,
  lookback_days: 30,
  is_active: true
)
```

### 4. Environment Variables

```bash
export MBUZZ_API_KEY=sk_test_your_key_here
export MBUZZ_API_URL=http://localhost:3000/api/v1
```

---

## Test Suite Structure

Each SDK must pass these test suites in order:

| Suite | Description | Critical? |
|-------|-------------|-----------|
| **T1** | Health & Authentication | Yes |
| **T2** | Basic Event Tracking | Yes |
| **T3** | Session & Visitor Management | Yes |
| **T4** | UTM Attribution Capture | Yes |
| **T5** | Conversion Tracking | Yes |
| **T6** | Attribution Model Verification | Yes |
| **T7** | User Identification & Alias | No |
| **T8** | Edge Cases | No |

---

## Test Suite T1: Health & Authentication

### T1.1 Health Check

**Purpose**: Verify API is reachable

```bash
# REST API
curl -X GET $MBUZZ_API_URL/health

# Expected: 200 OK
# {"status":"ok"}
```

```ruby
# Ruby SDK
Mbuzz.health
# => { status: "ok" }
```

### T1.2 Valid API Key

```bash
# REST API
curl -X GET $MBUZZ_API_URL/validate \
  -H "Authorization: Bearer $MBUZZ_API_KEY"

# Expected: 200 OK
# {"valid":true,"account":{"id":"acct_...","name":"..."}}
```

```ruby
# Ruby SDK
Mbuzz.validate
# => { valid: true, account: { id: "acct_...", name: "..." } }
```

### T1.3 Invalid API Key

```bash
# REST API
curl -X GET $MBUZZ_API_URL/validate \
  -H "Authorization: Bearer sk_test_invalid"

# Expected: 401 Unauthorized
# {"error":"Invalid API key"}
```

---

## Test Suite T2: Basic Event Tracking

### T2.1 Track Event with User ID

```bash
# REST API
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "user_id": "uat_user_001",
    "properties": {
      "url": "https://example.com/pricing"
    }
  }'

# Expected: 200 OK
# {"accepted":1,"rejected":[]}
```

```ruby
# Ruby SDK
Mbuzz.track(
  user_id: "uat_user_001",
  event: "Page View",
  properties: { url: "https://example.com/pricing" }
)
# => true
```

### T2.2 Track Event with Visitor ID

```bash
# REST API
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_001",
    "properties": {
      "url": "https://example.com/features"
    }
  }'
```

```ruby
# Ruby SDK (in controller with request context)
Mbuzz.track(
  anonymous_id: mbuzz_visitor_id,
  event: "Page View",
  properties: { url: request.original_url }
)
```

### T2.3 Reject Event Without ID

```bash
# REST API - should be rejected
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Invalid Event",
    "properties": {}
  }'

# Expected: accepted: 0, rejected: 1
```

---

## Test Suite T3: Session & Visitor Management

### T3.1 Session Creation with UTM

```bash
SESSION_ID="sess_uat_$(date +%s)"
VISITOR_ID="vis_uat_$(date +%s)"

# First event creates session
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "'$VISITOR_ID'",
    "session_id": "'$SESSION_ID'",
    "properties": {
      "url": "https://example.com/?utm_source=google&utm_medium=cpc&utm_campaign=brand"
    }
  }'
```

**Verify in Rails console**:
```ruby
session = Session.find_by(session_id: "sess_uat_...")
session.initial_utm
# => {"utm_source"=>"google", "utm_medium"=>"cpc", "utm_campaign"=>"brand"}
session.channel
# => "paid_search"
```

### T3.2 Session UTM Not Overwritten

```bash
# Second event in same session - UTM should NOT change
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "'$VISITOR_ID'",
    "session_id": "'$SESSION_ID'",
    "properties": {
      "url": "https://example.com/pricing?utm_source=facebook&utm_medium=social"
    }
  }'
```

**Verify**: Session `initial_utm` still shows google/cpc, NOT facebook/social

---

## Test Suite T4: UTM Attribution Capture

### T4.1 Full UTM Parameters

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_utm_full",
    "session_id": "sess_uat_utm_full",
    "properties": {
      "url": "https://example.com/?utm_source=google&utm_medium=cpc&utm_campaign=spring_sale&utm_content=ad_v1&utm_term=analytics"
    }
  }'
```

**Verify Session**:
- `initial_utm.utm_source` = "google"
- `initial_utm.utm_medium` = "cpc"
- `initial_utm.utm_campaign` = "spring_sale"
- `initial_utm.utm_content` = "ad_v1"
- `initial_utm.utm_term` = "analytics"
- `channel` = "paid_search"

### T4.2 Channel Classification Matrix

| Test | URL / Referrer | Expected Channel |
|------|----------------|------------------|
| Paid Search | `?utm_medium=cpc` | `paid_search` |
| Paid Search | `?utm_medium=ppc` | `paid_search` |
| Email | `?utm_medium=email` | `email` |
| Paid Social | `?utm_medium=paid_social` | `paid_social` |
| Display | `?utm_medium=display` | `display` |
| Affiliate | `?utm_medium=affiliate` | `affiliate` |
| Organic Social | referrer=facebook.com | `organic_social` |
| Organic Search | referrer=google.com | `organic_search` |
| Video | referrer=youtube.com | `video` |
| Direct | (no referrer, no UTM) | `direct` |
| Referral | referrer=blog.example.com | `referral` |

---

## Test Suite T5: Conversion Tracking

### T5.1 Create Conversion from Event

```bash
# Step 1: Create a conversion event
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Purchase",
    "user_id": "uat_purchase_user",
    "visitor_id": "vis_uat_purchase",
    "session_id": "sess_uat_purchase",
    "properties": {
      "url": "https://example.com/checkout?utm_source=google&utm_medium=cpc",
      "order_id": "order_001",
      "amount": 99.99
    }
  }'

# Get the event_id from response or Rails console
# Event.last.prefix_id => "evt_..."
```

```bash
# Step 2: Create conversion from event
EVENT_ID="evt_..."  # From step 1

curl -X POST $MBUZZ_API_URL/conversions \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "conversion": {
      "event_id": "'$EVENT_ID'",
      "conversion_type": "purchase",
      "revenue": 99.99
    }
  }'

# Expected: 201 Created
# Response includes conversion and attribution credits
```

**Expected Response Structure**:
```json
{
  "conversion": {
    "id": "conv_...",
    "conversion_type": "purchase",
    "revenue": 99.99,
    "converted_at": "2025-11-26T..."
  },
  "attribution": {
    "first_touch": [...],
    "last_touch": [...],
    "linear": [...]
  }
}
```

---

## Test Suite T6: Attribution Model Verification

This is the **critical test suite** for validating attribution calculations.

### T6.1 Multi-Touch Journey Setup

Create a visitor journey with 3 sessions from different channels:

```bash
VISITOR_ID="vis_uat_attr_$(date +%s)"

# Session 1: Organic Search (Day 1)
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "'$VISITOR_ID'",
    "session_id": "sess_attr_1",
    "properties": {
      "url": "https://example.com/blog",
      "referrer": "https://google.com/search"
    }
  }'

# Session 2: Paid Social (Day 3)
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "'$VISITOR_ID'",
    "session_id": "sess_attr_2",
    "properties": {
      "url": "https://example.com/pricing?utm_source=facebook&utm_medium=paid_social&utm_campaign=retarget"
    }
  }'

# Session 3: Direct + Conversion (Day 5)
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Signup",
    "visitor_id": "'$VISITOR_ID'",
    "user_id": "uat_attr_user",
    "session_id": "sess_attr_3",
    "properties": {
      "url": "https://example.com/signup",
      "plan": "pro"
    }
  }'
```

### T6.2 Verify Session Channels

```ruby
# Rails console
visitor = Visitor.find_by(visitor_id: "vis_uat_attr_...")
sessions = Session.where(visitor: visitor).order(:started_at)

sessions.each do |s|
  puts "#{s.session_id}: #{s.channel} - #{s.initial_utm}"
end

# Expected:
# sess_attr_1: organic_search - nil
# sess_attr_2: paid_social - {"utm_source"=>"facebook",...}
# sess_attr_3: direct - nil
```

### T6.3 Create Conversion & Verify Attribution

```bash
# Get the Signup event ID
EVENT_ID=$(bin/rails runner "puts Event.where(event_type: 'Signup').last.prefix_id")

# Create conversion
curl -X POST $MBUZZ_API_URL/conversions \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "conversion": {
      "event_id": "'$EVENT_ID'",
      "conversion_type": "signup",
      "revenue": 49.00
    }
  }'
```

### T6.4 Verify Attribution Credits

```ruby
# Rails console
conversion = Conversion.last
credits = AttributionCredit.where(conversion: conversion)

credits.group_by(&:attribution_model).each do |model, model_credits|
  puts "\n=== #{model.name} (#{model.algorithm}) ==="
  model_credits.each do |c|
    puts "  #{c.channel}: credit=#{c.credit}, revenue=$#{c.revenue_credit}"
  end
end
```

**Expected Results**:

| Model | Channel | Credit | Revenue Credit |
|-------|---------|--------|----------------|
| **First Touch** | organic_search | 1.0 | $49.00 |
| **Last Touch** | direct | 1.0 | $49.00 |
| **Linear** | organic_search | 0.333 | $16.33 |
| **Linear** | paid_social | 0.333 | $16.33 |
| **Linear** | direct | 0.333 | $16.33 |

### T6.5 Attribution Credit Validation Checklist

- [ ] **First Touch**: 100% credit to first session (organic_search)
- [ ] **Last Touch**: 100% credit to last session before conversion (direct)
- [ ] **Linear**: Equal credit split across all sessions (33.3% each)
- [ ] **Revenue Credits**: Credit × Revenue correctly calculated
- [ ] **UTM Data**: Credits include utm_source, utm_medium, utm_campaign from session
- [ ] **Lookback Window**: Only sessions within lookback_days are included

---

## Test Suite T7: User Identification & Alias

### T7.1 Identify User with Traits

```bash
curl -X POST $MBUZZ_API_URL/identify \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "uat_identify_user",
    "visitor_id": "vis_uat_identify",
    "traits": {
      "email": "test@example.com",
      "name": "Test User",
      "plan": "enterprise"
    }
  }'

# Expected: 200 OK, {"success": true}
```

```ruby
# Ruby SDK
Mbuzz.identify(
  user_id: current_user.id,
  traits: {
    email: current_user.email,
    name: current_user.name,
    plan: current_user.plan
  }
)
```

### T7.2 Alias Anonymous Visitor to User

```bash
# Link pre-signup visitor to authenticated user
curl -X POST $MBUZZ_API_URL/alias \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "visitor_id": "vis_uat_anonymous",
    "user_id": "uat_aliased_user"
  }'

# Expected: 200 OK, {"success": true}
```

```ruby
# Ruby SDK
Mbuzz.alias(
  user_id: @user.id,
  previous_id: mbuzz_visitor_id
)
```

---

## Test Suite T8: Edge Cases

### T8.1 Empty Journey (No Sessions Before Conversion)

```bash
# Create event without prior journey
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Direct Signup",
    "user_id": "uat_direct_user",
    "visitor_id": "vis_uat_direct",
    "session_id": "sess_uat_direct",
    "properties": {"url": "https://example.com/signup"}
  }'

# Create conversion
curl -X POST $MBUZZ_API_URL/conversions \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "conversion": {
      "event_id": "evt_...",
      "conversion_type": "signup"
    }
  }'
```

**Expected**: Attribution returns single credit for the conversion session (direct channel)

### T8.2 Conversion Without Revenue

```bash
curl -X POST $MBUZZ_API_URL/conversions \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "conversion": {
      "event_id": "evt_...",
      "conversion_type": "lead"
    }
  }'
```

**Expected**: Attribution credits have `credit` values but `revenue_credit` is null

### T8.3 Sessions Outside Lookback Window

Create sessions older than lookback_days (default 30):

```ruby
# Rails console - create old session
old_session = Session.create!(
  account: account,
  visitor: visitor,
  session_id: "sess_old",
  started_at: 45.days.ago,
  channel: "organic_search"
)
```

**Expected**: Old session NOT included in attribution journey

### T8.4 Invalid Event ID for Conversion

```bash
curl -X POST $MBUZZ_API_URL/conversions \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "conversion": {
      "event_id": "evt_nonexistent",
      "conversion_type": "purchase"
    }
  }'

# Expected: 422 Unprocessable Entity
# {"success": false, "errors": ["Event not found"]}
```

### T8.5 Cross-Account Event Access (Security)

```bash
# Try to create conversion for event from different account
curl -X POST $MBUZZ_API_URL/conversions \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "conversion": {
      "event_id": "evt_from_other_account",
      "conversion_type": "purchase"
    }
  }'

# Expected: 422 Unprocessable Entity
# {"success": false, "errors": ["Event belongs to different account"]}
```

---

## SDK-Specific Test Addendum

### Ruby SDK (mbuzz-ruby)

Additional tests specific to Rails integration:

| Test | Description | Pass Criteria |
|------|-------------|---------------|
| R1 | Middleware auto-captures request URL | URL captured from `request.original_url` |
| R2 | Middleware auto-captures referrer | Referrer captured from `request.referrer` |
| R3 | Cookie management (_mbuzz_vid, _mbuzz_sid) | Cookies set/read correctly |
| R4 | Thread-safe request context | Concurrent requests don't leak data |
| R5 | Background job tracking | `Mbuzz.track` works from Sidekiq/ActiveJob |
| R6 | Silent failures | Network errors don't raise exceptions |

### REST API

| Test | Description | Pass Criteria |
|------|-------------|---------------|
| A1 | Rate limit headers present | X-RateLimit-* headers returned |
| A2 | Batch event ingestion | Multiple events in single request |
| A3 | ISO8601 timestamp format | Timestamps accepted and stored correctly |

---

## Test Execution Checklist

### Per-SDK Release Checklist

| Suite | Test | Ruby | REST | Python | PHP | Node |
|-------|------|------|------|--------|-----|------|
| T1 | Health Check | [ ] | [ ] | [ ] | [ ] | [ ] |
| T1 | Valid API Key | [ ] | [ ] | [ ] | [ ] | [ ] |
| T1 | Invalid API Key | [ ] | [ ] | [ ] | [ ] | [ ] |
| T2 | Track with user_id | [ ] | [ ] | [ ] | [ ] | [ ] |
| T2 | Track with visitor_id | [ ] | [ ] | [ ] | [ ] | [ ] |
| T2 | Reject without ID | [ ] | [ ] | [ ] | [ ] | [ ] |
| T3 | Session creation | [ ] | [ ] | [ ] | [ ] | [ ] |
| T3 | UTM not overwritten | [ ] | [ ] | [ ] | [ ] | [ ] |
| T4 | Full UTM capture | [ ] | [ ] | [ ] | [ ] | [ ] |
| T4 | Channel classification | [ ] | [ ] | [ ] | [ ] | [ ] |
| T5 | Conversion creation | [ ] | [ ] | [ ] | [ ] | [ ] |
| T6 | First Touch attribution | [ ] | [ ] | [ ] | [ ] | [ ] |
| T6 | Last Touch attribution | [ ] | [ ] | [ ] | [ ] | [ ] |
| T6 | Linear attribution | [ ] | [ ] | [ ] | [ ] | [ ] |
| T6 | Revenue credit calc | [ ] | [ ] | [ ] | [ ] | [ ] |
| T7 | Identify | [ ] | [ ] | [ ] | [ ] | [ ] |
| T7 | Alias | [ ] | [ ] | [ ] | [ ] | [ ] |
| T8 | Edge cases | [ ] | [ ] | [ ] | [ ] | [ ] |

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| 401 Unauthorized | Invalid/missing API key | Check `Authorization: Bearer` header |
| Empty attribution | No sessions in lookback window | Verify session dates within 30 days |
| Wrong channel | UTM not captured | Check session `initial_utm` field |
| Missing revenue_credit | Conversion has no revenue | Pass `revenue` in conversion params |
| Duplicate sessions | Same session_id reused | Generate unique session_id per session |

### Debug Commands

```ruby
# Rails console debugging

# Check event was created
Event.last

# Check session has UTM
Session.last.initial_utm

# Check visitor journey
Visitor.last.sessions.order(:started_at).pluck(:channel)

# Check attribution credits
AttributionCredit.where(conversion: Conversion.last).map do |c|
  { model: c.attribution_model.algorithm, channel: c.channel, credit: c.credit }
end
```

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| SDK Developer | | | |
| QA Engineer | | | |
| Product Owner | | | |

---

**End of SDK UAT Guide**
