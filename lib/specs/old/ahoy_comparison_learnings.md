# Ahoy Gem Comparison & Learnings

**Date**: 2025-12-13
**Status**: Research Complete - Pending Review

---

## Overview

Detailed comparison of the [Ahoy](https://github.com/ankane/ahoy) analytics gem against Multibuzz to identify patterns, features, and improvements we can adopt.

---

## Architecture Comparison

| Aspect | Ahoy | Multibuzz |
|--------|------|-----------|
| **Deployment** | Embedded Rails gem | SaaS API + SDK |
| **Data Model** | Visit → Events | Visitor → Session → Events → Conversions |
| **Multi-tenancy** | No (single app) | Yes (account-scoped) |
| **Data Storage** | App's database | Separate TimescaleDB |
| **Attribution** | First-visit only (implicit) | Session-based multi-touch (6 models) |
| **Channel Classification** | Basic referrer regex patterns | Database-backed (Matomo/Snowplow sync) |
| **Revenue Tracking** | No | Yes (Conversion model) |
| **Identity Resolution** | User linking only | Cross-device re-attribution |

---

## What Multibuzz Does Better

### 1. Session-Based Multi-Touch Attribution

Multibuzz correctly separates sessions from visitors, capturing fresh UTM data per session:

```ruby
# Multibuzz: Each session captures its own attribution data
session.update(
  initial_utm: utm_data,
  initial_referrer: referrer,
  channel: channel
)
```

Ahoy only captures UTM on the first visit - subsequent sessions don't update attribution context.

### 2. Sophisticated Channel Classification

Multibuzz has a database-backed referrer system (`ReferrerSources::LookupService`) that syncs nightly from Matomo and Snowplow, providing accurate classification for 500+ search engines and 120+ social networks.

Ahoy uses basic regex patterns that miss edge cases.

### 3. Six Attribution Models

Multibuzz implements complete attribution algorithms:
- First Touch
- Last Touch
- Linear
- Time Decay (configurable half-life)
- U-Shaped (40/40/20)
- Participation

Ahoy has no attribution - it's pure event logging.

### 4. Conversion Tracking with Revenue

Dedicated `Conversion` model with revenue attribution credits:

```ruby
# Attribution credit per touchpoint
{
  channel: "paid_search",
  credit: 0.33,
  revenue_credit: 32.99
}
```

### 5. Identity-Based Cross-Device Attribution

When linking a visitor to an existing identity, Multibuzz automatically queues re-attribution jobs:

```ruby
# Conversions::ReattributionJob recalculates attribution
# when new visitor data becomes available
```

### 6. Acquisition Inheritance

Novel pattern for subscription businesses:

```ruby
POST /api/v1/conversions
{
  "inherit_acquisition": true  # Copy attribution from original signup
}
```

All MRR from renewals attributed to original acquisition channel.

---

## What Multibuzz Can Learn from Ahoy

### 1. Visitable Pattern (High Priority)

Ahoy's `visitable` macro auto-populates visit associations on any model:

```ruby
# Ahoy pattern
class Order < ApplicationRecord
  visitable :ahoy_visit
end

# Auto-populated on create
order = Order.create!(...)
order.ahoy_visit  # => Current visit

# Enables powerful queries
Order.joins(:ahoy_visit).group("referring_domain").count
Order.joins(:ahoy_visit).where("visits.channel = ?", "paid_search").sum(:total)
```

**Recommendation**: Add `sessionable` or `attributable` macro to mbuzz gem:

```ruby
# Proposed Multibuzz pattern
class Subscription < ApplicationRecord
  include Mbuzz::Sessionable
end

# Usage in customer app
Subscription.joins(:mbuzz_session).group(:channel).count
```

**Implementation Location**: `lib/mbuzz/sessionable.rb` in mbuzz gem

```ruby
module Mbuzz::Sessionable
  extend ActiveSupport::Concern

  included do
    belongs_to :mbuzz_session,
               class_name: "Mbuzz::Session",
               optional: true,
               foreign_key: :mbuzz_session_id

    before_create :set_mbuzz_session
  end

  private

  def set_mbuzz_session
    self.mbuzz_session ||= Mbuzz.current_session
  end
end
```

### 2. Thread-Local Tracker Access (Medium Priority)

Ahoy provides simple access via `ahoy.track(...)` anywhere:

```ruby
# Ahoy - simple access from anywhere
ahoy.track "Viewed product", product_id: product.id

# Behind the scenes
Thread.current[:ahoy] ||= Ahoy::Tracker.new(controller: self)
```

**Current Multibuzz approach** requires explicit service instantiation:

```ruby
# Current (verbose)
Events::IngestionService.new(account).call(events_data)
```

**Recommendation**: Add simpler interface to mbuzz gem:

```ruby
# Proposed (simpler)
Mbuzz.track("add_to_cart", product_id: 123, price: 49.99)
Mbuzz.conversion("purchase", revenue: 99.99)
Mbuzz.identify("user_123", email: "user@example.com")
```

### 3. JavaScript Auto-Tracking (Medium Priority)

Ahoy.js provides declarative tracking:

```javascript
// Ahoy auto-tracking
ahoy.trackClicks("a, button, input[type=submit]");
ahoy.trackSubmits("form");

// Automatically extracts context
{
  tag: "a",
  id: "signup-cta",
  text: "Sign Up Now",
  href: "/signup",
  section: "hero"  // from data-section attribute
}
```

**Recommendation**: Add similar declarative tracking to mbuzz.js SDK:

```javascript
mbuzz.configure({
  autoTrackClicks: "a[data-mbuzz-track], button[data-mbuzz-track]",
  autoTrackForms: "form[data-mbuzz-track]",
  capturePageView: true
});

// Or declarative
mbuzz.trackClicks("[data-track]");
mbuzz.trackSubmits("form.tracked");
```

### 4. IP Masking (High Priority)

Ahoy masks the last octet of IPv4 addresses for GDPR compliance:

```ruby
# Ahoy IP masking
Ahoy.mask_ips = true
# 192.168.1.123 → 192.168.1.0 (IPv4)
# Masks last 80 bits for IPv6
```

**Current State**: Multibuzz enrichment already masks to /24:

```ruby
# Events::EnrichmentService
"ip_address": "192.168.1.0"  # masked to /24
```

**Recommendation**: Make this configurable and document it:

```ruby
Mbuzz.configure do |config|
  config.mask_ips = true  # default: true
  config.ip_mask_level = :subnet  # :full, :subnet, :none
end
```

### 5. Bot Filtering (High Priority)

Ahoy filters bots by default:

```ruby
# Ahoy bot filtering
Ahoy.track_bots = false  # default

# Uses device_detector gem for bot detection
# Bot detection version configurable
Ahoy.bot_detection_version = 2
```

**Recommendation**: Add bot filtering to event ingestion:

```ruby
# In Events::ValidationService or EnrichmentService
return if bot_request? && !Mbuzz.track_bots

def bot_request?
  DeviceDetector.new(user_agent).bot?
end
```

### 6. Custom Exclusions (Medium Priority)

Ahoy supports custom tracking exclusions:

```ruby
# Ahoy exclusion method
Ahoy.exclude_method = :exclude_ahoy?

# In ApplicationController
def exclude_ahoy?
  request.user_agent&.include?("Googlebot") ||
    request.path.start_with?("/admin") ||
    current_user&.staff?
end
```

**Recommendation**: Add configurable exclusion to mbuzz gem:

```ruby
Mbuzz.configure do |config|
  config.exclude_method = :exclude_from_tracking?
end

# In customer app
def exclude_from_tracking?
  request.path.start_with?("/health") ||
    current_user&.internal?
end
```

### 7. Token Generation Options (Low Priority)

Ahoy supports custom token generators including ULIDs:

```ruby
# Ahoy token customization
Ahoy.token_generator = -> { ULID.generate }

# Or prefixed tokens
Ahoy.token_generator = -> { "vis_#{SecureRandom.hex(16)}" }
```

**Current State**: Multibuzz uses 64-char hex strings.

**Recommendation**: Consider ULID option for time-sortable tokens:

```ruby
Mbuzz.configure do |config|
  config.token_format = :ulid  # or :hex (default)
end
```

### 8. Geocoding Infrastructure (Low Priority)

Ahoy has built-in geocoding support with background job:

```ruby
# Ahoy geocoding
Ahoy.geocode = true
Ahoy.job_queue = :low_priority

# Uses MaxMind GeoLite2 or external services
# Enriches: country, region, city, latitude, longitude
```

**Recommendation**: Consider adding optional geocoding for location-based attribution:

```ruby
# Background job enrichment
class Events::GeocodingJob < ApplicationJob
  def perform(event_id)
    event = Event.find(event_id)
    geo_data = Geocoder.search(event.ip_address).first

    event.update(
      properties: event.properties.merge(
        country: geo_data.country,
        region: geo_data.region,
        city: geo_data.city
      )
    )
  end
end
```

### 9. Cookie-Free GDPR Mode (Low Priority)

Ahoy supports tracking without cookies for strict GDPR compliance:

```ruby
# Ahoy cookie-free mode
Ahoy.cookies = false

# Uses IP+UA hash for anonymous tracking
# Generates deterministic UUID v5 from IP + User-Agent
```

**Recommendation**: Document or add cookie-free mode option:

```ruby
Mbuzz.configure do |config|
  config.cookies = false  # Uses IP+UA hash
  config.gdpr_mode = :strict  # or :standard
end
```

### 10. Store Abstraction Pattern (Low Priority)

Ahoy's pluggable data store is elegant for extensibility:

```ruby
# Ahoy store abstraction
class Ahoy::DatabaseStore
  def track_visit(data)
    # Persist visit
  end

  def track_event(data)
    # Persist event
  end
end

# Custom store for alternative backends
class KafkaStore < Ahoy::BaseStore
  def track_event(data)
    Kafka.publish("events", data)
  end
end
```

**Recommendation**: Consider for future if we need multiple backends (e.g., Kafka, ClickHouse).

### 11. Duplicate Handling

Ahoy gracefully handles duplicate token collisions:

```ruby
def track_visit(data)
  @visit = visit_model.new(slice_data(visit_model, data))
  @visit.save!
rescue *unique_violation_classes
  @visit = nil  # Clear to force re-fetch
end
```

**Current State**: Multibuzz uses unique constraints but may not handle collisions as gracefully.

**Recommendation**: Add explicit duplicate handling in ingestion:

```ruby
def create_event
  event.save!
rescue ActiveRecord::RecordNotUnique
  # Re-fetch existing event by visitor_id + timestamp + event_type
  find_existing_event
end
```

### 12. SPA/History API Integration

Ahoy.js hooks into browser navigation:

```javascript
// Turbo integration
document.addEventListener("turbo:load", function() {
  ahoy.trackView();
});

// React Router / Vue Router integration
router.afterEach((to, from) => {
  ahoy.trackView();
});
```

**Recommendation**: Document SPA integration patterns in mbuzz.js SDK docs:

```javascript
// mbuzz.js SPA support
import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';

function usePageTracking() {
  const location = useLocation();

  useEffect(() => {
    mbuzz.pageView();
  }, [location.pathname]);
}
```

---

## Documentation Patterns from Ahoy

Ahoy's README has excellent patterns Multibuzz docs could adopt:

1. **Quick Start** - 5 lines to get started
2. **Associated Models** - Clear `visitable` pattern examples
3. **Configuration Reference** - Table of all options with defaults
4. **Privacy Section** - GDPR compliance guide
5. **Upgrade Guide** - Breaking changes by version
6. **Data Exploration** - Query examples for common analytics tasks

---

## Implementation Priority

| Priority | Feature | Effort | Value | Files to Modify |
|----------|---------|--------|-------|-----------------|
| **High** | `sessionable` macro | Medium | High | mbuzz gem |
| **High** | IP masking config | Low | Medium | `Events::EnrichmentService` |
| **High** | Bot filtering | Low | Medium | `Events::ValidationService` |
| **Medium** | JS auto-click tracking | Medium | Medium | mbuzz.js SDK |
| **Medium** | Simpler API interface | Medium | Medium | mbuzz gem |
| **Medium** | Custom exclusions | Low | Medium | mbuzz gem middleware |
| **Low** | ULID token option | Low | Low | SDK configuration |
| **Low** | Geocoding enrichment | High | Medium | New job + service |
| **Low** | Cookie-free GDPR mode | Medium | Low | SDK + API |
| **Low** | Store abstraction | High | Low | Future consideration |

---

## Conclusion

**Multibuzz is architecturally superior for attribution** - it has session-based multi-touch attribution, conversion tracking, cross-device identity resolution, and sophisticated channel classification that Ahoy lacks entirely.

**However, Ahoy excels at developer experience** - its Rails integration patterns (`visitable`, thread-local tracker, declarative JS tracking) and privacy features are worth adopting.

### Top 3 Actionable Improvements

1. **Add `sessionable` macro** - Let customer apps associate orders/subscriptions with sessions for attribution queries
2. **Add privacy controls** - IP masking configuration and bot filtering
3. **Enhance JavaScript SDK** - Auto-tracking for clicks/forms like ahoy.js

---

## References

- [Ahoy GitHub](https://github.com/ankane/ahoy)
- [Ahoy.js GitHub](https://github.com/ankane/ahoy.js)
- Multibuzz SDK Specification: `lib/docs/sdk/sdk_specification.md`
- Attribution Methodology: `lib/docs/architecture/attribution_methodology.md`
- Server-Side Architecture: `lib/docs/architecture/server_side_attribution_architecture.md`
