# Ad Spend Intelligence Specification

**Date:** 2026-02-13
**Priority:** P0
**Status:** Draft
**Branch:** `feature/ad-spend-intelligence`

---

## Step Zero: Google Ads API Setup

> This is the boring prerequisite that blocks everything else. It's bureaucratic, time-gated, and has non-obvious gotchas. Start this **before writing any code** so approval timelines don't block development.

### What You Need Before Anything

| Prerequisite | What | How |
|---|---|---|
| **MCC account** | A Google Ads *manager* account (not a regular advertiser account). The API Center lives here. | Create free at [ads.google.com/home/tools/manager-accounts](https://ads.google.com/home/tools/manager-accounts/) |
| **GCP project** | Any Google Cloud project to hold OAuth credentials | [console.cloud.google.com/projectcreate](https://console.cloud.google.com/projectcreate) |
| **Privacy policy URL** | Required for the OAuth consent screen. Must be on a domain you control. | Host at `mbuzz.co/privacy` (already exists) |
| **Google account** | Admin access to both the MCC and GCP project | Use the Multibuzz service account |

### Setup Steps (Do These in Order)

#### 1. Create MCC + Get Developer Token (5 min, instant)

1. Sign into MCC at [ads.google.com](https://ads.google.com)
2. Navigate to **Admin → API Center**
3. Your developer token is displayed — it starts in **pending** status (test account access only)
4. Create a **test account** under the MCC: Accounts → Sub-account → Create → "Create a test account"

> **If you can't find API Center**: You're in a regular Google Ads account, not an MCC. The API Center only exists in manager accounts.

#### 2. Enable Google Ads API in GCP (2 min, instant)

1. Go to [console.cloud.google.com/apis/library/googleads.googleapis.com](https://console.cloud.google.com/apis/library/googleads.googleapis.com)
2. Select the Multibuzz GCP project
3. Click **Enable**

#### 3. Configure OAuth Consent Screen (15 min, triggers review)

This is where the first gotcha lives.

1. Go to [console.cloud.google.com/apis/credentials/consent](https://console.cloud.google.com/apis/credentials/consent)
2. Choose **External** (our customers connect their own accounts)
3. Fill in: app name, support email, `mbuzz.co` domain, privacy policy URL
4. Add scope: `https://www.googleapis.com/auth/adwords` — this is **sensitive**, triggering Google's verification review
5. Add test users (your email, team emails — max 100 while in Testing status)

> **GOTCHA: 7-day refresh token expiry.** While the consent screen is in "Testing" status (before verification), refresh tokens expire after 7 days. Your integration will silently break weekly. This is the #1 surprise. Budget for regenerating tokens during development, or build a re-auth utility.

#### 4. Create OAuth2 Credentials (5 min, instant)

1. Go to [console.cloud.google.com/apis/credentials](https://console.cloud.google.com/apis/credentials)
2. Click **+ CREATE CREDENTIALS → OAuth client ID**
3. Type: **Web application**
4. Authorized redirect URI: `https://mbuzz.co/oauth/google_ads/callback` (production) + `http://localhost:3000/oauth/google_ads/callback` (development)
5. Save the **Client ID** and **Client Secret** to Rails credentials:

```bash
bin/rails credentials:edit
# Add:
# google_ads:
#   client_id: "xxx.apps.googleusercontent.com"
#   client_secret: "GOCSPX-xxx"
#   developer_token: "xxx"
```

#### 5. Apply for Basic Access (5 min, then wait 2-7 business days)

1. In MCC → API Center, click **Apply for Basic Access**
2. Describe the use case specifically: *"Read-only integration. We pull campaign performance metrics (cost, impressions, clicks) via the Campaign reporting resource for marketing attribution. We do not create, edit, or manage campaigns."*
3. Submit

> **Common rejection reasons**: Vague descriptions ("we use the API for marketing"), no working website, or anything that sounds like automated ad management. Be specific about read-only reporting.

#### 6. Submit OAuth Consent Screen for Verification (triggers 2-6 week review)

1. In the OAuth consent screen settings, click **Publish App**
2. Google requires: a YouTube demo video showing the OAuth flow + how you use the data, domain verification, and privacy policy review
3. Respond to Google's follow-up emails promptly — your review pauses until you reply

### Timeline Reality

| Step | Time |
|---|---|
| MCC + developer token (test) | Instant |
| GCP setup + OAuth credentials | 30 minutes |
| **Development against test accounts** | **Immediate — start building now** |
| Basic access approval (real accounts) | 2-7 business days |
| OAuth consent screen verification (external users) | 2-6 weeks |
| **Production-ready** | **~3-6 weeks from kickoff** |

### Development Strategy

**Don't wait for approvals to start building.** The pending developer token + test account gives you full API access immediately. Build and test the entire integration against test accounts. Apply for Basic access and OAuth verification in parallel. By the time code is ready, approvals should be through.

| Phase | Access Level Needed |
|---|---|
| Phase 1-3 development | Test account access (instant) |
| Internal QA with real data | Basic access (2-7 days) |
| Customer-facing launch | Basic access + OAuth verification (2-6 weeks) |

> **Good news for us**: Multibuzz is **read-only** (we never write to ad accounts). This means: (1) Required Minimum Functionality rules likely don't apply, (2) Basic access is sufficient (low operation count), (3) Google's review is simpler for read-only apps.

---

## Summary

Connect ad platform spend data (starting with Google Ads) to mbuzz's multi-touch attribution, unlocking the metrics that answer "so what?" for MTA: attributed ROAS, CAC payback period, marginal ROAS curves, and budget reallocation recommendations. This transforms Multibuzz from "here's what drove conversions" to "here's how to spend your money better."

---

## The Problem

Multibuzz has excellent **attribution** -- we know which channels, campaigns, and touchpoints drive conversions. We have Markov chains, Shapley values, and heuristic models. We track CLV, recurring revenue, and cohorts.

But we're missing half the equation: **cost**.

Without cost data, users can't answer:

| Question | Requires |
|----------|----------|
| "What's my true ROAS on Google Ads?" | Ad spend + attributed revenue |
| "Which channel should I scale?" | Marginal ROAS by channel |
| "How long until this customer pays back?" | CAC + CLV over time |
| "What if I move 20% of Meta budget to Google?" | Response curves + scenario modeling |
| "Am I past the point of diminishing returns?" | Spend vs. conversion curve |

These are the questions CMOs, growth leads, and founders ask every day. Attribution without spend is an incomplete story. Spend intelligence completes it.

### Why This Is A Killer Feature

**For the market**: Triple Whale, Northbeam, Rockerbox all do this. It's table stakes for serious attribution platforms. Our open-source MTA models (Markov, Shapley) are differentiated -- but without spend integration, users export our data and do the math in spreadsheets.

**For retention**: Spend intelligence creates daily habit. Users check ROAS every morning. Attribution alone is checked weekly at best.

**For pricing**: This is the feature that justifies paid tiers. The data connection and compute justify real pricing.

---

## Current State

### What We Have

**Attribution data** (complete):
- 11 standardized channels: `paid_search`, `paid_social`, `organic_search`, `email`, `direct`, etc.
- `AttributionCredit` table: `channel`, `credit` (0.0-1.0), `revenue_credit`, `utm_source/medium/campaign`
- Multiple attribution models: First Touch, Last Touch, Linear, Time Decay, U-Shaped, Markov, Shapley
- CLV dashboard with cohort analysis and smiling curves
- Recurring revenue attribution via `is_acquisition` / `inherit_acquisition`

**Session data** (complete):
- UTM parameters extracted from landing URLs
- `gclid` captured when present (via click_ids on sessions)
- Channel classification from UTMs and referrers
- Device fingerprint-based session resolution

**What's missing**:
- No ad platform API connections
- No spend data anywhere in the system
- No ROAS, CAC, MER, or payback period calculations
- No budget recommendations or scenario modeling

### Data Flow (Current)

```
Visitor clicks ad → lands on site with ?gclid=xxx&utm_source=google&utm_medium=cpc
         ↓
SDK captures URL → POST /api/v1/sessions
         ↓
Server extracts UTMs → classifies channel as "paid_search"
         ↓
Conversion happens → attribution models distribute credit
         ↓
AttributionCredit: { channel: "paid_search", credit: 0.4, revenue_credit: $39.60 }
         ↓
Dashboard shows: "Paid Search drove 40% of this conversion's value"
         ↓
❌ Missing: "...and it cost $X to get that click, so ROAS is Y"
```

---

## Proposed Solution

### Core Insight: The Join

We don't need click-level GCLID matching (that's Google's game). We need **channel-level spend aggregation** joined with **channel-level attributed revenue**:

```
Attributed ROAS = Σ(revenue_credit WHERE channel = X) / Σ(ad_spend WHERE channel = X)
```

This works because:
1. Our channel taxonomy is standardized (11 channels)
2. Google Ads spend maps cleanly to `paid_search` (and optionally `display`, `video`)
3. UTM campaign data in `AttributionCredit` enables campaign-level ROAS drill-down
4. The join is a simple GROUP BY, not a complex click-level match

### Architecture

```
Google Ads API ──OAuth2──→ AdPlatformConnection (stores tokens)
       ↓
  Sync Job (daily + on-demand)
       ↓
  AdSpendRecord (date, channel, campaign, spend, impressions, clicks)
       ↓
  SpendIntelligence::MetricsService
       ↓
  Join: ad_spend_records ⟗ attribution_credits (on channel + date + campaign)
       ↓
  Dashboard: ROAS, CAC, Payback, Marginal ROAS, Recommendations
```

### Data Flow (Proposed)

```
[SPEND SIDE]                              [ATTRIBUTION SIDE]
Google Ads API                            Existing Multibuzz flow
     ↓                                          ↓
AdSpendRecord                             AttributionCredit
{ date, channel, campaign,                { channel, credit,
  spend, impressions, clicks }              revenue_credit, utm_campaign }
     ↓                                          ↓
     └──────────── JOIN on channel + date ──────┘
                         ↓
              SpendIntelligence::MetricsService
                         ↓
              { attributed_roas, cac, mer, payback_period,
                marginal_roas, recommendations }
```

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Join granularity | Channel + date (campaign drill-down) | Matches our channel-primary architecture. Campaign-level via utm_campaign secondary join. |
| Sync frequency | Daily (midnight UTC) + manual refresh | Google Ads data settles within 24-48h. More frequent creates false precision. |
| Historical backfill | 90 days on first connect | Enough for trend analysis and response curves without massive API load. |
| Monetary storage | `bigint` micros (1M = 1 currency unit) | Matches Google Ads API natively. Integer math is faster, avoids decimal rounding. Convert at display time only. |
| Multi-currency | Store in ad platform's native currency | Google API returns cost_micros in account currency. Phase 1 displays in native currency with label. Currency normalization is a Phase 2 concern requiring exchange rate API. |
| Google Ads hierarchy | Campaign-level aggregation | Ad Group and Ad level are too granular for attribution join. Campaign maps to utm_campaign. |
| OAuth scope | `https://www.googleapis.com/auth/adwords` (read-only) | We never write to their ad accounts. Read-only builds trust. |
| Channel mapping | Automatic via Google campaign type + network segment | Search → paid_search, Display → display, Video → video, Shopping → paid_search. PMax split by `segments.ad_network_type`. Configurable override. |
| Response curves | Hill saturation function, fitted in Ruby | Industry standard (PyMC-Marketing, Robyn). Pure Ruby via `matrix` stdlib — 3 parameters, ~50 data points, ~50 lines. Python sidecar deferred to ML attribution phase. |
| Token encryption | Rails `encrypts` (ActiveRecord Encryption) | Built into Rails 8. No gem needed. Non-deterministic AES-256-GCM. |
| Adapter pattern | `AdPlatforms::BaseAdapter` with platform-specific subclasses | Mirrors existing `Attribution::Algorithms` strategy pattern. Google first, Meta/TikTok/LinkedIn plug in identically. |

---

## Data Model

### New Tables

#### `ad_platform_connections`

OAuth connections to ad platforms. One per platform per account.

```ruby
create_table :ad_platform_connections do |t|
  t.references :account, null: false, foreign_key: true
  t.integer :platform, null: false            # enum: google_ads: 0, meta_ads: 1, linkedin_ads: 2, tiktok_ads: 3
  t.string :platform_account_id, null: false  # Google Ads Customer ID (no dashes)
  t.string :platform_account_name
  t.string :currency, limit: 3, null: false   # "USD", "AUD", etc.
  t.text :access_token                        # encrypted via Rails `encrypts`
  t.text :refresh_token                       # encrypted via Rails `encrypts`
  t.datetime :token_expires_at
  t.integer :status, null: false, default: 0  # enum: connected: 0, syncing: 1, error: 2, disconnected: 3
  t.datetime :last_synced_at
  t.string :last_sync_error
  t.jsonb :settings, default: {}              # channel_mapping overrides, sync preferences
  t.timestamps

  t.index [:account_id, :platform, :platform_account_id], unique: true,
    name: "idx_ad_connections_unique"
end
```

**Model** (`app/models/ad_platform_connection.rb`):

```ruby
class AdPlatformConnection < ApplicationRecord
  include AdPlatformConnection::Validations
  include AdPlatformConnection::Relationships
  include AdPlatformConnection::StatusManagement

  has_prefix_id :adcon

  encrypts :access_token
  encrypts :refresh_token

  enum :platform, { google_ads: 0, meta_ads: 1, linkedin_ads: 2, tiktok_ads: 3 }
  enum :status, { connected: 0, syncing: 1, error: 2, disconnected: 3 }
end
```

**Note**: This is the first use of `encrypts` in the codebase. Requires one-time setup:

```bash
bin/rails db:encryption:init
# Add output to config/credentials.yml.enc via:
bin/rails credentials:edit
```

#### `ad_spend_records`

Daily spend data per campaign. The atomic unit of spend intelligence. Standard PostgreSQL table — **not** a hypertable (daily aggregate data, modest volume: ~36K rows/year per 100 campaigns).

```ruby
create_table :ad_spend_records do |t|
  t.references :account, null: false, foreign_key: true
  t.references :ad_platform_connection, null: false, foreign_key: true
  t.date :spend_date, null: false
  t.string :channel, null: false              # Mapped to our channel taxonomy (Channels::ALL)
  t.string :platform_campaign_id, null: false # Google's campaign ID
  t.string :campaign_name, null: false
  t.string :campaign_type                     # SEARCH, DISPLAY, VIDEO, SHOPPING, PERFORMANCE_MAX
  t.string :network_type                      # For PMax: SEARCH, DISPLAY, VIDEO, CROSS_NETWORK
  t.bigint :spend_micros, null: false, default: 0  # 1,000,000 = 1 currency unit
  t.string :currency, limit: 3, null: false
  t.bigint :impressions, null: false, default: 0
  t.bigint :clicks, null: false, default: 0
  t.bigint :platform_conversions_micros, null: false, default: 0  # Google's own count × 1M
  t.bigint :platform_conversion_value_micros, null: false, default: 0
  t.boolean :is_test, default: false, null: false
  t.timestamps

  t.index [:account_id, :spend_date, :channel], name: "idx_spend_channel_date"
  t.index [:account_id, :ad_platform_connection_id, :spend_date, :platform_campaign_id],
    unique: true, name: "idx_spend_unique"
  t.index [:account_id, :channel, :spend_date], name: "idx_spend_date_range"
  t.index [:is_test], name: "index_ad_spend_records_on_is_test"
end
```

**Model** (`app/models/ad_spend_record.rb`):

```ruby
class AdSpendRecord < ApplicationRecord
  include AdSpendRecord::Validations
  include AdSpendRecord::Relationships
  include AdSpendRecord::Scopes

  has_prefix_id :aspend

  MICRO_UNIT = 1_000_000

  def spend
    spend_micros.to_d / MICRO_UNIT
  end
end
```

#### `ad_spend_sync_runs`

Track each sync execution for observability and debugging.

```ruby
create_table :ad_spend_sync_runs do |t|
  t.references :ad_platform_connection, null: false, foreign_key: true
  t.date :sync_date, null: false
  t.integer :status, null: false, default: 0  # enum: pending: 0, running: 1, completed: 2, failed: 3
  t.integer :records_synced, default: 0
  t.string :error_message
  t.datetime :started_at
  t.datetime :completed_at
  t.timestamps

  t.index [:ad_platform_connection_id, :sync_date], name: "idx_sync_runs_connection_date"
end
```

### Campaign-to-Channel Mapping

Google Ads campaigns map to our channels. Defined as a constant (mirrors `ClickIdentifiers::CHANNEL_MAP` pattern):

```ruby
# app/constants/ad_platform_channels.rb
module AdPlatformChannels
  # Google Ads campaign.advertising_channel_type → Multibuzz channel
  GOOGLE_CAMPAIGN_TYPE_MAP = {
    "SEARCH"          => Channels::PAID_SEARCH,
    "DISPLAY"         => Channels::DISPLAY,
    "VIDEO"           => Channels::VIDEO,
    "SHOPPING"        => Channels::PAID_SEARCH,
    "DEMAND_GEN"      => Channels::PAID_SOCIAL,
    "LOCAL"           => Channels::PAID_SEARCH
  }.freeze

  # Performance Max splits by segments.ad_network_type
  GOOGLE_NETWORK_TYPE_MAP = {
    "SEARCH"          => Channels::PAID_SEARCH,
    "CONTENT"         => Channels::DISPLAY,
    "YOUTUBE_SEARCH"  => Channels::VIDEO,
    "YOUTUBE_WATCH"   => Channels::VIDEO,
    "CROSS_NETWORK"   => Channels::PAID_SEARCH  # Default for mixed
  }.freeze
end
```

| Google Campaign Type | Default Channel | Notes |
|---------------------|----------------|-------|
| SEARCH | `paid_search` | Direct mapping |
| DISPLAY | `display` | Direct mapping |
| VIDEO | `video` | Direct mapping |
| SHOPPING | `paid_search` | Direct mapping |
| PERFORMANCE_MAX | **Split by network** | Uses `segments.ad_network_type` to distribute spend across channels accurately |
| DEMAND_GEN | `paid_social` | Direct mapping |

Users can override per-campaign in settings. Stored in `ad_platform_connections.settings`:

```json
{
  "channel_overrides": {
    "campaign_12345": "display",
    "campaign_67890": "paid_social"
  }
}
```

### UTM Campaign Matching

For campaign-level ROAS drill-down, we match:

```
ad_spend_records.campaign_name ↔ attribution_credits.utm_campaign
```

This relies on users having consistent UTM tagging. We provide guidance in onboarding:

> **Recommended Google Ads tracking template:**
> `{lpurl}?utm_source=google&utm_medium=cpc&utm_campaign={campaignname}&utm_content={adgroupid}&utm_term={keyword}`

---

## Metric Calculations

### Core Metrics

| Metric | Formula | Notes |
|--------|---------|-------|
| **Attributed ROAS** | `Σ(revenue_credit) / Σ(spend)` per channel per date range | Uses selected attribution model |
| **Platform ROAS** | `platform_conversion_value / spend` per campaign | Google's own number, for comparison |
| **Blended ROAS** | `total_revenue / total_spend` across all channels | The single most trusted number |
| **MER** | `total_business_revenue / total_marketing_spend` | Includes organic revenue in numerator |
| **Attributed CAC** | `Σ(spend) / COUNT(conversions WHERE credit > 0)` per channel | Cost per attributed conversion |
| **NCAC** | Same as CAC but only `is_acquisition` conversions | New customer acquisition cost |
| **Payback Period** | Days until `cumulative_clv >= ncac` per acquisition cohort | Requires CLV data (existing) |
| **Marginal ROAS** | `∂(revenue) / ∂(spend)` at current spend level | Derivative of response curve |

### Attributed ROAS Calculation (Detail)

**Performance note**: `attribution_credits` has no date column — date filtering joins through `conversions.converted_at`. For accounts with 100K+ conversions, this join gets slow. We address this with a materialized view (see below).

```ruby
# Follows existing Dashboard::Scopes + Dashboard::Queries pattern
module SpendIntelligence
  module Scopes
    class SpendScope
      def initialize(account:, date_range:, channels: Channels::ALL, test_mode: false)
        @account = account
        @date_range = date_range
        @channels = channels
        @test_mode = test_mode
      end

      def call
        account.ad_spend_records
          .then { |scope| test_mode ? scope.where(is_test: true) : scope.where(is_test: false) }
          .where(spend_date: date_range)
          .then { |scope| channels == Channels::ALL ? scope : scope.where(channel: channels) }
      end

      private

      attr_reader :account, :date_range, :channels, :test_mode
    end
  end
end
```

**Channel metrics query** (consolidated — ROAS, CAC, MER are methods, not separate classes):

```ruby
module SpendIntelligence
  module Queries
    class ChannelMetricsQuery
      def initialize(spend_scope:, credits_scope:)
        @spend_scope = spend_scope
        @credits_scope = credits_scope
      end

      def call
        channels.map { |channel| build_channel_metrics(channel) }
      end

      private

      def build_channel_metrics(channel)
        spend = channel_spend[channel] || 0
        revenue = channel_revenue[channel] || 0
        {
          channel: channel,
          spend_micros: spend,
          attributed_revenue: revenue,
          roas: spend.positive? ? revenue / MoneyMicros.from_micros(spend) : nil,
          impressions: channel_impressions[channel] || 0,
          clicks: channel_clicks[channel] || 0
        }
      end

      def channel_spend
        @channel_spend ||= @spend_scope.call.group(:channel).sum(:spend_micros)
      end

      def channel_revenue
        @channel_revenue ||= @credits_scope.call.group(:channel).sum(:revenue_credit)
      end

      def channel_impressions
        @channel_impressions ||= @spend_scope.call.group(:channel).sum(:impressions)
      end

      def channel_clicks
        @channel_clicks ||= @spend_scope.call.group(:channel).sum(:clicks)
      end
    end
  end
end
```

### Performance: Materialized View for Daily Attributed Revenue

To avoid the `attribution_credits → conversions` join on every dashboard load, create a materialized view (or continuous aggregate in production):

```sql
CREATE MATERIALIZED VIEW channel_revenue_daily AS
SELECT
  ac.account_id,
  ac.attribution_model_id,
  ac.channel,
  DATE(c.converted_at) AS day,
  SUM(ac.revenue_credit) AS total_revenue_credit,
  COUNT(DISTINCT ac.conversion_id) AS conversion_count
FROM attribution_credits ac
JOIN conversions c ON c.id = ac.conversion_id
WHERE ac.is_test = false
GROUP BY ac.account_id, ac.attribution_model_id, ac.channel, DATE(c.converted_at);

CREATE UNIQUE INDEX idx_channel_revenue_daily_unique
ON channel_revenue_daily (account_id, attribution_model_id, channel, day);
```

Refresh daily alongside the spend sync. ROAS query then becomes: `channel_revenue_daily.total_revenue_credit / ad_spend_records.spend_micros` — no joins at query time.

### Response Curve Model (Hill Function)

For marginal ROAS and budget optimization, we fit a **Hill saturation function** per channel:

```
Revenue(spend) = K * (spend^S) / (spend^S + EC50^S)
```

Where:
- `K` = maximum revenue (asymptote)
- `S` = steepness (Hill coefficient)
- `EC50` = spend level at half-max revenue

**Marginal ROAS** at any spend level = derivative of this curve:

```
mROAS(spend) = K * S * EC50^S * spend^(S-1) / (spend^S + EC50^S)^2
```

When mROAS > 1.0, additional spend is profitable. When mROAS < 1.0, you've hit diminishing returns.

**Fitting**: Pure Ruby via `matrix` stdlib — 3 parameters, ~50 data points, ~50 lines of code. OLS regression on log-transformed weekly (spend, revenue) pairs. Minimum 12 weeks of data for stable fit. Confidence intervals via bootstrapping. Python sidecar deferred to ML attribution phase.

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| **No connections** | `ad_platform_connections.empty?` | Show empty state with "Connect Google Ads" CTA |
| **Connecting** | OAuth in progress | Show loading state, redirect back on completion |
| **Syncing** | `status: :syncing` | Show "Syncing historical data..." with progress |
| **Connected, no data yet** | `ad_spend_records.empty?` | Show "Data syncing, check back in a few minutes" |
| **Connected, with data** | Happy path | Full dashboard with all metrics |
| **Sync error** | `status: :error` | Show error banner with retry button and error detail |
| **Token expired** | `token_expires_at < Time.current` | Auto-refresh via refresh_token. If fails, prompt re-auth |
| **Partial data** | Recent dates missing (< 48h old) | Show "Preliminary" badge on recent data |
| **Data discrepancy** | Attributed ROAS differs >50% from Platform ROAS | Show info tooltip explaining why discrepancies occur |
| **Insufficient data for curves** | < 12 weeks of spend data | Show metrics but disable "Recommendations" and "Scenario Modeling" tabs |
| **Multi-currency** | Account currency differs from ad platform | Display in ad platform's native currency with label (e.g., "AUD $1,200"). Currency normalization deferred to Phase 2. |
| **Disconnected** | User disconnects | Retain historical data, show "Reconnect" button |

---

## Dashboard UX

### Information Hierarchy

**Tier 1: Hero Metrics** (glanceable, answers "are we on track?")

```
┌─────────────────────────────────────────────────────────────────────┐
│  Spend Intelligence            [Google Ads ✓ Connected]             │
│  Date: [Last 30 days ▼]  Model: [Linear ▼]  [Refresh ↻]          │
│                                                                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐│
│  │Blended   │ │ Total    │ │Attributed│ │  NCAC    │ │  MER     ││
│  │ROAS      │ │ Spend    │ │Revenue   │ │          │ │          ││
│  │ 3.2x     │ │ $24,500  │ │ $78,400  │ │  $47     │ │  4.1x    ││
│  │ ▲ +0.3   │ │ ▲ +12%   │ │ ▲ +18%   │ │ ▼ -$3    │ │ ▲ +0.2   ││
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

**Tier 2: Trend + Channel Breakdown**

```
┌─────────────────────────────────────────────────────────────────────┐
│  [ROAS Trend]                           [Channel Performance]       │
│  ┌────────────────────────────┐        ┌──────────────────────────┐│
│  │ Spend ········              │        │ Channel    │Spend │ ROAS ││
│  │ ROAS  ────────              │        │ paid_search│$12.4K│ 4.1x ││
│  │                             │        │ paid_social│$ 8.2K│ 2.8x ││
│  │ 5x│     ╱──────            │        │ display    │$ 2.1K│ 1.4x ││
│  │ 3x│ ───╱                   │        │ video      │$ 1.8K│ 1.9x ││
│  │ 1x│╱                       │        │                          ││
│  │   └──────────────────       │        │ [Expand to campaign ▶]   ││
│  │   W1  W2  W3  W4           │        └──────────────────────────┘│
│  └────────────────────────────┘                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Tier 3: Deep Analysis Tabs**

```
[Overview] [Payback Period] [Recommendations] [Scenarios]
```

### Payback Period View

```
┌─────────────────────────────────────────────────────────────────────┐
│  Payback Period by Acquisition Channel                              │
│                                                                     │
│  ┌────────────────────────────┐  ┌────────────────────────────────┐│
│  │ Time to Payback             │  │ Channel     │ NCAC │ Payback  ││
│  │ Rev/                        │  │ organic     │  $0  │ Day 1    ││
│  │ Cust                        │  │ paid_search │ $47  │ 2.1 mo   ││
│  │ $60│        ╱───────        │  │ paid_social │ $62  │ 4.7 mo   ││
│  │    │     ╱──  ╱─────        │  │ display     │ $84  │ 7.2 mo   ││
│  │ $40│──╱────╱──              │  │ video       │ $71  │ 5.8 mo   ││
│  │    │╱───╱──  ← NCAC line   │  └────────────────────────────────┘│
│  │ $20│╱──                     │                                    │
│  │   └──────────────────       │  Payback = when cumulative CLV    │
│  │   M0  M1  M2  M3  M6  M12  │  exceeds NCAC for that channel    │
│  └────────────────────────────┘                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Recommendations View (Scale / Chill / Kill)

```
┌─────────────────────────────────────────────────────────────────────┐
│  Budget Recommendations          Based on last 30 days              │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ SCALE ▲                                                       │  │
│  │ paid_search  │ ROAS 4.1x │ mROAS 2.8x │ +$3K recommended    │  │
│  │              │ Still climbing the curve. Room to grow.        │  │
│  ├───────────────────────────────────────────────────────────────┤  │
│  │ MAINTAIN ─                                                    │  │
│  │ paid_social  │ ROAS 2.8x │ mROAS 1.2x │ Hold steady         │  │
│  │              │ Approaching saturation. Current spend optimal. │  │
│  ├───────────────────────────────────────────────────────────────┤  │
│  │ REDUCE ▼                                                      │  │
│  │ display      │ ROAS 1.4x │ mROAS 0.6x │ -$500 recommended   │  │
│  │              │ Past diminishing returns. Shift to search.     │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  Note: Recommendations based on 12 weeks of data.                  │
│  Confidence: moderate (wider range with more data).                │
└─────────────────────────────────────────────────────────────────────┘
```

### Scenario Modeling View

```
┌─────────────────────────────────────────────────────────────────────┐
│  Budget Scenario Modeling                                           │
│                                                                     │
│  Total Monthly Budget: [$24,500 ▼]                                 │
│                                                                     │
│  Channel      │ Current │ Proposed │ Est. Revenue │ Est. ROAS      │
│  paid_search  │ $12,400 │ [$15,400]│  $67,200     │  4.4x          │
│  paid_social  │  $8,200 │ [$ 6,200]│  $18,600     │  3.0x          │
│  display      │  $2,100 │ [$ 1,600]│   $2,400     │  1.5x          │
│  video        │  $1,800 │ [$ 1,300]│   $2,600     │  2.0x          │
│  ─────────────┼─────────┼──────────┼──────────────┼────────────────│
│  TOTAL        │ $24,500 │  $24,500 │  $90,800     │  3.7x          │
│                                     │  ▲ +$12,400  │  ▲ +0.5x       │
│                                                                     │
│  [Response Curves]                                                  │
│  ┌────────────────────────────────────────────────────────────────┐│
│  │ Rev │    ╱──── paid_search                                     ││
│  │     │  ╱──── paid_social                                       ││
│  │     │╱── display                                               ││
│  │     │  ● = current spend  ○ = proposed                         ││
│  │     └──────────────────────────── Spend →                      ││
│  └────────────────────────────────────────────────────────────────┘│
│                                                                     │
│  Confidence range: $85,200 - $96,400 (80% interval)               │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Platform Adapter Interface

All ad platform integrations implement a common adapter interface. This mirrors the existing `Attribution::Algorithms` strategy pattern:

```ruby
# app/services/ad_platforms/base_adapter.rb
module AdPlatforms
  class BaseAdapter
    def initialize(connection)
      @connection = connection
    end

    def fetch_spend(date_range:)
      raise NotImplementedError
    end

    def refresh_token!
      raise NotImplementedError
    end

    def validate_connection
      raise NotImplementedError
    end

    private

    attr_reader :connection
  end
end
```

```ruby
# app/services/ad_platforms/google/adapter.rb
module AdPlatforms
  module Google
    class Adapter < BaseAdapter
      def fetch_spend(date_range:)
        SpendSyncService.new(connection, date_range: date_range).call
      end

      def refresh_token!
        OauthService.new(connection).refresh!
      end

      def validate_connection
        OauthService.new(connection).validate!
      end
    end
  end
end
```

Platform-specific adapters (Meta, TikTok, LinkedIn) implement the same interface. The sync job is adapter-agnostic:

```ruby
adapter = AdPlatforms.adapter_for(connection)  # Returns Google::Adapter, Meta::Adapter, etc.
adapter.fetch_spend(date_range: 3.days.ago..Date.current)
```

---

## Google Ads API Integration

### Authentication

**OAuth2 Web Application Flow**:
1. User clicks "Connect Google Ads" in settings
2. Generate cryptographic `state` parameter (CSRF protection), store in session
3. Redirect to Google OAuth consent screen
4. Scopes: `https://www.googleapis.com/auth/adwords` (read-only)
5. On callback, **verify `state` parameter matches session** before proceeding
6. Exchange code for access_token + refresh_token
7. Call `CustomerService.ListAccessibleCustomers` to get account list
8. User selects account(s) to connect
9. Store encrypted tokens in `ad_platform_connections` (via Rails `encrypts`)

**Token Refresh**: Access tokens expire after 1 hour. Refresh automatically before each API call. If refresh fails (revoked), set status to `:error` and prompt re-auth.

### Reporting API (GAQL)

Daily spend sync query (non-PMax campaigns):

```sql
SELECT
  campaign.id,
  campaign.name,
  campaign.advertising_channel_type,
  segments.date,
  metrics.cost_micros,
  metrics.impressions,
  metrics.clicks,
  metrics.conversions,
  metrics.conversions_value,
  customer.currency_code
FROM campaign
WHERE segments.date DURING LAST_90_DAYS
  AND campaign.status != 'REMOVED'
  AND metrics.cost_micros > 0
  AND campaign.advertising_channel_type != 'PERFORMANCE_MAX'
ORDER BY segments.date DESC
```

**Performance Max query** (separate, with network type segmentation):

```sql
SELECT
  campaign.id,
  campaign.name,
  campaign.advertising_channel_type,
  segments.date,
  segments.ad_network_type,
  metrics.cost_micros,
  metrics.impressions,
  metrics.clicks,
  metrics.conversions,
  metrics.conversions_value,
  customer.currency_code
FROM campaign
WHERE segments.date DURING LAST_90_DAYS
  AND campaign.status != 'REMOVED'
  AND metrics.cost_micros > 0
  AND campaign.advertising_channel_type = 'PERFORMANCE_MAX'
ORDER BY segments.date DESC
```

**Why two queries**: Adding `segments.ad_network_type` to non-PMax campaigns would unnecessarily split rows for single-channel campaign types. PMax is the only type that genuinely spans networks.

**Cost storage**: `cost_micros` is stored directly as `spend_micros` (bigint). No conversion needed at sync time — convert to display currency at read time only.

**Rate limits**: 10,000 requests/day per developer token. Our daily sync uses ~1 request per account. No concern.

### Data Freshness

Google Ads data for a given day is considered final after **48 hours**. For the most recent 2 days:
- Mark data as "Preliminary" in UI
- Re-sync last 3 days on each daily run to capture corrections

---

## Implementation Tasks

### Phase 1: Data Foundation

- [ ] **1.1** Run `bin/rails db:encryption:init` and add keys to credentials (first use of `encrypts` in codebase)
- [ ] **1.2** Create `ad_platform_connections` migration (integer enums, plain text columns for encrypted fields)
- [ ] **1.3** Create `ad_spend_records` migration (bigint micros, network_type, is_test)
- [ ] **1.4** Create `ad_spend_sync_runs` migration (sync tracking)
- [ ] **1.5** Create `AdPlatformConnection` model with concerns (Validations, Relationships, StatusManagement) + `encrypts :access_token, :refresh_token`
- [ ] **1.6** Create `AdSpendRecord` model with concerns (Validations, Relationships, Scopes)
- [ ] **1.7** Create `AdSpendSyncRun` model
- [ ] **1.8** Create `AdPlatformChannels` constant module (campaign type + network type maps)
- [ ] **1.9** Add `has_many :ad_platform_connections` to Account
- [ ] **1.10** Write model tests

### Phase 2: Google Ads OAuth

- [ ] **2.1** Register OAuth application with Google (developer token, OAuth client)
- [ ] **2.2** Create `AdPlatforms::BaseAdapter` interface (abstract: `fetch_spend`, `refresh_token`, `validate_connection`)
- [ ] **2.3** Create `AdPlatforms::Google::Adapter` implementing BaseAdapter
- [ ] **2.4** Create `AdPlatforms::Google::OauthService` (authorization URL with CSRF state param, token exchange, refresh)
- [ ] **2.5** Create `AdPlatformConnectionsController` (connect, callback with state verification, disconnect)
- [ ] **2.6** Create account selection flow (list accessible customers via `CustomerService.ListAccessibleCustomers`)
- [ ] **2.7** Create settings UI: "Integrations" page with Google Ads connection card
- [ ] **2.8** Write controller + service tests (including OAuth state CSRF verification)

### Phase 3: Spend Sync

- [ ] **3.1** Create `AdPlatforms::Google::SpendSyncService` (two GAQL queries: standard + PMax, upsert records, create sync run)
- [ ] **3.2** Create `AdPlatforms::Google::CampaignChannelMapper` (campaign type → channel, PMax network type splitting)
- [ ] **3.3** Create `AdPlatforms::SpendSyncSchedulerJob` (iterates `Account.active.find_each`, enqueues per-connection jobs — mirrors `DataIntegrity::SurveillanceSchedulerJob`)
- [ ] **3.4** Create `AdPlatforms::SpendSyncJob` (per-connection sync, wraps adapter call)
- [ ] **3.5** Add entry to `config/recurring.yml`: `ad_spend_sync: { class: AdPlatforms::SpendSyncSchedulerJob, schedule: at 4am every day }`
- [ ] **3.6** Implement 90-day historical backfill on first connect
- [ ] **3.7** Implement incremental daily sync (last 3 days for corrections)
- [ ] **3.8** Add manual "Refresh" button
- [ ] **3.9** Write sync service tests with mocked API responses

### Phase 4: Core Metrics

- [ ] **4.1** Create `SpendIntelligence::Scopes::SpendScope` (account, date_range, channels, test_mode)
- [ ] **4.2** Create `SpendIntelligence::Queries::ChannelMetricsQuery` (ROAS, CAC, MER as methods on one consolidated query class)
- [ ] **4.3** Create `SpendIntelligence::Queries::PaybackPeriodQuery` (integrates with CLV data)
- [ ] **4.4** Create `channel_revenue_daily` materialized view migration (with `return if Rails.env.test?`)
- [ ] **4.5** Create `SpendIntelligence::MetricsService` (aggregates all metrics for dashboard, delegates to scope + queries)
- [ ] **4.6** Write comprehensive metric tests

### Phase 5: Dashboard UI

- [ ] **5.1** Create `Dashboard::SpendIntelligenceController`
- [ ] **5.2** Create `_spend_hero_metrics.html.erb` partial (5 KPI cards)
- [ ] **5.3** Create `_spend_trend_chart.html.erb` (ROAS + spend time-series via Highcharts)
- [ ] **5.4** Create `_channel_performance_table.html.erb` (sortable table)
- [ ] **5.5** Create `_payback_period.html.erb` (chart + table)
- [ ] **5.6** Create empty state with onboarding CTA
- [ ] **5.7** Add data freshness badges ("Last synced", "Preliminary" labels)
- [ ] **5.8** Add "Attributed vs Platform" ROAS comparison column with tooltip
- [ ] **5.9** Write controller + view tests

### Phase 6: Response Curves + Recommendations

- [ ] **6.1** Create `SpendIntelligence::ResponseCurveService` (Hill function fitting per channel)
- [ ] **6.2** Create `SpendIntelligence::MarginalRoasQuery` (derivative at current spend)
- [ ] **6.3** Create `SpendIntelligence::RecommendationService` (Scale/Maintain/Reduce per channel)
- [ ] **6.4** Create `_recommendations.html.erb` partial
- [ ] **6.5** Write recommendation service tests

### Phase 7: Scenario Modeling

- [ ] **7.1** Create `SpendIntelligence::ScenarioService` (given proposed allocation, predict revenue)
- [ ] **7.2** Create `SpendIntelligence::BudgetOptimizerService` (given total budget, find optimal split)
- [ ] **7.3** Create `_scenario_modeling.html.erb` (interactive inputs + response curve chart)
- [ ] **7.4** Create Stimulus controller for interactive slider UX
- [ ] **7.5** Write optimizer service tests with edge cases

### Phase 8: Platform Expansion (Future)

- [ ] **8.1** Meta Ads integration (same pattern, different API)
- [ ] **8.2** TikTok Ads integration
- [ ] **8.3** LinkedIn Ads integration
- [ ] **8.4** Manual spend import (CSV upload for platforms without API)

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| AdPlatformConnection model | `test/models/ad_platform_connection_test.rb` | Validations, encryption round-trip, status enum, prefix_id |
| AdSpendRecord model | `test/models/ad_spend_record_test.rb` | Validations, scopes, spend_micros → spend conversion, prefix_id |
| AdSpendSyncRun model | `test/models/ad_spend_sync_run_test.rb` | Validations, status enum |
| AdPlatformChannels constant | `test/constants/ad_platform_channels_test.rb` | All campaign type mappings, PMax network type maps, override handling |
| Google Adapter | `test/services/ad_platforms/google/adapter_test.rb` | Implements BaseAdapter interface, API call delegation |
| OauthService | `test/services/ad_platforms/google/oauth_service_test.rb` | Auth URL with state param, token exchange, refresh, state verification |
| SpendSyncService | `test/services/ad_platforms/google/spend_sync_service_test.rb` | GAQL parsing, PMax network splitting, upsert logic, sync run tracking |
| CampaignChannelMapper | `test/services/ad_platforms/google/campaign_channel_mapper_test.rb` | All campaign types, PMax by network, user overrides |
| SpendScope | `test/services/spend_intelligence/scopes/spend_scope_test.rb` | Date range, channel filter, test_mode filter |
| ChannelMetricsQuery | `test/services/spend_intelligence/queries/channel_metrics_query_test.rb` | ROAS, CAC, MER calculations, zero-spend guard |
| PaybackPeriodQuery | `test/services/spend_intelligence/queries/payback_period_query_test.rb` | CLV integration, cohort grouping |
| ResponseCurveService | `test/services/spend_intelligence/response_curve_service_test.rb` | Hill function fit, marginal ROAS calc, insufficient data guard |
| RecommendationService | `test/services/spend_intelligence/recommendation_service_test.rb` | Scale/Maintain/Reduce thresholds |
| ScenarioService | `test/services/spend_intelligence/scenario_service_test.rb` | Prediction accuracy, confidence intervals |
| BudgetOptimizerService | `test/services/spend_intelligence/budget_optimizer_service_test.rb` | Optimal allocation, constraints |

### Integration Tests

| Test | Verifies |
|------|----------|
| OAuth flow | Full connect → callback → account selection → redirect |
| Sync job | Scheduled execution, idempotency, error handling |
| Dashboard render | All states (empty, loading, error, populated) |
| Multi-tenancy | Account A cannot see Account B's spend data |

### Manual QA

1. Connect a Google Ads test account
2. Verify historical sync completes with correct data
3. Verify daily sync captures new spend
4. Compare Attributed ROAS with manual calculation
5. Disconnect and verify data retained
6. Reconnect and verify no duplicate data

---

## Definition of Done

- [ ] Google Ads OAuth connect/disconnect working
- [ ] Daily spend sync running reliably
- [ ] Attributed ROAS matches manual calculation within 1%
- [ ] Dashboard shows all 5 hero metrics
- [ ] Channel breakdown table sortable and filterable
- [ ] Payback period integrates with existing CLV data
- [ ] Response curves fit with R^2 > 0.7 for channels with sufficient data
- [ ] Recommendations displayed with confidence indicators
- [ ] Scenario modeling produces realistic predictions
- [ ] All tests pass (unit + integration)
- [ ] Manual QA on dev with real Google Ads account
- [ ] Multi-tenancy verified
- [ ] Spec updated with final state

---

## Out of Scope

- **Click-level GCLID matching** -- We don't need to match individual clicks to conversions. Channel and campaign level aggregation is sufficient and more reliable.
- **Writing to ad platforms** -- We will never modify bids, budgets, or campaigns. Read-only always.
- **Real-time spend** -- Daily granularity is sufficient. Intra-day spend fluctuations aren't actionable.
- **Ad creative analysis** -- Which ad copy/image performs best is a different feature.
- **Offline conversion upload** -- Sending our attributed conversions back to Google Ads. Future consideration.
- **Automated budget execution** -- We recommend; humans decide. No auto-pilot.

---

## Methodology & Research

### Attributed ROAS vs. Platform ROAS

Platform-reported ROAS (what Google/Meta show) systematically overcounts because:
1. **View-through attribution**: Platforms count conversions from users who merely *saw* an ad
2. **Overlapping credit**: Multiple platforms claim credit for the same conversion
3. **Self-reporting bias**: The player is also the referee

Our attributed ROAS uses the user's chosen MTA model to distribute credit fairly. The discrepancy is expected and should be shown transparently.

### Marginal ROAS and Diminishing Returns

Every channel follows a saturation curve. Initial spend produces high returns, but each additional dollar produces less incremental revenue. The key concept:

**Average ROAS** (what most people track) ≠ **Marginal ROAS** (what determines if you should spend more).

A channel can have 4x average ROAS but 0.5x marginal ROAS -- meaning historically it's been profitable, but the next dollar spent will lose money. This is the insight that drives intelligent budget allocation.

### Response Curve Modeling (Hill Function)

The Hill function (logistic saturation curve) is the industry standard for modeling channel response:

```
f(x) = K * x^S / (x^S + EC50^S)
```

Where:
- `K` = saturation level (maximum achievable revenue from this channel)
- `S` = steepness (how quickly returns diminish)
- `EC50` = half-saturation point (spend level yielding half of maximum revenue)

This is the same model used by:
- **Meta's Robyn** (open-source MMM)
- **Google's Meridian** (successor to LightweightMMM)
- **PyMC-Marketing** (Bayesian MMM framework)

We fit this curve using 12+ weeks of weekly (spend, attributed_revenue) data points per channel. Bootstrap confidence intervals provide uncertainty bounds.

### Budget Optimization Theory

Given response curves for N channels and a total budget B, the optimal allocation is found by equalizing marginal ROAS across all channels (Lagrangian optimization). In practice, we use Sequential Least Squares Quadratic Programming (SLSQP) with constraints:

- Total budget constraint: `Σ(channel_spend) = B`
- Per-channel minimum: `channel_spend >= min_spend` (don't zero out any channel)
- Per-channel maximum: `channel_spend <= max_spend` (realistic scale limits)

---

## Sources

### Academic Papers
- Zhao et al. (2019) - "[A Unified Framework for Marketing Budget Allocation](https://arxiv.org/abs/1902.01128)" - KDD '19, Alibaba
- Jin et al. (2017) - "Bayesian Methods for Media Mix Modeling with Carryover and Shape Effects" - Google Research
- Wang et al. (2017) - "Deep Learning for Optimal Budget Allocation" - Criteo Research

### Open Source Tools
- [PyMC-Marketing](https://github.com/pymc-labs/pymc-marketing) - Bayesian MMM with budget optimization
- [Meta's Robyn](https://github.com/facebookexperimental/Robyn) - Automated MMM with response curves
- [Google's Meridian](https://github.com/google/meridian) - Successor to LightweightMMM
- [Meta's GeoLift](https://github.com/facebookincubator/GeoLift) - Incrementality testing

### Google Ads API
- [Google Ads API v22 Reference](https://developers.google.com/google-ads/api/fields/v22/campaign)
- [OAuth2 for Google Ads](https://developers.google.com/google-ads/api/docs/oauth/overview)
- [GAQL Query Language](https://developers.google.com/google-ads/api/docs/query/overview)
- [ListAccessibleCustomers](https://developers.google.com/google-ads/api/docs/account-management/listing-accounts)

### Industry Platforms (UX Research)
- [Triple Whale - Attribution Dashboard](https://kb.triplewhale.com/en/articles/6855429-attribution-dashboard-metrics-library)
- [Northbeam - Overview Page](https://docs.northbeam.io/docs/overview-page)
- [Rockerbox - Goals & Recommendations](https://help.rockerbox.com/article/wi5m1awn1v-optimizing-against-target-cpa-or-roas-goals)
- [Wicked Reports - Scale/Kill/Chill Framework](https://help.wickedreports.com/wicked-playbook-scale-kill-chill-framework)
- [Measured - Media Plan Optimizer](https://www.measured.com/blog/navigate-the-maze-of-budget-planning-with-media-plan-optimizer/)
- [Dashboard UX Patterns - Pencil & Paper](https://www.pencilandpaper.io/articles/ux-pattern-analysis-data-dashboards)

### Metric Methodology
- [Blended ROAS Explained - Requisite Reporting](https://www.requisitereporting.io/blog/why-blended-roas-is-the-only-number-you-should-trust)
- [Ad Response Curves 101 - Mutt Data](https://blog.muttdata.ai/post/2025-04-25-Ad-response-curves)
- [Diminishing Returns in Marketing - Recast](https://getrecast.com/diminishing-returns/)
- [CAC Payback Dashboard - Phoenix Strategy Group](https://www.phoenixstrategy.group/blog/building-cac-payback-dashboard-step-by-step-guide)
