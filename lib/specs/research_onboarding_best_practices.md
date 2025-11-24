# Multibuzz Analytics Tracking: Architecture Review & Best Practices Research

**Date**: 2025-11-14
**Status**: Phase 1 MVP Complete - Architecture Analysis for Future Rails Gem/Client Libraries

---

## Executive Summary

This document analyzes the current Multibuzz REST API implementation against industry best practices for server-side analytics tracking systems. Based on deep research into how systems like Segment, Mixpanel, Google Analytics, and other enterprise analytics platforms handle visitor/session tracking, this document identifies critical architectural improvements needed for the upcoming Rails gem and client library implementations.

**Key Findings**:
1. ❌ **Current approach requires client-side visitor/session ID generation** - brittle and insecure
2. ❌ **UTM parameters manually extracted client-side** - fragile and error-prone
3. ✅ **Server should extract all tracking data from HTTP request** - industry standard
4. ⚠️ **PII/sensitive data filtering is missing** - compliance risk

---

## 1. Current Implementation Analysis

### 1.1 How Visitor/Session Tracking Works Today

**Current API Contract** (from specs):
```json
POST /api/v1/events
{
  "events": [{
    "event_type": "page_view",
    "visitor_id": "abc123...",      // ❌ CLIENT must generate
    "session_id": "xyz789...",      // ❌ CLIENT must generate
    "timestamp": "2025-11-06T10:30:45Z",
    "properties": {
      "url": "https://example.com/page",
      "utm_source": "google",       // ❌ CLIENT must extract
      "utm_medium": "cpc",          // ❌ CLIENT must extract
      "utm_campaign": "spring_sale" // ❌ CLIENT must extract
    }
  }]
}
```

**Problems**:
1. **Client-side ID management is brittle**
   - Each client library (Rails gem, Django package, Laravel, etc.) must implement cookie/session logic
   - Inconsistent implementations across frameworks lead to data quality issues
   - Client can send any visitor_id/session_id, making deduplication hard

2. **Manual UTM extraction is error-prone**
   - Client must parse URL query strings
   - Developers must remember to pass ALL UTM parameters
   - Missing parameters = lost attribution data
   - No validation of UTM format

3. **No request metadata captured**
   - IP address, User-Agent, Referrer ignored
   - Can't detect bots, scrapers, or fraud
   - Can't enrich events with device/browser data
   - Can't perform server-side attribution validation

---

## 2. Industry Best Practices Research

### 2.1 How Modern Analytics Systems Handle Visitor/Session Tracking

Based on research of Segment, Mixpanel, Google Analytics (GA4), Amplitude, and Plausible:

#### **Pattern 1: Server-Side Cookie Management**

