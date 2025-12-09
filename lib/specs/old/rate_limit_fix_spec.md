# Rate Limiting & Session Filtering Fix

**Status**: Critical Fix Required
**Created**: 2025-12-05
**Priority**: P0 - Blocking Production

---

## Problem Statement

The current rate limiting approach is fundamentally broken:

1. **Rate limit of 1000/hour is too low** - Even small sites exceed this
2. **Health checks consume quota** - 2 LB instances × 20 checks/min = 2400/hour
3. **All API calls count equally** - Sessions, events, conversions all count as 1
4. **No path filtering in middleware** - Creates sessions for `/up`, `/assets`, `/cable`, etc.

**Result**: Real customer traffic is blocked (429) while health checks pollute the data.

---

## Solution Overview

### 1. Remove Rate Limiting (Server-Side)

For MVP, remove rate limiting entirely. Track usage for billing but don't block.

**Rationale**:
- No paying customers yet = no abuse risk
- Blocking legitimate traffic is worse than theoretical abuse
- Billing system can enforce limits when needed

### 2. Path Filtering in Middleware (Gem-Side)

Skip tracking for non-user requests:
- Health checks (`/up`, `/health`, `/healthz`)
- Static assets (`/assets`, `.js`, `.css`, `.png`, etc.)
- WebSocket connections (`/cable`)
- API endpoints (`/api`)

### 3. Usage Tracking for Billing (Server-Side)

Keep tracking usage per account for:
- Billing calculations
- Usage dashboards
- Future rate limiting (when needed)

---

## Implementation Plan

### Phase 1: Immediate Unblock (5 min)

**Action**: Clear rate limit and temporarily disable

```ruby
# mbuzz production console
account = Account.find_by(name: 'PetPro360')
Rails.cache.delete("rate_limit:account:#{account.id}")
```

### Phase 2: Remove Rate Limiting from API (multibuzz)

**File**: `app/controllers/api/v1/base_controller.rb`

**Change**: Comment out or remove rate limit checks

```ruby
# BEFORE
before_action :check_rate_limit
after_action :set_rate_limit_headers

# AFTER
# Rate limiting disabled for MVP - usage tracked via Billing::UsageCounter
# before_action :check_rate_limit
# after_action :set_rate_limit_headers
```

**Also remove/comment**:
- `check_rate_limit` method
- `rate_limit_result` method
- `set_rate_limit_headers` method
- `render_rate_limited` method

**Keep**: `Billing::UsageCounter` for tracking (already in events ingestion)

### Phase 3: Path Filtering in Middleware (mbuzz-ruby gem)

**File**: `lib/mbuzz/middleware/tracking.rb`

**Add path filtering**:

```ruby
module Mbuzz
  module Middleware
    class Tracking
      # Paths to skip - no tracking needed
      SKIP_PATHS = %w[
        /up
        /health
        /healthz
        /ping
        /cable
        /assets
        /packs
        /rails/active_storage
      ].freeze

      # Extensions to skip - static assets
      SKIP_EXTENSIONS = %w[
        .js .css .map .png .jpg .jpeg .gif .ico .svg .woff .woff2 .ttf .eot
      ].freeze

      def call(env)
        return app.call(env) if skip_request?(env)

        # ... existing tracking logic
      end

      private

      def skip_request?(env)
        path = env['PATH_INFO'].to_s.downcase

        skip_by_path?(path) || skip_by_extension?(path)
      end

      def skip_by_path?(path)
        SKIP_PATHS.any? { |skip| path.start_with?(skip) }
      end

      def skip_by_extension?(path)
        SKIP_EXTENSIONS.any? { |ext| path.end_with?(ext) }
      end
    end
  end
end
```

### Phase 4: Configurable Skip Paths (mbuzz-ruby gem)

Allow customers to configure additional skip paths:

**File**: `lib/mbuzz/configuration.rb`

```ruby
module Mbuzz
  class Configuration
    attr_accessor :api_key, :api_url, :enabled, :debug, :timeout,
                  :skip_paths, :skip_extensions

    def initialize
      @api_url = "https://mbuzz.co/api/v1"
      @enabled = true
      @debug = false
      @timeout = 5
      @skip_paths = []      # Additional paths to skip
      @skip_extensions = [] # Additional extensions to skip
    end
  end
end
```

**Usage in initializer**:

```ruby
Mbuzz.init(
  api_key: "sk_live_...",
  skip_paths: ["/admin", "/internal"],
  skip_extensions: [".pdf"]
)
```

---

## Changes Required

### multibuzz (Server)

| File | Change |
|------|--------|
| `app/controllers/api/v1/base_controller.rb` | Remove/disable rate limiting |
| `app/services/api_keys/rate_limiter_service.rb` | Keep but don't use (future use) |

### mbuzz-ruby (Gem)

| File | Change |
|------|--------|
| `lib/mbuzz/middleware/tracking.rb` | Add path/extension filtering |
| `lib/mbuzz/configuration.rb` | Add `skip_paths`, `skip_extensions` options |
| `lib/mbuzz.rb` | Pass new config options to init |

---

## Testing

### Gem Tests

```ruby
# test/mbuzz/middleware/tracking_test.rb

test "skips health check paths" do
  env = { 'PATH_INFO' => '/up' }
  middleware = Mbuzz::Middleware::Tracking.new(app)

  # Should call app directly without tracking
  assert middleware.send(:skip_request?, env)
end

test "skips static assets" do
  env = { 'PATH_INFO' => '/assets/application.js' }
  middleware = Mbuzz::Middleware::Tracking.new(app)

  assert middleware.send(:skip_request?, env)
end

test "tracks normal page requests" do
  env = { 'PATH_INFO' => '/products/123' }
  middleware = Mbuzz::Middleware::Tracking.new(app)

  refute middleware.send(:skip_request?, env)
end
```

### Integration Tests

1. Deploy gem update to pet_resorts staging
2. Verify health checks don't create sessions
3. Verify real page views create sessions
4. Verify events/conversions are tracked

---

## Rollout Plan

1. **Clear rate limit cache** (immediate)
2. **Deploy multibuzz** with rate limiting disabled
3. **Release mbuzz-ruby gem** v0.6.0 with path filtering
4. **Update pet_resorts** Gemfile to new gem version
5. **Deploy pet_resorts** with new gem
6. **Verify** sessions are created only for real traffic

---

## Future Considerations

### Smart Rate Limiting (When Needed)

When we have paying customers, implement smarter limits:

```ruby
# Different limits by request type
LIMITS = {
  sessions: 100_000,  # Generous - these are page views
  events: 50_000,     # Track significant actions
  conversions: 10_000 # Revenue events
}.freeze

# Or by plan
PLAN_LIMITS = {
  free: { events: 10_000 },
  starter: { events: 100_000 },
  pro: { events: 1_000_000 },
  enterprise: { events: :unlimited }
}.freeze
```

### Abuse Protection

- IP-based rate limiting for anonymous/unauthenticated requests
- Anomaly detection for sudden traffic spikes
- Account suspension for confirmed abuse

---

## Success Criteria

- [ ] Health checks no longer create sessions
- [ ] Static assets no longer create sessions
- [ ] Real user page views create sessions with UTM data
- [ ] Events and conversions flow through without 429s
- [ ] Usage is tracked for billing purposes
- [ ] No data loss for legitimate traffic
