# SDK Registry

**Purpose**: Central registry of all mbuzz SDKs with version info, status, and maintenance notes.

**Last Updated**: 2025-11-25

---

## Active SDKs

### Ruby SDK

**Repository**: https://github.com/mbuzz-tracking/mbuzz-ruby
**Package**: https://rubygems.org/gems/mbuzz
**Status**: 🟡 In Development
**Current Version**: 0.1.0
**Target Version**: 0.2.0 (fixing critical bugs)

**Maintainer**: Vlad
**Last Verified**: 2025-11-25

**Framework Support**:
- ✅ Ruby on Rails (5.2+)
- ✅ Sinatra
- ✅ Rack middleware
- ✅ Plain Ruby

**Features**:
- ✅ Event tracking (`Mbuzz.track`)
- ✅ Visitor identification (automatic via cookies)
- ✅ Session tracking (automatic)
- ⚠️ User identification (`Mbuzz.identify`) - implemented but backend endpoint missing
- ⚠️ Visitor aliasing (`Mbuzz.alias`) - implemented but backend endpoint missing
- ✅ Automatic page view tracking (Rack middleware)
- ❌ Batch event sending (planned)

**Known Issues**:
- 🐛 Sends Unix timestamp instead of ISO8601 (will break validation)
- 🐛 Sends `event` parameter instead of `event_type`
- 📝 SPECIFICATION.md says `anonymous_id` but should say `visitor_id`

**Fix Status**: See [bug_fixes_critical_inconsistencies.md](../../specs/bug_fixes_critical_inconsistencies.md)

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

### All SDKs Must Implement

**Required Methods**:
```
track(user_id:, visitor_id:, event_type:, properties:, timestamp:)
identify(user_id:, visitor_id:, traits:)
alias(visitor_id:, user_id:)
```

**Required Configuration**:
```
api_key (required)
api_url (default: https://mbuzz.co/api/v1)
enabled (default: true)
debug (default: false)
```

**Required Behavior**:
- Never raise exceptions (return false on errors)
- Log errors if debug mode enabled
- Auto-generate visitor IDs if not provided
- Send timestamps in ISO8601 format
- Include User-Agent header with SDK version

**See**: [API Contract](./api_contract.md) for complete specification

---

## Version Compatibility Matrix

| Backend Version | Ruby SDK | Python SDK | PHP SDK | Node SDK |
|----------------|----------|------------|---------|----------|
| 1.0.0 (current) | 0.2.0+   | N/A        | N/A     | N/A      |

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
