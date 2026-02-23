# Session Bot Detection Specification

**Date:** 2026-02-19
**Priority:** P0
**Status:** Complete (code shipped, pending deploy + production validation)
**Branch:** `feature/session-bot-detection`

---

## Summary

Server-side session creation can't distinguish real browsers from bots at the HTTP level. Qualified sessions significantly exceed GA4 because bots crawling ad landing pages arrive with real attribution signals (UTMs, click_ids, referrers) and pass the current `suspect_session?` heuristic. This spec adds User-Agent storage to sessions and a bot classifier powered by daily-synced open-source bot pattern databases. All intelligence is server-side. SDKs just pass one extra field.

See `lib/docs/architecture/session_intelligence.md` for the full research document.

---

## Current State

### How Sessions Are Classified Today

`Sessions::CreationService#suspect_session?` marks sessions as suspect when they have **zero** attribution signals:

```ruby
# app/services/sessions/creation_service.rb:238-242
def suspect_session?
  referrer.blank? &&
    normalized_utm.values.none?(&:present?) &&
    click_ids.empty?
end
```

This catches direct-with-no-signals traffic (64% ghost rate) but misses bots that arrive via URLs containing `?utm_source=google&gclid=abc123`.

### Production Evidence (PetPro360)

Dashboard shows ~76k visitors. Raw console queries from Feb 18 showed higher qualified session counts — the discrepancy suggests the dashboard applies additional scoping (date range, engagement filters, or visitor dedup) beyond the raw `.qualified` scope. The core signal remains: the majority of qualified sessions have zero page views, zero duration, and nil landing page host — hallmarks of bot traffic with real attribution signals.

**TODO:** Run a verified analysis on production comparing dashboard visitor count, `.qualified` session count, and GA4 sessions for the same date range to establish the true inflation ratio. Document results in `lib/docs/architecture/session_intelligence.md`.

### SDK Session Payloads (Current — all v0.7.4)

| SDK | Sends `user_agent`? | Has it available? |
|-----|---------------------|-------------------|
| Ruby | No | Yes — `request.user_agent` in middleware |
| Node | No | Yes — `getUserAgent(req)` in middleware |
| Python | No | Yes — `_get_user_agent()` in middleware |
| PHP | No | Yes — `$_SERVER['HTTP_USER_AGENT']` in Context |
| Shopify | **Yes** | Yes — `navigator.userAgent` (client-side) |
| sGTM | No | Yes — `getRequestHeader('user-agent')` |

Every server-side SDK captures `user_agent` to compute `device_fingerprint` but does not include it in the session API payload.

### Existing Pattern: `ReferrerSources::SyncService`

mbuzz already syncs referrer classification data from upstream open-source lists:

| Source | URL | Format |
|--------|-----|--------|
| Matomo Search | `raw.githubusercontent.com/matomo-org/.../SearchEngines.yml` | YAML |
| Matomo Social | `raw.githubusercontent.com/matomo-org/.../Socials.yml` | YAML |
| Matomo Spam | `raw.githubusercontent.com/matomo-org/.../spammers.txt` | TXT |
| Snowplow | `s3-eu-west-1.amazonaws.com/.../referers-latest.json` | JSON |

Pattern: fetch → parse → deduplicate by priority → upsert atomically → invalidate cache. `ReferrerSources::LookupService` checks the synced data at session creation time with 24h caching.

---

## Proposed Solution

### Architecture

Follow the sync pattern from `ReferrerSources::SyncService` (fetch upstream → parse → cache) but skip the DB layer. Bot patterns are regex-matched against UA strings — fundamentally different from referrer domain lookups. They belong in memory, not in a table.

**Why no `bot_sources` table (DRY analysis):**

| | Referrer Sources | Bot Patterns |
|--|-----------------|-------------|
| Lookup type | Exact string match on domain | Regex match against full UA string |
| Must be in DB? | Yes — domain lookup via `find_by` | No — must compile to `Regexp.union` in memory anyway |
| Custom entries | Added via migrations (AI engine seeds) | Config file (`config/bot_patterns.yml`, version controlled) |
| Need to query patterns? | Yes — "all search engine domains" | No — only need `match?(ua)` |
| Priority conflicts | Same domain in multiple sources | Same bot in multiple lists — just match any |

A DB table would add a migration, model, validations, scopes, and constants module — all to load patterns into memory on every sync anyway. Skip the middleman.

