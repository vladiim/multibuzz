# mbuzz Business Rules

> The definitive reference for every rule mbuzz enforces. Written for anyone -- technical or not -- who needs to understand exactly how the system behaves.

**Last Updated:** 2026-03-12

---

## Table of Contents

1. [Visitors](#1-visitors)
2. [Sessions](#2-sessions)
3. [Channel Classification](#3-channel-classification)
4. [Events](#4-events)
5. [Conversions](#5-conversions)
6. [Attribution](#6-attribution)
7. [Identity and Cross-Device](#7-identity-and-cross-device)
8. [Bot Detection](#8-bot-detection)
9. [Billing and Usage](#9-billing-and-usage)
10. [Data Retention and Privacy](#10-data-retention-and-privacy)
11. [API and Authentication](#11-api-and-authentication)

---

## 1. Visitors

A **visitor** represents one anonymous person on one device.

### Rules

| # | Rule | Detail |
|---|------|--------|
| V1 | Every visitor gets a unique identifier | A 64-character random string, stored in a cookie called `_mbuzz_vid` |
| V2 | Visitor cookies last 2 years | After 2 years of no visits, the cookie expires and the visitor is treated as new |
| V3 | One visitor = one device | The same person on their phone and laptop is two visitors until they are identified (see [Identity](#7-identity-and-cross-device)) |
| V4 | Visitors are created on first session | The first time someone visits your site, the SDK calls the session endpoint, which creates both the visitor and the session |
| V5 | Visitors must exist before events are accepted | If an event arrives for a visitor that doesn't exist in the system, it is rejected. This prevents orphaned data. |
| V6 | Visitors are deduplicated by fingerprint | If two requests arrive with different visitor IDs but the same device fingerprint (same IP + same browser), the system detects this and merges them |

### Example

> Sarah visits your store for the first time on her laptop. mbuzz creates Visitor A with a unique ID and sets a cookie. Two months later, she returns on the same laptop -- the cookie is still there, so she's recognized as Visitor A. She also browses on her phone -- that's Visitor B (a separate device). When she logs in on her phone, her identity links Visitors A and B together.

---

## 2. Sessions

A **session** represents a single visit -- from when a visitor arrives until they leave or go idle.

### Rules

| # | Rule | Detail |
|---|------|--------|
| S1 | Sessions have a 30-minute inactivity timeout | If a visitor does nothing for 30 minutes, the session ends. Any new activity starts a new session. |
| S2 | Sessions use a sliding window | The 30-minute timer resets with every action. A visitor who clicks every 20 minutes stays in the same session indefinitely. |
| S3 | New traffic source = new session | If a visitor arrives from a different marketing channel (new UTM parameters, different referrer, different ad click), a new session starts even if the previous one is still active. This ensures each session has a single, clear channel attribution. |
| S4 | Sessions are resolved server-side | The server computes a device fingerprint from IP address + browser user agent: `SHA256(ip|user_agent)` truncated to 32 characters. This fingerprint, combined with the 30-minute window, determines session boundaries. |
| S5 | One session = one channel | A session is classified into exactly one marketing channel at creation time. This never changes. |
| S6 | Sessions capture the landing page | The URL of the first page in the session is stored, including all query parameters (UTM tags, click IDs, etc.) |
| S7 | Sessions capture the referrer | The website that sent the visitor (if any) is stored for channel classification |
| S8 | Sessions use advisory locks for concurrency | When multiple requests arrive simultaneously for the same visitor (e.g., the page loads multiple resources), a database lock ensures only one session is created, not duplicates |

### What Starts a New Session

| Condition | New Session? | Why |
|-----------|-------------|-----|
| First visit ever | Yes | No existing session |
| Returned after 30+ minutes idle | Yes | Previous session timed out |
| Arrived from new UTM parameters | Yes | Different marketing campaign |
| Arrived from a new ad click (gclid, fbclid, etc.) | Yes | Different paid channel interaction |
| Arrived from a different external referrer | Yes | Different traffic source |
| Same visitor, same source, within 30 minutes | No | Continues existing session |
| Internal page navigation (same site) | No | Same visit continues |

### Example

> Monday 2:00 PM: Jane clicks a Google Ad. Session 1 starts (channel: paid_search).
> Monday 2:15 PM: Jane browses 3 product pages. Session 1 continues (within 30 min).
> Monday 4:00 PM: Jane returns by typing the URL directly. Session 2 starts (channel: direct, 30+ min gap).
> Monday 4:05 PM: Jane clicks a link in her email. Session 3 starts (channel: email, new traffic source even though Session 2 is active).

---

## 3. Channel Classification

Every session is classified into exactly one of 12 marketing channels. Classification happens automatically based on a strict priority hierarchy.

### The 12 Channels

| Channel | Description | Examples |
|---------|------------|---------|
| `paid_search` | Paid advertisements on search engines | Google Ads, Microsoft Ads (Bing) |
| `organic_search` | Free (unpaid) search engine results | Google organic, DuckDuckGo |
| `paid_social` | Paid advertisements on social platforms | Facebook Ads, Instagram Ads, LinkedIn Ads, TikTok Ads |
| `organic_social` | Free social media traffic | Shared links on Twitter, Facebook, LinkedIn |
| `email` | Traffic from email campaigns | Newsletters, promotional emails, transactional emails |
| `display` | Banner and visual display advertising | Google Display Network, programmatic ads |
| `affiliate` | Traffic from affiliate/partner programs | Commission-based referral partners |
| `referral` | Traffic from other websites (not social/search) | Blog mentions, press articles, directory listings |
| `video` | Traffic from video platforms | YouTube, Vimeo |
| `ai` | Traffic from AI assistants and tools | ChatGPT, Perplexity, Claude |
| `direct` | No identifiable external source | Typed URL, bookmarks, app links |
| `other` | Identified source that doesn't fit any category | Unusual or unrecognized traffic |

### Classification Priority (Highest to Lowest)

The system checks signals in this exact order. The first match wins.

**Priority 1: Click Identifiers** (most reliable)

When someone clicks an ad, the ad platform appends a unique identifier to the URL. These are impossible to fake and always indicate a paid click.

| Click ID | Platform | Channel |
|----------|----------|---------|
| `gclid` | Google Ads | paid_search |
| `gbraid`, `wbraid` | Google Ads (iOS) | paid_search |
| `msclkid` | Microsoft Ads | paid_search |
| `fbclid` | Meta (Facebook/Instagram) | paid_social |
| `ttclid` | TikTok Ads | paid_social |
| `li_fat_id` | LinkedIn Ads | paid_social |
| `twclkid` | Twitter/X Ads | paid_social |
| `ScCid` | Snapchat Ads | paid_social |
| `rdt_cid` | Reddit Ads | paid_social |
| `epik` | Pinterest Ads | paid_social |
| `qclid` | Quora Ads | paid_social |
| `dclid` | Google Display & Video 360 | display |
| `yclid` | Yandex Direct | paid_search |
| `s_kwcid` | Adobe Advertising | paid_search |
| `sxsrf` | Google Search (signed) | organic_search |
| `irclickid` | Impact Radius (affiliate) | affiliate |
| `sscid` | ShareASale (affiliate) | affiliate |

**Priority 2: UTM Medium**

If no click ID is present, the system looks at `utm_medium` (a tag marketers add to URLs).

| utm_medium contains | Channel |
|--------------------|---------|
| `cpc`, `ppc`, `paid_search`, `sea` | paid_search |
| `organic` | organic_search |
| `paid_social`, `social_paid`, `paidsocial` | paid_social |
| `social`, `social_organic` | organic_social |
| `email`, `e-mail`, `newsletter` | email |
| `display`, `banner`, `cpm` | display |
| `affiliate`, `partner` | affiliate |
| `referral` | referral |
| `video` | video |

**Priority 3: UTM Source (no medium)**

If only `utm_source` is present (no `utm_medium`), the system infers the channel from the source name.

| utm_source matches | Channel |
|-------------------|---------|
| google, bing, yahoo, duckduckgo, baidu, yandex | organic_search |
| facebook, instagram, twitter, linkedin, tiktok, pinterest, reddit, snapchat | organic_social |
| youtube, vimeo | video |
| chatgpt, perplexity, claude | ai |

**Priority 4: Referrer Domain**

If no UTM parameters are present, the system checks the referring website against a database of known domains (synced daily from open-source referrer databases).

| Referrer matches | Channel |
|-----------------|---------|
| google.com, bing.com, yahoo.com, duckduckgo.com, etc. | organic_search |
| facebook.com, twitter.com, linkedin.com, instagram.com, etc. | organic_social |
| youtube.com, vimeo.com | video |
| chatgpt.com, perplexity.ai | ai |
| Any other external domain | referral |
| Your own domain (internal referrer) | direct |

**Priority 5: Direct (fallback)**

If none of the above signals are present -- no UTM tags, no click IDs, no external referrer -- the session is classified as `direct`.

### Examples

| Scenario | URL / Referrer | Channel | Why |
|----------|---------------|---------|-----|
| Google Ad click | `?gclid=abc123` | paid_search | Click ID takes priority |
| Facebook Ad with UTM | `?fbclid=xyz&utm_medium=social` | paid_social | Click ID beats UTM |
| Email campaign | `?utm_medium=email&utm_source=mailchimp` | email | UTM medium match |
| Google organic search | referrer: `google.com/search` | organic_search | Referrer domain match |
| Typed URL directly | no referrer, no UTM | direct | Fallback |
| Blog post link | referrer: `techcrunch.com` | referral | External referrer, not in known lists |

---

## 4. Events

An **event** is any action a visitor takes -- a page view, a button click, a form submission, or any custom action you define.

### Rules

| # | Rule | Detail |
|---|------|--------|
| E1 | Events require a visitor | Every event must include a visitor ID. Events for unknown visitors are rejected (see V5). |
| E2 | Events are processed in batches | The API accepts arrays of events in a single request for efficiency |
| E3 | Events are enriched server-side | The server extracts and adds: URL components (host, path), UTM parameters, referrer information, anonymized IP address |
| E4 | Events are attached to sessions | Each event is linked to the visitor's active session. If the visitor has no active session, server-side resolution creates or finds one based on the device fingerprint. |
| E5 | Events carry custom properties | Any key-value data can be attached to an event (product ID, price, category, etc.). Maximum 50KB per event. |
| E6 | Events are immutable | Once stored, events are never modified or deleted (append-only) |
| E7 | Event timestamps can be provided by the client | If no timestamp is sent, the server uses the current time |

### Event Types

Events can be any string you choose. Common conventions:

| Event Type | Description |
|-----------|-------------|
| `page_view` | Visitor viewed a page |
| `add_to_cart` | Added a product to cart |
| `checkout_started` | Began checkout process |
| `form_submitted` | Submitted a form |
| `signup` | Created an account |
| `login` | Logged into an account |
| *(any custom name)* | Whatever makes sense for your business |

---

## 5. Conversions

A **conversion** is a business outcome you want to measure and attribute. Conversions are special -- they trigger the attribution engine.

### Rules

| # | Rule | Detail |
|---|------|--------|
| C1 | Conversions are explicitly tracked | You decide what counts as a conversion and send it via the API. mbuzz does not guess. |
| C2 | Conversions have a type | A string label like "purchase", "signup", "trial_start". You can have as many types as you need. |
| C3 | Conversions can carry revenue | A numeric value (e.g., $99.00) and currency code. Revenue is distributed to channels proportionally to attribution credit. |
| C4 | Conversions are idempotent | Each conversion can include a unique `idempotency_key`. Sending the same key twice returns the existing conversion -- no double-counting. |
| C5 | Conversions trigger attribution | After a conversion is recorded, attribution calculation runs automatically in the background. Results appear in the dashboard within seconds. |
| C6 | Conversions support acquisition tracking | A conversion can be marked as the "acquisition" conversion for a user (the first time they became a customer). Later conversions can inherit this attribution, enabling lifetime value analysis. |
| C7 | Conversions require a visitor | The system must be able to link the conversion to a visitor, either by visitor ID, event ID, or fingerprint fallback (within 30 seconds). |

### Conversion Resolution Chain

When a conversion arrives, the system finds the associated visitor using this chain:

1. **By event ID** -- if the conversion references a specific event, use that event's visitor
2. **By visitor ID** -- if a visitor ID is provided directly
3. **By fingerprint fallback** -- if IP and user agent are provided, compute the fingerprint and find the visitor who was active within the last 30 seconds

### Acquisition and Recurring Revenue

For SaaS and subscription businesses, mbuzz supports linking recurring revenue back to the original customer acquisition:

**Step 1:** Track the signup as an acquisition conversion:
```
conversion_type: "signup", user_id: "user_123", is_acquisition: true
```

**Step 2:** Track monthly payments with inherited attribution:
```
conversion_type: "payment", user_id: "user_123", revenue: $49.00, inherit_acquisition: true
```

When a payment inherits acquisition attribution, the system:
1. Finds the user's original signup conversion
2. Copies the attribution credits from that conversion
3. Recalculates revenue distribution based on the payment amount

This enables reporting like "Paid Search acquired customers worth $12,000 in lifetime value" vs "Email acquired customers worth $8,000 in lifetime value."

---

## 6. Attribution

Attribution is the process of distributing credit for a conversion across the marketing touchpoints that influenced it.

### Core Concepts

**Journey:** The ordered sequence of sessions (touchpoints) a visitor had before converting, within the lookback window.

**Touchpoint:** One session = one touchpoint. A session where the visitor came from Google Organic is one touchpoint, regardless of how many pages they viewed in that session.

**Credit:** A number between 0.0 and 1.0 representing what fraction of the conversion a touchpoint receives.

**Constraint:** All credits for a conversion must sum to exactly 1.0 (with one exception: the Participation model).

### Rules

| # | Rule | Detail |
|---|------|--------|
| A1 | Attribution is session-based | Each session counts as one touchpoint, regardless of how many events happened within it |
| A2 | Lookback window is configurable | Default: 90 days. Only sessions within this window before the conversion are considered. |
| A3 | Credits must sum to 1.0 | For all models except Participation, the total credit across all touchpoints equals exactly 1.0. Enforced with a tolerance of 0.0001. |
| A4 | All active models run for every conversion | When a conversion happens, all enabled attribution models calculate credits simultaneously. This allows instant model comparison. |
| A5 | Attribution runs asynchronously | Calculation happens in a background job. The conversion API returns immediately. |
| A6 | Direct sessions are burst-deduplicated | If a visitor has multiple "direct" sessions within a 5-minute window, they are collapsed into one touchpoint. This prevents inflated direct traffic from page refreshes. |
| A7 | Revenue is distributed proportionally | If a conversion has $100 revenue and a channel gets 0.4 credit, that channel receives $40 in revenue credit. |
| A8 | Attribution can be recalculated | When new information arrives (identity linking, model changes), attribution is automatically recalculated. |

### The 7 Attribution Models

#### First Touch

All credit goes to the first touchpoint in the journey.

> Google Organic -> Facebook Ad -> Email -> **Purchase**
> Result: Google Organic = 100%

**Use when:** You want to understand which channels discover new customers.

#### Last Touch

All credit goes to the last touchpoint before conversion.

> Google Organic -> Facebook Ad -> Email -> **Purchase**
> Result: Email = 100%

**Use when:** You want to understand which channels close deals.

#### Linear

Equal credit to every touchpoint.

> Google Organic -> Facebook Ad -> Email -> **Purchase**
> Result: Google Organic = 33.3%, Facebook Ad = 33.3%, Email = 33.3%

**Use when:** You want a balanced, unbiased view with no assumptions about position value.

#### Time Decay

More credit to touchpoints closer to the conversion. Uses a 7-day half-life: a touchpoint 7 days before conversion gets half the weight of one at conversion time, 14 days gets a quarter, etc.

> Google Organic (14 days ago) -> Facebook Ad (7 days ago) -> Email (today) -> **Purchase**
> Result: Google Organic = 14.3%, Facebook Ad = 28.6%, Email = 57.1%

**Use when:** You believe recent interactions matter more than older ones. Good for short buying cycles.

#### U-Shaped (Position-Based)

40% to the first touchpoint, 40% to the last, 20% split evenly among the middle.

> Google Organic -> Facebook Ad -> Referral -> Email -> **Purchase**
> Result: Google Organic = 40%, Facebook Ad = 10%, Referral = 10%, Email = 40%

**Use when:** You value both customer discovery and deal closing, but believe the middle interactions matter less.

#### Participation

Every unique channel that appeared in the journey gets 100% credit. Credits can sum to more than 1.0.

> Google Organic -> Facebook Ad -> Google Organic -> Email -> **Purchase**
> Result: Google Organic = 100%, Facebook Ad = 100%, Email = 100% (3 channels, 300% total)

**Use when:** You want to understand total channel reach and involvement, without worrying about splitting credit.

#### Markov Chain

A statistical model that calculates each channel's importance by asking: "What would happen to the overall conversion rate if we completely removed this channel from all customer journeys?"

Channels that appear in many converting paths and whose removal would most reduce conversions get the most credit.

**Requirements:** At least 500 conversions and 5 channels for statistically meaningful results.

**Use when:** You have enough data and want a mathematically rigorous, data-driven attribution that reflects your specific business patterns.

#### Shapley Value

Based on game theory (the same math that won a Nobel Prize in Economics). Calculates each channel's "fair" contribution by examining every possible combination of channels and measuring each channel's marginal impact.

**Requirements:** Same as Markov Chain -- 500+ conversions recommended.

**Use when:** You want the most theoretically fair distribution of credit, where each channel gets credit based on its actual marginal contribution.

### Attribution Example -- Complete Walkthrough

**Scenario:** Jane's journey to purchasing a $100 product.

| Day | Action | Channel |
|-----|--------|---------|
| Day 1 | Clicked Google Ad, browsed products | Paid Search |
| Day 5 | Saw Facebook retargeting ad, added to cart | Paid Social |
| Day 8 | Opened promotional email, completed purchase | Email |

**Results by Model:**

| Model | Paid Search | Paid Social | Email |
|-------|------------|-------------|-------|
| First Touch | $100 (100%) | $0 (0%) | $0 (0%) |
| Last Touch | $0 (0%) | $0 (0%) | $100 (100%) |
| Linear | $33.33 (33%) | $33.33 (33%) | $33.33 (33%) |
| Time Decay | $16 (16%) | $28 (28%) | $56 (56%) |
| U-Shaped | $40 (40%) | $20 (20%) | $40 (40%) |

**The insight:** First Touch says "Paid Search drove this sale." Last Touch says "Email drove this sale." The truth is all three channels worked together. Multi-model comparison reveals the full picture.

---

## 7. Identity and Cross-Device

**Identity** connects anonymous visitors to known users, enabling attribution across multiple devices.

### Rules

| # | Rule | Detail |
|---|------|--------|
| I1 | Identity is created on identification | When you call the identify endpoint with a user ID, the system creates or updates an Identity record |
| I2 | Traits are deep-merged | Each identify call merges new traits with existing ones. Sending `{plan: "pro"}` doesn't erase `{email: "jane@example.com"}`. |
| I3 | Visitor-Identity linking is permanent | Once a visitor is linked to an identity, the link persists. One identity can have multiple visitors. |
| I4 | Linking triggers reattribution | When a new visitor is linked to an identity that already has other visitors with conversions, attribution is automatically recalculated to include touchpoints from the new visitor. |
| I5 | Identity linking is bidirectional in time | Past sessions from the newly-linked visitor count toward existing conversions. Future sessions also count. |

### Cross-Device Example

> **Before identification:**
> - Visitor A (laptop): 3 sessions over 2 weeks
> - Visitor B (phone): 2 sessions over 1 week
> - These are treated as two separate people
>
> **Jane logs in on her phone (Visitor B is linked to Identity "jane@example.com"):**
> - Visitor B's sessions are now attributed to Jane
>
> **Jane logs in on her laptop (Visitor A is also linked to "jane@example.com"):**
> - Visitor A's sessions are merged with Visitor B's
> - Jane's full journey now spans 5 sessions across 2 devices
> - Any conversions are recalculated with the combined journey

---

## 8. Bot Detection

mbuzz automatically detects and filters bot traffic to ensure clean data.

### Rules

| # | Rule | Detail |
|---|------|--------|
| B1 | Known bot patterns are matched against user agent strings | A database of known bot signatures (crawlers, scrapers, monitoring tools) is synced daily from community-maintained lists |
| B2 | No-signals heuristic catches unknown bots | Sessions with no JavaScript signals, no referrer, no cookies, and suspicious patterns are flagged |
| B3 | Suspected bot sessions are marked, not deleted | Sessions get a `suspect: true` flag and a reason (e.g., "known_bot", "no_signals"). The data is preserved for auditing. |
| B4 | Bot sessions are excluded from all dashboard metrics | The `.qualified` scope on session queries automatically filters out suspected bot traffic |
| B5 | Bot patterns are updated daily | Pattern databases sync from Matomo and Crawler User Agents projects |

---

## 9. Billing and Usage

### Rules

| # | Rule | Detail |
|---|------|--------|
| BL1 | Usage is tracked per session, event, and conversion | Each account has monthly limits based on their plan |
| BL2 | Usage checks happen at ingestion time | Before processing a session, event, or conversion, the system checks if the account is within its plan limits |
| BL3 | Over-limit requests receive a billing blocked response | The API returns a 202 status with `billing_blocked: true` rather than a hard error, so SDK integrations don't crash |
| BL4 | Usage counters are cache-backed | Real-time counting uses the cache for performance, with periodic database reconciliation |

---

## 10. Data Retention and Privacy

### Rules

| # | Rule | Detail |
|---|------|--------|
| P1 | IP addresses are anonymized | The last octet of IPv4 addresses is zeroed (e.g., 192.168.1.100 becomes 192.168.1.0) |
| P2 | Events are immutable | Once written, event data is never modified. This creates a reliable audit trail. |
| P3 | All data is account-isolated | Every database query is scoped to the requesting account. Account A cannot see Account B's data under any circumstances. |
| P4 | API keys are stored as hashes | The actual key value is never stored. Only its SHA256 digest is kept for authentication matching. |
| P5 | Visitor data has no PII by default | Visitor records contain only a random ID and device fingerprint. No names, emails, or personal data unless explicitly provided via the identify endpoint. |
| P6 | Custom properties have size limits | JSONB fields (event properties, UTM data, identity traits) are capped at 50KB to prevent abuse |

---

## 11. API and Authentication

### Rules

| # | Rule | Detail |
|---|------|--------|
| AP1 | Authentication uses Bearer tokens | Every API request must include an `Authorization: Bearer sk_...` header |
| AP2 | API keys have environment separation | Test keys (`sk_test_...`) and live keys (`sk_live_...`) access separate data pools |
| AP3 | Rate limiting is per-account | Requests are throttled at the account level to prevent abuse |
| AP4 | SDKs must never crash the host application | All errors are caught and logged. The SDK returns false on failure, never raises exceptions. |
| AP5 | The API is non-blocking | Ingestion endpoints return 202 (Accepted) immediately. Processing happens asynchronously in the background. |
| AP6 | Sessions must be created before events | SDKs must call the session endpoint before tracking events. This is enforced server-side (see V5). |

### Edge Ingest Proxy

| # | Rule | Detail |
|---|------|--------|
| AP7 | SDKs send to the edge proxy by default | The primary endpoint is `api.mbuzz.co`, a Cloudflare Worker that durably stores payloads in R2 before forwarding to Rails. |
| AP8 | The direct endpoint is a permanent fallback | `mbuzz.co/api/v1` remains available forever. SDKs can be configured to use it directly. It is not deprecated. |
| AP9 | The proxy returns full Rails responses | When Rails is up (99%+), the proxy forwards synchronously and returns the Rails response verbatim. When Rails is down, the proxy returns a simplified `202 { "status": "accepted", "request_id": "..." }`. |
| AP10 | Replay preserves dependency order | The replay worker processes pending payloads in order: sessions → events → conversions → identify. This ensures visitors exist before events reference them. |

### Idempotency

| # | Rule | Detail |
|---|------|--------|
| ID1 | Ingestion endpoints support idempotency keys | The proxy sends an `X-Idempotency-Key` header with each forwarded request. Rails uses this to prevent duplicate processing during replay. |
| ID2 | Duplicate requests return the original result | If a session, event, or conversion with the same `request_id` already exists for the account, the service returns the existing record instead of creating a new one. |
| ID3 | Idempotency is optional | Requests without an `X-Idempotency-Key` header are processed normally. Direct API calls and older SDK versions are unaffected. |
| ID4 | Conversions use `idempotency_key` param | Conversions already had an `idempotency_key` field before the proxy. The `X-Idempotency-Key` header serves as a fallback if the param is not set. |

### The Four API Endpoints

| Endpoint | Purpose | When to Call |
|----------|---------|-------------|
| `POST /api/v1/sessions` | Create a visitor and session | On every new page navigation |
| `POST /api/v1/events` | Track actions and page views | On custom events (clicks, form submits, etc.) |
| `POST /api/v1/conversions` | Record business outcomes | On purchase, signup, trial start, etc. |
| `POST /api/v1/identify` | Link visitor to known user | On login, signup, or when user ID becomes available |

### Request Flow

```
1. Visitor lands on your site
   |
   v
2. SDK calls POST /sessions
   --> Server creates Visitor + Session
   --> Classifies channel from URL + referrer
   --> Returns session confirmation
   |
   v
3. Visitor takes actions
   --> SDK calls POST /events for each action
   --> Server enriches and stores events
   |
   v
4. Visitor converts (purchase, signup, etc.)
   --> SDK calls POST /conversions
   --> Server records conversion
   --> Attribution engine runs in background
   --> Credits distributed across touchpoints
   |
   v
5. (Optional) Visitor logs in
   --> SDK calls POST /identify
   --> Server links visitor to identity
   --> Cross-device journeys unified
   --> Attribution recalculated if needed
```

---

## Related Documentation

- [Product Overview](PRODUCT.md) -- High-level explanation of what mbuzz is and how it works
- [API Contract](sdk/api_contract.md) -- Technical API reference with request/response formats
- [Attribution Methodology](architecture/attribution_methodology.md) -- Mathematical formulas for all 7 models
- [Channel Classification](architecture/channel_vs_utm_attribution.md) -- Technical details on channel derivation
- [Session Intelligence](architecture/session_intelligence.md) -- Bot detection architecture and roadmap
