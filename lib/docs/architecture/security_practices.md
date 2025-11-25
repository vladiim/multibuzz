# Security Practices

This document defines the security standards and practices for the Multibuzz codebase. **All code must adhere to these guidelines.**

---

## 1. Multi-Tenancy

### The Golden Rule

**Every database query MUST be scoped to an account.**

```ruby
# ✅ CORRECT - Always scope to account
current_account.events.where(event_type: "page_view")
account.visitors.find_by(visitor_id: params[:visitor_id])
@account.sessions.active.limit(10)

# ❌ WRONG - Never do this
Event.where(event_type: "page_view")
Visitor.find(params[:id])
Session.all
```

### Implementation Pattern

**In Controllers:**
```ruby
class Dashboard::ApiKeysController < ApplicationController
  before_action :require_login

  def index
    @api_keys = current_account.api_keys.order(created_at: :desc)
  end

  def destroy
    # Always scope find to account
    api_key = current_account.api_keys.find(params[:id])
    api_key.revoke!
  end

  private

  def current_account
    @current_account ||= current_user.account
  end
end
```

**In Services:**
```ruby
module Events
  class ProcessingService < ApplicationService
    def initialize(account, params)
      @account = account
      @params = params
    end

    private

    def find_visitor
      # Always scope to account
      account.visitors.find_by(visitor_id: visitor_id)
    end

    def create_event
      # Build through account association
      account.events.build(event_params)
    end
  end
end
```

### Testing Multi-Tenancy

**Always test cross-account isolation:**

```ruby
class ApiKeysControllerTest < ActionDispatch::IntegrationTest
  test "cannot access other account's API keys" do
    other_account_key = accounts(:two).api_keys.create!(...)

    delete dashboard_api_key_path(other_account_key),
           headers: auth_headers_for(users(:one))

    assert_response :not_found
    assert other_account_key.reload.active?
  end

  private

  def auth_headers_for(user)
    # Helper to authenticate as user
  end
end
```

---

## 2. ID Exposure

### Never Expose Raw Database IDs

**Use `prefixed_ids` gem for all customer-facing IDs.**

### Required Prefix IDs

Every model that may be exposed externally MUST have a prefix ID:

| Model | Prefix | Declaration |
|-------|--------|-------------|
| Account | `acct_` | `has_prefix_id :acct` |
| User | `user_` | `has_prefix_id :user` |
| Visitor | `vis_` | `has_prefix_id :vis` |
| Session | `sess_` | `has_prefix_id :sess` |
| Event | `evt_` | `has_prefix_id :evt` |
| Conversion | `conv_` | `has_prefix_id :conv` |
| AttributionModel | `attr_` | `has_prefix_id :attr` |
| AttributionCredit | `cred_` | `has_prefix_id :cred` |
| FormSubmission | `form_` | `has_prefix_id :form` |
| WaitlistSubmission | `wait_` | `has_prefix_id :wait` |

### Implementation

```ruby
# app/models/event.rb
class Event < ApplicationRecord
  has_prefix_id :evt

  # ...
end
```

### API Response Format

```ruby
# ✅ CORRECT - Use prefix_id in responses
render json: {
  id: event.prefix_id,  # => "evt_abc123xyz"
  event_type: event.event_type
}

# ❌ WRONG - Never expose database ID
render json: {
  id: event.id,  # => 12345 (BAD!)
  event_type: event.event_type
}
```

### URL Parameters

Rails will automatically use `prefix_id` when configured. Lookups should use:

```ruby
# In controller
Event.find_by_prefix_id(params[:id])

# Or via account scope
current_account.events.find_by_prefix_id(params[:id])
```

### Exceptions

- **ApiKey**: Uses custom format `sk_{env}_{random32}` - acceptable
- **Internal background job IDs**: Not exposed externally
- **Database foreign keys**: Use regular IDs internally

---

## 3. PII Handling

### Parameter Filtering

Sensitive parameters are filtered from logs in `config/initializers/filter_parameter_logging.rb`:

