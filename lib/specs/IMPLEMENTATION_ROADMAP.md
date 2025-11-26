# Implementation Roadmap: Server-Side Attribution Architecture

**Status**: Phase 1 & 2 Complete ✅ | Phase 3 Next 🚧
**Timeline**: 4-6 days (2 days complete, 2-3 days remaining)
**Created**: 2025-11-14
**Last Updated**: 2025-11-14

## Summary

- ✅ **Phase 1 (Backend)**: Complete - All services built, tested, working
- ✅ **Phase 2 (Testing)**: Complete - 242 tests passing, full coverage
- 🚧 **Phase 3 (Rails Gem)**: Not started - Ready to begin

---

## Current State

### ✅ What Works (Phase 1 MVP)
- Event ingestion API with batch processing
- Multi-tenancy, rate limiting, authentication
- Basic visitor/session/event tracking
- UTM extraction from properties hash
- **API accepts**: `visitor_id`, `session_id`, `properties` in payload

### ❌ What's Missing (New Architecture)
- Server-side cookie management
- Automatic UTM extraction from URLs
- Channel attribution (UTM + referrer-based)
- Funnel tracking
- HTTP metadata enrichment (IP, User-Agent, language)
- **Target API**: Just `url` + `referrer`, server handles IDs

---

## Architecture Changes Overview

### Current Flow
```
Client generates IDs → Client extracts UTMs → Client sends everything → Server stores
```

### Target Flow
```
Client sends URL + referrer → Server extracts IDs from cookies → Server extracts UTMs from URL → 
Server derives channel → Server enriches metadata → Server returns Set-Cookie
```

**Benefit**: Client code reduces from ~500 lines to ~50 lines (90% reduction)

---

## Required Changes

### 1. Database Schema (Migrations)

**Add to `sessions` table**:
- `initial_referrer` (string) - Store raw referrer URL
- `channel` (string) - Derived channel (denormalized for perf)
- Index on `channel`

**Add to `events` table**:
- GIN indexes on `properties->>'funnel'` and `properties->>'funnel_step'`

---

### 2. New Services (Domain Objects)

#### Cookie Management
**`Visitors::IdentificationService`**:
- Input: `request`, `account`
- Logic: Read `_mbuzz_vid` cookie OR generate new ID
- Output: `{ visitor_id:, set_cookie: }`
- Cookie: 1 year expiry, HttpOnly, Secure, SameSite=Lax

**`Sessions::IdentificationService`**:
- Input: `request`, `account`, `visitor_id`
- Logic: Read `_mbuzz_sid` cookie, check expiry (30 min), OR create new
- Output: `{ session_id:, set_cookie:, created: bool }`
- Marks old sessions as `ended_at` when expired

#### Attribution Logic
**`Sessions::ChannelAttributionService`**:
- Input: `utm_data` (hash), `referrer` (string)
- Logic: Derive channel from UTM medium OR referrer domain pattern matching
- Output: `channel` (string)
- Channels: `paid_search`, `organic_search`, `organic_social`, `paid_social`, `email`, `display`, `referral`, `direct`, etc.

#### Enrichment
**`Events::EnrichmentService`**:
- Input: `request` (Rack::Request)
- Logic: Extract IP (anonymized), User-Agent (parse device/browser/OS), Accept-Language, DNT
- Output: `metadata` hash
- Uses `device_detector` gem for User-Agent parsing

---

### 3. Update Existing Services

**`Sessions::UtmCaptureService`**:
- Current: Extracts from properties hash
- Update: Parse URL query string, extract `utm_*` params
- Input changes from `properties` to `url` (string)

**`Events::ProcessingService`**:
- Add: Call `ChannelAttributionService` when creating new session
- Add: Store `initial_referrer` and `channel` in session
- Add: Call `EnrichmentService` to add metadata to event

**`Events::IngestionService`**:
- Add: Support both old format (with `visitor_id`/`session_id`) and new format (without)
- Add: Accept `request` parameter for cookie extraction
- Backward compatibility during transition

**`Api::V1::EventsController`**:
- Add: Call `IdentificationService` to extract/generate IDs from cookies
- Add: Set `Set-Cookie` headers in response
- Pass `request` to ingestion service

---

### 4. Dependencies

**Add to Gemfile**:
```ruby
gem 'device_detector'  # User-Agent parsing
```

---

### 5. API Contract Changes

**Old (current)**:
```json
{
  "visitor_id": "abc123",
  "session_id": "xyz789",
  "properties": { "utm_source": "google", ... }
}
```

**New (target)**:
```json
{
  "url": "https://example.com/pricing?utm_source=google&utm_medium=cpc",
  "referrer": "https://google.com/search",
  "properties": { "funnel": "subscription", "funnel_step": "pricing_view" }
}
```

**Response adds**:
```
Set-Cookie: _mbuzz_vid=...; Expires=...; HttpOnly; Secure
Set-Cookie: _mbuzz_sid=...; Max-Age=1800; HttpOnly; Secure
```

---

## Testing Requirements

### Unit Tests (New Services)
- `Visitors::IdentificationService`: Cookie extraction, ID generation
- `Sessions::IdentificationService`: Session timeout, expiry, renewal
- `Sessions::ChannelAttributionService`: All channel derivation rules
- `Sessions::UtmCaptureService`: URL parsing edge cases
- `Events::EnrichmentService`: IP anonymization, device detection

### Integration Tests
- Cookie flow: First request (no cookies) → sets cookies → subsequent requests reuse
- Channel attribution: UTM-based, referrer-based, direct
- Funnel tracking: Events with funnel properties
- Backward compatibility: Old format still works
- Multi-tenancy: Account A can't access Account B's cookies

