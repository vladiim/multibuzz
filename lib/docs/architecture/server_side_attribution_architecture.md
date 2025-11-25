# Server-Side Attribution Architecture

**Date**: 2025-11-14

---

## TL;DR: Does Server-Side Cookie Approach Give Us All Attribution Data?

### ✅ YES - Captures Everything Needed

| Requirement | Supported | How |
|------------|-----------|-----|
| **Extract channel info (UTM + non-UTM)** | ✅ | Server extracts from URL + analyzes referrer |
| **First visit vs session visits** | ✅ | Cookie presence + DB lookup + `initial_utm` flag |
| **Events vs page views** | ✅ | `event_type` field + session linkage |

---

## Architecture Overview

### Cookie-Based Visitor/Session Tracking

**Client sends**:
- Full URL (with query params intact)
- Referrer URL
- Existing cookies (if any)

**Server extracts**:
- Visitor ID (from `_mbuzz_vid` cookie or generates new)
- Session ID (from `_mbuzz_sid` cookie or generates new)
- UTM parameters (from URL query string)
- Referrer domain/path
- IP address, User-Agent (request metadata)

**Server returns**:
- `Set-Cookie: _mbuzz_vid=...` (1 year expiry)
- `Set-Cookie: _mbuzz_sid=...` (30 min expiry)

---

## Domain Model

### Core Entities

```
Visitor (Anonymous User)
├── identified by: visitor_id (cookie value)
├── has many Sessions
└── has many Events

Session (Visit Journey)
├── belongs to Visitor
├── identified by: session_id (cookie value)
├── tracks: initial_utm (JSONB - first page view UTM only)
├── tracks: initial_referrer (string)
├── tracks: channel (derived - see below)
├── tracks: page_view_count (integer)
├── timeout: 30 minutes of inactivity
└── has many Events

Event (Page View or Conversion)
├── belongs to Visitor + Session
├── types: page_view, signup, purchase, etc.
└── properties: url, referrer, custom data (JSONB)
```

---

## Three Visit Scenarios

### 1. First Visit (New Visitor)
- **Cookie state**: No `_mbuzz_vid`
- **DB state**: Visitor not found
- **Action**: Create Visitor + Create Session + Capture `initial_utm` + Capture `initial_referrer`
- **Channel attribution**: Derive from UTM or referrer

### 2. Session Page View (Same Session)
- **Cookie state**: Has both `_mbuzz_vid` + `_mbuzz_sid`, session not expired
- **DB state**: Active Session exists
- **Action**: Find Session + Increment `page_view_count` + **DO NOT** update `initial_utm`
- **Channel attribution**: Use Session's existing `initial_utm`

### 3. New Session (Returning Visitor)
- **Cookie state**: Has `_mbuzz_vid`, missing or expired `_mbuzz_sid`
- **DB state**: Visitor exists, Session missing/expired
- **Action**: Find Visitor + Create NEW Session + Capture **fresh** `initial_utm` + Capture **fresh** `initial_referrer`
- **Channel attribution**: Derive from new UTM or referrer (enables multi-touch)

---

## Channel Attribution Logic

### Service: `Sessions::ChannelAttributionService`

**Input**: `initial_utm` (JSONB), `initial_referrer` (string)

**Output**: `channel` (string)

### Derivation Rules (Priority Order)

**1. UTM-based channels** (if `utm_medium` present):
- `utm_medium = "cpc" | "ppc" | "paid"` → `"paid_search"`
- `utm_medium = "social"` + paid indicators → `"paid_social"`
- `utm_medium = "social"` → `"organic_social"`
- `utm_medium = "email"` → `"email"`
- `utm_medium = "display" | "banner"` → `"display"`
- `utm_medium = "affiliate"` → `"affiliate"`
- `utm_medium = "referral"` → `"referral"`
- `utm_medium = "organic"` → `"organic_search"`

**2. Referrer-based channels** (if no UTM, fallback to `initial_referrer`):
- Referrer domain matches `google|bing|yahoo|duckduckgo` → `"organic_search"`
- Referrer domain matches `facebook|instagram|linkedin|twitter|tiktok` → `"organic_social"`
- Referrer domain matches `youtube` → `"video"`
- Referrer domain is external → `"referral"`

**3. Direct** (no UTM, no referrer):
- Empty referrer → `"direct"`

### Channel Values

Standard channel taxonomy:
- `paid_search` - Google Ads, Bing Ads
- `organic_search` - SEO traffic from search engines
- `paid_social` - Facebook Ads, LinkedIn Ads
- `organic_social` - Social media posts (unpaid)
- `email` - Email campaigns
- `display` - Display/banner ads
- `affiliate` - Affiliate links
- `referral` - External website links
- `video` - YouTube, Vimeo
- `direct` - Direct traffic (typed URL, bookmarks)
- `other` - Unknown/uncategorized

