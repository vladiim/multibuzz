# Security Audit Report - November 2025

**Audit Date:** November 25, 2025
**Auditor:** Claude Code Security Audit
**Codebase Version:** feature/e1-mvp branch (commit 6a2a0b6)

---

## Executive Summary

This security audit examined the Multibuzz Rails application for vulnerabilities across four key areas: multi-tenancy isolation, ID exposure, PII handling, and general security issues. The application demonstrates **strong security practices overall** with one critical vulnerability requiring immediate remediation.

### Risk Summary

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 1 | Requires immediate fix |
| High | 0 | - |
| Medium | 4 | Should be addressed |
| Low | 5 | Recommended improvements |

---

## 1. Multi-Tenancy Audit

### Status: ✅ EXCELLENT

The application implements strict multi-tenancy through account scoping. All database queries are properly scoped.

### Verified Safe Patterns

**Controllers:**
- `app/controllers/dashboard_controller.rb:5` - Uses `current_user.account`
- `app/controllers/dashboard_controller.rb:7` - `@account.events.recent.limit(10)` ✓
- `app/controllers/dashboard/api_keys_controller.rb:6` - `current_account.api_keys.order(...)` ✓
- `app/controllers/dashboard/api_keys_controller.rb:16` - `current_account.api_keys.find(params[:id])` ✓

**Services:**
- `app/services/events/processing_service.rb:77` - `account.events.build()` ✓
- `app/services/users/identification_service.rb:37` - `account.users.find_or_initialize_by()` ✓
- `app/services/visitors/lookup_service.rb:27` - `account.visitors.find_by()` ✓
- `app/services/sessions/tracking_service.rb:29` - `account.sessions.active.find_by()` ✓

### Acceptable Exceptions

- `app/controllers/sessions_controller.rb:21` - `User.find_by(email: params[:email])` is global by design for login authentication

### Recommendations

None - multi-tenancy is properly implemented.

---

## 2. ID Exposure Audit

### Status: ⚠️ NEEDS ATTENTION

Most models use `prefixed_ids`, but two models are missing this protection.

### Models WITH prefix_id (Correct):

| Model | Prefix | File Location |
|-------|--------|---------------|
| Account | `acct_` | `app/models/account.rb:6` |
| User | `user_` | `app/models/user.rb:6` |
| Visitor | `vis_` | `app/models/visitor.rb:8` |
| Session | `sess_` | `app/models/session.rb:8` |
| Event | `evt_` | `app/models/event.rb:7` |
| Conversion | `conv_` | `app/models/conversion.rb:5` |
| AttributionModel | `attr_` | `app/models/attribution_model.rb:9` |

### Models MISSING prefix_id:

| Model | Risk Level | Recommendation |
|-------|-----------|----------------|
| ApiKey | LOW | Uses custom key format (`sk_live_*`, `sk_test_*`) - acceptable |
| FormSubmission | MEDIUM | Add `has_prefix_id :form` |
| WaitlistSubmission | **CRITICAL** | Add `has_prefix_id :wait` (see IDOR below) |
| AttributionCredit | MEDIUM | Add `has_prefix_id :cred` |

### Required Actions

1. **CRITICAL**: Add `has_prefix_id :wait` to `WaitlistSubmission` model
2. **MEDIUM**: Add `has_prefix_id :form` to `FormSubmission` model
3. **MEDIUM**: Add `has_prefix_id :cred` to `AttributionCredit` model

---

## 3. PII Handling Audit

### Status: ✅ GOOD

### Positive Findings

**Parameter Filtering** (`config/initializers/filter_parameter_logging.rb`):
```ruby
:passw, :email, :secret, :token, :_key, :crypt, :salt,
:certificate, :otp, :ssn, :cvv, :cvc, :plaintext_key, :api_key, :key_digest
```

**IP Address Anonymization** (`app/services/events/enrichment_service.rb:134-135`):
```ruby
def anonymized_ip
  @anonymized_ip ||= IPAddr.new(request.ip).mask(24).to_s
end
```
IP addresses are masked to /24 subnet before storage - excellent privacy practice.

