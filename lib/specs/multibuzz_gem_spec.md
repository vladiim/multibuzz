# Multibuzz Ruby Gem Specification

**Version**: 1.0.0
**Created**: 2025-11-14
**Status**: Design Phase

---

## Overview

A minimal Rails gem for multi-channel attribution tracking, following Segment's API design pattern.

**API Design**: Inspired by Segment analytics-ruby - simple class methods with named parameters.

---

## Installation & Setup

### Gemfile

```ruby
gem 'multibuzz'
```

### Configuration

```ruby
# config/initializers/multibuzz.rb
Multibuzz.configure do |config|
  config.api_key = ENV['MULTIBUZZ_API_KEY']
end
```

---

## API

### Track Events

```ruby
Multibuzz.track(
  user_id: current_user.id,           # Required (or anonymous_id)
  event: 'Signup',                    # Required
  properties: {                       # Optional
    plan: 'pro'
  }
)
```

### Identify Users

```ruby
Multibuzz.identify(
  user_id: current_user.id,           # Required
  traits: {                           # Optional
    email: current_user.email,
    name: current_user.name,
    plan: current_user.plan
  }
)
```

---

## Usage Examples

### In Controllers

```ruby
class SignupsController < ApplicationController
  def create
    @user = User.create!(signup_params)

    # Identify the user
    Multibuzz.identify(
      user_id: @user.id,
      traits: {
        email: @user.email,
        name: @user.name,
        created_at: @user.created_at
      }
    )

    # Track the signup event
    Multibuzz.track(
      user_id: @user.id,
      event: 'Signup',
      properties: {
        plan: @user.plan,
        trial_days: 14
      }
    )

    redirect_to dashboard_path
  end
end
```

### Anonymous Visitors (No Login Required)

For tracking before user signs up:

```ruby
class LandingController < ApplicationController
  def show
    # Track anonymous visitor (Multibuzz creates visitor from cookies)
    Multibuzz.track(
      anonymous_id: multibuzz_visitor_id,  # Helper method
      event: 'Landing Page View'
    )
  end
end

class SignupsController < ApplicationController
  def create
    @user = User.create!(params)

    # Alias anonymous visitor to user
    Multibuzz.alias(
      user_id: @user.id,
      previous_id: multibuzz_visitor_id
    )

    Multibuzz.identify(
      user_id: @user.id,
      traits: { email: @user.email }
    )

    redirect_to dashboard_path
  end
end
```

### Funnel Tracking

```ruby
class SubscriptionsController < ApplicationController
  def pricing
    Multibuzz.track(
      user_id: current_user.id,
      event: 'Pricing Page Viewed',
      properties: { funnel: 'subscription' }
    )
  end

  def checkout
    Multibuzz.track(
      user_id: current_user.id,
      event: 'Checkout Started',
      properties: { funnel: 'subscription' }
    )
  end

  def create
    @subscription = Subscription.create!(params)

    Multibuzz.track(
      user_id: current_user.id,
      event: 'Subscription Created',
      properties: {
        funnel: 'subscription',
        plan: @subscription.plan,
        amount: @subscription.amount_cents
      }
    )

    redirect_to dashboard_path
  end
end
```

### Background Jobs / Models

**Yes! You can track from anywhere if you have user_id:**

```ruby
class Subscription < ApplicationRecord
  after_create :track_conversion

  private

  def track_conversion
    Multibuzz.track(
      user_id: user_id,
      event: 'Subscription Created',
      properties: {
        plan: plan,
        amount: amount_cents
      }
    )
  end
end

class InvoiceGenerationJob < ApplicationJob
  def perform(user_id)
    # ... generate invoice

    Multibuzz.track(
      user_id: user_id,
      event: 'Invoice Generated'
    )
  end
end
```

**How attribution works without request context:**
- User signs up → identified with `user_id: 123`
- Later: background job tracks event with `user_id: 123`
- Multibuzz backend looks up visitor/session by user_id
- Attribution maintained across request boundaries

---

## API Reference

### `Multibuzz.track`

Tracks an event.

```ruby
Multibuzz.track(
  user_id: String|Integer,        # Required (or anonymous_id)
  anonymous_id: String,           # Required (or user_id)
  event: String,                  # Required
  properties: Hash,               # Optional
  timestamp: Time                 # Optional (defaults to now)
)
```

**Parameters:**
- `user_id`: Your database user ID
- `anonymous_id`: Visitor ID (from cookies) for pre-signup tracking
- `event`: Event name (e.g., "Signup", "Purchase")
- `properties`: Event metadata (plan, amount, funnel, etc.)
- `timestamp`: When event occurred (defaults to `Time.current`)

**Returns:** `true` on success, `false` on failure (never raises)

### `Multibuzz.identify`

Identifies a user and their traits.

