# User Acceptance Testing (UAT) Test Plan

**Version**: 1.1
**Created**: 2025-11-25
**Updated**: 2025-11-26
**Author**: Vlad
**Status**: Ready for Execution

---

## Related Documents

- **SDK UAT Guide**: `SDK_UAT_GUIDE.md` - Comprehensive SDK testing including attribution model verification
- This document covers REST API testing; see SDK UAT Guide for SDK-specific tests and attribution model testing

---

## Overview

This document provides a comprehensive UAT test plan for mbuzz, covering event tracking, UTM attribution, session management, and channel classification across development, staging, and production environments.

### Environments

| Environment | API URL | Purpose |
|-------------|---------|---------|
| **Development** | `http://localhost:3000/api/v1` | Local Rails server testing |
| **Staging** | `https://staging.mbuzz.co/api/v1` | Pre-production validation |
| **Production** | `https://mbuzz.co/api/v1` | Final verification |

### Test API Key Format

```
Test keys:    sk_test_{32_random_chars}
Live keys:    sk_live_{32_random_chars}
```

---

## Pre-Requisites

### Environment Setup

- [ ] Rails server running (development)
- [ ] Database migrated and seeded
- [ ] Test account created
- [ ] API key generated (test environment)
- [ ] cURL or Postman installed
- [ ] Dashboard access verified

### Environment Variables

```bash
# Set these before running tests
export MBUZZ_API_KEY=sk_test_your_key_here
export MBUZZ_API_URL=http://localhost:3000/api/v1  # or staging/prod URL
```

---

## Test Suite 1: API Health & Authentication

### T1.1 Health Check (No Auth Required)

**Priority**: Critical
**Expected**: API is reachable and healthy

```bash
curl -X GET $MBUZZ_API_URL/health
```

**Expected Response (200 OK)**:
```json
{
  "status": "ok",
  "version": "1.0.0"
}
```

**Pass Criteria**:
- [ ] Status code is 200
- [ ] Response includes `status: "ok"`
- [ ] Response time < 500ms

---

### T1.2 Validate API Key (Valid Key)

**Priority**: Critical
**Expected**: Valid API key is accepted

```bash
curl -X GET $MBUZZ_API_URL/validate \
  -H "Authorization: Bearer $MBUZZ_API_KEY"
```

**Expected Response (200 OK)**:
```json
{
  "valid": true,
  "account": {
    "id": "acct_*",
    "name": "Your Account Name"
  }
}
```

**Pass Criteria**:
- [ ] Status code is 200
- [ ] `valid` is `true`
- [ ] Account ID is prefixed with `acct_`

---

### T1.3 Validate API Key (Invalid Key)

**Priority**: Critical
**Expected**: Invalid API key is rejected

```bash
curl -X GET $MBUZZ_API_URL/validate \
  -H "Authorization: Bearer sk_test_invalid_key_12345"
```

**Expected Response (401 Unauthorized)**:
```json
{
  "error": "Invalid API key"
}
```

**Pass Criteria**:
- [ ] Status code is 401
- [ ] Error message indicates invalid key

---

### T1.4 Missing Authorization Header

**Priority**: High
**Expected**: Request without auth header is rejected

```bash
curl -X GET $MBUZZ_API_URL/validate
```

**Expected Response (401 Unauthorized)**:
```json
{
  "error": "Unauthorized"
}
```

**Pass Criteria**:
- [ ] Status code is 401
- [ ] Clear error message about missing auth

---

## Test Suite 2: Event Tracking (Basic)

### T2.1 Track Event with User ID Only

**Priority**: Critical
**Expected**: Event with user_id is accepted

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "UAT Test Event",
    "user_id": "uat_user_001",
    "properties": {
      "test_suite": "T2.1",
      "description": "Basic user_id event"
    },
    "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
  }'
