# Server-Side Session Intelligence

**Created:** 2026-02-19
**Status:** Research & Architecture
**Related:** `session_qualification.md`, `session_continuity_fingerprint_fallback.md`, `server_side_attribution_architecture.md`

This document is the **single source of truth** for how mbuzz identifies real visitors, filters noise, and achieves parity with client-side analytics (GA4). It exists so we build on accumulated research rather than re-discovering the same problems.

---

## The Core Problem

mbuzz is a **server-side** attribution platform. Sessions are created from HTTP requests, not from JavaScript execution in a browser. This means every request that passes our filters — bots, crawlers, prefetchers, ad verification services — creates a session indistinguishable from a real visitor at the HTTP level.

GA4 solves this implicitly: its JavaScript only executes in real browsers. No JS execution = no session. We don't have that luxury.

### Production Evidence (PetPro360, 2026-02-01 to 2026-02-18)

| Source | Sessions | Unique Visitors |
|--------|----------|-----------------|
| GA4 | 43,000 | 34,000 |
| mbuzz (all) | 542,613 | — |
| mbuzz (qualified, `suspect: false`) | 107,874 | 122,831 |
| mbuzz (qualified + has landing page host) | 16,121 | — |
| mbuzz (qualified + `page_view_count > 0`) | 4,451 | — |

Even after ghost session filtering, we're **2.5x GA4** on qualified sessions. The `suspect` heuristic catches direct-with-no-signals traffic but misses bots that arrive with real attribution data (UTMs, click_ids, referrers from crawling ad landing pages).

---

## Timeline: What We've Tried

| Date | Change | What It Fixed | What Remained |
|------|--------|---------------|---------------|
| 2025-11-28 | Identity & sessions model | Cross-device linking | No bot filtering |
| 2026-01-10 | Visitor dedup via fingerprint | Concurrent request merging | Ghost sessions still counted |
| 2026-01-29 | Sec-Fetch-* navigation detection in SDK | 5x Turbo Frame inflation | Bots (no Sec-Fetch headers) pass through fallback |
| 2026-02-09 | Session continuity (reuse active sessions) | 92% ghost reduction for returning visitors | New visitors still create sessions on every request |
| 2026-02-11 | Fingerprint fallback to visitor_id | Session misattribution from IP rotation | Doesn't filter bots |
| 2026-02-13 | `suspect` flag + `.qualified` scope | 64.2% ghost rate → 0% for direct-no-signals | Bots with attribution signals (UTMs, referrers) pass through |
| 2026-02-13 | Ghost session cleanup service | Removed poisoned journey data | Doesn't prevent future bot sessions |

**Pattern:** Each fix addressed one symptom. The root cause — server-side session creation can't distinguish browsers from bots at the HTTP level — remains unsolved.

---

## Anatomy of the Remaining Problem

### What the 107k Qualified Sessions Look Like

Of 107,874 qualified sessions (Feb 1-18):

**By page engagement:**
- 0 page views: 103,616 (96.1%)
- 1+ page views: 4,451 (3.9%)

**By session duration:**
- 0 seconds (single-hit): 103,177 (95.6%)
- > 0 seconds: 4,697 (4.4%)

**By landing page host:**
- `nil` (no host parsed from URL): 95,914 (88.9%)
- With host: 16,121 (14.9%) — `note: some overlap with nil`

**The 95k nil-host sessions have real attribution signals:**
- With referrer: 83,868
- With UTMs: 31,986
- With click_ids: 29,173
- Channels: paid_search (19k), organic_search (11k), paid_social (10k), email (8k), referral (7k), direct (38k)

These are **bots crawling URLs that contain attribution parameters**. Search engine crawlers follow ad landing page URLs (with `gclid`, `utm_source`, etc.), email preview bots fetch URLs from marketing emails, social media crawlers fetch URLs shared in posts. They all arrive with real attribution data but never render the page.

### Why `suspect_session?` Misses Them

```ruby
def suspect_session?
  referrer.blank? &&
    normalized_utm.values.none?(&:present?) &&
    click_ids.empty?
end
```

This only flags sessions with **zero** attribution signals. A Googlebot crawling `https://example.com/?utm_source=google&gclid=abc123` has UTMs, click_ids, and a referrer. It looks identical to a real paid search visitor at the HTTP level.

### Why the SDK Can't Solve This

The SDK middleware's `should_create_session?` gate:

```ruby
def should_create_session?(env)
  return page_navigation?(env) if sec_fetch_headers?(env)
  !framework_sub_request?(env)
end
```

