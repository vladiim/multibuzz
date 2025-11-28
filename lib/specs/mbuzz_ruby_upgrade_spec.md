# mbuzz-ruby SDK Upgrade Specification

Version: 2.0.0
Last Updated: 2025-11-28
Relates To: [SDK Specification](sdk_specification.md)

---

## Problem Statement

The current mbuzz-ruby gem (v0.2.x) has critical gaps that break marketing attribution:

### Current State

| Feature | Status | Impact |
|---------|--------|--------|
| Visitor ID generation | ✅ Works | Cookie set correctly |
| Session ID management | ❌ Missing | No session tracking |
| URL capture | ❌ Missing | No landing page data |
| Referrer capture | ❌ Missing | No referrer attribution |
| UTM extraction | ❌ Missing | No campaign tracking |
| Auto page view | ❌ Missing | Visitors invisible until conversion |

### Broken User Journey

```
Day 1: Visitor lands from Google Ads (utm_source=google)
       → Cookie set ✅
       → Nothing sent to Multibuzz ❌
       → Visitor completely invisible ❌

Day 7: Visitor returns directly, converts
       → Conversion tracked ✅
       → Attributed to "direct" ❌ (should be Google Ads)
       → Original session data lost ❌
```

### Root Cause

1. **No session_id**: Gem doesn't generate or send session IDs
2. **No request context in payloads**: URL/referrer not included in API calls
3. **No auto-tracking**: Must explicitly call track() - page views not captured

---

## Solution Overview

Upgrade mbuzz-ruby to comply with the [SDK Specification](sdk_specification.md):

1. Add session ID management with 30-minute timeout
2. Enrich all events with URL, referrer from request context
3. Add `page_view` convenience method
4. Update middleware to handle sessions
5. Ensure all API calls include full context

---

## Implementation Plan

### Phase 1: Session Management

#### 1.1 Add Session ID to Middleware

**File:** `lib/mbuzz/middleware/tracking.rb`

```ruby
module Mbuzz
  module Middleware
    class Tracking
      SESSION_TIMEOUT = 30.minutes.to_i
      VISITOR_COOKIE = "_mbuzz_vid"
      SESSION_COOKIE = "_mbuzz_sid"

      def initialize(app)
        @app = app
      end

      def call(env)
        @request = Rack::Request.new(env)

        env[ENV_VISITOR_ID_KEY] = visitor_id
        env[ENV_SESSION_ID_KEY] = session_id

        RequestContext.with_context(request: @request) do
          status, headers, body = @app.call(env)
          set_cookies(headers)
          [status, headers, body]
        end
      end

      private

      def visitor_id
        @visitor_id ||= @request.cookies[VISITOR_COOKIE] || generate_id
      end

      def session_id
        @session_id ||= valid_session_id || generate_id
      end

      def valid_session_id
        existing = @request.cookies[SESSION_COOKIE]
        return nil unless existing
        # Session cookie has Max-Age, so if it exists, it's valid
        existing
      end

      def generate_id
        SecureRandom.hex(32)
      end

      def set_cookies(headers)
        cookies = []
        cookies << build_visitor_cookie
        cookies << build_session_cookie
        Rack::Utils.set_cookie_header!(headers, VISITOR_COOKIE, visitor_cookie_options)
        Rack::Utils.set_cookie_header!(headers, SESSION_COOKIE, session_cookie_options)
      end

      def visitor_cookie_options
        {
          value: visitor_id,
          path: "/",
          max_age: 63072000, # 2 years
          httponly: true,
          same_site: :lax,
          secure: @request.ssl?
        }
      end

      def session_cookie_options
        {
          value: session_id,
          path: "/",
          max_age: SESSION_TIMEOUT,
          httponly: true,
          same_site: :lax,
          secure: @request.ssl?
        }
      end
    end
  end
end
```

#### 1.2 Add Constants

**File:** `lib/mbuzz.rb`

```ruby
module Mbuzz
  # ... existing constants ...

  ENV_SESSION_ID_KEY = "mbuzz.session_id"
  SESSION_COOKIE_NAME = "_mbuzz_sid"
  SESSION_TIMEOUT = 1800 # 30 minutes

  def self.session_id
    RequestContext.current&.request&.env&.dig(ENV_SESSION_ID_KEY)
  end
end
```

