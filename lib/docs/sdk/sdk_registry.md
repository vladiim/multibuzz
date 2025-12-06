# SDK Registry

**Purpose**: Central registry of all mbuzz SDKs with version info, status, and maintenance notes.

**Last Updated**: 2025-11-29

---

## Active SDKs

### Ruby SDK

**Repository**: https://github.com/mbuzz-tracking/mbuzz-ruby
**Package**: https://rubygems.org/gems/mbuzz
**Status**: ✅ Production Ready
**Current Version**: 0.5.0

**Maintainer**: Vlad
**Last Verified**: 2025-11-29

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
- ✅ Session ID generation (cookie `_mbuzz_sid`, 64 hex chars, 30min expiry)
- ✅ Session creation (`POST /sessions`) on new session
- ✅ URL/referrer auto-enrichment via RequestContext

**Deprecated Methods** (emit warnings, still work):
- `Mbuzz.configure { }` → use `Mbuzz.init`
- `Mbuzz.track(...)` → use `Mbuzz.event`

**Removed**:
- `Mbuzz.alias` → merged into `Mbuzz.identify` with `visitor_id:` param

**Installation**:
```ruby
# Gemfile
gem 'mbuzz'
```

**Quick Start**: [Getting Started →](https://mbuzz.co/docs/getting-started)

---

## Planned SDKs

### Python SDK

**Repository**: https://github.com/mbuzz-tracking/mbuzz-python (not created yet)
**Package**: https://pypi.org/project/mbuzz/ (not published yet)
**Status**: 📋 Planned
**Target Version**: 0.1.0

**Framework Support** (planned):
- Django
- Flask
- FastAPI
- Plain Python

**Timeline**: Q1 2026

---

### PHP SDK

**Repository**: https://github.com/mbuzz-tracking/mbuzz-php (not created yet)
**Package**: https://packagist.org/packages/mbuzz/mbuzz (not published yet)
**Status**: 📋 Planned
**Target Version**: 0.1.0

**Framework Support** (planned):
- Laravel
- Symfony
- WordPress plugin
- Plain PHP

**Timeline**: Q2 2026

---

### Node.js SDK

**Repository**: https://github.com/mbuzz-tracking/mbuzz-node (not created yet)
**Package**: https://www.npmjs.com/package/mbuzz (not published yet)
**Status**: 📋 Planned
**Target Version**: 0.1.0

**Framework Support** (planned):
- Express.js
- Next.js
- Nest.js
- Plain Node.js

**Timeline**: Q1 2026

---

### Magento 2 Extension

**Repository**: https://github.com/mbuzz-tracking/mbuzz-magento (not created yet)
**Package**: https://packagist.org/packages/mbuzz/module-tracking (not published yet)
**Status**: 📋 Planned (Spec Complete)
**Target Version**: 0.1.0

**Platform Support** (planned):
- Magento 2.4.x (Open Source)
- Adobe Commerce (Cloud & On-Premise)
- PHP 8.1+

**Features** (planned):
- Server-side purchase tracking (ad-blocker resistant)
- Automatic page view tracking
- Add to cart / remove from cart events
- Customer registration & login (identify)
- Admin configuration UI
- Message queue support (RabbitMQ)
- CLI test commands

**Specification**: [lib/specs/magento_sdk_spec.md](../../specs/magento_sdk_spec.md)

**Timeline**: Q2 2026

---

### Shopify App

**Repository**: https://github.com/mbuzz-tracking/mbuzz-shopify (not created yet)
**Status**: 📋 Planned
**Target Version**: 0.1.0

**Features** (planned):
- Shopify Plus support
- Order webhook integration
- Customer event tracking
- Automatic UTM capture
- Shopify Admin embedded app

**Timeline**: Q3 2026

---

## SDK Development Guidelines

### All SDKs Must Implement (4-Call Model)

**Required Methods**:
```
# 1. init(config) - Configure SDK and establish session
# Internally: Creates session via POST /sessions on new session detection

# 2. event(event_type, properties) - Track journey steps
# Maps to: POST /events

# 3. conversion(conversion_type, revenue, properties) - Track business outcomes
# Maps to: POST /conversions

# 4. identify(user_id, traits) - Link visitor to known user
# Maps to: POST /identify (with visitor_id from cookie)
# Note: alias() is deprecated - use identify() with visitor_id instead
```

**Required Configuration**:
```
api_key (required)
api_url (default: https://mbuzz.co/api/v1)
enabled (default: true)
debug (default: false)
```

**Required Behavior**:
- Auto-generate visitor_id (64 hex chars) and store in cookie `_mbuzz_vid`
- Auto-generate session_id (64 hex chars) and store in cookie `_mbuzz_sid`
- Detect new sessions (no cookie or 30+ min expired)
- POST to `/sessions` on new session (async, non-blocking)
- Include URL and referrer in session and event calls
- Never raise exceptions (return false on errors)
- Log errors if debug mode enabled
- Send timestamps in ISO8601 format

**See**: [API Contract](./api_contract.md) for complete specification
**See**: [Identity & Sessions Spec](../../specs/identity_and_sessions_spec.md) for concepts

---

## Version Compatibility Matrix

| Backend Version | Ruby SDK | Python SDK | PHP SDK | Node SDK |
|----------------|----------|------------|---------|----------|
| 1.2.0 (current) | 0.5.0+   | N/A        | N/A     | N/A      |

**Breaking Change Policy**:
- Backend maintains compatibility for 1 major version back
- SDKs should handle graceful degradation for missing features
- All breaking changes documented in CHANGELOG
- Migration guides provided for major version bumps

---

## SDK Release Checklist

Before releasing any SDK version:

### Code
- [ ] All methods match API contract
- [ ] Parameter names match backend expectations
- [ ] Timestamp format is ISO8601
- [ ] Error handling never raises exceptions
- [ ] Tests cover all public methods
- [ ] Examples in README work
- [ ] Session creation on new session (POST /sessions)
- [ ] URL and referrer included in sessions/events
- [ ] Session detection (cookie missing or expired)

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