### Upstream Bot Lists

| Source | URL | Format | Entries | License | Updated |
|--------|-----|--------|---------|---------|---------|
| crawler-user-agents | `raw.githubusercontent.com/monperrus/crawler-user-agents/master/crawler-user-agents.json` | JSON | 300+ regex patterns | MIT | Weekly |
| Matomo bots | `raw.githubusercontent.com/matomo-org/device-detector/master/regexes/bots.yml` | YAML | 1,100+ entries | LGPL-3.0 | Weekly |

Both actively maintained, widely used (Plausible, Matomo, Voight-Kampff gem), fetchable via single HTTP GET.

### Data Flow (Proposed)

```
DAILY SYNC (BotPatterns::SyncJob)
  ├─ Fetch crawler-user-agents JSON → parse regex patterns
  └─ Fetch Matomo bots.yml YAML → parse regex patterns
  ├─ Load custom patterns from config/bot_patterns.yml
  → Merge all patterns, compile into Regexp.union
  → Store compiled matcher in Rails.cache + class-level singleton
  → Log stats (pattern count, sources loaded)

SESSION CREATION (per request)
  SDK middleware (v0.7.5) → POST /api/v1/sessions (now includes user_agent)
  → Sessions::CreationService
    → Sessions::BotClassifier.new(user_agent, referrer:, utm:, click_ids:).classify
      → BotPatterns::Matcher.bot?(user_agent) → compiled regex match (O(1) amortized)
      → Falls back to no-signals heuristic if UA not a bot
    → Session saved with user_agent, suspect, suspect_reason
```

### Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| In-memory patterns vs DB table | In-memory | Bot detection is regex matching — must be in memory. DB would just add a load step before the same in-memory work. No table, no model, no migration for patterns. DRYer. |
| Daily-synced lists vs bundled gem | Synced | Lists update weekly. Daily sync keeps us current without gem bumps or deploys. |
| crawler-user-agents + Matomo bots | Both | crawler-user-agents has the broadest regex coverage. Matomo has 3x entries with categories. Together: comprehensive. |
| Custom patterns in config YAML | `config/bot_patterns.yml` | Version controlled, reviewed in PRs, loaded at sync time. Same role as `config/sdk_registry.yml` for SDK metadata. |
| `Regexp.union` for matching | Single compiled regex | Ruby's regex engine handles union efficiently. One match call vs iterating 1,400 patterns. Cached as singleton. |
| Cache result per UA string | Rails.cache, 24h TTL | Avoid recomputing for repeat UAs (most traffic is a handful of distinct UAs). Same TTL as referrer source lookups. |

### Custom Bot Patterns

```yaml
# config/bot_patterns.yml
# Custom bot patterns not covered by upstream lists.
# These are merged with upstream patterns at sync time.
# Format: regex pattern string (Ruby-compatible)
patterns:
  - pattern: "InternalMonitor"
    name: "Internal Health Check"
  - pattern: "CustomScraper"
    name: "Known Scraper"
```

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Known bot | UA matches bot_sources pattern (Googlebot, AhrefsBot, etc.) | `suspect: true`, `suspect_reason: "known_bot"` |
| No signals | Real browser UA + no referrer, no UTMs, no click_ids | `suspect: true`, `suspect_reason: "no_signals"` |
| Real visitor with attribution | Real browser UA + has referrer/UTMs/click_ids | `suspect: false`, `suspect_reason: nil` |
| Missing user_agent | Pre-0.7.5 SDK or edge case | Falls back to no-signals heuristic only |
| Empty string UA | UA present but blank | Treated as missing — no-signals heuristic only |
| Bot UA with UTMs | Bot crawling ad URL with `?gclid=abc` | `suspect: true`, `suspect_reason: "known_bot"` (bot detection takes priority) |
| Spoofed UA | Bot sends Chrome UA string | Not caught — future layers (datacenter IP, behavioral) |
| Shopify (client-side) | JS execution = real browser, UA always real | `suspect: false` (unchanged) |
| Custom bot pattern | Entry in `config/bot_patterns.yml` | Merged with upstream patterns at sync time |
| No patterns loaded | Sync hasn't run, cache empty | Falls back to no-signals heuristic only (graceful degradation) |
| Sync failure | Upstream URL unreachable | Previous cached patterns preserved. Retry with backoff. Log error. |
| Server restart | Patterns in memory lost | Reloaded from Rails.cache on first lookup. If cache also cold, sync job runs. |