### Phase 2: Request Context Enrichment

#### 2.1 Enhance RequestContext

**File:** `lib/mbuzz/request_context.rb`

```ruby
module Mbuzz
  class RequestContext
    def self.with_context(request:)
      Thread.current[:mbuzz_request] = request
      Thread.current[:mbuzz_context] = new(request)
      yield
    ensure
      Thread.current[:mbuzz_request] = nil
      Thread.current[:mbuzz_context] = nil
    end

    def self.current
      Thread.current[:mbuzz_context]
    end

    attr_reader :request

    def initialize(request)
      @request = request
    end

    def url
      request.url
    end

    def referrer
      request.referrer
    end

    def user_agent
      request.user_agent
    end

    def visitor_id
      request.env[ENV_VISITOR_ID_KEY]
    end

    def session_id
      request.env[ENV_SESSION_ID_KEY]
    end

    # Build properties hash with full context
    def enriched_properties(custom_properties = {})
      {
        url: url,
        referrer: referrer
      }.compact.merge(custom_properties)
    end
  end
end
```

### Phase 3: Update API Methods

#### 3.1 Update Track Method

**File:** `lib/mbuzz.rb`

```ruby
module Mbuzz
  def self.track(event_type, properties: {})
    return false unless config.enabled

    Client.track(
      visitor_id: visitor_id,
      session_id: session_id,
      event_type: event_type,
      properties: enriched_properties(properties),
      timestamp: Time.now.utc.iso8601
    )
  end

  def self.page_view(properties: {})
    track("page_view", properties: properties)
  end

  def self.conversion(conversion_type, revenue: nil, properties: {})
    return false unless config.enabled

    Client.conversion(
      visitor_id: visitor_id,
      conversion_type: conversion_type,
      revenue: revenue,
      properties: enriched_properties(properties)
    )
  end

  private

  def self.enriched_properties(custom_properties)
    return custom_properties unless RequestContext.current

    RequestContext.current.enriched_properties(custom_properties)
  end
end
```

#### 3.2 Update TrackRequest

**File:** `lib/mbuzz/client/track_request.rb`

```ruby
module Mbuzz
  class Client
    class TrackRequest
      def initialize(visitor_id, session_id, event_type, properties, timestamp)
        @visitor_id = visitor_id
        @session_id = session_id
        @event_type = event_type
        @properties = properties
        @timestamp = timestamp
      end

      def call
        return false unless valid?

        { success: true, event_id: event["id"], session_id: event["session_id"] }
      end

      private

      def valid?
        present?(@event_type) &&
          hash?(@properties) &&
          (@visitor_id || @session_id) &&
          event
      end

      def payload
        {
          visitor_id: @visitor_id,
          session_id: @session_id,
          event_type: @event_type,
          properties: @properties,
          timestamp: @timestamp
        }.compact
      end

      # ... rest unchanged
    end
  end
end
```

#### 3.3 Update Client Interface

**File:** `lib/mbuzz/client.rb`

```ruby
module Mbuzz
  class Client
    def self.track(visitor_id: nil, session_id: nil, event_type:, properties: {}, timestamp: nil)
      TrackRequest.new(
        visitor_id,
        session_id,
        event_type,
        properties,
        timestamp || Time.now.utc.iso8601
      ).call
    end

    # ... other methods
  end
end
```

### Phase 4: Controller Helpers

#### 4.1 Update ControllerHelpers

**File:** `lib/mbuzz/controller_helpers.rb`

```ruby
module Mbuzz
  module ControllerHelpers
    def mbuzz_track(event_type, properties: {})
      Mbuzz.track(event_type, properties: properties)
    end

    def mbuzz_page_view(properties: {})
      Mbuzz.page_view(properties: properties)
    end

    def mbuzz_conversion(conversion_type, revenue: nil, properties: {})
      Mbuzz.conversion(conversion_type, revenue: revenue, properties: properties)
    end

    def mbuzz_identify(user_id, traits: {})
      Mbuzz.identify(user_id, traits: traits)
    end

    def mbuzz_alias(user_id)
      Mbuzz.alias_user(user_id)
    end

    def mbuzz_visitor_id
      request.env[Mbuzz::ENV_VISITOR_ID_KEY]
    end

    def mbuzz_session_id
      request.env[Mbuzz::ENV_SESSION_ID_KEY]
    end
  end
end
```