The `Sec-Fetch-*` check was added to solve **Turbo Frame inflation** (5x duplicate sessions from concurrent frame loads). It was never designed as bot detection. The fallback path (`!framework_sub_request?`) exists for browsers that don't send `Sec-Fetch-*` headers.

Bots don't send `Sec-Fetch-*` headers. They're not Turbo/HTMX/XHR. They pass.

**The SDK should stay thin.** Bot detection is complex, evolving, and cross-cutting. Every SDK (Ruby, Node, Python, PHP, Shopify) would need the same logic. One server-side solution covers all SDKs.

---

## How Others Solve This

### Snowplow: Server-Side Enrichment Pipeline

Snowplow's architecture separates **collection** from **intelligence**. SDKs are dumb collectors. All classification happens in a server-side enrichment pipeline:

1. **IAB Spiders & Robots Enrichment** — classifies requests using IP + UA + timestamp against the IAB/ABC commercial bot database
2. **UA Parser Enrichment** — extracts browser, OS, device from User-Agent string
3. **IP Lookup Enrichment** — resolves IP to geo, ISP, organization (datacenter IPs → likely bot)
4. **Custom Enrichments** — arbitrary server-side logic

Each enrichment adds structured context before storage. Sessions are computed **post-hoc** in dbt, not at collection time. Bot classification happens at the enrichment layer — SDKs know nothing about it.

**Key insight:** Snowplow treats session intelligence as a **data pipeline concern**, not an SDK concern.

### Amplitude: Server-Side Events Are Out-of-Session by Default

Events sent via Amplitude's HTTP API (server-side) get a session ID of **`-1`**, explicitly excluding them from all session metrics. To include server-side events in sessions, you must pass a valid `session_id` matching a client-side session.

**Key insight:** Amplitude acknowledges that server-side events often don't represent user-initiated activity and makes exclusion the default.

### Mixpanel: Sessions as Analytics Computation

Mixpanel computes sessions **automatically from event timestamps** — no SDK session management needed. Any event within the timeout window (30 min) extends the session. Sessions are a pure analytics construct, never a data collection concern.

**Key insight:** If sessions are computed from events, bot requests that never generate events never create sessions.

### Plausible: Multi-Layered Server-Side Filtering

1. User-Agent bot list matching
2. Referrer spam domain list
3. 32,000 datacenter IP ranges blocked by default
4. Behavioral pattern detection
5. JavaScript requirement (implicit bot filter)

In testing, Plausible correctly identified bot traffic that **GA4 failed to detect**.

### GA4: Implicit Filtering via JavaScript

GA4's primary bot filter is that `gtag.js` must execute in a real browser. On top of that:
- IAB/ABC bot list (updated monthly)
- Google's internal bot research database
- Engaged session threshold (10s+ or 2+ page views)
- Data thresholding and sampling

GA4 also **under-counts** due to ad blockers (~30-40% of users) and cookie consent rejection. One study found GA4 accuracy dropped to 55.6% due to consent banners.

---

## Proposed Architecture: Server-Side Session Intelligence

### Design Principles

1. **SDKs stay thin** — send raw signals (visitor_id, URL, referrer, IP, UA, device_fingerprint). No bot logic.
2. **Server classifies** — all intelligence lives in `Sessions::CreationService` and enrichment layers
3. **Solve once** — a new SDK (Go, Java, sGTM) gets bot filtering for free
4. **Layered defense** — multiple independent signals, no single point of failure
5. **Preserve data** — classify, don't delete. Reclassify when heuristics improve.

### Layer 1: Store User-Agent on Sessions (prerequisite)

Currently the User-Agent is hashed into `device_fingerprint` and discarded. We need to store it for all downstream detection.

- Add `user_agent` column to `sessions` table
- SDK already sends UA via API (`ip` and `user_agent` params on events/conversions)
- `CreationService` needs to accept and persist it from the session creation payload

### Layer 2: User-Agent Bot Detection