---

## Session `initial_utm` Capture Rules

### Critical Rule: Only Capture on Session Creation

**Capture `initial_utm`**: When `session.initial_utm.blank?` (new session)
**Do NOT update**: When `session.initial_utm.present?` (existing session)

### Why?

Preserves **first-touch attribution** for the session. If user lands on:
1. `/pricing?utm_source=google&utm_medium=cpc` → Capture UTM
2. `/features` (no UTM) → **Do NOT** overwrite with empty
3. `/signup` (no UTM) → **Do Not** overwrite

Session's `initial_utm` remains `{ utm_source: "google", utm_medium: "cpc" }` for entire session.

---

## Event Types

### Page Views (Automatic)
- `event_type = "page_view"`
- Tracked automatically by middleware
- Increments `session.page_view_count`

### Conversion Events (Manual - Phase 2)
- `event_type = "signup"`
- `event_type = "purchase"`
- `event_type = "trial_started"`
- Tracked via explicit API calls
- Linked to active session (inherits `initial_utm`)

### Event Attribution

```ruby
# All events link to session
event.session.initial_utm # First-touch UTM
event.session.channel      # Derived channel
event.session.visitor      # Visitor across all sessions
```

---

## Multi-Touch Attribution Support

### Per-Session UTM Capture

Each new session captures its own `initial_utm`:
- Session 1 (Day 1, 10am): `{ utm_source: "google", utm_medium: "cpc" }`
- Session 2 (Day 1, 3pm): `{ utm_source: "facebook", utm_medium: "social" }`
- Session 3 (Day 2, 9am): `{}` (direct)

### Attribution Models

**First-Touch**: `visitor.sessions.order(:started_at).first.initial_utm`

**Last-Touch**: `conversion_event.session.initial_utm`

**Multi-Touch**: `visitor.sessions.order(:started_at).pluck(:initial_utm, :channel)`

---

## Key Services

### `Visitors::IdentificationService`
- **Input**: `request` (Rack::Request), `account`
- **Output**: `{ visitor_id:, set_cookie: }`
- **Logic**: Read `_mbuzz_vid` cookie OR generate new visitor_id

### `Sessions::IdentificationService`
- **Input**: `request`, `account`, `visitor_id`
- **Output**: `{ session_id:, set_cookie:, created: }`
- **Logic**: Read `_mbuzz_sid` cookie, check expiry, OR create new session

### `Sessions::UtmCaptureService`
- **Input**: `url` (string)
- **Output**: `{ utm_source:, utm_medium:, utm_campaign:, utm_content:, utm_term: }` (hash)
- **Logic**: Parse URL query string, extract `utm_*` params

### `Sessions::ChannelAttributionService`
- **Input**: `initial_utm` (hash), `initial_referrer` (string)
- **Output**: `channel` (string)
- **Logic**: Apply rules (UTM → referrer → direct)

### `Events::ProcessingService`
- **Input**: `event_data`, `visitor_id`, `session_id`
- **Logic**:
  1. Find/create Visitor
  2. Find/create Session
  3. IF session is NEW → capture `initial_utm` + `initial_referrer`
  4. Create Event record
  5. Increment `session.page_view_count` (if page_view)

---

## Database Schema Additions Needed

### `sessions` table (current):
```ruby
t.jsonb :initial_utm, default: {}
t.datetime :started_at
t.datetime :ended_at
t.integer :page_view_count, default: 0
```

### `sessions` table (add):
```ruby
t.string :initial_referrer  # Store raw referrer from first page view
t.string :channel           # Derived channel (denormalized for performance)
```

---

## Attribution Without UTM Tags

### Supported via Referrer Analysis

**Example flow**:
1. User lands from Google organic search (no UTM tags)
   - URL: `https://example.com/`
   - Referrer: `https://www.google.com/search?q=analytics+tool`

2. Server processing:
   - `UtmCaptureService.call(url)` → `{}` (no UTMs)
   - `ChannelAttributionService.call({}, referrer)`
     - Parse referrer domain: `google.com`
     - Match pattern: `/google|bing|yahoo/`
     - Return: `"organic_search"`

3. Session created:
   ```ruby
   {
     initial_utm: {},
     initial_referrer: "https://www.google.com/search?q=analytics+tool",
     channel: "organic_search"
   }
   ```

### Non-UTM Channel Detection

| Traffic Source | Referrer Pattern | Channel |
|---------------|------------------|---------|
| Google SEO | `google.com/search` | `organic_search` |
| Facebook post | `facebook.com` (no fbclid) | `organic_social` |
| Reddit link | `reddit.com` | `referral` |
| Direct type-in | (empty referrer) | `direct` |
| Bookmark | (empty referrer) | `direct` |