```

**Expected Response (200 OK)**:
```json
{
  "accepted": 1,
  "rejected": []
}
```

**Pass Criteria**:
- [ ] Status code is 200
- [ ] `accepted` count is 1
- [ ] `rejected` array is empty
- [ ] Event visible in dashboard

---

### T2.2 Track Event with Visitor ID Only

**Priority**: Critical
**Expected**: Event with visitor_id is accepted

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_anonymous_001",
    "properties": {
      "test_suite": "T2.2",
      "url": "https://example.com/pricing",
      "referrer": "https://google.com/search"
    }
  }'
```

**Expected Response (200 OK)**:
```json
{
  "accepted": 1,
  "rejected": []
}
```

**Pass Criteria**:
- [ ] Status code is 200
- [ ] `accepted` count is 1
- [ ] Event visible in dashboard
- [ ] Visitor created/updated in system

---

### T2.3 Track Event with Both User ID and Visitor ID

**Priority**: High
**Expected**: Event with both IDs is accepted

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Signup",
    "user_id": "uat_user_002",
    "visitor_id": "vis_uat_anonymous_002",
    "properties": {
      "test_suite": "T2.3",
      "plan": "pro",
      "trial_days": 14
    }
  }'
```

**Pass Criteria**:
- [ ] Status code is 200
- [ ] `accepted` count is 1
- [ ] Both user_id and visitor_id recorded

---

### T2.4 Reject Event Without Any ID

**Priority**: Critical
**Expected**: Event without user_id or visitor_id is rejected

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Invalid Event",
    "properties": {
      "test_suite": "T2.4"
    }
  }'
```

**Expected Response (422 or 200 with rejection)**:
```json
{
  "accepted": 0,
  "rejected": [
    {
      "event": {...},
      "errors": ["user_id or visitor_id required"]
    }
  ]
}
```

**Pass Criteria**:
- [ ] `accepted` is 0
- [ ] `rejected` array contains the event
- [ ] Error message indicates missing ID

---

### T2.5 Batch Event Tracking

**Priority**: High
**Expected**: Multiple events in single request are processed

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "events": [
      {
        "event_type": "Page View",
        "visitor_id": "vis_uat_batch_001",
        "properties": { "url": "/landing", "test_suite": "T2.5" }
      },
      {
        "event_type": "Page View",
        "visitor_id": "vis_uat_batch_001",
        "properties": { "url": "/pricing", "test_suite": "T2.5" }
      },
      {
        "event_type": "Signup",
        "visitor_id": "vis_uat_batch_001",
        "user_id": "uat_batch_user_001",
        "properties": { "plan": "basic", "test_suite": "T2.5" }
      }
    ]
  }'
```

**Pass Criteria**:
- [ ] Status code is 200
- [ ] `accepted` count is 3
- [ ] All events visible in dashboard
- [ ] Events linked to same visitor

---

## Test Suite 3: UTM Parameter Tracking

### T3.1 Full UTM Parameters (All 5 Fields)

**Priority**: Critical
**Expected**: All 5 UTM parameters are captured and stored

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_utm_full_001",
    "properties": {
      "test_suite": "T3.1",
      "url": "https://example.com/pricing?utm_source=google&utm_medium=cpc&utm_campaign=black_friday_2024&utm_content=ad_v1&utm_term=analytics+software",
      "referrer": "https://google.com/search"
    }
  }'
```

**Pass Criteria**:
- [ ] Event captured successfully
- [ ] Dashboard shows utm_source: `google`
- [ ] Dashboard shows utm_medium: `cpc`
- [ ] Dashboard shows utm_campaign: `black_friday_2024`
- [ ] Dashboard shows utm_content: `ad_v1`
- [ ] Dashboard shows utm_term: `analytics software`
- [ ] Channel derived as `paid_search`

---

### T3.2 Partial UTM Parameters (Source + Medium Only)

**Priority**: High
**Expected**: Partial UTM parameters are captured

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_utm_partial_001",
    "properties": {
      "test_suite": "T3.2",
      "url": "https://example.com/landing?utm_source=facebook&utm_medium=social"
    }
  }'
