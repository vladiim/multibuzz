# Self-Referral Poisoning Fix

**Date:** 2026-04-10
**Priority:** P0
**Status:** In Progress
**Branch:** `feature/session-bot-detection`

---

## Summary

Organic search traffic has been misclassified as "direct" since ~March 10, 2026. The `self_referral?` check in `ChannelAttributionService` matches the referrer domain against `account_domains` (all distinct `landing_page_host` values). A bug in `CreationService.page_host` allowed search engine domains (e.g., `google.com`) to be stored as `landing_page_host`, poisoning the list. Once poisoned, every future Google-referred session is classified as a self-referral → direct.

**Impact:** 12,673 sessions with a Google referrer misclassified as direct. Organic search volume dropped from ~5,000/week to ~1,400/week.

---

## Current State

### Data flow (poisoning)

```
1. SDK sends session with malformed URL (no host, e.g. "/page" or empty)
   → CreationService.page_host
   → URI.parse(url).host == nil
   → falls back to host_from_referrer → "google.com"
   → stored as landing_page_host: "google.com"

2. Next session from Google
   → account_domains includes "google.com"
   → self_referral?("google.com", account_domains: [..., "google.com"])
   → true → Channels::DIRECT   ← WRONG, should be ORGANIC_SEARCH
```

### Key files

| File | Role |
|------|------|
| `app/services/sessions/creation_service.rb:322` | `page_host` with `host_from_referrer` fallback |
| `app/services/sessions/creation_service.rb:331` | `account_domains` query |
| `app/services/sessions/channel_attribution_service.rb:62` | `self_referral?` check in attribution hierarchy |
| `app/services/sessions/channel_attribution_service.rb:164` | `self_referral?` implementation |

### Production evidence

```
Poisoned landing_page_host values:
  - google.com
  - stackoverflow.com

Misclassified sessions (March 10+): 12,673
  All have: channel=direct, initial_referrer ILIKE '%google%', valid landing_page_host

Weekly organic_search volume:
  Feb 23: 9,218  (healthy)
  Mar 2:  4,366  (start of decline)
  Mar 9:  1,466  (poisoned)
  Mar 16: 1,271
  Apr 6:    579
```

---

## Proposed Solution

Two code fixes (defense in depth) + data backfill.

### Fix 1: Remove `host_from_referrer` fallback

`CreationService.page_host` should return `nil` when the URL has no parseable host, not fall back to the referrer host. The page host is where the user IS, not where they came FROM.

```ruby
# BEFORE (creation_service.rb:322)
def page_host
  @page_host ||= URI.parse(url).host || host_from_referrer
end

# AFTER
def page_host
  @page_host ||= begin
    URI.parse(url).host
  rescue URI::InvalidURIError
    nil
  end
end
```

Remove the `host_from_referrer` method entirely (now unused).

### Fix 2: Guard `self_referral?` against known referrer domains

Even with Fix 1, poisoned data could re-enter via other paths. Add a guard: if the referrer domain matches a known channel pattern (search engines, social networks, etc.), it is NOT a self-referral.

```ruby
# BEFORE (channel_attribution_service.rb:164)
def self_referral?
  return false unless referrer_domain.present?
  return false unless account_domains.any?
  account_domains.any? { |domain| normalize_host(referrer_domain) == normalize_host(domain) }
end

# AFTER
def self_referral?
  return false unless referrer_domain.present?
  return false unless account_domains.any?
  return false if known_referrer_source?
  account_domains.any? { |domain| normalize_host(referrer_domain) == normalize_host(domain) }
end

def known_referrer_source?
  REFERRER_DOMAIN_PATTERNS.any? { |pattern, _| referrer_domain.match?(pattern) }
end
```

### Fix 3: Data backfill (post-deploy)

Three-step process:

**Step A:** Clean poisoned `landing_page_host` values — any domain matching existing `REFERRER_DOMAIN_PATTERNS` or `ReferrerSource` lookups.

```ruby
# Use the same categorisation rules as ChannelAttributionService
poisoned = account.sessions
  .where.not(landing_page_host: nil)
  .distinct.pluck(:landing_page_host)
  .select { |host| Channels::REFERRER_DOMAIN_PATTERNS_FLAT.match?(host) || ReferrerSources::LookupService.new("https://#{host}").call }

account.sessions
  .where(landing_page_host: poisoned)
  .update_all(landing_page_host: nil)
```