**API Key Storage** (`app/services/api_keys/generation_service.rb`):
- Keys are hashed with SHA256 before storage
- Plaintext key only shown once at creation time
- Key format: `sk_{environment}_{random32}`

### Areas Requiring Attention

**FormSubmission/WaitlistSubmission:**
- Stores: `email`, `ip_address`, `user_agent`
- Recommendation: Consider IP anonymization for form submissions
- Recommendation: Add data retention policy

### Recommendations

1. Add `ip_address` to filtered parameters
2. Consider IP anonymization for `FormSubmission` records
3. Document data retention policy for PII

---

## 4. Security Vulnerabilities

### CRITICAL: Insecure Direct Object Reference (IDOR) in WaitlistSubmission

**Location:** `app/controllers/waitlist_controller.rb:10-12`

```ruby
def show
  @submission = WaitlistSubmission.find(params[:id])
end
```

**Vulnerability:**
- Unauthenticated endpoint allows access to ANY waitlist submission by ID
- Sequential integer IDs are easily enumerable
- Exposes: email, role, framework choice, IP address, user agent

**Attack Vector:**
```
GET /waitlist/1
GET /waitlist/2
GET /waitlist/3
... (enumerate all submissions)
```

**Required Remediation:**
1. Add `has_prefix_id :wait` to `WaitlistSubmission` model
2. Consider adding session-based access control (only show your own submission)
3. Or implement signed/encrypted URLs for submission confirmation

**Severity:** CRITICAL
**CVSS Score (estimated):** 7.5 (High)

---

### MEDIUM: Account Status Not Enforced in API

**Location:** `app/controllers/api/v1/base_controller.rb:12-19`

**Issue:** Account status enum exists (`active`, `suspended`, `cancelled`) but is not checked during API authentication.

**Impact:** Suspended or cancelled accounts can continue making API requests.

**Required Remediation:**
Add to `authenticate_api_key` method:
```ruby
return render_unauthorized("Account suspended") unless current_account.active?
```

**Severity:** MEDIUM

---

### MEDIUM: Missing Content Security Policy

**Location:** `config/initializers/content_security_policy.rb`

**Issue:** CSP configuration is commented out. No Content-Security-Policy headers are sent.

**Impact:** Increases XSS attack surface.

**Remediation:** Enable and configure CSP headers for dashboard pages.

**Severity:** MEDIUM

---

### MEDIUM: Admin Role Defined But Not Enforced

**Location:** `app/models/user.rb:8`

```ruby
enum :role, { member: 0, admin: 1 }
```

**Issue:** Role exists but no authorization checks enforce admin-only actions.

**Impact:** If admin-specific features are planned, they lack protection.

**Remediation:** Implement role-based access control for admin actions.

**Severity:** MEDIUM

---

### MEDIUM: Rate Limiting Only Per-Account

**Location:** `app/services/api_keys/rate_limiter_service.rb`

**Issue:** Rate limiting tracks by account, not by API key.

**Impact:** Multiple API keys for same account share one rate limit.

**Remediation:** Consider per-API-key rate limiting for better isolation.

**Severity:** MEDIUM

---

### LOW: Health Endpoint Exposes Database Status

**Location:** `app/controllers/api/v1/health_controller.rb`

**Issue:** Health check is unauthenticated and reveals database connection status.

**Remediation:** Move to non-API namespace or make generic.

**Severity:** LOW

---

### LOW: Error Messages May Leak Information

**Location:** `app/services/application_service.rb:4-9`

**Issue:** Exception messages are returned in API responses.

**Remediation:** Use generic error messages in production environment.

**Severity:** LOW

---

### LOW: Session Cookie SameSite=Lax

**Location:** `app/services/visitors/identification_service.rb:31-41`

**Issue:** Visitor cookie uses `SameSite=Lax` (acceptable but not strictest).

**Remediation:** Consider `SameSite=Strict` for enhanced CSRF protection.

**Severity:** LOW

---

### LOW: No Explicit Session Timeout

**Issue:** Relies on Rails default session handling. No explicit session timeout.