```ruby
Multibuzz.identify(
  user_id: String|Integer,        # Required
  traits: Hash,                   # Optional
  timestamp: Time                 # Optional
)
```

**Parameters:**
- `user_id`: Your database user ID
- `traits`: User attributes (email, name, plan, etc.)
- `timestamp`: When identification occurred

**When to call:**
- On signup (associate user_id with visitor)
- When user traits change (upgrade plan, change email)
- On login (optional - refresh traits)

**Returns:** `true` on success, `false` on failure

### `Multibuzz.alias`

Links anonymous visitor to user_id on signup.

```ruby
Multibuzz.alias(
  user_id: String|Integer,        # Required (new ID)
  previous_id: String             # Required (old anonymous_id)
)
```

**Use case:** User browses anonymously → signs up → you want to connect pre-signup events to their account.

### Helper: `multibuzz_visitor_id`

Available in controllers. Returns visitor ID from cookies (or creates one).

```ruby
# In controller
def show
  visitor_id = multibuzz_visitor_id  # Reads from cookies

  Multibuzz.track(
    anonymous_id: visitor_id,
    event: 'Page View'
  )
end
```

---

## How It Works

### With Request Context (Controllers)

```ruby
class SignupsController < ApplicationController
  def create
    @user = User.create!(params)

    Multibuzz.track(
      user_id: @user.id,
      event: 'Signup'
    )
  end
end
```

**Behind the scenes:**
1. Gem reads `request.original_url` (captures UTM params)
2. Gem reads `request.referrer`
3. Gem reads cookies for visitor/session tracking
4. Sends all to Multibuzz API
5. API returns Set-Cookie headers
6. Gem forwards cookies to response

### Without Request Context (Background Jobs)

```ruby
class SubscriptionJob < ApplicationJob
  def perform(user_id)
    Multibuzz.track(
      user_id: user_id,
      event: 'Trial Expired'
    )
  end
end
```

**Behind the scenes:**
1. No URL/referrer (okay - not needed for this event)
2. Multibuzz backend looks up visitor/session by user_id
3. Attribution maintained via user_id linkage

---

## Architecture

### Gem Structure

```
multibuzz/
├── lib/
│   ├── multibuzz.rb                    # Main module
│   ├── multibuzz/
│   │   ├── configuration.rb
│   │   ├── client.rb                   # Main API (track, identify, alias)
│   │   ├── request_context.rb          # Captures request data
│   │   ├── api.rb                      # HTTP client
│   │   ├── controller_helpers.rb       # multibuzz_visitor_id
│   │   ├── railtie.rb
│   │   └── version.rb
```

### Implementation

#### Main Module

```ruby
module Multibuzz
  def self.track(user_id: nil, anonymous_id: nil, event:, properties: {}, timestamp: nil)
    Client.track(
      user_id: user_id,
      anonymous_id: anonymous_id,
      event: event,
      properties: properties,
      timestamp: timestamp
    )
  end

  def self.identify(user_id:, traits: {}, timestamp: nil)
    Client.identify(
      user_id: user_id,
      traits: traits,
      timestamp: timestamp
    )
  end

  def self.alias(user_id:, previous_id:)
    Client.alias(user_id: user_id, previous_id: previous_id)
  end
end
```

#### Client

```ruby
module Multibuzz
  class Client
    def self.track(user_id:, anonymous_id:, event:, properties:, timestamp:)
      # Build event payload
      payload = {
        user_id: user_id,
        anonymous_id: anonymous_id,
        event: event,
        properties: properties,
        timestamp: timestamp || Time.current.utc.iso8601
      }.compact

      # Add request context if available (URL, referrer, cookies)
      if context = RequestContext.current
        payload[:url] = context.url
        payload[:referrer] = context.referrer
        payload[:context] = context.to_h
      end

      # Send to API
      Api.post('/events', events: [payload])
    end

    def self.identify(user_id:, traits:, timestamp:)
      payload = {
        user_id: user_id,
        traits: traits,
        timestamp: timestamp || Time.current.utc.iso8601
      }.compact

      Api.post('/identify', payload)
    end

    def self.alias(user_id:, previous_id:)
      Api.post('/alias', user_id: user_id, previous_id: previous_id)
    end
  end
end
```

#### Request Context (Thread-Safe)

```ruby
module Multibuzz
  class RequestContext
    def self.with_context(request:, response:)
      Thread.current[:multibuzz_request] = request
      Thread.current[:multibuzz_response] = response
      yield
    ensure
      Thread.current[:multibuzz_request] = nil
      Thread.current[:multibuzz_response] = nil
    end

    def self.current
      return nil unless Thread.current[:multibuzz_request]

      new(
        Thread.current[:multibuzz_request],
        Thread.current[:multibuzz_response]
      )
    end

    def initialize(request, response)
      @request = request
      @response = response
    end

    def url
      @request.original_url
    end

    def referrer
      @request.referrer
    end

    def cookies
      {
        '_multibuzz_vid' => @request.cookies['_multibuzz_vid'],
        '_multibuzz_sid' => @request.cookies['_multibuzz_sid']
      }.compact
    end

    def to_h
      {
        url: url,
        referrer: referrer,
        cookies: cookies
      }
    end
  end
end
```

