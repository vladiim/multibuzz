# SDK Registry

**Purpose**: Central registry of all mbuzz SDKs with version info, status, and maintenance notes.

**Last Updated**: 2026-02-05

---

## Session Management (v0.7.0+)

**IMPORTANT**: As of SDK v0.7.0, session management has moved to server-side resolution.

| Behavior | Pre-v0.7.0 (Legacy) | v0.7.0+ (Current) |
|----------|---------------------|-------------------|
| Session cookie | `_mbuzz_sid` (SDK-managed) | **Removed** - server resolves |
| Session ID | SDK-generated time-bucket | Server-side sliding window |
| Required params | `visitor_id`, `session_id` | `visitor_id`, `ip`, `user_agent` |
| Session timeout | Fixed 30-min buckets | True 30-min sliding window |
| Cross-device | Not supported | Via `identifier` param |

See [Visitor & Session Tracking Spec](../../specs/1_visitor_session_tracking_spec.md) for details.

---

## Active Server-Side SDKs

### Ruby SDK

**Repository**: `/Users/vlad/code/m/mbuzz-ruby`
**Package**: https://rubygems.org/gems/mbuzz
**Status**: ✅ Production Ready (v0.7.3)
**Current Version**: 0.7.3

**Maintainer**: Vlad
**Last Verified**: 2026-02-05

**Framework Support**:
- ✅ Ruby on Rails (6.0+)
- ✅ Sinatra
- ✅ Rack middleware
- ✅ Plain Ruby

**Features** (4-Call Model):
- ✅ `Mbuzz.init(api_key:, ...)` - Configure SDK
- ✅ `Mbuzz.event(type, **props)` - Track journey steps
- ✅ `Mbuzz.conversion(type, revenue:, **props)` - Track business outcomes
- ✅ `Mbuzz.identify(user_id, traits:, visitor_id:)` - Link visitor to user + traits
- ✅ Visitor ID generation (cookie `_mbuzz_vid`, 64 hex chars, 2yr expiry)
- ✅ **Server-side session resolution** (passes `ip`, `user_agent` to API)
- ✅ **Cross-device identity** (passes `identifier` to API)
- ✅ URL/referrer auto-enrichment via RequestContext
- ✅ **Navigation-aware session creation** (Sec-Fetch-* whitelist + framework blacklist fallback)
- ✅ **Device fingerprint** (`SHA256(ip|user_agent)[0:32]`) in session creation

**v0.7.3 Changes** (navigation detection):
- ✅ `should_create_session?` gates session creation on real page navigations only
- ✅ Turbo frames, htmx, Unpoly, XHR, prefetch, iframes filtered out
- ✅ Session cookie (`_mbuzz_sid`) fully removed (constants + methods deleted)

**v0.7.0 Changes** (session simplification):
- ❌ Session cookie (`_mbuzz_sid`) - **REMOVED**
- ❌ Client-side session ID generation - **REMOVED**
- ✅ `ip` and `user_agent` passed to all API calls
- ✅ `identifier` param for cross-device resolution

**Installation**:
```ruby
# Gemfile
gem 'mbuzz'
```

---

### Node.js SDK

**Repository**: `/Users/vlad/code/m/mbuzz-node`
**Package**: https://www.npmjs.com/package/mbuzz
**Status**: ✅ Production Ready (v0.7.3)
**Current Version**: 0.7.3

**Framework Support**:
- ✅ Express.js
- ✅ Next.js
- ✅ Nest.js
- ✅ Plain Node.js

**Features**:
- ✅ Full 4-Call Model
- ✅ Server-side session resolution
- ✅ TypeScript types included
- ✅ Navigation-aware session creation (Sec-Fetch-* whitelist)
- ✅ Device fingerprint in session creation

---

### Python SDK

**Repository**: `/Users/vlad/code/m/mbuzz-python`
**Package**: https://pypi.org/project/mbuzz/
**Status**: ✅ Production Ready (v0.7.3)
**Current Version**: 0.7.3