### Controller Tests
- New event format acceptance
- Set-Cookie headers present in response
- Legacy format still works

---

## Implementation Phases

### Phase 1: Backend Services (1-2 days) ✅ COMPLETE
**Goal**: Server can accept new format, extract IDs from cookies, derive channels

**Tasks**:
- [x] Database migrations (`initial_referrer`, `channel`, indexes)
- [x] Create Visitors::IdentificationService
- [x] Create Sessions::IdentificationService
- [x] Create Sessions::ChannelAttributionService
- [x] Create Events::EnrichmentService
- [x] Update Sessions::UtmCaptureService (URL parsing)
- [x] Update Events::ProcessingService (channel capture)
- [x] Update Api::V1::EventsController (Set-Cookie headers)
- [ ] Add `device_detector` gem (deferred - not blocking)

**Success**: API accepts `{url, referrer}`, returns cookies, extracts UTMs, derives channel ✅

---

### Phase 2: Testing (1 day) ✅ COMPLETE
**Goal**: Comprehensive test coverage, backward compatibility verified

**Tasks**:
- [x] Write unit tests for ChannelAttributionService (18 tests)
- [x] Write unit tests for EnrichmentService (11 tests)
- [x] Write unit tests for UtmCaptureService URL parsing (9 new tests)
- [x] Update integration tests for JSONB query syntax
- [x] Test backward compatibility (old format still works)
- [x] Test multi-tenancy isolation

**Success**: All tests passing, 242 tests, 1621 assertions ✅

---

### Phase 3: Rails Gem (2-3 days) 🚧 NOT STARTED
**Goal**: Working Rails gem that auto-tracks page views

**Tasks**:
- [ ] Generate gem skeleton (`bundle gem mbuzz`)
- [ ] Create `Mbuzz::Middleware::Tracking` (Rack middleware)
- [ ] Create `Mbuzz::Api::Client` (HTTP client)
- [ ] Cookie forwarding (request → API → response)
- [ ] Configuration (API key, URL, batch settings)
- [ ] Manual tracking helpers (for custom events)
- [ ] Example Rails app for testing
- [ ] Gem tests (unit + integration)
- [ ] Documentation (README, installation guide)

**Success**: Gem installs, tracks page views, forwards cookies transparently

---

## Critical Decisions

### 1. Session Timeout Handling
**Decision needed**: When session expires (30 min), should new session capture fresh UTM?

**Option A** (Recommended): YES - Enables multi-touch attribution
- Session 1: Google Ads → Session 2: Facebook → Session 3: Direct
- Can analyze full visitor journey

**Option B**: NO - Only first-ever session captures UTM
- Simpler, but loses multi-touch data

**Recommendation**: Option A (capture per session)

### 2. Backward Compatibility Duration
**Decision needed**: How long to support old API format?

**Recommendation**:
- Phase 1: Support both formats (backward compatible)
- After 6 months: Log deprecation warnings
- After 12 months: Reject old format (breaking change)

### 3. Cookie Domain Strategy
**Decision needed**: Set cookies on which domain?

**Options**:
- Same domain as client app (requires subdomain setup)
- mbuzz API domain (simpler, works cross-domain)

**Recommendation**: mbuzz API domain (simpler for MVP)

---

## Domain Naming Conventions

### Services
- `Visitors::IdentificationService` - Cookie-based visitor ID management
- `Sessions::IdentificationService` - Cookie-based session ID management
- `Sessions::ChannelAttributionService` - UTM/referrer → channel derivation
- `Events::EnrichmentService` - HTTP metadata extraction

### Models (No changes)
- `Visitor`, `Session`, `Event` - Existing models work as-is

### Cookies
- `_mbuzz_vid` - Visitor ID cookie (1 year)
- `_mbuzz_sid` - Session ID cookie (30 min)

### Channels (Standard Taxonomy)
- `paid_search`, `organic_search`
- `paid_social`, `organic_social`
- `email`, `display`, `affiliate`, `referral`, `video`, `direct`

---

## Success Criteria

### Phase 1 Complete ✅
- [x] Server accepts events with just `url` + `referrer`
- [x] Server extracts visitor/session IDs from cookies
- [x] Server returns `Set-Cookie` headers
- [x] Server extracts UTMs from URL automatically
- [x] Server derives channel (UTM or referrer-based)
- [x] Server enriches with HTTP metadata
- [x] Backward compatibility maintained
- [x] All tests passing (242 tests, 1621 assertions)

**Status**: Complete - All 8 criteria met

### Phase 2 Complete
- [ ] Rails gem tracks page views automatically
- [ ] Gem forwards cookies transparently
- [ ] Example app demonstrates integration
- [ ] Documentation updated

**Status**: Not started

---

## Timeline

| Phase | Duration | Start | End |
|-------|----------|-------|-----|
| Phase 1: Backend | 1-2 days | Day 1 | Day 2 |
| Phase 2: Testing | 1 day | Day 3 | Day 3 |
| Phase 3: Rails Gem | 2-3 days | Day 4 | Day 6 |
| **Total** | **4-6 days** | | |

---

## Next Actions

**Completed** (Phase 1 & 2):
- [x] Database migrations
- [x] All 4 new services created
- [x] All 3 existing services updated
- [x] Controller updated with Set-Cookie
- [x] Comprehensive tests (242 passing)
- [x] Documentation updated

**Up Next** (Phase 3 - Rails Gem):
1. Generate gem skeleton
2. Implement Rack middleware
3. Implement API client
4. Cookie forwarding logic
5. Configuration system
6. Example app integration
7. Gem testing
8. Documentation

**Optional** (Can defer):
- Add `device_detector` gem for better User-Agent parsing
- Performance optimization
- Deploy to staging/production