```ruby
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt,
  :certificate, :otp, :ssn, :cvv, :cvc,
  :plaintext_key, :api_key, :key_digest,
  :ip_address
]
```

### IP Address Handling

**Always anonymize IP addresses before storage:**

```ruby
# ✅ CORRECT - Anonymize to /24 subnet
def anonymized_ip
  IPAddr.new(request.ip).mask(24).to_s
end

# Stores: 192.168.1.0 instead of 192.168.1.123

# ❌ WRONG - Never store full IP
event.ip_address = request.ip
```

### PII Storage Guidelines

| Data Type | Storage Allowed | Anonymization Required |
|-----------|-----------------|----------------------|
| Email | Yes (for users) | No, but filter from logs |
| IP Address | Yes | Yes, mask to /24 |
| User Agent | Yes | No |
| Passwords | Never plaintext | Hash with bcrypt |
| API Keys | Never plaintext | Hash with SHA256 |
| Full Name | Yes | Filter from logs |
| Location | Coarse only | No city-level precision |

### Logging Safety

```ruby
# ✅ CORRECT - Use structured logging without PII
Rails.logger.info("Event processed", event_id: event.prefix_id, type: event.event_type)

# ❌ WRONG - Never log PII
Rails.logger.info("User #{user.email} created event")
Rails.logger.debug("Request from IP: #{request.ip}")
```

---

## 4. API Authentication

### Bearer Token Format

```
Authorization: Bearer sk_live_abc123...
```

### Validation Pattern

```ruby
class ApiKeys::AuthenticationService < ApplicationService
  VALID_KEY_FORMAT = /\Abearer\s+sk_(test|live)_\w+\z/i

  def initialize(authorization_header)
    @authorization_header = authorization_header
  end

  private

  def run
    return error_result("Missing authorization header") if authorization_header.blank?
    return error_result("Invalid authorization format") unless valid_format?
    return error_result("Invalid API key") unless api_key
    return error_result("API key revoked") if api_key.revoked?
    return error_result("Account suspended") unless api_key.account.active?

    record_usage
    success_result(account: api_key.account, api_key: api_key)
  end

  def valid_format?
    authorization_header.match?(VALID_KEY_FORMAT)
  end

  def api_key
    @api_key ||= ApiKey.find_by(key_digest: key_digest)
  end

  def key_digest
    Digest::SHA256.hexdigest(extracted_token)
  end
end
```

### Account Status Enforcement

**Always check account status after authentication:**

```ruby
def authenticate_api_key
  result = ApiKeys::AuthenticationService.new(auth_header).call

  return render_unauthorized(result[:error]) unless result[:success]
  return render_unauthorized("Account suspended") unless result[:account].active?

  @current_account = result[:account]
end
```

---

## 5. Authorization

### IDOR Prevention

**Never use unscoped finds with user-provided IDs:**

```ruby
# ✅ CORRECT - Scoped to account
def show
  @resource = current_account.resources.find_by_prefix_id!(params[:id])
end

# ❌ WRONG - Allows access to any resource
def show
  @resource = Resource.find(params[:id])
end
```

### Role-Based Access

```ruby
class AdminController < ApplicationController
  before_action :require_admin

  private

  def require_admin
    return if current_user.admin?

    redirect_to dashboard_path, alert: "Admin access required"
  end
end
```

---

## 6. Input Validation

### Strong Parameters

**Always whitelist allowed parameters:**

```ruby
def event_params
  params.require(:event).permit(
    :event_type,
    :visitor_id,
    :session_id,
    :timestamp,
    properties: {}
  )
end
```

### Path Traversal Prevention

```ruby
ALLOWED_PAGES = %w[getting-started authentication api-reference].freeze

def show
  page = params[:page]
  return head :not_found unless ALLOWED_PAGES.include?(page)

  render "docs/#{page}"
end
```

### SQL Injection Prevention

**Always use parameterized queries:**

