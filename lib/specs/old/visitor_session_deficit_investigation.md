# Visitor/Session Deficit Investigation

## Problem
Pet Resorts has thousands of events and conversions but only hundreds of visitors and sessions.

---

## ROOT CAUSE IDENTIFIED: Middleware Singleton Bug

**File:** `mbuzz-ruby/lib/mbuzz/middleware/tracking.rb`

The Rack middleware is instantiated **once** when Rails boots and reused for ALL requests. Instance variables `@visitor_id`, `@session_id`, and `@user_id` are memoized with `||=` but **never reset between requests**.

### The Bug

```ruby
# Line 51-53
def visitor_id
  @visitor_id ||= visitor_id_from_cookie || Visitor::Identifier.generate
end

# Line 80-82
def session_id
  @session_id ||= session_id_from_cookie || generate_session_id
end
```

### What Happens

1. **Request 1 (User A):** No cookies → generates `visitor_id = "abc123"` → stores in `@visitor_id`
2. **Request 2 (User B, different browser):** No cookies → `@visitor_id ||=` short-circuits → returns `"abc123"` from User A!
3. **All subsequent requests:** Same visitor_id and session_id for ALL users

### Evidence

- Incognito browser visit sent `session_id` that already existed in DB from Dec 10
- Only 72 sessions for thousands of visits
- Same visitor_id appearing across multiple domains in logs

### The Fix

Reset instance variables at the start of each request in `call(env)`:

```ruby
def call(env)
  return app.call(env) if skip_request?(env)

  @request = Rack::Request.new(env)
  @visitor_id = nil  # Reset per request
  @session_id = nil  # Reset per request
  @user_id = nil     # Reset per request

  # ... rest of method
end
```

---

## Other Issues (Lower Priority)

### 1. Async Session Creation is Fire-and-Forget
**File:** `mbuzz-ruby/lib/mbuzz/middleware/tracking.rb:104-106`
```ruby
def create_session_async
  Thread.new { create_session }
end
```
Background thread can fail silently. When events arrive without a pre-created session, `Sessions::TrackingService` creates a NEW session.

### 2. Session Lookup Uses `.active` Scope
**File:** `multibuzz/app/services/sessions/tracking_service.rb:35`
```ruby
def session
  @session ||= account.sessions.active.find_by(session_id: session_id, visitor: visitor)
end
```
With 30-min session cookie timeout, if session ends, subsequent events for same `session_id` create NEW session.

### 3. Unique Index Allows Duplicates
Index is on `(account_id, session_id, started_at)`. Same `session_id` can exist with different `started_at` values.

### 4. Race Conditions
Both `Visitors::LookupService` and `Sessions::TrackingService` use `find_by` then `create` instead of `find_or_create_by!`.

---

## Production Queries (Rails Console)

```ruby
# Set account
a = Account.find_by(slug: "pet-resorts")

# Overall stats
{
  events: Event.where(account: a).count,
  conversions: Conversion.where(account: a).count,
  visitors: Visitor.where(account: a).count,
  sessions: Session.where(account: a).count,
  unique_session_ids: Session.where(account: a).distinct.count(:session_id)
}

# Duplicate session_ids (same session_id, different started_at)
Session.where(account: a).group(:session_id).having("COUNT(*) > 1").count

# Sessions created within 2s of event (means not pre-created)
Event.joins(:session).where(account: a).where("ABS(EXTRACT(EPOCH FROM (events.occurred_at - sessions.started_at))) < 2").count

# Sessions per visitor (high = problem)
Session.where(account: a).group(:visitor_id).order("count_all DESC").limit(10).count

# Duplicate visitor_ids (should be 0)
Visitor.where(account: a).group(:visitor_id).having("COUNT(*) > 1").count
```

---

## Key Files

| File | Issue |
|------|-------|
| `mbuzz-ruby/lib/mbuzz/middleware/tracking.rb:104` | Async fire-and-forget |
| `multibuzz/app/services/sessions/tracking_service.rb:35` | `.active` scope |
| `multibuzz/app/services/visitors/lookup_service.rb:28` | Race condition |
