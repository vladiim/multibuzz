# mbuzz -- Marketing Attribution Platform

---

## What is mbuzz?

mbuzz answers the question every marketer asks: **"Which of my marketing efforts are actually working?"**

When a customer buys your product, they didn't just appear out of nowhere. Maybe they first found you through a Google search. A week later, they clicked a Facebook ad. Then they opened an email, and finally made the purchase. Each of those interactions is a **touchpoint** -- a moment where your marketing influenced their decision.

mbuzz tracks every touchpoint across every channel, connects them into a complete customer journey, and uses mathematical models to determine how much credit each channel deserves for each sale. This is called **multi-touch attribution**.

---

## Who is mbuzz for?

**Marketing teams** who spend money across multiple channels (Google Ads, Facebook, email, SEO, affiliates) and need to know which investments are driving revenue.

**Product and growth teams** who want to understand how users discover and move through their product.

**Business owners** who want data-driven answers to "Where should I spend my next marketing dollar?"

mbuzz is designed for companies with websites and web applications -- e-commerce stores, SaaS products, marketplaces, and media businesses.

---

## The Problem mbuzz Solves

Modern marketing is fragmented. A single customer might interact with your brand across a dozen channels before converting. Traditional analytics tools give you two bad options:

1. **Last-click attribution** -- give all the credit to whatever the customer clicked right before buying. This over-values channels that close deals (like email) and under-values channels that introduce new customers (like paid ads or content marketing).

2. **First-click attribution** -- give all the credit to whatever first brought the customer to your site. This over-values discovery channels and ignores everything that happened after.

Neither tells the full story. The truth is: multiple channels worked together. mbuzz gives you the full picture.

---

## How It Works

### 1. Tracking

mbuzz provides lightweight SDKs (small code libraries) for your website or application. These SDKs are available for Ruby, Node.js, Python, PHP, and Google Tag Manager. They work invisibly in the background.

When someone visits your site, mbuzz:

- **Identifies the visitor** using a persistent cookie (lasting 2 years)
- **Creates a session** that captures where they came from -- which ad they clicked, which search brought them, which email link they followed
- **Classifies the channel** automatically: was this paid search, organic search, social media, email, or something else?
- **Tracks events** like page views, button clicks, form submissions, or any custom actions you define

All of this happens server-side. The intelligence lives on mbuzz's servers, not in the browser. This means it works consistently across all platforms and can't be defeated by ad blockers or browser privacy features that break client-side tracking.

### 2. Session Resolution

This is where mbuzz is fundamentally different from tools like Google Analytics.

When a visitor arrives, mbuzz computes a **device fingerprint** from their IP address and browser information. This fingerprint, combined with a 30-minute activity window, lets mbuzz maintain accurate sessions without relying on browser cookies for session tracking.

**What a session captures:**
- Landing page URL
- UTM parameters (the tracking tags marketers add to links, like `utm_source=google`)
- Click identifiers from 18 ad platforms (Google, Meta, Microsoft, TikTok, LinkedIn, and more)
- Referrer (the website that linked to you)
- Marketing channel (automatically classified from all of the above)

**Session rules:**
- A session stays active as long as the visitor does something at least every 30 minutes
- A new session starts when the visitor arrives from a new traffic source (different UTM parameters, different referrer, different ad click)
- Bot traffic is automatically detected and filtered out

### 3. Channel Classification

Every session is classified into one of 12 marketing channels:

| Channel | What It Means | Example |
|---------|--------------|---------|
| **Paid Search** | Paid ads on search engines | Google Ads, Bing Ads |
| **Organic Search** | Free search engine results | Someone Googled your brand |
| **Paid Social** | Paid ads on social platforms | Facebook Ads, Instagram Ads, LinkedIn Ads |
| **Organic Social** | Free social media traffic | Someone shared your link on Twitter |
| **Email** | Email campaigns | Newsletter, promotional email |
| **Display** | Banner and display ads | Google Display Network |
| **Affiliate** | Affiliate partner referrals | Commission-based partners |
| **Referral** | Links from other websites | Blog post linking to you |
| **Video** | Video platform traffic | YouTube |
| **AI** | Traffic from AI tools | ChatGPT, Perplexity |
| **Direct** | No identifiable source | Typed URL directly, bookmarked |
| **Other** | Doesn't fit any category | Unusual traffic sources |

Classification follows a strict priority order. The most reliable signal wins:

1. **Click identifiers** (highest reliability) -- if someone clicked a Google ad, the `gclid` parameter proves it
2. **UTM parameters** -- marketing tags added to campaign URLs
3. **Referrer domain** -- the website that sent the visitor
4. **Direct** (fallback) -- no signal available

### 4. Conversions

A **conversion** is any business outcome you want to measure: a purchase, a signup, a trial start, a form submission. You define what counts as a conversion.

When a conversion happens, mbuzz:

1. Looks back through the visitor's history (default: 90 days)
2. Collects every session they had during that period
3. Builds a **journey** -- the ordered sequence of marketing touchpoints that led to the conversion
4. Runs attribution models to distribute credit

Conversions can carry a revenue value (e.g., "$99.00 purchase") which gets distributed to channels proportionally to their attribution credit.

### 5. Attribution Models