**Framework Support**:
- ✅ Django
- ✅ Flask
- ✅ FastAPI
- ✅ Plain Python

**Features**:
- ✅ Full 4-Call Model
- ✅ Server-side session resolution
- ✅ Navigation-aware session creation (Sec-Fetch-* whitelist)
- ✅ Device fingerprint in session creation

---

### PHP SDK

**Repository**: `/Users/vlad/code/m/mbuzz-php`
**Package**: https://packagist.org/packages/mbuzz/mbuzz
**Status**: ✅ Production Ready (v0.7.3)
**Current Version**: 0.7.3

**Framework Support**:
- ✅ Laravel
- ✅ Symfony
- ✅ Plain PHP

**Features**:
- ✅ Full 4-Call Model
- ✅ Server-side session resolution
- ✅ Navigation-aware session creation (Sec-Fetch-* whitelist)
- ✅ Device fingerprint in session creation

---

## Browser/Platform SDKs

### Shopify App

**Repository**: `/Users/vlad/code/m/mbuzz-shopify`
**Status**: ✅ Production Ready (v0.7.0)

**Features**:
- ✅ Shopify theme extension
- ✅ Checkout pixel integration
- ✅ Auto page view tracking
- ✅ Add to cart tracking
- ✅ Server-side session resolution (passes `user_agent`)
- ✅ Visitor cookie only (`_mbuzz_vid`)
- N/A Navigation detection — client-side JS SDK, exempt (no middleware, no sub-request inflation)

**v0.7.0 Changes** (2026-01-10):
- Removed `_mbuzz_sid` session cookie
- Removed client-side session ID generation
- Added `user_agent` to all API payloads
- Server handles session resolution via fingerprinting

---

## Tag Manager Integrations

### Server-Side GTM (sGTM)

**Repository**: `https://github.com/mbuzzco/mbuzz-sgtm`
**Status**: ✅ Live
**Category**: `tag_manager`

**How it works**: An sGTM tag template that runs inside the customer's server-side GTM container. Makes HTTP calls to mbuzz's existing API — no new endpoints, no backend access required on the customer's site.

**Features**:
- ✅ Visitor ID management (server-set `_mbuzz_vid` cookie, survives ITP)
- ✅ Session creation (`POST /sessions`) with UTM/referrer/channel capture
- ✅ Event tracking (`POST /events`) with custom properties
- ✅ Conversion tracking (`POST /conversions`) with revenue/currency
- ✅ Identity linking (`POST /identify`) for cross-device attribution
- ✅ Device fingerprint (`SHA256(ip|user_agent)[0:32]`) for session resolution
- ✅ GTM consent mode support

**Supported Platforms** (any site with GTM):
- Webflow
- Squarespace
- WordPress
- Custom builds
- Any website with a GTM container

**Distribution**: GTM Community Template Gallery

**Documentation**: [mbuzz.co/docs/integrations-sgtm](/docs/integrations-sgtm)

---

## Planned SDKs

### Magento 2 Extension

**Status**: 📋 Planned (Spec Complete)
**Specification**: [lib/specs/magento_sdk_spec.md](../../specs/magento_sdk_spec.md)

---

## SDK Development Guidelines

### All SDKs Must Implement (4-Call Model)

**Required Methods**:
```
# 1. init(config) - Configure SDK
# Sets up API key, base URL, debug mode

# 2. event(event_type, properties) - Track journey steps
# Maps to: POST /events
# Must include: visitor_id, ip, user_agent

# 3. conversion(conversion_type, revenue, properties) - Track business outcomes
# Maps to: POST /conversions
# Must include: visitor_id, ip, user_agent

# 4. identify(user_id, traits) - Link visitor to known user
# Maps to: POST /identify (with visitor_id from cookie)
```

**Required Configuration**:
```
api_key (required)
api_url (default: https://mbuzz.co/api/v1)
enabled (default: true)
debug (default: false)
```

