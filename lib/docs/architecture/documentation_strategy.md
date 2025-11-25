# Documentation Strategy & SDK Cross-Linking

**Purpose**: Define how we document mbuzz for users, maintain consistency across SDKs, and optimize for SEO through strategic cross-linking.

**Last Updated**: 2025-11-25

---

## Documentation Architecture

### 1. User-Facing Documentation (mbuzz.co/docs)

**Location**: `app/views/docs/`

**Structure**:
```
docs/
├── getting-started   # Quick start, installation, first event
├── authentication    # API keys, security
├── api-reference     # Complete API documentation
└── examples          # Real-world use cases
```

**Purpose**:
- Onboard new users in <5 minutes
- Provide complete API reference
- Show real-world examples
- Drive conversions (signup → first event tracked)

**SEO Optimization**:
- Target keywords: "multi-touch attribution", "server-side tracking", "attribution API"
- Deep link from SDK READMEs to specific doc sections
- Use canonical URLs to avoid duplicate content

---

### 2. SDK Documentation (GitHub Repositories)

**Current SDKs**:
- [mbuzz-ruby](https://github.com/multibuzz/mbuzz-ruby) - Ruby/Rails gem
- mbuzz-python (planned)
- mbuzz-php (planned)

**Each SDK Repository Contains**:
```
mbuzz-{language}/
├── README.md              # Installation, quick start, link to docs
├── SPECIFICATION.md       # Technical spec, parameter details
├── CHANGELOG.md           # Version history, breaking changes
├── CONTRIBUTING.md        # How to contribute
├── examples/              # Code examples
│   ├── rails_app.rb
│   ├── sinatra_app.rb
│   └── rack_middleware.rb
└── docs/                  # Advanced SDK-specific docs
    ├── configuration.md
    ├── middleware.md
    └── testing.md
```

**Purpose**:
- Framework-specific installation instructions
- Language idioms and best practices
- Advanced configuration options
- Drive traffic to mbuzz.co for full docs

---

### 3. Internal Documentation (lib/docs/)

**Location**: `lib/docs/`

**Structure**:
```
lib/docs/
├── SETUP.md                          # Developer setup
├── architecture/
│   ├── attribution_methodology.md
│   ├── server_side_attribution_architecture.md
│   ├── event_properties.md
│   ├── channel_vs_utm_attribution.md
│   ├── conversion_funnel_analysis.md
│   ├── code_highlighting_implementation.md
│   ├── documentation_strategy.md     # This file
│   └── sdk_consistency_process.md    # SDK review checklist
└── sdk/
    ├── sdk_registry.md               # List of all SDKs
    ├── sdk_development_guide.md      # How to build new SDKs
    └── api_contract.md               # Required API behavior
```

**Purpose**:
- Onboard new developers
- Document architectural decisions
- Maintain SDK consistency
- Serve as source of truth for all implementations

---

## SDK Cross-Linking Strategy

### Goal: Turn GitHub SEO Juice Into mbuzz.co Traffic

GitHub repositories have excellent SEO and trust signals. Use strategic linking to funnel this traffic to mbuzz.co where users can sign up.

### 1. SDK README Structure (Top of File)

```markdown
# mbuzz-ruby

Official Ruby SDK for [mbuzz](https://mbuzz.co) - Server-side multi-touch attribution.

[![Gem Version](https://badge.fury.io/rb/mbuzz.svg)](https://badge.fury.io/rb/mbuzz)
[![Documentation](https://img.shields.io/badge/docs-mbuzz.co-blue)](https://mbuzz.co/docs)

## Quick Links

- 📖 [Full Documentation](https://mbuzz.co/docs/getting-started) - Complete guides and tutorials
- 🔑 [Get Your API Key](https://mbuzz.co/dashboard/api-keys) - Sign up and get started
- 📚 [API Reference](https://mbuzz.co/docs/api-reference) - Complete API documentation
- 💡 [Examples](https://mbuzz.co/docs/examples) - Real-world use cases

## Installation

```ruby
# Gemfile
gem 'mbuzz'
```

Then run:
```bash
bundle install
```

**Next**: [Get your API key →](https://mbuzz.co/dashboard/api-keys)
```

### 2. Deep Linking Strategy

**Link to specific doc sections for better UX and SEO**:

```markdown
## Configuration

Configure mbuzz in your Rails initializer:

```ruby
# config/initializers/mbuzz.rb
Mbuzz.configure do |config|
  config.api_key = ENV['MBUZZ_API_KEY']
  config.api_url = 'https://mbuzz.co/api/v1'
end
```

**Learn more**: [Authentication & API Keys →](https://mbuzz.co/docs/authentication#api-keys)
```

**Benefits**:
- Users land on exact content they need
- Lower bounce rate from docs
- Better conversion (specific → general)
- Google indexes deep links with context

### 3. Example Code Comments Should Link

```ruby
# Track a signup event
# See: https://mbuzz.co/docs/getting-started#track-events
Mbuzz.track(
  user_id: current_user.id,
  event: 'Signup',
  properties: {
    plan: 'pro',
    trial_days: 14
  }
)

# Identify a user with traits
# See: https://mbuzz.co/docs/getting-started#user-identification
Mbuzz.identify(
  user_id: current_user.id,
  traits: {
    email: current_user.email,
    name: current_user.name
  }
)
```

### 4. CHANGELOG Cross-Links

```markdown
## [0.2.0] - 2025-11-25

### Breaking Changes

- Changed timestamp format from Unix epoch to ISO8601
- Changed `event` parameter to `event_type`

**Migration guide**: [Upgrading to v0.2.0 →](https://mbuzz.co/docs/migration/v0.2.0)

### Added

- Support for batch event tracking
- **Learn more**: [Batch Events →](https://mbuzz.co/docs/api-reference#batch-events)
```

### 5. Error Messages Should Link

```ruby
# mbuzz-ruby/lib/mbuzz/client.rb
def track(event:, **options)
  unless event.present?
    log_error("Event name required. See: https://mbuzz.co/docs/api-reference#events")
    return false
  end

  unless options[:user_id] || options[:visitor_id]
    log_error("user_id or visitor_id required. See: https://mbuzz.co/docs/getting-started#visitor-identification")
    return false
  end

  # ...
end
```

---

## Documentation Consistency Process

### Before Releasing Any SDK Update

**1. Check API Contract** (`lib/docs/sdk/api_contract.md`):
- [ ] Endpoint URLs match backend routes
- [ ] Request payload structure matches backend expectations
- [ ] Response format matches backend output
- [ ] Error codes match backend validation

**2. Check Parameter Names** (`lib/specs/bug_fixes_critical_inconsistencies.md`):
- [ ] `event_type` (not `event`)
- [ ] `visitor_id` (not `anonymous_id`)
- [ ] `user_id` (not `userId` or `user`)
- [ ] `properties` (not `props` or `attributes`)
- [ ] `timestamp` as ISO8601 string (not Unix epoch)

**3. Check Environment Variables**:
- [ ] Use `MBUZZ_API_KEY` (not `MULTIBUZZ_API_KEY`)
- [ ] Gem examples match user docs
- [ ] README shows correct env var name

**4. Check Documentation Links**:
- [ ] README links to https://mbuzz.co/docs/getting-started
- [ ] Code examples link to specific doc sections
- [ ] Error messages link to relevant help pages
- [ ] CHANGELOG links to migration guides

**5. Verify Examples Work**:
- [ ] Copy/paste README examples and run them
- [ ] Track an event end-to-end
- [ ] Verify response format matches docs
- [ ] Check error handling works

**6. Update SDK Registry** (`lib/docs/sdk/sdk_registry.md`):
- [ ] Add new version number
- [ ] Update "last verified" date
- [ ] Note any breaking changes
- [ ] Link to CHANGELOG

---

## SEO Optimization

### 1. Anchor Text Strategy

**❌ Bad**: Generic links
```markdown
Click [here](https://mbuzz.co) to learn more.
See the [documentation](https://mbuzz.co/docs).
```

**✅ Good**: Keyword-rich links
```markdown
Learn about [multi-touch attribution models](https://mbuzz.co/docs/attribution-models).
See our [server-side tracking guide](https://mbuzz.co/docs/getting-started).
Get started with [attribution API](https://mbuzz.co/docs/api-reference).
```

### 2. Page Titles & Meta Descriptions

Ensure all doc pages have unique, keyword-rich titles:

```erb
<%# app/views/docs/getting_started.html.erb %>
<% content_for :title, "Getting Started - Server-Side Attribution API | mbuzz" %>
<% content_for :description, "Install mbuzz in 5 minutes. Track events, identify users, and measure multi-touch attribution across all your marketing channels." %>
```

### 3. Canonical URLs

If SDK docs duplicate content from mbuzz.co, use canonical tags:

```html
<!-- mbuzz-ruby/docs/configuration.md rendered as HTML -->
<link rel="canonical" href="https://mbuzz.co/docs/configuration" />
```

### 4. Social Sharing Images

Add Open Graph images to docs for better social sharing:

```erb
<% content_for :head do %>
  <meta property="og:image" content="https://mbuzz.co/og/getting-started.png" />
  <meta property="og:description" content="Server-side multi-touch attribution in 5 minutes" />
<% end %>
```

---

## Documentation Review Checklist

### Weekly SDK Review

Every Monday, review all SDKs for consistency:

```bash
# Run automated consistency check
bin/rails docs:check_sdk_consistency

# This script checks:
# 1. Parameter names match API contract
# 2. Examples use correct env var names
# 3. Links to mbuzz.co are not broken
# 4. Code examples actually work
# 5. Versions match between gem and docs
```

### Before Each Release

1. **Update all examples** in docs to use new version
2. **Test every code example** - paste and run
3. **Check all links** - no 404s to mbuzz.co
4. **Verify API contract** - backend supports all gem features
5. **Update SDK registry** - new version, changelog link

### Monthly Deep Review

- Check Google Search Console for broken links
- Review Analytics: Which docs get most traffic from SDKs?
- Update examples based on user feedback
- Optimize for top search queries

---

## Files to Update When Changing API

### 1. Backend Changes

If you change the API (new endpoint, parameter, response format):

```
✅ Update API contract: lib/docs/sdk/api_contract.md
✅ Update user docs: app/views/docs/api-reference.html.erb
✅ Update getting started: app/views/docs/getting_started.html.erb
✅ Update all SDK examples: ../mbuzz-ruby/README.md, etc.
✅ Update helpers: app/helpers/docs_helper.rb
✅ Add migration guide if breaking: app/views/docs/migration/
```

### 2. SDK Changes

If you update an SDK (new feature, breaking change):

```
✅ Update SDK README: ../mbuzz-ruby/README.md
✅ Update CHANGELOG: ../mbuzz-ruby/CHANGELOG.md
✅ Update SPECIFICATION: ../mbuzz-ruby/SPECIFICATION.md
✅ Update examples: ../mbuzz-ruby/examples/
✅ Update user docs: app/views/docs/getting_started.html.erb
✅ Update SDK registry: lib/docs/sdk/sdk_registry.md
```

### 3. Documentation Changes

If you update docs (new guide, better examples):

```
✅ Check all SDKs still link correctly
✅ Update internal docs if architecture changed
✅ Add redirects if URLs changed
✅ Update sitemap.xml
```

---

## Tools & Automation

### 1. Link Checker (Planned)

```ruby
# lib/tasks/docs.rake
namespace :docs do
  desc "Check all documentation links"
  task check_links: :environment do
    # Check all links in app/views/docs/
    # Check all links in SDK READMEs
    # Report broken links
  end
end
```

### 2. SDK Consistency Checker (Planned)

```ruby
# lib/tasks/docs.rake
namespace :docs do
  desc "Check SDK consistency with backend API"
  task check_sdk_consistency: :environment do
    # Parse SDK code for parameter names
    # Compare with Events::ValidationService requirements
    # Report mismatches
  end
end
```

### 3. Example Runner (Planned)

```ruby
# lib/tasks/docs.rake
namespace :docs do
  desc "Run all code examples from documentation"
  task run_examples: :environment do
    # Extract code blocks from docs
    # Run them in sandbox
    # Verify they work
  end
end
```

---

## Writing Style Guide

### For User Docs (mbuzz.co/docs)

**Tone**: Professional but friendly, action-oriented

**Structure**:
- Start with what user wants to accomplish
- Show code first, explain second
- Link to details ("Learn more →")
- Always show working examples

**Example**:
```markdown
## Track Your First Event

Track user actions with a single method call:

```ruby
Mbuzz.track(
  user_id: current_user.id,
  event: 'Purchase',
  properties: {
    amount: 99.99,
    plan: 'pro'
  }
)
```

That's it! The event is now tracked and will appear in your attribution reports.

**Learn more**: [Event Properties →](https://mbuzz.co/docs/api-reference#event-properties)
```

### For SDK Docs (GitHub)

**Tone**: Technical, concise, complete

**Structure**:
- Quick start at top (5 lines of code)
- Installation
- Configuration
- Common use cases
- Advanced features
- Link to mbuzz.co for full docs

---

## Success Metrics

**Track these metrics**:
- Referral traffic from GitHub → mbuzz.co (Google Analytics)
- Time to first event after signup (Mixpanel/mbuzz itself)
- Documentation bounce rate (lower is better)
- Search rankings for "server-side attribution API"
- SDK GitHub stars and forks

**Monthly goals**:
- 30% of signups come from SDK READMEs
- <2% bounce rate from SDK links to docs
- All docs examples tested and working
- Zero broken links between SDKs and docs

---

## Related Documentation

- [SDK Registry](../sdk/sdk_registry.md) - List of all SDKs
- [API Contract](../sdk/api_contract.md) - Required API behavior
- [Bug Fixes](../../specs/bug_fixes_critical_inconsistencies.md) - Current issues
- [Code Highlighting](./code_highlighting_implementation.md) - How we style code

---

**Next Steps**:
1. Create SDK registry doc
2. Create API contract doc
3. Build SDK consistency checker
4. Update all SDKs with proper cross-links
5. Set up analytics to track SDK → docs → signup conversion