```

**Pass Criteria**:
- [ ] Event captured successfully
- [ ] utm_source: `facebook`
- [ ] utm_medium: `social`
- [ ] utm_campaign: null/empty
- [ ] Channel derived as `organic_social`

---

### T3.3 UTM Source Only

**Priority**: Medium
**Expected**: Single UTM parameter is captured

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_utm_source_only",
    "properties": {
      "test_suite": "T3.3",
      "url": "https://example.com/page?utm_source=newsletter"
    }
  }'
```

**Pass Criteria**:
- [ ] Event captured
- [ ] utm_source: `newsletter`
- [ ] Other UTM fields: null/empty
- [ ] Channel: depends on referrer

---

### T3.4 Email Campaign UTM

**Priority**: High
**Expected**: Email UTM parameters derive correct channel

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_utm_email",
    "properties": {
      "test_suite": "T3.4",
      "url": "https://example.com/promo?utm_source=mailchimp&utm_medium=email&utm_campaign=weekly_digest"
    }
  }'
```

**Pass Criteria**:
- [ ] Channel derived as `email`
- [ ] utm_source: `mailchimp`
- [ ] utm_medium: `email`
- [ ] utm_campaign: `weekly_digest`

---

### T3.5 Paid Social UTM (Facebook Ads)

**Priority**: High
**Expected**: Paid social parameters derive correct channel

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_utm_paid_social",
    "properties": {
      "test_suite": "T3.5",
      "url": "https://example.com/landing?utm_source=facebook&utm_medium=paid_social&utm_campaign=retargeting_q4"
    }
  }'
```

**Pass Criteria**:
- [ ] Channel derived as `paid_social`
- [ ] utm_source: `facebook`
- [ ] utm_medium: `paid_social`

---

### T3.6 Display Advertising UTM

**Priority**: Medium
**Expected**: Display ad parameters derive correct channel

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_utm_display",
    "properties": {
      "test_suite": "T3.6",
      "url": "https://example.com/offer?utm_source=gdn&utm_medium=display&utm_campaign=brand_awareness"
    }
  }'
```

**Pass Criteria**:
- [ ] Channel derived as `display`
- [ ] utm_medium: `display`

---

### T3.7 Affiliate UTM

**Priority**: Medium
**Expected**: Affiliate parameters derive correct channel

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_utm_affiliate",
    "properties": {
      "test_suite": "T3.7",
      "url": "https://example.com/deal?utm_source=partner_site&utm_medium=affiliate&utm_campaign=summer_promo"
    }
  }'
```

**Pass Criteria**:
- [ ] Channel derived as `affiliate`
- [ ] utm_medium: `affiliate`

---

### T3.8 UTM with URL Encoding

**Priority**: High
**Expected**: URL-encoded UTM parameters are correctly decoded

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_utm_encoded",
    "properties": {
      "test_suite": "T3.8",
      "url": "https://example.com/page?utm_source=google&utm_medium=cpc&utm_campaign=black%20friday%20sale&utm_term=analytics%2Bsoftware"
    }
  }'
```

**Pass Criteria**:
- [ ] utm_campaign decoded to `black friday sale`
- [ ] utm_term decoded to `analytics+software`

---

### T3.9 Case Sensitivity in UTM

**Priority**: Medium
**Expected**: UTM parameters are stored as-is (case preserved)

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_utm_case",
    "properties": {
      "test_suite": "T3.9",
      "url": "https://example.com/page?utm_source=Google&utm_medium=CPC&utm_campaign=Black_Friday"
    }
  }'
```

**Pass Criteria**:
- [ ] utm_source stored as `Google`
- [ ] utm_medium stored as `CPC`
- [ ] Channel classification still works (case-insensitive matching)

---

## Test Suite 4: Non-UTM Attribution (Referrer-Based)