**Required Behavior (v0.7.0+)**:
- Auto-generate visitor_id (64 hex chars) and store in cookie `_mbuzz_vid`
- **DO NOT** manage session cookies - server handles session resolution
- Pass `ip` and `user_agent` with all event/conversion calls
- Optionally pass `identifier` for cross-device resolution
- Include URL and referrer in event properties
- Never raise exceptions (return false on errors)
- Log errors if debug mode enabled
- Send timestamps in ISO8601 format
- **Navigation detection (v0.7.3+)**: Only create sessions for requests where `Sec-Fetch-Mode: navigate` AND `Sec-Fetch-Dest: document` AND `Sec-Purpose` absent. Fall back to framework blacklist (`Turbo-Frame`, `HX-Request`, `X-Up-Version`, `X-Requested-With`) for old browsers
- **Device fingerprint (v0.7.3+)**: Compute `SHA256(ip|user_agent)[0:32]` and include as `device_fingerprint` in `POST /sessions`

**See**: [API Contract](./api_contract.md) for complete specification
**See**: [Visitor & Session Tracking Spec](../../specs/1_visitor_session_tracking_spec.md) for session resolution

---

## Version Compatibility Matrix

| Backend Version | Ruby SDK | Python SDK | PHP SDK | Node SDK | Shopify |
|----------------|----------|------------|---------|----------|---------|
| 1.4.0 (current) | 0.7.3+ | 0.7.3+ | 0.7.3+ | 0.7.3+ | 0.7.0+ |
| 1.4.0 | 0.7.0+ | 0.7.0+ | 0.7.0+ | 0.7.0+ | 0.7.0+ |
| 1.3.0 | 0.6.0+ | 0.6.0+ | 0.6.0+ | 0.6.0+ | Works (legacy) |

**v0.7.3**: Navigation-aware session creation. All server-side SDKs should be at v0.7.3+ to prevent visit count inflation from sub-requests.

**Breaking Change Policy**:
- Backend maintains compatibility for 1 major version back
- SDKs should handle graceful degradation for missing features
- All breaking changes documented in CHANGELOG
- Migration guides provided for major version bumps

---

## SDK Release Checklist

Before releasing any SDK version:

### Code (v0.7.3+ Server-Side SDKs)
- [ ] All methods match API contract
- [ ] Parameter names match backend expectations
- [ ] Timestamp format is ISO8601
- [ ] Error handling never raises exceptions
- [ ] Tests cover all public methods
- [ ] Examples in README work
- [ ] `ip` and `user_agent` included in event/conversion calls
- [ ] `identifier` param supported for cross-device resolution
- [ ] URL and referrer included in event properties
- [ ] **NO** session cookie management (server resolves)
- [ ] Navigation detection implemented (Sec-Fetch-* whitelist + framework blacklist fallback)
- [ ] Session creation only fires for real page navigations
- [ ] Tests verify sub-requests (Turbo, htmx, fetch, XHR, prefetch) do NOT create sessions
- [ ] Device fingerprint (`SHA256(ip|user_agent)[0:32]`) sent in `POST /sessions`

### Documentation
- [ ] README updated with new features
- [ ] CHANGELOG updated
- [ ] SPECIFICATION.md matches implementation
- [ ] Links to mbuzz.co docs are correct
- [ ] Migration guide if breaking changes

### Testing
- [ ] Unit tests pass
- [ ] Integration tests against staging API pass
- [ ] Manual test: install → track event → see in dashboard
- [ ] Examples from README copy-paste and work

### Registry
- [ ] Update this file (sdk_registry.md) with new version
- [ ] Update [documentation_strategy.md](../architecture/documentation_strategy.md)
- [ ] Update user docs at mbuzz.co/docs if needed

### Release
- [ ] Bump version in gemspec/setup.py/composer.json
- [ ] Tag release in git
- [ ] Publish to package registry
- [ ] Announce in changelog
- [ ] Monitor for issues in first 48 hours

---

## Maintenance Schedule