**Mixpanel Server-Side Best Practices** ([source](https://docs.mixpanel.com/docs/tracking-best-practices/server-side-best-practices)):
> "For logged-in users, send their userId in events to ensure events are attributed to the correct user. To tie anonymous events from devices with server-side events, extract the cookie value from the client and pass it to your server."

**Bloomreach Server-Side Identity Management** ([source](https://documentation.bloomreach.com/engagement/docs/1st-party-cookie-tracking-solutions)):
> "Advanced systems employ a 1-year server-set cookie to identify returning users, ensuring uninterrupted tracking and better identification accuracy. A unique identifier is generated and stored on a server when a user interacts with an ad or webpage."

**Key Insight**: The SERVER should:
- Set and manage visitor/session cookies via `Set-Cookie` headers
- Read cookies from incoming requests automatically
- Generate IDs server-side for security and consistency
- Handle cookie expiration, renewal, and migration

#### **Pattern 2: Server-Side UTM Extraction**

**Stack Overflow - Server-Side UTM Tracking** ([source](https://webmasters.stackexchange.com/questions/81198/store-utm-values-on-my-server)):
> "UTM values are in the query string. You can extract those URL parameters using server-side code - for example, in PHP, you can inspect the values using `$_GET['utm_source']`."

**Stape UTM Transformation** ([source](https://community.stape.io/t/utm-parameters-and-serverside-tracking/839)):
> "Most analytics platforms focus only on UTM parameters, but with server-side tracking, you can transform custom parameters back to UTMs. This allows your analytics platform to get correct UTM parameters for accurate attribution."

**Key Insight**: The CLIENT should:
- Send the full page URL (with query string intact)
- Send the referrer URL
- NOT extract or parse UTM parameters themselves
- Let the server handle ALL URL parsing and parameter extraction

#### **Pattern 3: Rich Request Metadata Collection**

**Google Analytics Cookie Data** ([source](https://stackoverflow.com/questions/892049/how-does-google-analytics-collect-its-data)):
> "Most browsers send data such as OS, platform, browser, version, and locale in HTTP headers. HTTP requests send data about IP address, referrer, browser, language, and system."

**What to Collect** ([source](https://medium.com/analytics-and-data/cookies-tracking-and-pixels-where-does-your-web-data-comes-from-ff5d9b8bc8f7)):
> - IP address and the referer field of the HTTP request header
> - User-agent information to identify browser type and version
> - Language preferences
> - Session parameters and personalization parameters
> - Which pages users visit, how long they stay on a page

**Key Insight**: The SERVER should automatically extract from `Rack::Request`:
- `request.ip` - IP address (with proxy handling)
- `request.user_agent` - Browser, OS, device info
- `request.referrer` - Traffic source
- `request.url` - Full URL with query params
- `request.path` - Path component
- `request.headers['Accept-Language']` - User language
- `request.cookies` - Existing tracking cookies

---

### 2.2 Sensitive Data Filtering - Critical Security Requirement

**Google Analytics PII Policy** ([source](https://support.google.com/analytics/answer/6366371)):
> "Google policies mandate that no data be passed to Google that could be recognized as personally identifiable information (PII), which includes email addresses, personal mobile numbers, and social security numbers. Google cannot collect financial information, which includes billing information, credit card details, location, purchase amount, and more."

**Common PII Leakage Vectors** ([source](https://www.wpbeginner.com/wp-tutorials/how-to-keep-personally-identifiable-info-out-of-google-analytics/)):
> "The basic Analytics page tag collects the page URL and page title, and PII is often inadvertently sent in these URLs and titles. Website visitors sometimes enter PII into search boxes and form fields, so be sure to remove PII from user-entered information before it is sent to Analytics."

**URL Parameter Filtering** ([source](https://blog.logrocket.com/how-to-handle-pii-websites-web-apps/)):
> "Common query parameters that often contain sensitive information include email, credit_card, and password. Submit data as a payload in the body of the request instead of in the request URL, as this is a general privacy/security best practice."

**MUST FILTER** (before storing):
- Passwords: `password`, `pwd`, `pass`, `passwd`
- Credit cards: `cc`, `credit_card`, `card_number`, `cvv`
- Personal info: `email`, `ssn`, `phone`, `dob`, `address`
- Tokens: `token`, `api_key`, `secret`, `auth`
- Session IDs in URLs (only in cookies!)

---

## 3. Recommended Architecture Changes

### 3.1 Visitor/Session ID Management: Move to Server-Side

#### ❌ **Current (Client-Generated IDs)**

**Client code** (future Rails gem):
```ruby
# Client must implement this in EVERY framework:
class Multibuzz::Visitor::Identifier
  def self.identify(request, response)
    visitor_id = request.cookies["multibuzz_visitor_id"]
    visitor_id ||= SecureRandom.hex(32)

    response.set_cookie("multibuzz_visitor_id",
      value: visitor_id,
      expires: 1.year.from_now,
      httponly: true,
      secure: true
    )

    visitor_id
  end
end
```

**Problems**:
- Must implement in Rails gem, Django package, Laravel package, etc.
- Cookie security varies by implementation
- Client can manipulate IDs
- Hard to ensure consistency

#### ✅ **Recommended (Server-Managed IDs)**

**New API Contract**:
```json
POST /api/v1/events
{
  "events": [{
    "event_type": "page_view",
    // NO visitor_id field - server extracts from Cookie header
    // NO session_id field - server generates/manages
    "timestamp": "2025-11-06T10:30:45Z",
    "url": "https://example.com/page?utm_source=google&utm_medium=cpc",
    "referrer": "https://google.com/search?q=shoes"
  }]
}

// Server response includes Set-Cookie headers:
Set-Cookie: _multibuzz_vid=abc123...; Expires=...; HttpOnly; Secure; SameSite=Lax
Set-Cookie: _multibuzz_sid=xyz789...; Max-Age=1800; HttpOnly; Secure; SameSite=Lax
```

**Benefits**:
- Clients just forward cookies, don't generate IDs
- Server has single source of truth for ID generation
- Consistent security across all client libraries
- Server can rotate/invalidate IDs centrally

**Implementation**:
```ruby
# app/services/visitors/identification_service.rb
module Visitors
  class IdentificationService
    COOKIE_NAME = "_multibuzz_vid"
    COOKIE_EXPIRY = 1.year

    def initialize(request, account)
      @request = request
      @account = account
    end

    def call
      visitor_id = extract_visitor_id || generate_visitor_id
      cookie_value = build_cookie_value(visitor_id)

      { visitor_id: visitor_id, set_cookie: cookie_value }
    end

    private

    attr_reader :request, :account

    def extract_visitor_id
      # Read from Cookie header
      request.cookies[COOKIE_NAME]
    end

    def generate_visitor_id
      # Server-side generation with account prefix
      "#{account.prefix_id}_#{SecureRandom.hex(32)}"
    end

    def build_cookie_value
      {
        value: visitor_id,
        expires: COOKIE_EXPIRY.from_now,
        httponly: true,
        secure: Rails.env.production?,
        same_site: :lax,
        domain: account.cookie_domain # Multi-domain support
      }
    end
  end
end

# app/services/sessions/identification_service.rb
module Sessions
  class IdentificationService
    COOKIE_NAME = "_multibuzz_sid"
    SESSION_TIMEOUT = 30.minutes

    def initialize(request, account, visitor_id)
      @request = request
      @account = account
      @visitor_id = visitor_id
    end

    def call
      session_id = extract_session_id || generate_session_id
      cookie_value = build_cookie_value(session_id)

      { session_id: session_id, set_cookie: cookie_value }
    end

    private

    # Similar to visitor identification
    # Session cookie expires after 30 minutes of inactivity
  end
end
```

---

### 3.2 UTM Extraction: Move to Server-Side URL Parsing

#### ❌ **Current (Client Extracts UTMs)**

Client must parse URL:
```ruby
# Client gem code (brittle!)
url = "https://example.com/page?utm_source=google&utm_medium=cpc&ref=blog"
uri = URI.parse(url)
utm_params = CGI.parse(uri.query).slice("utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term")

# Then send to API
Multibuzz.track("page_view", properties: utm_params.merge(url: url))
```

**Problems**:
- Developer must remember to extract UTMs
- Easy to miss parameters
- URL parsing bugs in client libraries
- No validation of UTM format

#### ✅ **Recommended (Server Extracts Everything)**

**New event payload**:
```json
{
  "event_type": "page_view",
  "url": "https://example.com/page?utm_source=google&utm_medium=cpc&foo=bar",
  "referrer": "https://google.com/search"
}
```

**Server extracts UTMs automatically**:
```ruby
# app/services/sessions/utm_capture_service.rb
module Sessions
  class UtmCaptureService
    UTM_PARAMS = %w[utm_source utm_medium utm_campaign utm_content utm_term].freeze

    def initialize
      # No dependencies
    end

    def call(url)
      return {} if url.blank?

      uri = URI.parse(url)
      query_params = CGI.parse(uri.query || "")

      UTM_PARAMS.each_with_object({}) do |param, result|
        value = query_params[param]&.first
        result[param.to_sym] = value if value.present?
      end
    rescue URI::InvalidURIError
      {} # Return empty if URL is malformed
    end
  end
end
```

**Benefits**:
- Clients send raw URL, server does ALL parsing
- Consistent extraction logic in one place
- Easy to add new parameters (e.g., `fbclid`, `gclid`)
- Can validate and sanitize URLs server-side

---

### 3.3 Request Metadata Enrichment

**Server should automatically capture**:
```ruby
# app/services/events/enrichment_service.rb
module Events
  class EnrichmentService
    def initialize(request)
      @request = request
    end

    def call(event_data)
      event_data.merge(
        request_metadata: build_metadata
      )
    end

    private

    attr_reader :request

    def build_metadata
      {
        ip_address: anonymize_ip(request.ip),
        user_agent: request.user_agent,
        referrer: request.referrer,
        language: request.headers["Accept-Language"],
        device_info: parse_user_agent(request.user_agent),
        geo: geolocate_ip(request.ip) # Optional: Use MaxMind GeoIP
      }
    end

    def anonymize_ip(ip)
      # GDPR compliance: Mask last octet
      # 192.168.1.100 -> 192.168.1.0
      IPAddr.new(ip).mask(24).to_s
    end

    def parse_user_agent(ua)
      # Use gem like `device_detector` or `browser`
      detector = DeviceDetector.new(ua)
      {
        browser: detector.name,
        browser_version: detector.full_version,
        os: detector.os_name,
        device_type: detector.device_type # desktop, mobile, tablet, bot
      }
    end

    def geolocate_ip(ip)
      # Optional: MaxMind GeoIP2 integration
      # Returns country, city, timezone
    end
  end
end
```

**Storage**:
```json
// events.properties
{
  "url": "https://example.com/page?utm_source=google",
  "utm_source": "google",
  "utm_medium": "cpc",
  "request_metadata": {
    "ip_address": "192.168.1.0",
    "user_agent": "Mozilla/5.0...",
    "referrer": "https://google.com",
    "language": "en-US,en;q=0.9",
    "device_info": {
      "browser": "Chrome",
      "browser_version": "119.0",
      "os": "macOS",
      "device_type": "desktop"
    }
  }
}
```

---

### 3.4 PII/Sensitive Data Filtering

**Critical for compliance** (GDPR, CCPA, SOC 2):

```ruby
# app/services/events/sanitization_service.rb
module Events
  class SanitizationService
    SENSITIVE_PARAM_PATTERNS = [
      /password/i,
      /pwd/i,
      /passwd/i,
      /pass/i,
      /cc/i,
      /credit_card/i,
      /card_number/i,
      /cvv/i,
      /ssn/i,
      /social_security/i,
      /email/i,
      /phone/i,
      /address/i,
      /token/i,
      /api_key/i,
      /secret/i,
      /auth/i
    ].freeze

    def initialize
      # No dependencies
    end

    def call(url)
      return url if url.blank?

      uri = URI.parse(url)
      return url unless uri.query

      # Parse and filter query params
      params = CGI.parse(uri.query)
      filtered_params = params.reject { |key, _| sensitive_param?(key) }

      # Rebuild URL with filtered params
      uri.query = URI.encode_www_form(filtered_params.map { |k, v| [k, v.first] })
      uri.to_s
    rescue URI::InvalidURIError
      url # Return original if parsing fails
    end

    private

    def sensitive_param?(key)
      SENSITIVE_PARAM_PATTERNS.any? { |pattern| key.match?(pattern) }
    end
  end
end
```

**Apply to ALL URLs**:
```ruby
# Before storing event
sanitized_url = Events::SanitizationService.new.call(event_data["url"])
sanitized_referrer = Events::SanitizationService.new.call(event_data["referrer"])
```

---

## 4. Proposed New API Design

### 4.1 Simplified Event Payload

**Old (current)**:
```json
{
  "events": [{
    "event_type": "page_view",
    "visitor_id": "abc123",     // ❌ Client-generated
    "session_id": "xyz789",     // ❌ Client-generated
    "timestamp": "2025-11-06T10:30:45Z",
    "properties": {
      "url": "https://example.com/page",
      "utm_source": "google",   // ❌ Client-extracted
      "utm_medium": "cpc"       // ❌ Client-extracted
    }
  }]
}
```

**New (recommended)**:
```json
{
  "events": [{
    "event_type": "page_view",
    "timestamp": "2025-11-06T10:30:45Z",
    "url": "https://example.com/page?utm_source=google&utm_medium=cpc",
    "referrer": "https://google.com/search?q=shoes",
    "properties": {
      "custom_field": "value"  // Only custom app data
    }
  }]
}
```

**Server extracts automatically**:
- `visitor_id` from `Cookie: _multibuzz_vid=...` header
- `session_id` from `Cookie: _multibuzz_sid=...` header
- UTM params from `url` query string
- IP, User-Agent, etc. from request headers

**Server returns**:
```http
HTTP/1.1 202 Accepted
Set-Cookie: _multibuzz_vid=acct_abc_visitor123; Expires=...; HttpOnly; Secure; SameSite=Lax
Set-Cookie: _multibuzz_sid=acct_abc_sess456; Max-Age=1800; HttpOnly; Secure; SameSite=Lax

{
  "accepted": 1,
  "rejected": []
}
```

---

### 4.2 Rails Gem Simplified Implementation

**Before (complex client-side logic)**:
```ruby
# Middleware must do everything
class Multibuzz::Middleware::Tracking
  def call(env)
    request = Rack::Request.new(env)

    # Extract visitor ID
    visitor_id = extract_visitor_id(request)

    # Extract session ID
    session_id = extract_session_id(request)

    # Parse URL for UTMs
    url = request.url
    utm_source = parse_utm(url, "utm_source")
    utm_medium = parse_utm(url, "utm_medium")
    # ... etc

    # Build event
    event = {
      event_type: "page_view",
      visitor_id: visitor_id,
      session_id: session_id,
      properties: {
        url: url,
        utm_source: utm_source,
        utm_medium: utm_medium
        # ... manual extraction
      }
    }

    # Send to API
    Multibuzz::Api::Client.send_events([event])

    @app.call(env)
  end
end
```

**After (simple pass-through)**:
```ruby
# Middleware just forwards data
class Multibuzz::Middleware::Tracking
  def call(env)
    request = Rack::Request.new(env)

    # Build minimal event payload
    event = {
      event_type: "page_view",
      timestamp: Time.now.utc.iso8601,
      url: request.url,
      referrer: request.referrer
    }

    # Forward to API with cookies
    Multibuzz::Api::Client.send_events([event], cookies: request.cookies)

    status, headers, body = @app.call(env)

    # Server returns Set-Cookie headers, propagate to response
    [status, headers, body]
  end
end
```

**Benefits**:
- Client library = 90% less code
- No URL parsing bugs
- No cookie management complexity
- Works identically across ALL frameworks

---

## 5. Migration Path

### Phase 1: Backward-Compatible Server Changes

**Support BOTH old and new formats**:
```ruby
# app/services/events/ingestion_service.rb
module Events
  class IngestionService
    def call(events_data, request: nil)
      events_data.map do |event_data|
        # Legacy format: visitor_id/session_id in payload
        if event_data["visitor_id"].present?
          process_legacy_event(event_data)
        else
          # New format: extract from request
          process_new_event(event_data, request)
        end
      end
    end

    private

    def process_new_event(event_data, request)
      # Extract visitor/session from cookies
      visitor_result = Visitors::IdentificationService.new(request, @account).call
      session_result = Sessions::IdentificationService.new(request, @account, visitor_result[:visitor_id]).call

      # Extract UTMs from URL
      utm_data = Sessions::UtmCaptureService.new.call(event_data["url"])

      # Enrich with request metadata
      enriched_data = Events::EnrichmentService.new(request).call(event_data)

      # Sanitize URLs
      sanitized_data = sanitize_event_data(enriched_data)

      # Process event
      process_event(sanitized_data, visitor_result, session_result)

      # Return Set-Cookie headers for response
      {
        cookies: [visitor_result[:set_cookie], session_result[:set_cookie]]
      }
    end
  end
end
```

### Phase 2: Update Client Libraries

**Rails Gem v2.0**:
- Remove `Visitor::Identifier` (no longer needed)
- Remove UTM extraction logic
- Simplify middleware to just send `url` and `referrer`
- Forward `Set-Cookie` headers from API response

**Django/Laravel packages**:
- Same simplified approach
- Consistent behavior across all frameworks

### Phase 3: Deprecate Old Format

**After 6 months**:
- Log warnings for `visitor_id`/`session_id` in payload
- After 12 months: Reject old format

---

## 6. Security & Compliance Benefits

### 6.1 GDPR Compliance

✅ **IP Anonymization**: Last octet masked before storage
✅ **PII Filtering**: Sensitive params removed from URLs
✅ **Cookie Consent**: Server can check consent before setting cookies
✅ **Right to Erasure**: Central visitor ID management enables deletion

### 6.2 Security Improvements

✅ **No client-side ID manipulation**: Server controls all IDs
✅ **HttpOnly cookies**: XSS protection
✅ **Secure flag**: HTTPS-only transmission
✅ **SameSite=Lax**: CSRF protection
✅ **URL sanitization**: No secrets leaked in query params

### 6.3 Data Quality

✅ **Consistent ID generation**: No framework-specific bugs
✅ **Complete UTM capture**: Server extracts all parameters
✅ **Rich metadata**: User-Agent, referrer, geo always captured
✅ **Bot detection**: Server-side User-Agent parsing

---

## 7. Implementation Checklist

### Backend (Multibuzz SaaS API)

- [ ] Create `Visitors::IdentificationService` (cookie-based)
- [ ] Create `Sessions::IdentificationService` (cookie-based)
- [ ] Update `Sessions::UtmCaptureService` to parse URLs
- [ ] Create `Events::EnrichmentService` (request metadata)
- [ ] Create `Events::SanitizationService` (PII filtering)
- [ ] Update `Events::IngestionService` to accept `request` parameter
- [ ] Add `Set-Cookie` header support in API responses
- [ ] Add IP anonymization
- [ ] Add User-Agent parsing (use `device_detector` gem)
- [ ] Write comprehensive tests for all services

### Frontend (Rails Gem v2.0)

- [ ] Remove `Visitor::Identifier` class
- [ ] Remove UTM extraction logic
- [ ] Update middleware to send only `url`, `referrer`, `timestamp`
- [ ] Add cookie forwarding from request to API call
- [ ] Add `Set-Cookie` header propagation from API response to client response
- [ ] Update documentation
- [ ] Bump to v2.0.0

### Documentation

- [ ] Update API spec (OpenAPI) with new format
- [ ] Write migration guide for existing users
- [ ] Document cookie behavior
- [ ] Document PII filtering
- [ ] Add code examples for new format

### Testing

- [ ] Test cookie creation and renewal
- [ ] Test session timeout and expiration
- [ ] Test UTM extraction from complex URLs
- [ ] Test PII filtering
- [ ] Test IP anonymization
- [ ] Test request metadata enrichment
- [ ] Test backward compatibility

---

## 8. Conclusion & Recommendations

### Critical Changes Required

1. **Move visitor/session ID management to server-side**
   - Current client-generated approach is brittle and inconsistent
   - Server-managed cookies are industry standard
   - Reduces client library complexity by 90%

2. **Move UTM extraction to server-side URL parsing**
   - Clients should send full URL, server extracts UTMs
   - Eliminates client-side parsing bugs
   - Enables consistent extraction logic

3. **Add request metadata enrichment**
   - IP address, User-Agent, Referrer critical for analytics
   - Enable bot detection, device classification, geo-targeting
   - Required for attribution validation

4. **Implement PII/sensitive data filtering**
   - GDPR/CCPA compliance requirement
   - Filter URLs, referrers for passwords, emails, credit cards
   - Prevent accidental data leaks

### Benefits of Recommended Approach

| Aspect | Current (Client-Heavy) | Recommended (Server-Heavy) |
|--------|------------------------|----------------------------|
| **Client code** | ~500 lines | ~50 lines |
| **Framework consistency** | Varies by implementation | Identical across all |
| **UTM accuracy** | Depends on developer | 100% automatic |
| **Security** | Varies | Centrally managed |
| **PII compliance** | Client responsibility | Server enforced |
| **Metadata richness** | Minimal | Comprehensive |

### Next Steps

1. **Prototype server-side identification services** (1-2 days)
2. **Update API to accept `request` object** (1 day)
3. **Test with backward compatibility** (1 day)
4. **Update Rails gem to new format** (2-3 days)
5. **Document and release v2.0** (1 day)

**Total effort**: ~1 week for complete transition

---

## References

- [Mixpanel Server-Side Best Practices](https://docs.mixpanel.com/docs/tracking-best-practices/server-side-best-practices)
- [Bloomreach Server-Side Identity Management](https://documentation.bloomreach.com/engagement/docs/1st-party-cookie-tracking-solutions)
- [Google Analytics PII Policy](https://support.google.com/analytics/answer/6366371)
- [Segment Identity Resolution](https://segment.com/docs/connections/destinations/catalog/adobe-analytics/identity/)
- [Server-Side Tracking Guide 2025](https://www.trackbee.io/blog/the-ultimate-server-side-tracking-guide-in-2025)
- [Rack Middleware Request Handling](https://github.com/rack/rack/blob/main/lib/rack/request.rb)
- [Rails ActionDispatch::RemoteIp](https://api.rubyonrails.org/classes/ActionDispatch/RemoteIp.html)

---

**Document Version**: 1.0
**Last Updated**: 2025-11-14
**Author**: Architecture Review based on Industry Research
