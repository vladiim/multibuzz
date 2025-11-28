# Documentation Update Checklist

Following the Identity & Sessions spec, these documents need updating.

---

## Priority 1: API Contract (Critical)

**File:** `lib/docs/sdk/api_contract.md`

### Add: POST /sessions Endpoint

Currently missing. Add full documentation for:
- Endpoint definition
- Request/response format
- When SDKs should call it (new session detection)
- Async/non-blocking requirement

### Update: Identity Concepts

The contract doesn't explain:
- How visitor_id links to user_id
- That alias creates backward+forward attribution links
- That identify also links visitor to user

### Fix: Status of Endpoints

Currently says:
```
### POST /api/v1/identify
**Status**: 🚧 Planned (not yet implemented)
```

But identify IS implemented. Update status.

### Add: Session ID

Currently doesn't mention session_id at all. Events should include session_id.

---

## Priority 2: SDK Registry

**File:** `lib/docs/sdk/sdk_registry.md`

### Update: Required Methods

Currently lists:
```
track(user_id:, visitor_id:, event_type:, properties:, timestamp:)
identify(user_id:, visitor_id:, traits:)
alias(visitor_id:, user_id:)
```

Add:
```
create_session(visitor_id:, session_id:, url:, referrer:, started_at:)
```

### Update: Required Behavior

Add:
- Auto-create session on new visit (POST /sessions)
- Session detection (cookie expired or missing)
- Non-blocking session POST requirement

### Update: Ruby SDK Features

Currently shows:
```
- ✅ Session tracking (automatic)
```

This is misleading - it tracks session_id but doesn't POST to API. Update to reflect current state vs target state.

---

## Priority 3: Server-Side Architecture

**File:** `lib/docs/architecture/server_side_attribution_architecture.md`

### Fix: Client Library Description

Currently says:
```
**Client library code**: ~50 lines (just forwards cookies + URLs)
```

This is incorrect/incomplete. SDK must:
- Generate visitor_id and session_id
- Detect new sessions
- POST to /sessions endpoint (async)
- Forward context with events

### Add: Sessions Endpoint

Document mentions session creation in services but doesn't mention the dedicated API endpoint.

### Add: Identity Resolution Section

Document focuses on sessions but doesn't cover:
- Visitor → User linking
- Cross-device attribution
- Backward/forward compatibility of alias

---

## Priority 4: Getting Started (User-Facing)

**File:** `app/views/docs/_getting_started.html.erb`

### Update: Automatic Tracking Description

Currently says:
```
## Automatic Page View Tracking

The Ruby gem includes Rack middleware that automatically tracks page views.
```

This should be updated to explain:
- Middleware creates sessions (not just page views)
- Sessions are POSTed to API with acquisition context
- This is what enables attribution

### Add: Sessions Concept

Users should understand:
- Session = a visit with acquisition context (UTMs, referrer, channel)
- Sessions are tracked automatically
- Sessions enable multi-touch attribution

### Add: Identity Section Expansion

Current identify/alias docs are minimal. Expand to explain:
- Why you should call alias (links anonymous → known)
- What happens to past sessions (they get attributed)
- Cross-device scenario

---

## Priority 5: SDK UAT Guide

**File:** `lib/docs/sdk/SDK_UAT_GUIDE.md`

### Add: Session Testing

Test cases for:
- New visitor creates session
- Returning visitor (same session) doesn't create new session
- Expired session creates new session
- Session includes correct UTMs/referrer/channel

### Add: Identity Testing

Test cases for:
- Alias links visitor to user
- Past sessions attributed after alias
- New device → login → alias → sessions linked

---

## New Documents Needed

### 1. Identity Resolution Guide (User-Facing)

**File:** `app/views/docs/_identity.html.erb` (new)

Explain to users:
- What is a visitor vs user
- When to call identify vs alias
- Cross-device tracking setup
- In-store/offline integration

### 2. Sessions Endpoint Reference

**File:** `app/views/docs/_sessions.html.erb` (new)

API reference for:
- POST /sessions endpoint
- Request/response format
- SDK integration examples

---

## Cross-References to Add

After updates, ensure these docs link to each other:

```
identity_and_sessions_spec.md
    ↓ references
api_contract.md ←→ sdk_registry.md
    ↓ referenced by
server_side_attribution_architecture.md
    ↓ simplified for users in
_getting_started.html.erb
```

---

## Consistency Checklist

After all updates, verify:

- [ ] All docs agree on endpoint: `POST /api/v1/sessions`
- [ ] All docs agree on session timeout: 30 minutes
- [ ] All docs agree on cookie names: `_mbuzz_vid`, `_mbuzz_sid`
- [ ] All docs agree on visitor_id format: 64-char hex
- [ ] All docs agree on alias behavior: backward + forward linking
- [ ] All docs explain: sessions enable attribution, not just page views