**Remediation:** Configure explicit session expiry for dashboard sessions.

**Severity:** LOW

---

### LOW: Cache-Based Rate Limiting

**Issue:** Rate limiting uses `Rails.cache` which may be memory-based in some environments.

**Remediation:** Ensure Redis or similar persistent cache in production.

**Severity:** LOW

---

## 5. Security Strengths

The following security practices are well implemented:

### API Authentication ✅
- Bearer token authentication with proper format validation
- SHA256 digest comparison (keys not stored in plaintext)
- Last usage tracking
- Revocation support

### SQL Injection Protection ✅
- All queries use Rails ORM with parameterized queries
- No raw SQL or `find_by_sql` usage found

### Mass Assignment Protection ✅
- All controllers use `.permit()` for parameter whitelisting

### CSRF Protection ✅
- Rails default CSRF protection enabled
- API endpoints properly use ActionController::API

### No Hardcoded Credentials ✅
- API keys use SecureRandom generation
- No secrets found in codebase

### Input Validation ✅
- Path traversal protection in docs controller
- Whitelist approach for allowed pages

---

## 6. Remediation Checklist

### Priority 1 - Critical (Immediate)

- [ ] Fix WaitlistSubmission IDOR vulnerability
  - [ ] Add `has_prefix_id :wait` to model
  - [ ] Consider adding session-based access control

### Priority 2 - Medium (This Sprint)

- [ ] Add account status check to API authentication
- [ ] Enable Content Security Policy
- [ ] Add `has_prefix_id` to remaining models (FormSubmission, AttributionCredit)
- [ ] Implement admin role authorization checks

### Priority 3 - Low (Backlog)

- [ ] Add `ip_address` to parameter filter list
- [ ] Generic error messages in production
- [ ] Explicit session timeout configuration
- [ ] Consider per-API-key rate limiting
- [ ] Document data retention policy

---

## 7. Compliance Notes

### GDPR Considerations
- IP anonymization is implemented ✓
- Email is properly filtered from logs ✓
- Data retention policy should be documented
- Consider right-to-erasure implementation

### OWASP Top 10 Coverage

| Risk | Status |
|------|--------|
| A01:2021 Broken Access Control | ⚠️ IDOR in waitlist |
| A02:2021 Cryptographic Failures | ✅ Proper key hashing |
| A03:2021 Injection | ✅ Parameterized queries |
| A04:2021 Insecure Design | ✅ Good patterns |
| A05:2021 Security Misconfiguration | ⚠️ CSP disabled |
| A06:2021 Vulnerable Components | ✅ Check with bundler-audit |
| A07:2021 Auth Failures | ✅ Strong implementation |
| A08:2021 Data Integrity Failures | ✅ No unsafe deserialization |
| A09:2021 Security Logging | ⚠️ Add security event logging |
| A10:2021 SSRF | ✅ No external URL fetching |

---

## 8. Next Steps

1. **Immediate**: Address critical IDOR vulnerability
2. **Short-term**: Implement medium priority fixes
3. **Ongoing**: Schedule quarterly security reviews
4. **Consider**: Automated security scanning (Brakeman is in Gemfile - ensure it runs in CI)

---

## Appendix A: Files Reviewed

### Controllers
- `app/controllers/api/v1/base_controller.rb`
- `app/controllers/api/v1/events_controller.rb`
- `app/controllers/api/v1/health_controller.rb`
- `app/controllers/api/v1/identify_controller.rb`
- `app/controllers/api/v1/validate_controller.rb`
- `app/controllers/dashboard_controller.rb`
- `app/controllers/dashboard/api_keys_controller.rb`
- `app/controllers/docs_controller.rb`
- `app/controllers/sessions_controller.rb`
- `app/controllers/waitlist_controller.rb`

### Models
- All models in `app/models/`

### Services
- All services in `app/services/`

### Configuration
- `config/initializers/filter_parameter_logging.rb`
- `config/initializers/content_security_policy.rb`
- `config/routes.rb`

---

**Report Generated:** November 25, 2025
**Classification:** Internal Use Only