#### Controller Middleware

```ruby
module Multibuzz
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      request = ActionDispatch::Request.new(env)

      # Capture request context in thread-local
      response = nil

      RequestContext.with_context(request: request, response: response) do
        status, headers, body = @app.call(env)

        # Store response for cookie forwarding
        response = ActionDispatch::Response.new(status, headers, body)

        [status, headers, body]
      end
    end
  end
end
```

#### Controller Helper

```ruby
module Multibuzz
  module ControllerHelpers
    def multibuzz_visitor_id
      cookies[:_multibuzz_vid] ||= SecureRandom.hex(32)
      cookies[:_multibuzz_vid]
    end
  end
end
```

---

## Configuration

```ruby
module Multibuzz
  class Configuration
    attr_accessor :api_key, :api_url, :timeout

    def initialize
      @api_url = 'https://multibuzz.io/api/v1'
      @timeout = 5
    end
  end

  def self.configure
    yield(config)
  end

  def self.config
    @config ||= Configuration.new
  end
end
```

---

## Error Handling

Silent failures - never raise errors:

```ruby
def self.track(...)
  # ... build payload
  Api.post('/events', payload)
rescue => e
  Rails.logger.error("[Multibuzz] #{e.message}")
  false
end
```

---

## Comparison to Segment

| Feature | Segment | Multibuzz |
|---------|---------|-----------|
| API Style | `Analytics.track(user_id:, event:)` | `Multibuzz.track(user_id:, event:)` ✅ Same |
| Identify | `Analytics.identify(user_id:, traits:)` | `Multibuzz.identify(user_id:, traits:)` ✅ Same |
| Alias | `Analytics.alias(user_id:, previous_id:)` | `Multibuzz.alias(user_id:, previous_id:)` ✅ Same |
| Dependencies | Many | Zero ✅ |
| Focus | Multi-destination | Single destination (Multibuzz) |
| Server-Side | ✅ | ✅ |

**Multibuzz advantage**: Simpler (no batching, queuing complexity), zero dependencies, focused on attribution.

---

## README Example

```markdown
# Multibuzz

Multi-channel attribution tracking for Rails.

## Installation

```ruby
gem 'multibuzz'
```

## Setup

```ruby
# config/initializers/multibuzz.rb
Multibuzz.configure do |config|
  config.api_key = ENV['MULTIBUZZ_API_KEY']
end
```

## Usage

### Track Events

```ruby
Multibuzz.track(
  user_id: current_user.id,
  event: 'Signup',
  properties: { plan: 'pro' }
)
```

### Identify Users

```ruby
Multibuzz.identify(
  user_id: current_user.id,
  traits: {
    email: current_user.email,
    name: current_user.name
  }
)
```

### Anonymous Tracking (Before Signup)

```ruby
Multibuzz.track(
  anonymous_id: multibuzz_visitor_id,
  event: 'Landing Page View'
)

# On signup, link anonymous visitor to user
Multibuzz.alias(
  user_id: @user.id,
  previous_id: multibuzz_visitor_id
)
```

### Background Jobs

```ruby
class SubscriptionJob < ApplicationJob
  def perform(user_id)
    Multibuzz.track(
      user_id: user_id,
      event: 'Trial Expired'
    )
  end
end
```

Works anywhere you have a user_id!
```

---

## Success Criteria

- [x] Segment-style API (`track`, `identify`, `alias`)
- [x] Works with `user_id` from anywhere (controllers, jobs, models)
- [x] Works with `anonymous_id` for pre-signup tracking
- [x] Automatically captures URL/referrer in controllers
- [x] Thread-safe request context
- [x] Zero dependencies
- [x] Silent error handling

---

## Open Questions

1. **Should we auto-install middleware?** Or require manual setup?
   - Auto: Simpler for users
   - Manual: More explicit

2. **Batching?** Segment batches events for performance
   - Pro: Better performance
   - Con: More complexity
   - **Decision**: Skip for v1.0, add later if needed

3. **Async?** Segment uses background threads
   - Pro: Non-blocking
   - Con: Need thread pool
   - **Decision**: Synchronous for v1.0 (simple)

---

## Implementation Timeline

- **Day 1**: Core (config, client, API)
- **Day 2**: Rails integration (middleware, helpers, context)
- **Day 3**: Testing, docs, example app

**Total**: 3 days