---

## Summary

### ✅ Requirement 1: Channel Attribution
- Server extracts UTMs from URL automatically
- Fallback to referrer analysis for non-UTM traffic
- Derives channel using standard taxonomy
- Supports SEO, social, referral, direct without UTM tags

### ✅ Requirement 2: Visit Differentiation
- **First visit**: Create Visitor + Session, capture attribution
- **Session page views**: Reuse Session, increment counter, preserve `initial_utm`
- **New session**: Create new Session, capture fresh attribution (multi-touch)

### ✅ Requirement 3: Event Importance
- Events linked to Sessions (inherit attribution)
- Query conversions independently of page views
- Support first-touch, last-touch, multi-touch models

**Client library code**: ~50 lines (just forwards cookies + URLs)
**Server handles**: ID generation, UTM extraction, channel derivation, session management


---

## Funnel Tracking Extension

### Overview

Support multiple parallel funnels per account (e.g., lead funnel, subscription funnel, trial funnel). Events can be tagged with funnel context to enable funnel-specific conversion tracking and analysis.

---

### Domain Model Extension

**Event properties** (JSONB extension):
```json
{
  "funnel": "subscription",     // Which funnel this event belongs to
  "funnel_step": "pricing_view", // Position/step in funnel (optional)
  "funnel_position": 2,          // Numeric position (optional)
  // ... existing properties
}
```

**Alternative approach** - Dedicated funnel tracking:
```json
{
  "funnel_id": "sub_funnel_123",  // Reference to predefined funnel
  "step_name": "trial_signup",
  // ... existing properties
}
```

---

### Use Cases

**1. Lead Funnel**
```ruby
# Step 1: Landing page view
Mbuzz.track("page_view", funnel: "lead", funnel_step: "landing")

# Step 2: Lead form view
Mbuzz.track("page_view", funnel: "lead", funnel_step: "form_view")

# Step 3: Lead submitted
Mbuzz.track("lead_submitted", funnel: "lead", funnel_step: "conversion")
```

**2. Subscription Funnel**
```ruby
# Step 1: Pricing page
Mbuzz.track("page_view", funnel: "subscription", funnel_step: "pricing")

# Step 2: Checkout started
Mbuzz.track("checkout_started", funnel: "subscription", funnel_step: "checkout")

# Step 3: Payment completed
Mbuzz.track("subscription_created", funnel: "subscription", funnel_step: "conversion")
```

**3. Multiple Funnels per Session**
Same visitor can progress through different funnels:
```ruby
# Morning: Browse content (lead funnel)
Mbuzz.track("ebook_download", funnel: "lead")

# Afternoon: Sign up for trial (subscription funnel)
Mbuzz.track("trial_started", funnel: "subscription")
```

---

### Recommended Approach: Flexible Event Properties

**Why**: Simple, extensible, no schema changes needed

**Implementation**:
- Use existing `events.properties` JSONB field
- Add convention for funnel metadata
- No new tables or columns required

**Event structure**:
```json
{
  "event_type": "page_view",
  "url": "https://example.com/pricing",
  "referrer": "...",
  "properties": {
    "funnel": "subscription",        // Funnel identifier
    "funnel_step": "pricing_view",   // Step name
    "funnel_position": 1,            // Numeric position (optional)
    "custom_data": "..."             // App-specific data
  }
}
```

---

### Funnel Analysis Queries

**Funnel conversion rate**:
```sql
-- Subscription funnel: pricing view → checkout → conversion
WITH funnel_events AS (
  SELECT 
    session_id,
    MAX(CASE WHEN properties->>'funnel_step' = 'pricing_view' THEN 1 ELSE 0 END) as saw_pricing,
    MAX(CASE WHEN properties->>'funnel_step' = 'checkout' THEN 1 ELSE 0 END) as started_checkout,
    MAX(CASE WHEN event_type = 'subscription_created' THEN 1 ELSE 0 END) as converted
  FROM events
  WHERE properties->>'funnel' = 'subscription'
  AND occurred_at >= NOW() - INTERVAL '30 days'
  GROUP BY session_id
)
SELECT 
  COUNT(*) as total_sessions,
  SUM(saw_pricing) as pricing_views,
  SUM(started_checkout) as checkouts,
  SUM(converted) as conversions,
  ROUND(100.0 * SUM(started_checkout) / NULLIF(SUM(saw_pricing), 0), 2) as pricing_to_checkout_rate,
  ROUND(100.0 * SUM(converted) / NULLIF(SUM(started_checkout), 0), 2) as checkout_to_conversion_rate
FROM funnel_events;
```