Use the `device_detector` gem (Matomo's UA database, 2,000+ bot patterns, fastest Ruby implementation):

```ruby
client = DeviceDetector.new(user_agent)
client.bot?       # => true/false
client.bot_name   # => "Googlebot", "AhrefsBot", etc.
```

Run at session creation time. Mark detected bots as `suspect: true` with a `suspect_reason` for observability.

**What this catches:** Googlebot, Bingbot, AhrefsBot, SEMrushBot, GPTBot, ClaudeBot, FacebookExternalHit, Twitterbot, email preview bots, SEO crawlers, ad verification bots — everything that self-identifies in its User-Agent.

**What this misses:** Sophisticated bots that spoof legitimate User-Agent strings (headless Chrome, Puppeteer, Playwright).

### Layer 3: Datacenter IP Detection

Bots overwhelmingly run from cloud infrastructure. AWS, GCP, Azure, and other providers publish their IP ranges. An estimated **99% of traffic from datacenter IPs is automated**.

```ruby
DATACENTER_RANGES = load_cidr_ranges("config/datacenter_ips.json")

def datacenter_ip?(ip)
  addr = IPAddr.new(ip)
  DATACENTER_RANGES.any? { |range| range.include?(addr) }
end
```

Sources for IP ranges:
- AWS: `https://ip-ranges.amazonaws.com/ip-ranges.json`
- GCP: `https://www.gstatic.com/ipranges/cloud.json`
- Azure: ServiceTags JSON
- DigitalOcean, Hetzner, OVH, Linode (published ranges)

**What this catches:** Bots running from cloud servers — the majority of automated traffic.

**What this misses:** Bots running from residential IPs (rare but growing).

### Layer 4: Behavioral Signals (Post-Hoc)

Some signals can only be evaluated after the session exists:

| Signal | Real User | Bot |
|--------|-----------|-----|
| Session duration | > 0s (browsed) | 0s (single hit) |
| `page_view_count` | 1+ (SDK tracked page views) | 0 (no page interaction) |
| `landing_page_host` | Present (valid URL) | Often `nil` |
| Request frequency | Irregular, human cadence | Regular intervals, high frequency |

These can be evaluated by a periodic background job or at query time via an enhanced `qualified` scope.

### Layer 5: Cloudflare Bot Score (If Available)

If the customer uses Cloudflare, the `cf-bot-score` header (1-99, where < 30 = likely bot) is the gold standard. It uses ML trained on billions of requests, TLS fingerprinting, and JS challenges.

The SDK can forward this header to the server, and `CreationService` can use it as the primary signal when present:

```ruby
# In CreationService
def suspect_session?
  return cloudflare_bot? if cloudflare_score.present?
  ua_bot? || datacenter_ip? || no_attribution_signals?
end
```

### Classification Model

```ruby
# Proposed: Sessions::BotClassifier
# Called from CreationService at session creation time

def classify(user_agent:, ip:, referrer:, utm:, click_ids:, cloudflare_score: nil)
  return :verified_bot if cloudflare_score.present? && cloudflare_score < 5
  return :likely_bot if cloudflare_score.present? && cloudflare_score < 30
  return :known_bot if ua_bot?(user_agent)
  return :datacenter if datacenter_ip?(ip)
  return :no_signals if no_attribution_signals?(referrer, utm, click_ids)
  :qualified
end
```

Store classification as `suspect_reason` (enum or string) alongside the boolean `suspect` flag. This enables:
- Observability: "How many sessions are blocked by each layer?"
- Tuning: "Are we over-filtering? Under-filtering?"
- Reclassification: "Update the UA database and reclassify"

---

## The `nil` Landing Page Host Problem

95,914 qualified sessions (88.9%) have `landing_page_host: nil`. This is the single largest signal of non-human traffic.

`landing_page_host` is set by `CreationService` from `URI.parse(url).host`. For this to be `nil`, either:

1. The `url` param is missing or empty — but `run` checks `url.present?` and returns early
2. The `url` doesn't parse to a valid host — edge case (relative URLs, malformed URLs)
3. The `url` is valid but `normalized_page_host` returns `nil` — only if `page_host` is blank
4. The session was created before the `landing_page_host` column existed and was never backfilled

**Most likely:** Sessions created before the column was added, or URL parsing edge cases from bot traffic with malformed URLs.

**Investigation needed:** Sample the `session_id` values from nil-host sessions to determine creation dates and whether they predate the column migration.

---

## Implementation Roadmap

### Phase 1: Store User-Agent (prerequisite)

1. Migration: add `user_agent` text column to sessions
2. SDK: include `user_agent` in session creation API payload
3. Server: `CreationService` persists `user_agent` from params
4. Backfill: not possible for existing sessions (UA was never stored)

### Phase 2: UA-Based Bot Detection

1. Add `device_detector` gem
2. Create `Sessions::BotClassifier` service
3. Wire into `CreationService#suspect_session?`
4. Add `suspect_reason` column to sessions
5. Backfill: once UA is stored, reclassify existing sessions

### Phase 3: Datacenter IP Detection

1. Build `config/datacenter_ips.json` from published cloud provider ranges
2. Add IP check to `BotClassifier`
3. Periodic refresh of IP ranges (monthly cron or rake task)

### Phase 4: Enhanced Qualification Scope

1. Evaluate whether to tighten `.qualified` or add `.engaged` scope
2. Consider: `where(suspect: false).where.not(landing_page_host: nil)` as minimum
3. Dashboard scopes may need separate treatment for funnel (visits) vs attribution (journeys)

### Phase 5: Cloudflare Integration (optional)

1. SDK forwards `cf-bot-score` header when present
2. Server uses it as primary signal
3. Highest accuracy but depends on customer's infrastructure

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Bot detection on server, not SDK | Server-side | Solve once for all SDKs. SDKs stay thin. Bot databases evolve — update once, all customers benefit. |
| Store UA on sessions | Required | Can't do UA-based detection without it. The UA was discarded (hashed into fingerprint) since day one. |
| Classify, don't delete | Preserve data | Same reasoning as current `suspect` flag. Enables reclassification, audit, debugging. |
| Multiple layers | Defense in depth | No single signal catches all bots. UA detection misses spoofed UAs. IP detection misses residential bots. Behavioral signals are post-hoc. Layer them. |
| `suspect_reason` column | Observability | Need to know which layer caught what. Critical for tuning false positive / false negative rates. |
| Cloudflare as optional enhancement | Not all customers use CF | Can't depend on it, but when available it's the best signal. |

---

## What GA4 Gets Right That We Don't (Yet)

1. **JavaScript execution as proof of browser** — GA4's implicit filter. We can approximate this by requiring at least one SDK event (page view, custom event) to mark a session as "engaged."
2. **IAB/ABC bot list** — Commercial database, updated monthly. `device_detector` provides a free equivalent using Matomo's database.
3. **Engaged session threshold** — GA4 deprioritizes sessions under 10 seconds with < 2 page views. We could add a similar concept.
4. **ML-based detection** — Trained on billions of requests. We don't have this scale. Cloudflare integration is the closest proxy.

## What We Get Right That GA4 Doesn't

1. **No ad blocker blind spot** — GA4 loses ~30-40% of real users to ad blockers. Server-side tracking sees everyone.
2. **No consent blind spot** — GA4 requires cookie consent in many jurisdictions. One study found 55.6% accuracy loss.
3. **Server-side attribution** — First-party data, no JavaScript dependency, works across all platforms.

The goal isn't to match GA4 exactly — it's to get close enough that customers trust the data while retaining our server-side advantages.

---

## References

### Internal Documentation
- `lib/docs/architecture/session_qualification.md` — current `suspect` flag and `.qualified` scope
- `lib/docs/architecture/session_continuity_fingerprint_fallback.md` — fingerprint stability fixes
- `lib/specs/old/ghost_session_filtering_spec.md` — Phase 1 ghost filtering (complete)
- `lib/specs/old/1_visitor_session_tracking_spec.md` — visitor dedup and session model
- `lib/specs/incidents/2026-01-29-visit-count-inflation-5x.md` — Sec-Fetch navigation detection

### External Research
- Snowplow enrichment pipeline: [docs.snowplow.io/docs/pipeline/enrichments](https://docs.snowplow.io/docs/pipeline/enrichments/)
- Snowplow IAB enrichment: [docs.snowplow.io/docs/pipeline/enrichments/available-enrichments/iab-enrichment](https://docs.snowplow.io/docs/pipeline/enrichments/available-enrichments/iab-enrichment/)
- IAB/ABC Spiders & Bots List: [iab.com/guidelines/iab-abc-international-spiders-bots-list](https://www.iab.com/guidelines/iab-abc-international-spiders-bots-list/)
- DeviceDetector gem (Matomo): [github.com/podigee/device_detector](https://github.com/podigee/device_detector)
- Cloudflare Bot Management: [developers.cloudflare.com/bots/concepts/bot-score](https://developers.cloudflare.com/bots/concepts/bot-score/)
- Cloud provider IP ranges: [github.com/rezmoss/cloud-provider-ip-addresses](https://github.com/rezmoss/cloud-provider-ip-addresses)
- Amplitude server-side sessions: [amplitude.com/docs/data/sources/instrument-track-sessions](https://amplitude.com/docs/data/sources/instrument-track-sessions)
- Mixpanel automatic sessions: [docs.mixpanel.com/docs/features/sessions](https://docs.mixpanel.com/docs/features/sessions)
- Plausible accuracy vs GA4: [plausible.io/most-accurate-web-analytics](https://plausible.io/most-accurate-web-analytics)
- GA4 bot filtering limitations: [analyticsdetectives.com/blog/bot-traffic-and-filtering-in-ga4](https://analyticsdetectives.com/blog/bot-traffic-and-filtering-in-ga4)