### T4.1 Organic Search (Google)

**Priority**: Critical
**Expected**: Google referrer without UTM derives organic_search

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_organic_google",
    "properties": {
      "test_suite": "T4.1",
      "url": "https://example.com/landing",
      "referrer": "https://www.google.com/search?q=analytics+tools"
    }
  }'
```

**Pass Criteria**:
- [ ] Channel derived as `organic_search`
- [ ] Referrer host stored as `google.com`
- [ ] No UTM parameters

---

### T4.2 Organic Search (Bing)

**Priority**: High
**Expected**: Bing referrer derives organic_search

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_organic_bing",
    "properties": {
      "test_suite": "T4.2",
      "url": "https://example.com/features",
      "referrer": "https://www.bing.com/search?q=marketing+attribution"
    }
  }'
```

**Pass Criteria**:
- [ ] Channel derived as `organic_search`
- [ ] Referrer host: `bing.com`

---

### T4.3 Organic Social (Facebook)

**Priority**: High
**Expected**: Facebook referrer without UTM derives organic_social

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_organic_fb",
    "properties": {
      "test_suite": "T4.3",
      "url": "https://example.com/blog/post",
      "referrer": "https://www.facebook.com/"
    }
  }'
```

**Pass Criteria**:
- [ ] Channel derived as `organic_social`
- [ ] Referrer host: `facebook.com`

---

### T4.4 Organic Social (LinkedIn)

**Priority**: High
**Expected**: LinkedIn referrer derives organic_social

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_organic_linkedin",
    "properties": {
      "test_suite": "T4.4",
      "url": "https://example.com/enterprise",
      "referrer": "https://www.linkedin.com/feed/"
    }
  }'
```

**Pass Criteria**:
- [ ] Channel derived as `organic_social`
- [ ] Referrer host: `linkedin.com`

---

### T4.5 Organic Social (Twitter/X)

**Priority**: Medium
**Expected**: Twitter referrer derives organic_social

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_organic_twitter",
    "properties": {
      "test_suite": "T4.5",
      "url": "https://example.com/product",
      "referrer": "https://twitter.com/someuser/status/123"
    }
  }'
```

**Pass Criteria**:
- [ ] Channel derived as `organic_social`

---

### T4.6 Video (YouTube)

**Priority**: Medium
**Expected**: YouTube referrer derives video channel

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_video_youtube",
    "properties": {
      "test_suite": "T4.6",
      "url": "https://example.com/demo",
      "referrer": "https://www.youtube.com/watch?v=abc123"
    }
  }'
```

**Pass Criteria**:
- [ ] Channel derived as `video`
- [ ] Referrer host: `youtube.com`

---

### T4.7 External Referral (Generic)

**Priority**: High
**Expected**: Unknown external site derives referral

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_referral",
    "properties": {
      "test_suite": "T4.7",
      "url": "https://example.com/featured",
      "referrer": "https://someotherblog.com/best-tools-2024"
    }
  }'
```

**Pass Criteria**:
- [ ] Channel derived as `referral`
- [ ] Referrer host stored correctly

---

### T4.8 Direct Traffic (No Referrer)

**Priority**: Critical
**Expected**: No referrer and no UTM derives direct

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_direct",
    "properties": {
      "test_suite": "T4.8",
      "url": "https://example.com/"
    }
  }'
```

**Pass Criteria**:
- [ ] Channel derived as `direct`
- [ ] No referrer stored
- [ ] No UTM parameters

---

### T4.9 Direct Traffic (Empty Referrer)

**Priority**: High
**Expected**: Empty referrer string derives direct

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_direct_empty",
    "properties": {
      "test_suite": "T4.9",
      "url": "https://example.com/",
      "referrer": ""
    }
  }'
```

**Pass Criteria**:
- [ ] Channel derived as `direct`

---

## Test Suite 5: Session Management

### T5.1 First Session Creation

**Priority**: Critical
**Expected**: New visitor creates new session with initial_utm

```bash
VISITOR_ID="vis_uat_session_$(date +%s)"

curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "'$VISITOR_ID'",
    "properties": {
      "test_suite": "T5.1",
      "url": "https://example.com/landing?utm_source=google&utm_medium=cpc&utm_campaign=launch",
      "referrer": "https://google.com/search"
    }
  }'
```

**Pass Criteria**:
- [ ] New visitor record created
- [ ] New session record created
- [ ] Session has initial_utm with all parameters
- [ ] Session has initial_referrer

---

### T5.2 Same Session - UTM Not Overwritten

**Priority**: Critical
**Expected**: Subsequent events in same session do NOT overwrite initial_utm

```bash
# Step 1: First event with UTM (creates session)
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_session_preserve",
    "session_id": "sess_uat_preserve_001",
    "properties": {
      "test_suite": "T5.2.1",
      "url": "https://example.com/?utm_source=google&utm_medium=cpc"
    }
  }'

# Step 2: Second event WITHOUT UTM (should NOT clear initial_utm)
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_session_preserve",
    "session_id": "sess_uat_preserve_001",
    "properties": {
      "test_suite": "T5.2.2",
      "url": "https://example.com/pricing"
    }
  }'

# Step 3: Third event with DIFFERENT UTM (should NOT overwrite)
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_session_preserve",
    "session_id": "sess_uat_preserve_001",
    "properties": {
      "test_suite": "T5.2.3",
      "url": "https://example.com/checkout?utm_source=facebook&utm_medium=social"
    }
  }'
```

**Pass Criteria**:
- [ ] Session initial_utm remains `google/cpc`
- [ ] Session initial_utm is NOT overwritten with `facebook/social`
- [ ] All 3 events linked to same session

---

### T5.3 Multi-Session Multi-Touch Attribution

**Priority**: High
**Expected**: Different sessions capture different initial_utm (enables multi-touch)

```bash
VISITOR_ID="vis_uat_multitouch_$(date +%s)"

# Session 1: Organic search
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "'$VISITOR_ID'",
    "session_id": "sess_uat_mt_001",
    "properties": {
      "test_suite": "T5.3.1",
      "url": "https://example.com/",
      "referrer": "https://google.com/search"
    }
  }'

# Session 2: Paid social
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "'$VISITOR_ID'",
    "session_id": "sess_uat_mt_002",
    "properties": {
      "test_suite": "T5.3.2",
      "url": "https://example.com/pricing?utm_source=facebook&utm_medium=paid_social"
    }
  }'

# Session 3: Direct + Conversion
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Signup",
    "visitor_id": "'$VISITOR_ID'",
    "user_id": "uat_user_multitouch",
    "session_id": "sess_uat_mt_003",
    "properties": {
      "test_suite": "T5.3.3",
      "url": "https://example.com/signup"
    }
  }'
```

**Pass Criteria**:
- [ ] Session 1 channel: `organic_search`
- [ ] Session 2 channel: `paid_social`
- [ ] Session 3 channel: `direct`
- [ ] Same visitor linked to all 3 sessions
- [ ] Journey: organic_search → paid_social → direct → conversion

---

## Test Suite 6: User Identification

### T6.1 Identify User with Traits

**Priority**: High
**Expected**: User traits are stored and associated with user_id

```bash
curl -X POST $MBUZZ_API_URL/identify \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "uat_user_identify_001",
    "traits": {
      "email": "uat-test@example.com",
      "name": "UAT Test User",
      "plan": "enterprise",
      "company": "UAT Testing Inc"
    }
  }'
```

**Expected Response (200 OK)**:
```json
{
  "success": true
}
```

**Pass Criteria**:
- [ ] Status code is 200
- [ ] Success response received
- [ ] User traits stored correctly

---

### T6.2 Alias Visitor to User

**Priority**: High
**Expected**: Anonymous visitor is linked to authenticated user

```bash
# First, create some events as anonymous visitor
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_pre_alias",
    "properties": {
      "test_suite": "T6.2.1",
      "url": "https://example.com/pricing"
    }
  }'