---

## Migration Guide

### For Existing Integrations (e.g., pet_resorts)

#### Before (v0.2.x)

```ruby
# app/services/mta/track.rb
module Mta
  class Track < Base
    def run
      Mbuzz.track(event, **properties)  # Missing context!
    end
  end
end
```

#### After (v2.0.0)

```ruby
# app/services/mta/track.rb
module Mta
  class Track < Base
    def run
      # Context automatically enriched by SDK
      Mbuzz.track(event, properties: properties)
    end
  end
end
```

No changes needed! The SDK now automatically includes URL, referrer, session_id.

#### Optional: Add Page View Tracking

To track all page views (recommended):

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  after_action :track_page_view, if: :trackable_request?

  private

  def track_page_view
    mbuzz_page_view
  end

  def trackable_request?
    request.get? &&
      response.successful? &&
      !request.xhr? &&
      Mbuzz.config.enabled
  end
end
```

Or use a concern:

```ruby
# app/controllers/concerns/mbuzz_trackable.rb
module MbuzzTrackable
  extend ActiveSupport::Concern

  included do
    after_action :track_page_view, if: :should_track_page_view?
  end

  private

  def track_page_view
    mbuzz_page_view(page_properties)
  end

  def page_properties
    {} # Override in controllers to add custom properties
  end

  def should_track_page_view?
    request.get? && response.successful? && !request.xhr?
  end
end
```

---

## Testing Plan

### Unit Tests

```ruby
# test/mbuzz/middleware/tracking_test.rb
class Mbuzz::Middleware::TrackingTest < Minitest::Test
  def test_generates_visitor_id_when_missing
    env = Rack::MockRequest.env_for("/")

    middleware.call(env)

    assert env["mbuzz.visitor_id"].present?
    assert_equal 64, env["mbuzz.visitor_id"].length
  end

  def test_preserves_existing_visitor_id
    env = Rack::MockRequest.env_for("/",
      "HTTP_COOKIE" => "_mbuzz_vid=existing123")

    middleware.call(env)

    assert_equal "existing123", env["mbuzz.visitor_id"]
  end

  def test_generates_session_id
    env = Rack::MockRequest.env_for("/")

    middleware.call(env)

    assert env["mbuzz.session_id"].present?
  end

  def test_sets_visitor_cookie_in_response
    env = Rack::MockRequest.env_for("/")

    _, headers, _ = middleware.call(env)

    assert headers["Set-Cookie"].include?("_mbuzz_vid=")
    assert headers["Set-Cookie"].include?("Max-Age=63072000")
  end

  def test_sets_session_cookie_in_response
    env = Rack::MockRequest.env_for("/")

    _, headers, _ = middleware.call(env)

    assert headers["Set-Cookie"].include?("_mbuzz_sid=")
    assert headers["Set-Cookie"].include?("Max-Age=1800")
  end
end
```

```ruby
# test/mbuzz/track_test.rb
class Mbuzz::TrackTest < Minitest::Test
  def test_track_includes_url_from_context
    with_request_context(url: "https://example.com/page") do
      stub_api_post do |payload|
        assert_equal "https://example.com/page", payload[:events][0][:properties][:url]
      end

      Mbuzz.track("page_view")
    end
  end

  def test_track_includes_referrer_from_context
    with_request_context(referrer: "https://google.com") do
      stub_api_post do |payload|
        assert_equal "https://google.com", payload[:events][0][:properties][:referrer]
      end

      Mbuzz.track("page_view")
    end
  end

  def test_track_includes_session_id
    with_request_context(session_id: "sess_123") do
      stub_api_post do |payload|
        assert_equal "sess_123", payload[:events][0][:session_id]
      end

      Mbuzz.track("page_view")
    end
  end