_(The exact constant name depends on implementation — the point is to reuse `SEARCH_ENGINES`, `SOCIAL_NETWORKS`, `AI_ENGINES`, etc. and the `ReferrerSource` database, not hardcode domain lists.)_

**Step B:** Re-attribute misclassified sessions using existing rake task.

```bash
bin/rails attribution:backfill_channels ACCOUNT_ID=<id>
```

**Step C:** Recompute conversion attribution credits.

```bash
bin/rails attribution:reattribute_conversions ACCOUNT_ID=<id>
```

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Organic search referrer | referrer=google.com, no UTM | `organic_search` (via referrer pattern/lookup) |
| Self-referral (legit) | referrer=mysite.com, account owns mysite.com | `direct` |
| Self-referral + search engine in account_domains | referrer=google.com, google.com in account_domains | `organic_search` (guard prevents match) |
| Malformed URL | url="/page", referrer=google.com | page_host=nil, landing_page_host=nil, channel=`organic_search` |
| No URL host, no referrer | url="/page", referrer=nil | page_host=nil, channel=`direct` |
| Social referrer in account_domains | referrer=facebook.com, facebook.com in account_domains | `organic_social` (guard prevents match) |
| UTM present + self-referral domain | utm_medium=cpc, referrer=mysite.com | `paid_search` (UTM takes priority) |

---

## Implementation Phases

### Phase 1: TDD code fixes

- [x] **1.1** Add test: `self_referral? should not match search engine domains in account_domains`
- [x] **1.2** Add test: `self_referral? should not match social network domains in account_domains`
- [x] **1.3** Add test: `self_referral? should not match AI engine domains in account_domains`
- [x] **1.4** Add test: `page_host returns nil when URL has no host` (CreationService)
- [x] **1.5** Add test: `page_host does not fall back to referrer host` (CreationService)
- [x] **1.6** Implement `known_referrer_source?` guard in `ChannelAttributionService.self_referral?`
- [x] **1.7** Remove `host_from_referrer` fallback from `CreationService.page_host`
- [x] **1.8** Remove unused `host_from_referrer` method
- [x] **1.9** Run full test suite — no regressions (3193 runs, 0 failures)

### Phase 2: Deploy + backfill

- [ ] **2.1** Deploy code fixes
- [ ] **2.2** Clean poisoned `landing_page_host` values in production
- [ ] **2.3** Run `attribution:backfill_channels` (dry run first)
- [ ] **2.4** Run `attribution:backfill_channels` (real)
- [ ] **2.5** Run `attribution:reattribute_conversions`
- [ ] **2.6** Verify organic_search channel is correctly attributed for new sessions

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| self_referral? skips search engine domains | `test/services/sessions/channel_attribution_service_test.rb` | google.com in account_domains → still organic_search |
| self_referral? skips social domains | same | facebook.com in account_domains → still organic_social |
| self_referral? skips AI engine domains | same | chatgpt.com in account_domains → still ai |
| self_referral? still works for real account domains | same | mysite.com in account_domains → direct (no regression) |
| page_host nil for hostless URL | `test/services/sessions/creation_service_test.rb` | url="/page" → page_host stored as nil |
| page_host does not use referrer host | same | url="/page", referrer=google.com → landing_page_host nil |

### Manual QA (post-deploy)

1. Send session with referrer=https://www.google.com/ via API
2. Verify session.channel == "organic_search"
3. Check `landing_page_host` list no longer contains search engine domains
4. Verify dashboard shows organic_search traffic recovering

---

## Definition of Done

- [ ] All tests pass (unit + existing suite)
- [ ] `self_referral?` cannot match known referrer source domains
- [ ] `page_host` never falls back to referrer host
- [ ] Poisoned `landing_page_host` records cleaned in production
- [ ] Misclassified sessions backfilled
- [ ] Conversion credits recomputed
- [ ] Dashboard shows organic_search recovery
- [ ] Spec moved to `old/`
- [ ] `BUSINESS_RULES.md` reviewed (channel classification rules unchanged, no update needed)

---

## Out of Scope

- Alerting/monitoring for future channel misattribution drift
- SDK-side URL validation (SDKs should send full URLs, but server should be resilient)
- Cleaning up other non-search poisoned domains (stackoverflow.com is low impact, cleaned as part of Step A)