# Then alias the visitor to a user
curl -X POST $MBUZZ_API_URL/alias \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "visitor_id": "vis_uat_pre_alias",
    "user_id": "uat_user_alias_001"
  }'
```

**Pass Criteria**:
- [ ] Alias call succeeds
- [ ] Pre-signup events linked to user
- [ ] Full journey visible under user account

---

## Test Suite 7: Rate Limiting

### T7.1 Rate Limit Headers Present

**Priority**: Medium
**Expected**: Rate limit headers returned on every request

```bash
curl -v -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Rate Limit Test",
    "user_id": "uat_rate_limit",
    "properties": {"test_suite": "T7.1"}
  }' 2>&1 | grep -i "X-RateLimit"
```

**Pass Criteria**:
- [ ] Header `X-RateLimit-Limit` present
- [ ] Header `X-RateLimit-Remaining` present
- [ ] Header `X-RateLimit-Reset` present

---

### T7.2 Rate Limit Enforcement (Optional - High Volume)

**Priority**: Low
**Expected**: Exceeding rate limit returns 429

```bash
# WARNING: This test sends many requests - only run if needed
for i in {1..1100}; do
  curl -s -X POST $MBUZZ_API_URL/events \
    -H "Authorization: Bearer $MBUZZ_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"event_type":"Rate Test '$i'","user_id":"uat_rate_flood","properties":{}}' &
done
wait
```

**Pass Criteria**:
- [ ] Eventually returns 429 status
- [ ] Error message indicates rate limit exceeded
- [ ] `retry_after` value provided

---

## Test Suite 8: Dashboard Verification

### T8.1 Recent Events Display

**Priority**: High
**Expected**: Events from tests appear in dashboard

**Manual Steps**:
1. Log in to dashboard
2. Navigate to Events/Recent Activity
3. Filter by test_suite property

**Pass Criteria**:
- [ ] Events from T2.x tests visible
- [ ] Events from T3.x tests visible
- [ ] Event details show correct properties

---

### T8.2 UTM Report Breakdown

**Priority**: High
**Expected**: UTM parameters aggregated in reports

**Manual Steps**:
1. Navigate to Dashboard > Attribution/UTM Reports
2. Check UTM source breakdown
3. Check UTM campaign breakdown

**Pass Criteria**:
- [ ] `google` source shows in breakdown
- [ ] `facebook` source shows in breakdown
- [ ] Campaign names visible
- [ ] Channel classification correct

---

### T8.3 Session Journey View

**Priority**: High
**Expected**: Multi-session journeys display correctly

**Manual Steps**:
1. Find visitor from T5.3 tests
2. View session history
3. Check each session's attribution

**Pass Criteria**:
- [ ] All 3 sessions visible
- [ ] Each session has correct channel
- [ ] Timeline shows chronological order

---

## Test Suite 9: Edge Cases

### T9.1 Very Long URL with UTM

**Priority**: Medium
**Expected**: Long URLs are handled gracefully

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_long_url",
    "properties": {
      "test_suite": "T9.1",
      "url": "https://example.com/very/long/path/that/goes/on/and/on/forever?utm_source=google&utm_medium=cpc&utm_campaign=this_is_a_very_long_campaign_name_that_might_cause_issues_in_some_systems&utm_content=ad_variant_with_lots_of_detail_about_the_creative&utm_term=many+different+keywords+that+someone+might+search+for+when+looking+for+a+product+like+ours"
    }
  }'
```

**Pass Criteria**:
- [ ] Event accepted
- [ ] UTM parameters extracted correctly
- [ ] No truncation errors

---

### T9.2 Special Characters in UTM