### Daily
- Monitor error rates from SDK logging
- Check for new issues on GitHub

### Weekly
- Review SDK consistency (see [documentation_strategy.md](../architecture/documentation_strategy.md))
- Check for security updates in dependencies
- Review analytics: which methods are used most?

### Monthly
- Deep dive: ensure all examples still work
- Check link health (no 404s to mbuzz.co)
- Review user feedback and feature requests
- Update compatibility matrix

### Quarterly
- Security audit
- Performance benchmarks
- Consider new framework support
- Plan next minor version

---

## Cross-SDK Consistency

### Parameter Names (MUST BE IDENTICAL)

| Concept | Parameter Name | Type | Required |
|---------|---------------|------|----------|
| Event name | `event_type` | String | Yes |
| User ID | `user_id` | String/Integer | Conditional* |
| Visitor ID | `visitor_id` | String | Conditional* |
| Event metadata | `properties` | Hash/Object | No |
| When it happened | `timestamp` | ISO8601 String | No (auto) |
| User traits | `traits` | Hash/Object | No |
| Client IP | `ip` | String | Yes (v0.7.0+) |
| Client User-Agent | `user_agent` | String | Yes (v0.7.0+) |
| Cross-device identity | `identifier` | Hash/Object | No |

*Either `user_id` OR `visitor_id` required for `track()`

### Environment Variables (MUST BE IDENTICAL)

| Purpose | Variable Name | Example |
|---------|--------------|---------|
| API Key | `MBUZZ_API_KEY` | `sk_test_abc123...` |
| API URL | `MBUZZ_API_URL` | `https://mbuzz.co/api/v1` |

### Response Formats (MUST BE IDENTICAL)

**Success** (200 OK):
```json
{
  "success": true,
  "accepted": 1
}
```

**Validation Error** (422 Unprocessable Entity):
```json
{
  "error": "Validation failed",
  "details": ["user_id or visitor_id required"]
}
```

**Authentication Error** (401 Unauthorized):
```json
{
  "error": "Invalid API key"
}
```

**Rate Limit** (429 Too Many Requests):
```json
{
  "error": "Rate limit exceeded",
  "retry_after": 3600
}
```

---

## GitHub Repository Template

Each SDK should use this structure:

```
mbuzz-{language}/
├── .github/
│   ├── workflows/
│   │   ├── test.yml          # Run tests on push
│   │   └── release.yml       # Publish to package registry
│   └── ISSUE_TEMPLATE/
│       ├── bug_report.md
│       └── feature_request.md
├── lib/                      # Source code
├── test/                     # Tests
├── examples/                 # Working examples
│   ├── rails_app.rb
│   └── sinatra_app.rb
├── docs/                     # SDK-specific docs
│   ├── configuration.md
│   └── advanced.md
├── .gitignore
├── CHANGELOG.md              # All version changes
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md           # How to contribute
├── LICENSE                   # MIT License
├── README.md                 # Main docs, links to mbuzz.co
├── SPECIFICATION.md          # Technical spec
└── {gemspec|setup.py|etc}    # Package definition
```

---

## Support & Contact

**Questions about SDKs**:
- GitHub Issues: https://github.com/mbuzz-tracking/mbuzz-ruby/issues
- Email: support@mbuzz.co
- Docs: https://mbuzz.co/docs

**Report a Bug**:
1. Check [known issues](../../specs/bug_fixes_critical_inconsistencies.md)
2. Search existing GitHub issues
3. Create new issue with reproducible example
4. Tag with SDK name and version

**Request a Feature**:
1. Check roadmap in repo
2. Open GitHub discussion
3. Describe use case and benefit
4. Upvote existing requests

---

## Related Documentation

- [API Contract](./api_contract.md) - Required API behavior
- [Documentation Strategy](../architecture/documentation_strategy.md) - Cross-linking guide
- [Bug Fixes](../../specs/bug_fixes_critical_inconsistencies.md) - Current issues
- [Getting Started](https://mbuzz.co/docs/getting-started) - User docs