---

## Implementation Tasks

### Phase 1: Bot Pattern Infrastructure ✓

- [x] **1.1** Create `config/bot_patterns.yml` (custom patterns file)
- [x] **1.2** Create `BotPatterns::SyncService` (fetch upstream lists, parse, merge with custom, compile `Regexp.union`, write to cache)
- [x] **1.3** Create `BotPatterns::Matcher` (singleton — loads compiled regex from cache, exposes `bot?(ua)` and `bot_name(ua)`)
- [x] **1.4** Create `BotPatterns::Parsers::CrawlerUserAgentsParser` (JSON → pattern list)
- [x] **1.5** Create `BotPatterns::Parsers::MatomoBotsParser` (YAML → pattern list)
- [x] **1.6** Create `BotPatterns::SyncJob` (thin wrapper)
- [x] **1.7** Write tests for all of the above (34 tests, 0 failures)
- [x] **1.8** Run initial sync to populate cache (post-deploy) — `config/initializers/bot_patterns.rb` syncs on boot

### Phase 2: Session Classification ✓

- [x] **2.1** Migration: add `user_agent` (text) and `suspect_reason` (string) to sessions
- [x] **2.2** Create `Sessions::BotClassifier` service (lookup + no-signals fallback)
- [x] **2.3** Wire `BotClassifier` into `CreationService` — replace `suspect_session?` with classifier
- [x] **2.4** Update `session_attributes` to include `user_agent` and `suspect_reason`
- [x] **2.5** Permit `:user_agent` in `Api::V1::SessionsController` strong params
- [x] **2.6** Write tests (full suite: 2518 runs, 0 failures)

### Phase 3: SDK Updates (all → v0.7.5) ✓

All server-side SDKs: include `user_agent` in session payload. Data already captured — just not forwarded.

**Ruby** (`mbuzz` gem):
- [x] **3.1** `lib/mbuzz/middleware/tracking.rb` — add `user_agent: context[:user_agent]` to `create_session`
- [x] **3.2** `lib/mbuzz/client/session_request.rb` — add `user_agent` to initializer + payload
- [x] **3.3** `lib/mbuzz/client.rb` — pass `user_agent:` kwarg through `Client.session`
- [x] **3.4** Bump to 0.7.5, release

**Node** (`@mbuzz/node`):
- [x] **3.5** `src/middleware/express.ts` — add `user_agent: userAgent` to session payload
- [x] **3.6** Bump to 0.7.5, publish

**Python** (`mbuzz`):
- [x] **3.7** `src/mbuzz/middleware/flask.py` — add `"user_agent": user_agent` to session payload
- [x] **3.8** Bump to 0.7.5, publish

**PHP** (`mbuzz/mbuzz-php`):
- [x] **3.9** `src/Mbuzz/Client.php` — add `'user_agent' => $userAgent` to session payload
- [x] **3.10** Bump to 0.7.5, publish

**Shopify** — no change (already sends `user_agent`).

**sGTM**:
- [x] **3.11** `template.tpl` — add `user_agent: getRequestHeader('user-agent')` to session body
- [x] **3.12** Bump template version

**E2E Verification** (all SDKs verified via `sdk_integration_tests/scenarios/bot_detection_test.rb`):
- [x] Ruby: 5/5 pass — user_agent stored, bot classified, real browser qualified
- [x] Node: 5/5 pass
- [x] Python: 5/5 pass
- [x] PHP: 2/2 pass (cookie-first variant)

### Phase 4: Deploy + Validate

- [x] **4.1** Update server `Gemfile` to `mbuzz ~> 0.7.5`
- [x] **4.2** Update `config/sdk_registry.yml` with version 0.7.5 for all SDKs
- [ ] **4.3** Deploy server (migration + bot sync + updated gem)
- [ ] **4.4** Deploy updated SDKs to test app (PetPro360)
- [ ] **4.5** 24-hour production validation (see below)
- [ ] **4.6** 72-hour production validation (see below)
- [ ] **4.7** Update `lib/docs/architecture/session_intelligence.md` with results

---

## Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `config/bot_patterns.yml` | Custom bot patterns | **New** |
| `db/migrate/xxx_add_user_agent_to_sessions.rb` | UA + suspect_reason columns | **New** |
| `app/services/bot_patterns/sync_service.rb` | Fetch upstream lists, compile, cache | **New** |
| `app/services/bot_patterns/matcher.rb` | Singleton regex matcher | **New** |
| `app/services/bot_patterns/parsers/crawler_user_agents_parser.rb` | JSON parser | **New** |
| `app/services/bot_patterns/parsers/matomo_bots_parser.rb` | YAML parser | **New** |
| `app/jobs/bot_patterns/sync_job.rb` | Daily sync job | **New** |
| `app/services/sessions/bot_classifier.rb` | Classification orchestrator | **New** |
| `app/services/sessions/creation_service.rb` | Session creation | **Modified** — use BotClassifier |
| `app/controllers/api/v1/sessions_controller.rb` | Strong params | **Modified** — permit :user_agent |
| `config/initializers/bot_patterns.rb` | Boot-time pattern sync | **New** |
| `app/controllers/api/v1/test/verifications_controller.rb` | Test verification | **Modified** — expose user_agent, suspect, suspect_reason |
| `sdk_integration_tests/scenarios/bot_detection_test.rb` | E2E bot detection tests | **New** |

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Parse crawler-user-agents JSON | `test/services/bot_patterns/parsers/crawler_user_agents_parser_test.rb` | Extracts patterns from JSON |
| Parse Matomo bots YAML | `test/services/bot_patterns/parsers/matomo_bots_parser_test.rb` | Extracts patterns from YAML |
| SyncService compiles + caches | `test/services/bot_patterns/sync_service_test.rb` | Fetch, parse, compile, write to cache |
| SyncService merges custom patterns | `test/services/bot_patterns/sync_service_test.rb` | `config/bot_patterns.yml` included |
| SyncService handles fetch failure | `test/services/bot_patterns/sync_service_test.rb` | Previous cache preserved, error logged |
| Matcher detects Googlebot | `test/services/bot_patterns/matcher_test.rb` | Regex match against known bot UA |
| Matcher detects AhrefsBot | `test/services/bot_patterns/matcher_test.rb` | SEO crawler caught |
| Matcher detects GPTBot | `test/services/bot_patterns/matcher_test.rb` | AI crawler caught |
| Matcher passes Chrome | `test/services/bot_patterns/matcher_test.rb` | Real browser not matched |
| Matcher passes Safari mobile | `test/services/bot_patterns/matcher_test.rb` | Mobile browser not matched |
| Matcher handles nil UA | `test/services/bot_patterns/matcher_test.rb` | Returns false gracefully |
| Matcher handles empty cache | `test/services/bot_patterns/matcher_test.rb` | Returns false when no patterns loaded |
| BotClassifier: bot UA → known_bot | `test/services/sessions/bot_classifier_test.rb` | Bot detection via Matcher |
| BotClassifier: real UA, no signals → no_signals | `test/services/sessions/bot_classifier_test.rb` | Existing heuristic preserved |
| BotClassifier: real UA, with signals → qualified | `test/services/sessions/bot_classifier_test.rb` | Real traffic passes |
| BotClassifier: nil UA → no_signals fallback | `test/services/sessions/bot_classifier_test.rb` | Graceful degradation |
| BotClassifier: bot UA with UTMs → known_bot | `test/services/sessions/bot_classifier_test.rb` | Bot trumps attribution signals |
| CreationService stores user_agent | `test/services/sessions/creation_service_test.rb` | UA persisted on session |
| CreationService stores suspect_reason | `test/services/sessions/creation_service_test.rb` | Reason persisted |
| Controller permits user_agent | `test/controllers/api/v1/sessions_controller_test.rb` | Strong params updated |
| Cross-account isolation | `test/services/sessions/creation_service_test.rb` | Multi-tenancy preserved |

### E2E Integration Tests

| Test | File | Verifies |
|------|------|----------|
| Session stores user_agent from middleware | `sdk_integration_tests/scenarios/bot_detection_test.rb` | SDK sends UA, server persists it |
| Bot UA classified as known_bot | Same | Googlebot → suspect: true, suspect_reason: "known_bot" |
| Real browser with UTM is qualified | Same | Chrome + UTMs → suspect: false |
| Bot with UTMs still classified as bot | Same | Bot detection takes priority over attribution signals |
| Real browser no signals → no_signals | Same | Direct visit → suspect: true, suspect_reason: "no_signals" |
| PHP session stores user_agent | Same | Cookie-first SDK variant |
| PHP bot detection | Same | Cookie-first bot classification |