**Priority**: Medium
**Expected**: Special characters handled correctly

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Page View",
    "visitor_id": "vis_uat_special_chars",
    "properties": {
      "test_suite": "T9.2",
      "url": "https://example.com/?utm_source=google&utm_campaign=50%25_off_sale%21&utm_content=Buy+Now%3F"
    }
  }'
```

**Pass Criteria**:
- [ ] Event accepted
- [ ] utm_campaign decoded correctly
- [ ] No SQL injection or XSS issues

---

### T9.3 Empty Properties Object

**Priority**: Low
**Expected**: Event with empty properties is accepted

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Minimal Event",
    "user_id": "uat_minimal_user",
    "properties": {}
  }'
```

**Pass Criteria**:
- [ ] Event accepted
- [ ] No errors

---

### T9.4 Null Properties

**Priority**: Low
**Expected**: Event with null properties is handled

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Null Props Event",
    "user_id": "uat_null_props_user",
    "properties": null
  }'
```

**Pass Criteria**:
- [ ] Event accepted OR clear validation error
- [ ] No server crash

---

### T9.5 Future Timestamp

**Priority**: Low
**Expected**: Future timestamps are handled

```bash
FUTURE_TS=$(date -u -v+1d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "+1 day" +"%Y-%m-%dT%H:%M:%SZ")

curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "Future Event",
    "user_id": "uat_future_ts",
    "timestamp": "'$FUTURE_TS'",
    "properties": {"test_suite": "T9.5"}
  }'
```

**Pass Criteria**:
- [ ] Event accepted OR clear validation error
- [ ] Timestamp stored as provided

---

### T9.6 Invalid JSON

**Priority**: High
**Expected**: Malformed JSON returns clear error

```bash
curl -X POST $MBUZZ_API_URL/events \
  -H "Authorization: Bearer $MBUZZ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"event_type": "Bad JSON", "user_id": "uat_bad_json", properties: invalid}'
```

**Pass Criteria**:
- [ ] Status code is 400 Bad Request
- [ ] Clear error message about invalid JSON
- [ ] No server crash

---

## Test Execution Summary

### Environment Checklist

| Environment | T1 Auth | T2 Events | T3 UTM | T4 Non-UTM | T5 Sessions | T6 Identify | T7 Rate | T8 Dashboard | T9 Edge |
|-------------|---------|-----------|--------|------------|-------------|-------------|---------|--------------|---------|
| Development | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Staging | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Production | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |

### Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Tester | | | |
| Developer | | | |
| Product Owner | | | |

---

## Appendix A: Channel Classification Reference

| Channel | UTM Medium Values | Referrer Patterns |
|---------|-------------------|-------------------|
| `paid_search` | cpc, ppc, paid | - |
| `organic_search` | organic | google, bing, yahoo, duckduckgo |
| `paid_social` | paid_social, social (with paid indicator) | - |
| `organic_social` | social | facebook, instagram, linkedin, twitter, tiktok |
| `email` | email | - |
| `display` | display, banner | - |
| `affiliate` | affiliate | - |
| `referral` | referral | any external domain |
| `video` | - | youtube, vimeo |
| `direct` | - | (empty or no referrer) |
| `other` | any unrecognized | any unrecognized |

---

## Appendix B: Test Data Cleanup

After testing, clean up test data:

```bash
# Mark test visitors/users for cleanup
# (Implementation depends on your cleanup strategy)
```

**Recommended**: Use separate test account for UAT, not production account.

---

## Appendix C: Troubleshooting

### Common Issues

**401 Unauthorized**:
- Check API key is correct
- Ensure `Bearer ` prefix included
- Verify key not revoked

**422 Validation Error**:
- Check required fields present
- Verify JSON structure
- Check for extra commas

**429 Rate Limited**:
- Wait for rate limit reset
- Check X-RateLimit-Reset header
- Consider batching events

**500 Server Error**:
- Check server logs
- Verify database connection
- Report to development team

---

**End of UAT Test Plan**