**Drop-off by channel**:
```sql
-- Which channels have best conversion in subscription funnel?
SELECT 
  s.channel,
  COUNT(DISTINCT e.session_id) as sessions_in_funnel,
  COUNT(DISTINCT CASE WHEN e.event_type = 'subscription_created' THEN e.session_id END) as conversions,
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN e.event_type = 'subscription_created' THEN e.session_id END) / 
        COUNT(DISTINCT e.session_id), 2) as conversion_rate
FROM events e
JOIN sessions s ON s.id = e.session_id
WHERE e.properties->>'funnel' = 'subscription'
GROUP BY s.channel
ORDER BY conversion_rate DESC;
```

---

### Database Indexing

**Add GIN index for funnel queries**:
```ruby
# Migration
add_index :events, "(properties->>'funnel')", using: :btree, name: 'index_events_on_funnel'
add_index :events, "(properties->>'funnel_step')", using: :btree, name: 'index_events_on_funnel_step'
```

---

### API Usage Examples

**Client-side tracking (Rails gem)**:
```ruby
# Automatic page view with funnel context
Mbuzz::Middleware.configure do |config|
  config.funnel_detector = ->(request) {
    case request.path
    when /^\/pricing/
      { funnel: "subscription", funnel_step: "pricing_view", funnel_position: 1 }
    when /^\/checkout/
      { funnel: "subscription", funnel_step: "checkout", funnel_position: 2 }
    when /^\/download-guide/
      { funnel: "lead", funnel_step: "landing", funnel_position: 1 }
    else
      nil # No funnel context
    end
  }
end

# Or manual tracking:
class SubscriptionsController < ApplicationController
  def create
    @subscription = Subscription.create!(...)
    
    Mbuzz.track("subscription_created", {
      funnel: "subscription",
      funnel_step: "conversion",
      funnel_position: 3,
      plan: @subscription.plan,
      mrr: @subscription.amount
    })
  end
end
```

**API request**:
```json
POST /api/v1/events
{
  "events": [{
    "event_type": "subscription_created",
    "timestamp": "2025-11-14T10:00:00Z",
    "properties": {
      "funnel": "subscription",
      "funnel_step": "conversion",
      "funnel_position": 3,
      "plan": "pro",
      "mrr": 9900
    }
  }]
}
```

---

### Funnel Configuration (Phase 2)

**Optional**: Predefined funnel schemas in account settings

```ruby
# Account.settings JSONB
{
  "funnels": {
    "subscription": {
      "name": "Subscription Funnel",
      "steps": [
        { "name": "landing", "position": 1, "event_types": ["page_view"] },
        { "name": "pricing_view", "position": 2, "event_types": ["page_view"] },
        { "name": "checkout", "position": 3, "event_types": ["checkout_started"] },
        { "name": "conversion", "position": 4, "event_types": ["subscription_created"] }
      ]
    },
    "lead": {
      "name": "Lead Generation Funnel",
      "steps": [
        { "name": "landing", "position": 1 },
        { "name": "form_view", "position": 2 },
        { "name": "conversion", "position": 3, "event_types": ["lead_submitted"] }
      ]
    }
  }
}
```

**Benefits**:
- Validates funnel/step names against schema
- Auto-generates funnel reports
- Consistent naming across team

---

### Key Design Decisions

**1. Use properties JSONB (not dedicated columns)**
- ✅ Flexible: Add any funnel without migrations
- ✅ Extensible: Add funnel metadata as needed
- ✅ Simple: No new tables/relationships
- ⚠️ Query performance: Mitigated with GIN indexes

**2. Funnel fields are optional**
- Not all events belong to funnels
- Page views can have funnel context (automatic)
- Conversion events SHOULD have funnel context (manual)

**3. Support multiple funnels per session**
- User can interact with lead funnel AND subscription funnel
- Each event tagged independently
- No session-level funnel lock-in

**4. Funnel naming convention**
- Recommended: `snake_case` strings
- Examples: `"subscription"`, `"lead"`, `"trial_activation"`, `"enterprise_sales"`
- Step names: `"landing"`, `"pricing_view"`, `"checkout"`, `"conversion"`

---

### Summary

**Funnel support via**:
- `properties.funnel` - Funnel identifier (e.g., `"subscription"`, `"lead"`)
- `properties.funnel_step` - Step name (e.g., `"pricing_view"`, `"checkout"`)
- `properties.funnel_position` - Numeric position (optional, for ordering)

**No schema changes needed** - uses existing JSONB `properties` field with GIN indexes.

**Enables queries**:
- Conversion rates per funnel
- Drop-off analysis by step
- Channel performance by funnel
- Multi-funnel attribution