end
```

### Integration Test (pet_resorts)

```ruby
# test/integration/mbuzz_tracking_test.rb
class MbuzzTrackingTest < ActionDispatch::IntegrationTest
  def test_page_view_sends_full_context
    stub_mbuzz_api do |request_body|
      event = request_body[:events].first

      assert_equal "page_view", event[:event_type]
      assert event[:visitor_id].present?
      assert event[:session_id].present?
      assert event[:properties][:url].include?("/pricing")
    end

    get pricing_path(utm_source: "google", utm_medium: "cpc")
  end

  def test_conversion_includes_session_context
    stub_mbuzz_api

    # First, visit with UTMs
    get root_path(utm_source: "facebook", utm_campaign: "q4")

    # Then convert
    stub_mbuzz_api do |request_body|
      conversion = request_body[:conversion]

      assert conversion[:visitor_id].present?
      assert conversion[:properties][:url].present?
    end

    post conversions_path, params: { type: "purchase", revenue: 99 }
  end
end
```

---

## Rollout Plan

### Phase 1: Release v2.0.0-beta

1. Implement all changes in mbuzz-ruby gem
2. Release as `2.0.0-beta`
3. Update pet_resorts Gemfile to use beta
4. Test on staging environment

### Phase 2: Staging Validation

1. Deploy pet_resorts staging with beta gem
2. Run manual test flow:
   - Visit with UTMs
   - Browse pages
   - Convert
3. Verify in Multibuzz:
   - Visitor created on first page view
   - Session created with UTMs
   - All page views tracked
   - Conversion attributed correctly

### Phase 3: Production Release

1. Release mbuzz-ruby v2.0.0
2. Update pet_resorts production
3. Monitor for 48 hours
4. Verify attribution reports

---

## Breaking Changes

### API Changes

| Method | v0.2.x | v2.0.0 |
|--------|--------|--------|
| `Mbuzz.track` | `track(event_type, properties: {})` | Same (backward compatible) |
| `Mbuzz.page_view` | N/A | **New** |
| `Mbuzz.session_id` | N/A | **New** |

### Cookie Changes

| Cookie | v0.2.x | v2.0.0 |
|--------|--------|--------|
| `_mbuzz_vid` | ✅ (name: `mbuzz_visitor_id`) | ✅ (renamed to `_mbuzz_vid`) |
| `_mbuzz_sid` | ❌ | ✅ **New** |

**Migration note:** Existing visitors will get new visitor IDs due to cookie name change. Consider keeping backward compatibility by checking both cookie names.

---

## Success Metrics

After deployment, verify:

1. **Visitor creation rate**: Should match unique visitors in analytics
2. **Session creation rate**: ~1.5-3x visitor count (return visits)
3. **UTM capture rate**: >95% of sessions with UTM params should have them stored
4. **Attribution accuracy**: Conversions attributed to original acquisition channel

### Queries to Validate

```ruby
# Visitors created (should increase significantly)
Visitor.where(account_id: 2, created_at: 1.day.ago..).count

# Sessions with UTMs
Session.where(account_id: 2)
  .where.not(initial_utm: {})
  .where(created_at: 1.day.ago..)
  .count

# Events with URL populated
Event.where(account_id: 2)
  .where("properties->>'url' IS NOT NULL")
  .where(created_at: 1.day.ago..)
  .count

# Attribution breakdown
Conversion.where(account_id: 2, created_at: 1.day.ago..)
  .joins(:session)
  .group("sessions.channel")
  .count
```

---

## Appendix: Current vs Target State

### Current Payload (v0.2.x)

```json
{
  "events": [{
    "event_type": "add_to_cart",
    "visitor_id": "abc123",
    "properties": {
      "revenue": 50,
      "location": "Sydney"
    },
    "timestamp": "2025-11-28T12:00:00Z"
  }]
}
```

**Missing:** session_id, url, referrer

### Target Payload (v2.0.0)

```json
{
  "events": [{
    "event_type": "add_to_cart",
    "visitor_id": "abc123",
    "session_id": "def456",
    "properties": {
      "url": "https://petpro360.com/cart?utm_source=google",
      "referrer": "https://google.com/search",
      "revenue": 50,
      "location": "Sydney"
    },
    "timestamp": "2025-11-28T12:00:00Z"
  }]
}
```

**Result:** Full context for attribution, UTM extraction, session tracking.