```ruby
# ✅ CORRECT - Parameterized
Event.where("occurred_at >= ?", start_date)
Event.where(event_type: params[:type])

# ❌ WRONG - String interpolation
Event.where("event_type = '#{params[:type]}'")
```

---

## 7. Rate Limiting

### Implementation

```ruby
class ApiKeys::RateLimiterService < ApplicationService
  REQUESTS_PER_HOUR = 1000
  WINDOW_SECONDS = 3600

  def initialize(account)
    @account = account
  end

  private

  def run
    return rate_limited_result if exceeded?

    increment_counter
    success_result(remaining: remaining, reset_at: reset_at)
  end

  def cache_key
    "rate_limit:account:#{account.id}"
  end

  def exceeded?
    current_count >= REQUESTS_PER_HOUR
  end
end
```

### Response Headers

Always include rate limit headers in API responses:

```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1700956800
```

---

## 8. Session Security

### Cookie Configuration

```ruby
# Visitor tracking cookie
def build_cookie
  "#{COOKIE_NAME}=#{visitor_id}; " \
  "Expires=#{cookie_expiry.httpdate}; " \
  "Path=/; " \
  "HttpOnly; " \
  "Secure; " \
  "SameSite=Strict"
end
```

| Attribute | Value | Purpose |
|-----------|-------|---------|
| HttpOnly | Yes | Prevents XSS access |
| Secure | Yes (production) | HTTPS only |
| SameSite | Strict | CSRF protection |

### Session Timeout

Configure explicit session expiry:

```ruby
# config/initializers/session_store.rb
Rails.application.config.session_store :cookie_store,
  key: '_multibuzz_session',
  expire_after: 24.hours
```

---

## 9. Content Security Policy

### Configuration

```ruby
# config/initializers/content_security_policy.rb
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, :https
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline
    policy.frame_ancestors :none
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
end
```

---

## 10. Error Handling

### Generic Error Messages

```ruby
class ApplicationService
  def call
    run
  rescue ActiveRecord::RecordNotFound
    error_result(["Resource not found"])
  rescue StandardError => e
    # Log detailed error internally
    Rails.logger.error("Service error: #{e.message}", backtrace: e.backtrace.first(5))

    # Return generic message externally
    error_result(["An error occurred"])
  end
end
```

### API Error Responses

```ruby
# Consistent error format
render json: { error: "Invalid request" }, status: :bad_request
render json: { error: "Unauthorized" }, status: :unauthorized
render json: { error: "Resource not found" }, status: :not_found
```

---

## 11. Dependency Security

### Automated Scanning

Run Brakeman in CI:

```yaml
# .github/workflows/security.yml
- name: Run Brakeman
  run: bundle exec brakeman -q -w2
```

### Gem Auditing

```yaml
- name: Audit gems
  run: bundle exec bundler-audit check --update
```

---

## 12. Security Checklist

Before merging any PR:

### Authentication & Authorization
- [ ] All endpoints require appropriate authentication
- [ ] Resources are scoped to current account
- [ ] No IDOR vulnerabilities
- [ ] Role checks where needed

### Data Protection
- [ ] No raw database IDs exposed
- [ ] PII is filtered from logs
- [ ] IP addresses are anonymized
- [ ] Sensitive params use strong parameters

### Input Validation
- [ ] All user input is validated
- [ ] No SQL injection vectors
- [ ] Path traversal prevented
- [ ] File uploads validated (if any)

### API Security
- [ ] Rate limiting applied
- [ ] Account status checked
- [ ] Proper error responses
- [ ] No sensitive data in responses

---

## 13. Incident Response

### If a Vulnerability is Found

1. **Assess severity** using CVSS scoring
2. **Document** in security audit spec
3. **Fix immediately** if Critical/High
4. **Create issue** for Medium/Low
5. **Post-mortem** for Critical issues

### Security Contact

Report security issues to the development team immediately. Do not commit fixes without review for Critical/High severity issues.

---

**This document is mandatory. All code must adhere to these security practices.**