This is the core of mbuzz. When a customer converts after touching 5 different channels, how do you divide the credit?

mbuzz offers 8 attribution models. Each answers the question differently:

**Simple Models (rule-based):**

| Model | How It Works | Best For |
|-------|-------------|----------|
| **First Touch** | 100% credit to the channel that first brought the customer | Understanding which channels discover new customers |
| **Last Touch** | 100% credit to the last channel before conversion | Understanding which channels close deals |
| **Linear** | Equal credit to every channel in the journey | A balanced, unbiased view |
| **Time Decay** | More credit to channels closer to the conversion | Businesses with short buying cycles |
| **U-Shaped** | 40% to first channel, 40% to last, 20% split among middle | Valuing both discovery and closing |
| **Participation** | 100% credit to every channel involved | Understanding total channel reach |

**Advanced Models (data-driven):**

| Model | How It Works | Best For |
|-------|-------------|----------|
| **Markov Chain** | Mathematically calculates what would happen if a channel were removed from all journeys | Large datasets (500+ conversions) where you want statistical rigor |
| **Shapley Value** | Game theory approach: calculates each channel's fair contribution based on all possible combinations | The most mathematically fair distribution |

All 8 models run for every conversion simultaneously. You can switch between models instantly in the dashboard to see how the story changes. This is the real power -- no single model is "right." Comparing them reveals the truth.

### 6. Cross-Device Attribution

People use multiple devices. Someone might browse on their phone during lunch, then buy on their laptop at home.

When a user is **identified** (through login, signup, or any identifier you provide), mbuzz links their devices together. From that point:

- All past sessions from both devices are combined into one journey
- All future sessions are attributed to the same person
- Attribution is automatically recalculated to include the full cross-device journey

### 7. Dashboard and Reporting

The mbuzz dashboard provides:

- **Channel performance** -- which channels drive the most conversions and revenue, under any attribution model
- **Time series** -- how channel performance changes over time
- **Conversion funnels** -- where users drop off in your buying process, segmented by channel
- **Customer lifetime value (CLV)** -- cohort analysis showing long-term value by acquisition channel
- **Journey explorer** -- the most common paths customers take to conversion
- **Real-time event feed** -- live stream of events as they happen
- **CSV exports** -- download any report for further analysis

Everything updates in real time. No waiting for data processing.

---

## Key Concepts Glossary

| Term | Definition |
|------|-----------|
| **Visitor** | An anonymous person interacting with your site, identified by a persistent cookie |
| **Session** | A single visit, bounded by a 30-minute inactivity timeout |
| **Touchpoint** | A session with a marketing channel -- the building block of attribution |
| **Journey** | The complete sequence of touchpoints leading to a conversion |
| **Conversion** | A business outcome you want to measure (purchase, signup, etc.) |
| **Channel** | A category of marketing effort (paid search, email, organic, etc.) |
| **Attribution Credit** | The fraction of a conversion assigned to a channel (0.0 to 1.0) |
| **Attribution Model** | The mathematical rule for distributing credit across touchpoints |
| **Lookback Window** | How far back in time to consider touchpoints (default: 90 days) |
| **Identity** | A known user linked to one or more visitors (enables cross-device tracking) |
| **Device Fingerprint** | A hash of IP + browser info used for session resolution |
| **UTM Parameters** | Tracking tags on URLs (utm_source, utm_medium, utm_campaign) |

---

## What Makes mbuzz Different

**Server-side intelligence.** Most analytics tools run in the browser. mbuzz runs on the server. This means accurate session management, bot detection that actually works, and tracking that survives ad blockers.

**Multi-model comparison.** Most tools give you one attribution model. mbuzz runs all 8 simultaneously. Compare first-touch and last-touch side by side. See how Markov chain differs from linear. The truth emerges from the differences.

**Privacy-first design.** IP addresses are anonymized. No personal data is stored unless you explicitly identify users. Cookie-based tracking respects browser settings. Server-side processing means no third-party scripts loading on your site.

**Lightweight integration.** One SDK, a few lines of code. The SDK sends events; the server does all the thinking. No complex client-side configuration, no tag management headaches.

**Built for developers.** Clean REST API. SDKs in 5 languages. Webhook notifications. CSV exports. Everything is API-accessible and automatable.

---

## Architecture at a Glance

```
Your Website / App
    |
    |  SDK sends events (sessions, page views, conversions)
    v
mbuzz API (4 endpoints)
    |
    +--> Session Resolution (visitor + session + channel classification)
    |
    +--> Event Storage (TimescaleDB -- optimized for time-series data)
    |
    +--> Conversion Detection --> Attribution Engine (8 models, runs async)
    |
    +--> Dashboard (real-time charts, channel performance, funnels, CLV)
```

The entire system is built on Ruby on Rails 8, PostgreSQL with TimescaleDB for time-series performance, and uses no external dependencies like Redis -- everything runs on the database (Solid Stack architecture).

---

## Related Documentation

- [Business Rules](BUSINESS_RULES.md) -- Detailed rules for every system behavior
- [API Contract](sdk/api_contract.md) -- Technical API reference for SDK developers
- [Attribution Methodology](architecture/attribution_methodology.md) -- Deep dive into attribution math
- [Channel Classification](architecture/channel_vs_utm_attribution.md) -- How channels are derived