### Production Validation

#### 24-Hour Check

```ruby
account = Account.find_by(prefix_id: "acct_xxx")
recent = account.sessions.where("created_at > ?", 24.hours.ago)
puts "Total sessions (24h): #{recent.count}"
puts "Suspect: #{recent.where(suspect: true).count}"
puts "Qualified: #{recent.where(suspect: false).count}"
puts "\nBy suspect_reason:"
recent.group(:suspect_reason).count.sort_by { |_, v| -v }.each do |reason, count|
  puts "  #{reason || 'nil (qualified)'}: #{count}"
end

# Verify real traffic not blocked
qualified = recent.where(suspect: false)
puts "\nQualified with page views: #{qualified.where('page_view_count > 0').count}"
puts "Qualified with host: #{qualified.where.not(landing_page_host: nil).count}"

# Sample bots
recent.where(suspect_reason: "known_bot").limit(5).pluck(:user_agent, :channel).each do |ua, ch|
  puts "  BOT: #{ua[0..80]} | #{ch}"
end

# Sample qualified
qualified.where.not(landing_page_host: nil).limit(5).pluck(:user_agent, :channel).each do |ua, ch|
  puts "  OK: #{ua[0..80]} | #{ch}"
end
```

**Pass criteria (24h):**
- [ ] `known_bot` captures > 0 sessions (classifier running)
- [ ] Qualified sessions with page views NOT marked suspect (no false positives)
- [ ] Sampled known_bot UAs are actual bots
- [ ] Sampled qualified UAs are real browsers
- [ ] No errors in logs related to BotClassifier or BotSources

#### 72-Hour Check

```ruby
account = Account.find_by(prefix_id: "acct_xxx")
window = account.sessions.where("created_at > ?", 72.hours.ago)

total = window.count
by_reason = window.group(:suspect_reason).count
puts "Total (72h): #{total}"
by_reason.sort_by { |_, v| -v }.each do |reason, count|
  pct = (count.to_f / total * 100).round(1)
  puts "  #{reason || 'qualified'}: #{count} (#{pct}%)"
end

qualified = window.where(suspect: false).count
puts "\nQualified: #{qualified}"
puts "Compare to GA4 for same window — target: within 1.5x (was 2.5x)"

qual_pv = window.where(suspect: false).where("page_view_count > 0").count
suspect_pv = window.where(suspect: true).where("page_view_count > 0").count
puts "\nQualified w/ page views: #{qual_pv}"
puts "Suspect w/ page views: #{suspect_pv} (should be ~0)"

puts "\nQualified by channel:"
window.where(suspect: false).group(:channel).count.sort_by { |_, v| -v }.each do |ch, count|
  puts "  #{ch}: #{count}"
end
```

**Pass criteria (72h):**
- [ ] Qualified sessions within 1.5x of GA4 for same window (was 2.5x)
- [ ] `known_bot` captures majority of zero-engagement sessions
- [ ] Suspect sessions with page views near 0
- [ ] Channel distribution of qualified sessions looks reasonable
- [ ] Funnel visit count plausible relative to GA4

---

## Definition of Done

- [ ] All Phase 1-4 tasks completed
- [ ] Bot patterns synced and cached (1,400+ patterns compiled)
- [ ] Unit tests pass (sync, parsers, matcher, classifier, creation service, controller)
- [ ] Full test suite passes, no regressions
- [ ] All SDKs bumped to 0.7.5 with `user_agent` in session payload
- [ ] `config/sdk_registry.yml` updated with version 0.7.5
- [ ] 24-hour production validation passes
- [ ] 72-hour production validation passes
- [ ] `lib/docs/architecture/session_intelligence.md` updated with results
- [ ] Spec moved to `lib/specs/old/`

---

## Out of Scope

- **Datacenter IP detection** — Next phase of session intelligence roadmap. Separate spec.
- **Cloudflare bot score** — Depends on customer infrastructure. Separate spec.
- **Behavioral signals (post-hoc reclassification)** — Background job to reclassify based on engagement. Separate spec.
- **Reclassifying historical sessions** — No stored UA on existing sessions. Future sessions only.
- **SDK-side bot filtering** — Explicitly rejected. SDKs stay thin.
- **Backfilling `landing_page_host`** — Separate investigation.
