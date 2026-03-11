# Ad Spend Intelligence Specification

**Date:** 2026-02-13
**Priority:** P0
**Status:** UAT
**Branch:** `feature/ad-spend-intelligence`

---

> **UAT UNBLOCKED** — 11 Mar 2026. Google Ads Basic Access approved. OAuth flow, MCC sub-account discovery, and sync pipeline are code-complete. Bugs found and fixed during earlier UAT attempt: API version `v18` → `v23`, session key serialization (symbol → string), MCC sub-account discovery via `customer_client` query, `login-customer-id` header propagation. **Next step: run the full UAT checklist in the Testing Strategy section against a live Google Ads account.**

---

## Step Zero: Google Ads API Setup

> **COMPLETED** — 2 Mar 2026. All setup steps done. Basic Access approved 11 Mar 2026. OAuth consent screen verification not yet submitted (requires working demo video first).

### Accounts & Credentials

| Resource | Value |
|---|---|
| **Google account** | vlad@mehakovic.com |
| **MCC account** | mbuzz — `652-093-6525` |
| **MCC sub-account** | mbuzz — `851-548-6033` |
| **Developer token** | `eXga_FDm2uazzjhgdlpwJw` (Explorer Access) |
| **GCP project** | mbuzz (`mbuzz-489003`) under mehakovic.com org |
| **OAuth client** | Web application, redirect URIs: `https://mbuzz.co/oauth/google_ads/callback` + `http://localhost:3000/oauth/google_ads/callback` |
| **OAuth consent screen** | External, Testing status, scope: `auth/adwords`, test user: vlad@mehakovic.com |
| **Rails credentials** | `google_ads.client_id`, `google_ads.client_secret`, `google_ads.developer_token` — added to development + production |

### Pending Approvals

| Approval | Status | Submitted | Expected |
|---|---|---|---|
| **Basic Access** | Approved | Mon 2 Mar 2026, 13:42 AEDT | Approved 11 Mar 2026 |
| **OAuth consent screen verification** | Not yet submitted | — | Submit after demo video (2-6 weeks review) |

### Gotchas Discovered

- **marketing@mbuzz.co Google account was auto-disabled** by Google's abuse detection (brand new account + custom domain + immediate Ads access). Appeal submitted. Using vlad@mehakovic.com instead.
- **Google Ads forces campaign creation wizard** when creating sub-accounts. Hit X to close, Discard the draft.
- **7-day refresh token expiry** while consent screen is in "Testing" status. Tokens will silently break weekly during development.

### Setup Steps Reference

<details>
<summary>Original setup steps (completed — click to expand)</summary>

#### 1. Create MCC + Get Developer Token (5 min, instant)

1. Sign into MCC at [ads.google.com](https://ads.google.com)
2. Navigate to **Admin → API Center**
3. Your developer token is displayed — it starts in **pending** status (test account access only)
4. Create a **test account** under the MCC: Accounts → Sub-account → Create → "Create a test account"

> **If you can't find API Center**: You're in a regular Google Ads account, not an MCC. The API Center only exists in manager accounts.

#### 2. Enable Google Ads API in GCP (2 min, instant)

1. Go to [console.cloud.google.com/apis/library/googleads.googleapis.com](https://console.cloud.google.com/apis/library/googleads.googleapis.com)
2. Select the mbuzz GCP project
3. Click **Enable**

#### 3. Configure OAuth Consent Screen (15 min, triggers review)

1. Go to [console.cloud.google.com/apis/credentials/consent](https://console.cloud.google.com/apis/credentials/consent)
2. Choose **External** (our customers connect their own accounts)
3. Fill in: app name (mbuzz), support email, `mbuzz.co` authorized domain, privacy policy URL
4. Add scope: `https://www.googleapis.com/auth/adwords` — this is **sensitive**, triggering Google's verification review
5. Add test users (vlad@mehakovic.com — max 100 while in Testing status)

> **GOTCHA: 7-day refresh token expiry.** While the consent screen is in "Testing" status (before verification), refresh tokens expire after 7 days. Your integration will silently break weekly. Budget for regenerating tokens during development, or build a re-auth utility.

#### 4. Create OAuth2 Credentials (5 min, instant)

1. Go to GCP → Google Auth Platform → Clients
2. Create OAuth client ID → **Web application**
3. Authorized redirect URIs: `https://mbuzz.co/oauth/google_ads/callback` + `http://localhost:3000/oauth/google_ads/callback`
4. Save Client ID and Client Secret to Rails credentials:

```bash
bin/rails credentials:edit
# Add:
# google_ads:
#   client_id: "xxx.apps.googleusercontent.com"
#   client_secret: "GOCSPX-xxx"
#   developer_token: "eXga_FDm2uazzjhgdlpwJw"
```

#### 5. Apply for Basic Access (5 min, then wait 2-7 business days)

1. In MCC → API Center, click **Apply for Basic Access**
2. Describe the use case: read-only reporting integration
3. Upload design document PDF
4. Submit

> **Common rejection reasons**: Vague descriptions ("we use the API for marketing"), no working website, or anything that sounds like automated ad management. Be specific about read-only reporting.

#### 6. Submit OAuth Consent Screen for Verification (triggers 2-6 week review)

1. In the OAuth consent screen settings, click **Publish App**
2. Google requires: a YouTube demo video showing the OAuth flow + how you use the data, domain verification, and privacy policy review
3. Respond to Google's follow-up emails promptly — your review pauses until you reply

</details>

### Timeline

| Step | Status |
|---|---|
| MCC + developer token (Explorer) | Done |
| GCP project + OAuth credentials | Done |
| Rails credentials (dev + prod) | Done |
| **Development against test accounts** | **Ready to start** |
| Basic access approval (real accounts) | Pending (~3 business days) |
| OAuth consent screen verification | Not yet submitted (needs demo video) |

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

## UX Placement

### Connection Management → Settings > Integrations (NEW)

New tab in account settings sidebar, between API Keys and Attribution:

```
General
Billing
Team
API Keys
Integrations  ← NEW (/account/integrations)
Attribution
```

The Integrations page shows platform cards:
- **Google Ads** card: Connect/Disconnect button, status dot (green/red), account name/ID, last synced, sync error if any
- **Coming Soon** cards (greyed out with "Notify Me" button): Meta Ads, TikTok Ads, LinkedIn Ads, Microsoft Ads (Bing), Pinterest Ads, Snapchat Ads, Reddit Ads, X (Twitter) Ads, Apple Search Ads, Phone/Call Tracking
- **CSV Import** card (coming soon): manual spend import for any platform
- **Request Integration** card: always-visible card at the bottom of the list, prompting users to request a platform we don't support yet

Connect flow:
1. User clicks "Connect Google Ads" → redirect to Google OAuth consent
2. User grants read-only access → callback to `/oauth/google_ads/callback`
3. Account picker: list accessible Google Ads accounts via `ListAccessibleCustomers` → user selects
4. `AdPlatformConnection` created (status: connected) → redirect back to Integrations
5. Background job: 90-day backfill starts (status: syncing)
6. Integrations page shows "Syncing historical data..." → completes in ~2-5 min

### Coming Soon Cards

Each upcoming platform gets a card on the Integrations page. Cards are greyed out with a **"Notify Me"** button instead of "Connect". Clicking "Notify Me" creates an `IntegrationRequestSubmission` (same model as the Request Integration form) with the platform name auto-populated — no form fields, single click.

```
┌─────────────────────────────────────────────────────────────────────┐
│  Ad Platforms                                                        │
│                                                                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐               │
│  │ Google   │ │ Meta     │ │ TikTok   │ │ LinkedIn │               │
│  │ Ads      │ │ Ads      │ │ Ads      │ │ Ads      │               │
│  │ ● Active │ │ Soon     │ │ Soon     │ │ Soon     │               │
│  │[Manage]  │ │[Notify]  │ │[Notify]  │ │[Notify]  │               │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘               │
│                                                                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐               │
│  │Microsoft │ │Pinterest │ │ Snapchat │ │ Reddit   │               │
│  │Ads (Bing)│ │ Ads      │ │ Ads      │ │ Ads      │               │
│  │ Soon     │ │ Soon     │ │ Soon     │ │ Soon     │               │
│  │[Notify]  │ │[Notify]  │ │[Notify]  │ │[Notify]  │               │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘               │
│                                                                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                            │
│  │ X (Twit) │ │Apple Ads │ │ Phone/   │                            │
│  │ Ads      │ │          │ │ Call     │                            │
│  │ Soon     │ │ Soon     │ │ Soon     │                            │
│  │[Notify]  │ │[Notify]  │ │[Notify]  │                            │
│  └──────────┘ └──────────┘ └──────────┘                            │
│                                                                      │
│  Data Import                                                         │
│  ┌──────────┐                                                       │
│  │ CSV      │                                                       │
│  │ Import   │                                                       │
│  │ Soon     │                                                       │
│  │[Notify]  │                                                       │
│  └──────────┘                                                       │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Don't see your platform?  [Request Integration →]           │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

**Coming Soon platforms** (ordered by priority):

| Platform | Category | Notes |
|----------|----------|-------|
| Meta Ads | Ad platform | API approval in progress |
| TikTok Ads | Ad platform | Deferred — fast approval when ready |
| LinkedIn Ads | Ad platform | API access submitted 5 Mar 2026 |
| Microsoft Ads (Bing) | Ad platform | Similar API to Google, easy build |
| Pinterest Ads | Ad platform | High value for e-commerce/DTC |
| Snapchat Ads | Ad platform | Younger demographics |
| Reddit Ads | Ad platform | Growing fast for SaaS/tech |
| X (Twitter) Ads | Ad platform | Declining but some B2B spend |
| Apple Search Ads | Ad platform | iOS app marketers |
| Phone/Call Tracking | Data source | Call tracking providers (CallRail, etc.) — spec separately |
| CSV Import | Data import | Manual upload for any platform — zero API overhead |

**"Notify Me" behavior:**
1. User clicks "Notify Me" → POST `/account/integrations/notify` with `platform_name` param
2. Creates `IntegrationRequestSubmission` with platform name auto-populated, no other fields
3. Button changes to "Notified ✓" (disabled state) — persisted via checking existing submission
4. Same duplicate check as Request Integration form (same email + platform = already notified)
5. Counts as demand signal in admin dashboard alongside full Request Integration submissions

### Request Integration

Below the coming-soon cards, a persistent "Request Integration" link opens a contact form for platforms not listed. This serves two purposes: (1) users feel heard, (2) we get demand signal to prioritize platform expansion (Phase 8).

#### User-Facing Form

The card sits below the coming-soon cards on the Integrations page, always visible regardless of connection state:

```
┌─────────────────────────────────────────────────────────────────────┐
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  🔌  Don't see your platform?                                │   │
│  │                                                              │   │
│  │  Platform  [Select platform      ▼]                          │   │
│  │            ○ Microsoft Ads (Bing)                             │   │
│  │            ○ Pinterest Ads                                    │   │
│  │            ○ Snapchat Ads                                     │   │
│  │            ○ Amazon Ads                                       │   │
│  │            ○ Twitter/X Ads                                    │   │
│  │            ○ Reddit Ads                                       │   │
│  │            ○ Other (specify below)                            │   │
│  │                                                              │   │
│  │  Monthly ad spend   [$___________]   (optional — helps       │   │
│  │                                        us prioritize)        │   │
│  │                                                              │   │
│  │  Anything else?     [___________]   (optional free text)     │   │
│  │                                                              │   │
│  │  [Request Integration]                                       │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

**Form fields:**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `platform_name` | Select (dropdown) | Yes | Predefined options + "Other" |
| `platform_name_other` | Text | Only if "Other" selected | Free text for unlisted platforms |
| `monthly_spend` | Select (dropdown) | No | Ranges: "Under $1K", "$1K–$10K", "$10K–$50K", "$50K–$100K", "$100K+" |
| `notes` | Text (textarea) | No | Free text for context ("We spend $200K/mo on Microsoft Ads and need this ASAP") |

**Auto-populated (not shown to user):**

| Field | Source |
|-------|--------|
| `email` | `current_user.email` (user is logged in — this is behind auth on Settings page) |
| `account_id` | `current_account.prefix_id` (links request to account for admin context) |
| `plan_name` | `current_account.plan&.name` (helps prioritize — Pro accounts get more weight) |
| `ip_address` | `request.remote_ip` (anonymized /24) |
| `user_agent` | `request.user_agent` |

**Predefined platform options** (ordered by market share / likely demand):

```ruby
PLATFORM_OPTIONS = [
  "Microsoft Ads (Bing)",
  "Pinterest Ads",
  "Snapchat Ads",
  "Amazon Ads",
  "Twitter/X Ads",
  "Reddit Ads",
  "Apple Search Ads",
  "Phone/Call Tracking",
  "Criteo",
  "The Trade Desk",
  "Other"
].freeze

MONTHLY_SPEND_OPTIONS = [
  "Under $1K",
  "$1K – $10K",
  "$10K – $50K",
  "$50K – $100K",
  "$100K+"
].freeze
```

**Behavior:**
1. User fills form → POST `/account/integrations/request`
2. Creates `IntegrationRequestSubmission` (STI subclass of `FormSubmission`)
3. Duplicate check: same email + same platform_name = "You've already requested this platform!" (redirect back with notice)
4. Success: "Thanks! We'll notify you when {platform} is available." (redirect back with notice)
5. `FormSubmissionMailer.notify` fires automatically (existing `after_create_commit` on `FormSubmission`)
6. No email field shown — user is authenticated, email auto-populated

#### Data Model

Follows existing `FormSubmission` STI pattern (like `SdkWaitlistSubmission`, `FeatureWaitlistSubmission`):

```ruby
# app/models/integration_request_submission.rb
class IntegrationRequestSubmission < FormSubmission
  # Used for both "Notify Me" (coming soon cards) and "Request Integration" (contact form)
  COMING_SOON_PLATFORMS = [
    "Meta Ads",
    "TikTok Ads",
    "LinkedIn Ads",
    "Microsoft Ads (Bing)",
    "Pinterest Ads",
    "Snapchat Ads",
    "Reddit Ads",
    "X (Twitter) Ads",
    "Apple Search Ads",
    "Phone/Call Tracking",
    "CSV Import"
  ].freeze

  REQUEST_ONLY_PLATFORMS = [
    "Amazon Ads",
    "Criteo",
    "The Trade Desk",
    "Other"
  ].freeze

  PLATFORM_OPTIONS = (COMING_SOON_PLATFORMS + REQUEST_ONLY_PLATFORMS).freeze

  MONTHLY_SPEND_OPTIONS = [
    "Under $1K",
    "$1K – $10K",
    "$10K – $50K",
    "$50K – $100K",
    "$100K+"
  ].freeze

  store_accessor :data, :platform_name, :platform_name_other, :monthly_spend,
                        :notes, :account_id, :plan_name

  validates :platform_name, presence: true, inclusion: { in: PLATFORM_OPTIONS }
  validates :platform_name_other, presence: true, if: -> { platform_name == "Other" }
  validates :monthly_spend, inclusion: { in: MONTHLY_SPEND_OPTIONS }, allow_blank: true
end
```

No migration needed — uses existing `form_submissions` table with JSONB `data` column.

#### Controller

```ruby
# In Accounts::IntegrationsController (existing)
def request_integration
  return handle_duplicate_request if already_requested?

  submission = IntegrationRequestSubmission.new(request_params)
  if submission.save
    redirect_to account_integrations_path,
      notice: "Thanks! We'll notify you when #{submission.display_platform_name} is available."
  else
    redirect_to account_integrations_path,
      alert: submission.errors.full_messages.first
  end
end

private

def already_requested?
  IntegrationRequestSubmission
    .where(email: current_user.email)
    .where("data->>'platform_name' = ?", params[:platform_name])
    .exists?
end

def handle_duplicate_request
  redirect_to account_integrations_path,
    notice: "You've already requested this platform!"
end

def request_params
  {
    email: current_user.email,
    platform_name: params[:platform_name],
    platform_name_other: params[:platform_name_other],
    monthly_spend: params[:monthly_spend],
    notes: params[:notes],
    account_id: current_account.prefix_id,
    plan_name: current_account.plan&.name,
    ip_address: anonymized_ip,
    user_agent: request.user_agent
  }
end
```

**Route** (add to existing `resource :integrations` block):

```ruby
resource :integrations, only: [:show], controller: "integrations" do
  post "refresh/:id", action: :refresh, as: :refresh
  post "request", action: :request_integration, as: :request_integration  # NEW
end
```

#### Admin: Integration Requests Dashboard

A dedicated admin page for integration requests at `/admin/integration_requests`. While these submissions also appear in the general `/admin/submissions` list, the dedicated page provides aggregated demand signals and request management.

**Route:**

```ruby
namespace :admin do
  # ... existing routes ...
  resources :integration_requests, only: [:index, :show, :update]
end
```

**Controller:**

```ruby
# app/controllers/admin/integration_requests_controller.rb
module Admin
  class IntegrationRequestsController < BaseController
    include Pagination

    per_page 25

    def index
      @filter = params[:filter] || "visible"
      @requests = paginate(filtered_requests)
      @platform_summary = platform_summary
    end

    def show
      @request = IntegrationRequestSubmission.find_by_prefix_id!(params[:id])
    end

    def update
      request = IntegrationRequestSubmission.find_by_prefix_id!(params[:id])
      request.update!(status: params[:status].to_i)
      redirect_to admin_integration_requests_path(filter: params[:filter]),
        notice: "Request updated."
    end

    private

    def filtered_requests
      scope = IntegrationRequestSubmission.order(created_at: :desc)
      case @filter
      when "hidden"
        scope.where(status: :spam)  # reuse "spam" status as "hidden"
      when "visible"
        scope.where.not(status: :spam)
      else # "all"
        scope
      end
    end

    def platform_summary
      IntegrationRequestSubmission
        .where.not(status: :spam)
        .group("data->>'platform_name'")
        .count
        .sort_by { |_, count| -count }
    end
  end
end
```

**Admin index view** (`/admin/integration_requests`):

```
┌─────────────────────────────────────────────────────────────────────┐
│  Integration Requests                                [Submissions]  │
│                                                                     │
│  ┌─ Demand Summary ────────────────────────────────────────────┐   │
│  │ Microsoft Ads (Bing)  ████████████████  12 requests          │   │
│  │ Pinterest Ads         ████████         8 requests            │   │
│  │ Amazon Ads            ██████           6 requests            │   │
│  │ Snapchat Ads          ███              3 requests            │   │
│  │ Other                 ██               2 requests            │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  Filter: [All] [Visible ✓] [Hidden]              31 requests       │
│                                                                     │
│  ┌───────────┬──────────────┬───────────┬──────────┬──────────┐   │
│  │ Platform  │ Email        │ Spend     │ Plan     │ Actions  │   │
│  │ Microsoft │ a@co.com     │ $10K-$50K │ Pro      │ Hide     │   │
│  │ Pinterest │ b@co.com     │ $1K-$10K  │ Growth   │ Hide     │   │
│  │ Other:    │ c@co.com     │ —         │ Starter  │ Hide     │   │
│  │  "Taboola"│              │           │          │          │   │
│  └───────────┴──────────────┴───────────┴──────────┴──────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

**Key design decisions:**

| Decision | Choice | Why |
|----------|--------|-----|
| **Hide mechanism** | Reuse existing `FormSubmission.status` enum — `spam` status = hidden | No migration, no new column. "spam" is the correct semantic for dismissed submissions. Admin can toggle back to `pending` to unhide. |
| **Filter default** | "Visible" (non-hidden) | Admin sees actionable requests by default. Hidden requests accessible via filter toggle. |
| **Demand summary** | Horizontal bar chart (simple HTML/CSS, no JS) | At-a-glance platform prioritization. Excludes hidden requests from count. |
| **Account context** | Show plan name alongside request | Pro/Growth account requesting Microsoft Ads carries more weight than Free account. |
| **Separate admin page** | `/admin/integration_requests` (not mixed into `/admin/submissions`) | Dedicated page enables demand summary aggregation. Requests still appear in general submissions list too. |

**States:**

| State | What User Sees | What Admin Sees |
|-------|---------------|-----------------|
| No requests yet | Form with "Request Integration" | Empty state: "No integration requests yet." |
| Request submitted | "Thanks! We'll notify you when {platform} is available." | New row in request list + email notification |
| Duplicate request | "You've already requested this platform!" | Nothing (blocked at controller) |
| Admin hides request | (no change — user-facing is fire-and-forget) | Request moves to "Hidden" filter, removed from demand summary |
| Admin unhides request | (no change) | Request returns to "Visible" filter, re-counted in demand summary |

### Spend Dashboard → New Dashboard Tab

Add 4th tab to main dashboard: **Conversions | Funnel | Spend | Events**

- **Empty state** (no connections): CTA → "Connect Google Ads to see spend intelligence" linking to Settings > Integrations
- **Syncing state**: "Historical data syncing, check back in a few minutes"
- **Full dashboard**: Hero metrics, trend chart, channel/platform breakdown, drill-down

### Daily Sync (Background)

```
Daily at 4am UTC:
  SpendSyncSchedulerJob → iterates connected accounts
    → SpendSyncJob per connection
      → Re-syncs last 3 days (hourly × device × network_type granularity)
      → Captures Google's corrections on recent data
      → Refreshes materialized view
      → Increments account usage meter with records_synced count
```

---

## Proposed Solution

### Core Insight: The Join

Click-level cost data doesn't exist in the Google Ads API (the `click_view` resource exposes GCLIDs but zero cost metrics). The finest cost granularity available is **hourly × device × campaign**. Our join operates at **channel-level spend aggregation** joined with **channel-level attributed revenue**:

```
Attributed ROAS = Σ(revenue_credit WHERE channel = X) / Σ(ad_spend WHERE channel = X)
```

This works because:
1. Our channel taxonomy is standardized (12 channels)
2. Google Ads spend maps cleanly to `paid_search`, `display`, `video`, `paid_social`
3. UTM campaign data in `AttributionCredit` enables campaign-level ROAS drill-down
4. The join is a simple GROUP BY, not a complex click-level match
5. Hourly × device × network_type dimensions roll up naturally via SUM — the ROAS join aggregates all hours/devices for a given channel+date, while drill-down views slice by hour or device independently

### Two Grouping Dimensions: Channel vs Platform

Industry research (Triple Whale, Northbeam, Rockerbox) shows marketers need both views:

| View | Primary Dimension | Answers | Join Key |
|------|-------------------|---------|----------|
| **Channel view** | paid_search, display, video | "Which channel strategies should we invest in?" | `ad_spend_records.channel = attribution_credits.channel` |
| **Platform view** | Google Ads, Meta Ads, TikTok | "Which platform is performing best?" | `ad_spend_records.ad_platform_connection_id` (platform inferred) |

We support both. Channel is the default (matches existing dashboard architecture). Platform view groups all spend from one `AdPlatformConnection` and joins against attribution credits where the session's click_id or utm_source maps to that platform.

### The Date Join

Three dates exist for any attributed conversion:

| Date | Source | What It Means |
|------|--------|---------------|
| **Spend date + hour** | Platform API (`segments.date` + `segments.hour`) | Day and hour money left the account |
| **Click date** | Platform-reported (what Google attributes conversions to) | Day user clicked the ad |
| **Conversion date** | Our data (`conversions.converted_at`) | Day user actually converted |

**Decision: Use conversion date for revenue, spend date for costs.** This is what every third-party platform does (Northbeam, Triple Whale, Rockerbox). Our dashboard already filters on `DATE(conversions.converted_at)`.

```
ROAS for Day X = Σ(revenue_credit WHERE DATE(converted_at) = X)
                 / Σ(spend_micros WHERE spend_date = X)
```

Over a 30-day window this is accurate and intuitive. Single-day ROAS can be misleading (spend today, conversions arrive over 7-30 days) — we note this in the UI.

### Campaign-Level Drill-Down

For campaign-level ROAS, we match `ad_spend_records.campaign_name` ↔ `attribution_credits.utm_campaign`. This is inherently fragile because:

1. Marketers set UTMs manually — names often don't match Google campaign names exactly
2. Auto-tagging (gclid) bypasses UTMs entirely
3. Campaign names change over time

**Mitigation:**
- Normalize both sides: lowercase, strip whitespace, collapse separators
- During onboarding, recommend tracking template: `{lpurl}?utm_source=google&utm_medium=cpc&utm_campaign={campaignid}`
- Using `{campaignid}` (numeric ID) instead of `{campaignname}` gives stable, exact matching
- Future: resolve `gclid` → campaign via Google Ads API for click-level join (Phase 8)

### Architecture

```
Google Ads API ──OAuth2──→ AdPlatformConnection (stores tokens)
       ↓
  Sync Job (daily + on-demand)
       ↓
  AdSpendRecord (date, hour, device, network_type, channel, campaign, spend, impressions, clicks)
       ↓
  account.increment_usage!(records_synced) → Billing::UsageCounter (same pool as SDK events)
       ↓
  SpendIntelligence::MetricsService
       ↓
  Join: ad_spend_records ⟗ attribution_credits (on channel + date)
       ↓                                          ↓
  Channel view: ROAS by channel          Platform view: ROAS by platform
       ↓                                          ↓
  Campaign drill-down                    Device / Hour drill-down
       ↓
  Dashboard: ROAS, CAC, Payback, Marginal ROAS, Recommendations
```

### Data Flow (Proposed)

```
[SPEND SIDE]                              [ATTRIBUTION SIDE]
Google Ads API                            Existing mbuzz flow
     ↓                                          ↓
AdSpendRecord                             AttributionCredit
{ spend_date, spend_hour, device,         { channel, credit,
  network_type, channel, campaign,          revenue_credit, utm_campaign,
  spend_micros, impressions, clicks,        conversion.converted_at }
  ad_platform_connection_id }
     ↓                                          ↓
     ├── increment_usage!(records_synced) → Billing::UsageCounter
     ↓                                          ↓
     └──────── JOIN on (account, channel, date) ┘
                         ↓
              SpendIntelligence::MetricsService
                         ↓
              { attributed_roas, platform_roas, blended_roas,
                cac, ncac, mer, payback_period,
                marginal_roas, recommendations,
                device_breakdown, hourly_breakdown }
```

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| **UX: Connection** | Settings > Integrations (new tab) | Follows existing account settings pattern. Between API Keys and Attribution in sidebar. |
| **UX: Dashboard** | New "Spend" tab on main dashboard | 4th tab: Conversions / Funnel / Spend / Events. Keeps spend analysis alongside attribution. |
| **Primary grouping** | Channel (default) + Platform (toggle) | Channel matches existing architecture. Platform view added because marketers think in platforms. Industry standard is hybrid (Rockerbox, Triple Whale). |
| **Date semantics** | Conversion date for revenue, spend date for costs | Industry standard (Northbeam, Triple Whale, Rockerbox). Matches existing `CreditsScope` filtering on `DATE(conversions.converted_at)`. |
| **Campaign matching** | Normalized `campaign_name ↔ utm_campaign` | Best-effort string match. Recommend `{campaignid}` in tracking templates for exact match. gclid resolution deferred to Phase 8. |
| Join granularity | Channel + date (campaign drill-down) | Matches our channel-primary architecture. Campaign-level via utm_campaign secondary join. |
| Sync frequency | Daily (4am UTC) + manual refresh | Google Ads data settles within 24-48h. Re-sync last 3 days for corrections. Hourly data returned in single API response per query. |
| Historical backfill | 90 days on first connect | Enough for trend analysis and response curves. ~90 × 24 × campaigns × ~4.5 dimension combos rows. Counts toward usage meter. |
| Monetary storage | `bigint` micros (1M = 1 currency unit) | Matches Google Ads API natively. Integer math is faster, avoids decimal rounding. Convert at display time only. |
| Multi-currency | Store in ad platform's native currency | Google API returns cost_micros in account currency. Phase 1 displays in native currency with label. Currency normalization deferred to Phase 2. |
| Google Ads hierarchy | Campaign-level aggregation | Ad Group and Ad level are too granular for attribution join. Campaign maps to utm_campaign. Keyword-level deferred to future phase. |
| Reporting granularity | Hourly × device × network_type | Finest cost granularity Google Ads API offers. Enables dayparting analysis, device-level ROAS, and near-real-time spend monitoring. ~39K rows/campaign/year. |
| Metered billing | Ad spend rows count toward usage meter | Each synced row increments same `Billing::UsageCounter` as SDK events. Natural alignment: bigger advertisers = more campaigns = more rows = higher plan. |
| Connection limits | Gated by plan tier | Free: 0, Starter: 1, Growth: 3, Pro: unlimited. Prevents Free accounts from consuming sync resources. |
| OAuth scope | `https://www.googleapis.com/auth/adwords` (read-only) | We never write to their ad accounts. Read-only builds trust. |
| Channel mapping | Automatic via Google campaign type + network segment | Search → paid_search, Display → display, Video → video, Shopping → paid_search. PMax split by `segments.ad_network_type` (API v23). Configurable override. |
| PMax handling | Split by sub-channel | Google exposes channel-level PMax data since API v23 (Jan 2026). Distributes spend correctly across paid_search, display, video. |
| Response curves | Hill saturation function, fitted in Ruby | Industry standard (PyMC-Marketing, Robyn). Pure Ruby via `matrix` stdlib — 3 parameters, ~50 data points, ~50 lines. |
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
  t.integer :platform, null: false            # enum: google_ads: 0, meta_ads: 1, linkedin_ads: 2, tiktok_ads: 3, microsoft_ads: 4, pinterest_ads: 5, snapchat_ads: 6, reddit_ads: 7, x_ads: 8, apple_search_ads: 9
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

  enum :platform, {
    google_ads: 0, meta_ads: 1, linkedin_ads: 2, tiktok_ads: 3,
    microsoft_ads: 4, pinterest_ads: 5, snapchat_ads: 6,
    reddit_ads: 7, x_ads: 8, apple_search_ads: 9
  }
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

Hourly spend data per campaign, segmented by device and network type. The atomic unit of spend intelligence. Each row represents one campaign × hour × device × network_type combination. **Every row counts toward the account's metered usage** (same pool as SDK events).

**Volume estimates** (per account, per year):

| Account Size | Campaigns | Rows/year | Plan Tier |
|---|---|---|---|
| Small (freelancer) | 5 | ~50K | Free/Starter |
| Medium (SMB) | 50 | ~500K | Starter/Growth |
| Large (growth team) | 200 | ~2M | Growth/Pro |
| Agency (multi-client) | 1,000+ | ~10M+ | Pro/Enterprise |

Formula: `campaigns × 365 days × 24 hours × ~3 devices × ~1.5 avg network types ≈ campaigns × 39K rows/year`

```ruby
create_table :ad_spend_records do |t|
  t.references :account, null: false, foreign_key: true
  t.references :ad_platform_connection, null: false, foreign_key: true
  t.date :spend_date, null: false
  t.integer :spend_hour, null: false          # 0-23 (from segments.hour)
  t.string :channel, null: false              # Mapped to our channel taxonomy (Channels::ALL)
  t.string :platform_campaign_id, null: false # Google's campaign ID
  t.string :campaign_name, null: false
  t.string :campaign_type                     # SEARCH, DISPLAY, VIDEO, SHOPPING, PERFORMANCE_MAX
  t.string :network_type                      # segments.ad_network_type: SEARCH, CONTENT, YOUTUBE_SEARCH, etc.
  t.string :device                            # segments.device: MOBILE, DESKTOP, TABLET, OTHER
  t.bigint :spend_micros, null: false, default: 0  # 1,000,000 = 1 currency unit
  t.string :currency, limit: 3, null: false
  t.bigint :impressions, null: false, default: 0
  t.bigint :clicks, null: false, default: 0
  t.bigint :platform_conversions_micros, null: false, default: 0  # Google's own count × 1M
  t.bigint :platform_conversion_value_micros, null: false, default: 0
  t.boolean :is_test, default: false, null: false
  t.timestamps

  t.index [:account_id, :spend_date, :channel], name: "idx_spend_channel_date"
  t.index [:account_id, :ad_platform_connection_id, :spend_date, :spend_hour,
           :platform_campaign_id, :device, :network_type],
    unique: true, name: "idx_spend_unique"
  t.index [:account_id, :channel, :spend_date], name: "idx_spend_date_range"
  t.index [:is_test], name: "idx_spend_is_test"
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

  DEVICES = %w[MOBILE DESKTOP TABLET OTHER].freeze

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

### Billing & Metering

#### Connection Limits by Plan

Ad platform connections are gated by plan tier. Free accounts cannot connect ad platforms (keeps sync resources and API quota for paying customers).

| Plan | Connections | Ad Spend Access |
|---|---|---|
| Free ($0) | 0 | None |
| Starter ($29) | 1 | 1 platform, 1 account |
| Growth ($99) | 3 | All platforms, 3 accounts |
| Pro ($299) | Unlimited | All platforms, unlimited |

**Implementation**: Add `ad_platform_connection_limit` column to `plans` table. Check in `AdPlatformConnectionsController#create` before starting OAuth flow. Display upgrade CTA for accounts at their limit.

```ruby
# Plan model addition
def ad_platform_connection_limit
  return 0 if free?
  read_attribute(:ad_platform_connection_limit)
end

# Billing constant additions
AD_PLATFORM_CONNECTION_LIMITS = {
  PLAN_FREE => 0,
  PLAN_STARTER => 1,
  PLAN_GROWTH => 3,
  PLAN_PRO => nil  # nil = unlimited
}.freeze
```

```ruby
# Account::Billing concern addition
def can_connect_ad_platform?
  limit = plan&.ad_platform_connection_limit
  return false if limit == 0
  return true if limit.nil?  # unlimited

  ad_platform_connections.connected_or_syncing.count < limit
end
```

#### Unified Usage Meter

Ad spend records count toward the **same usage pool** as SDK events (sessions, events, conversions, identify calls). One meter, one overage calculation, no new Stripe meters.

**How it works**:
1. `SpendSyncService` upserts ad spend records from Google Ads API
2. After sync, calls `account.increment_usage!(records_synced_count)`
3. Same `Billing::UsageCounter` increments the same Redis cache key
4. Same overage calculation applies: Starter $5/250K block, Growth $15/1M block, Pro $50/5M block

**Why this works**:
- **One number to track**: Users see total "data records" usage, not separate SDK vs ad spend meters
- **Natural alignment**: Bigger advertisers have more campaigns → more rows → higher plan tier
- **Covers costs**: Millions of ad spend rows consume storage and compute — metering ensures cost coverage
- **No billing complexity**: Zero new Stripe meters, zero new overage logic, zero new UI

**Volume context** (at campaign × hour × device × network_type granularity):

| Account Size | Ad Spend Rows/month | As % of Starter (1M) | As % of Growth (5M) |
|---|---|---|---|
| 5 campaigns | ~4K | 0.4% | 0.1% |
| 50 campaigns | ~42K | 4.2% | 0.8% |
| 200 campaigns | ~167K | 16.7% | 3.3% |
| 1,000 campaigns | ~833K | 83.3% | 16.7% |

For most accounts, ad spend rows are a small fraction of their allocation. Only agency-scale accounts (1,000+ campaigns) see meaningful usage from ad data alone — and those accounts should be on Pro or Enterprise.

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
      def initialize(account:, date_range:, channels: Channels::ALL, devices: nil, hours: nil, test_mode: false)
        @account = account
        @date_range = date_range
        @channels = channels
        @devices = devices       # nil = all devices, or Array of MOBILE/DESKTOP/TABLET/OTHER
        @hours = hours           # nil = all hours, or Range (e.g., 9..17 for business hours)
        @test_mode = test_mode
      end

      def call
        account.ad_spend_records
          .then { |scope| test_mode ? scope.where(is_test: true) : scope.where(is_test: false) }
          .where(spend_date: date_range)
          .then { |scope| channels == Channels::ALL ? scope : scope.where(channel: channels) }
          .then { |scope| devices ? scope.where(device: devices) : scope }
          .then { |scope| hours ? scope.where(spend_hour: hours) : scope }
      end

      private

      attr_reader :account, :date_range, :channels, :devices, :hours, :test_mode
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
[Overview] [Hourly / Device] [Payback Period] [Recommendations] [Scenarios]
```

### Hourly / Device View

```
┌─────────────────────────────────────────────────────────────────────┐
│  Spend by Hour of Day            [Last 30 days]  [paid_search ▼]   │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │ Spend│                                                         │ │
│  │ $800 │          ╱──╲                                           │ │
│  │ $600 │        ╱─    ─╲          ╱──╲                           │ │
│  │ $400 │      ╱─        ─╲     ╱─    ─╲                         │ │
│  │ $200 │──╱──               ──╱        ──╲──                     │ │
│  │      └──────────────────────────────── Hour →                  │ │
│  │      0  2  4  6  8  10 12 14 16 18 20 22                      │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  Device Breakdown                                                   │
│  ┌───────────┬──────────┬────────┬────────┬────────┐               │
│  │ Device    │ Spend    │ Clicks │ CPC    │ ROAS   │               │
│  │ Desktop   │ $14,200  │ 3,100  │ $4.58  │ 4.2x   │               │
│  │ Mobile    │  $8,400  │ 5,200  │ $1.62  │ 2.1x   │               │
│  │ Tablet    │  $1,900  │   480  │ $3.96  │ 3.8x   │               │
│  └───────────┴──────────┴────────┴────────┴────────┘               │
│                                                                     │
│  💡 Desktop ROAS is 2x mobile. Consider increasing desktop bids.   │
└─────────────────────────────────────────────────────────────────────┘
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
        TokenRefresher.new(connection).call
      end

      def validate_connection
        return refresh_token! if token_expired?
        { success: true }
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

Hourly spend sync query (non-PMax campaigns):

```sql
SELECT
  campaign.id,
  campaign.name,
  campaign.advertising_channel_type,
  segments.date,
  segments.hour,
  segments.device,
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
  segments.hour,
  segments.device,
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

**Dimensions pulled**: `date × hour × device × network_type (PMax only)`. This is the maximum useful granularity — `segments.hour` (0-23) is the finest time unit Google Ads API offers (no minute-level data exists). `segments.device` returns MOBILE, DESKTOP, TABLET, OTHER. Together they enable dayparting analysis, device-level ROAS, and near-real-time spend tracking.

**Dimensions NOT pulled**: `segments.click_type` (too noisy, 5-10x fan-out for marginal insight), `segments.slot` (top-of-page vs other — marginal value for ROAS), `segments.conversion_action` (we have our own attribution).

**Cost storage**: `cost_micros` is stored directly as `spend_micros` (bigint). No conversion needed at sync time — convert to display currency at read time only.

**Rate limits**: 15,000 requests/day at Basic Access. Our daily sync uses ~1 request per account (hourly data returned in a single query response). No concern.

**Metered billing**: After each sync, `account.increment_usage!(records_synced)` counts the upserted rows against the account's usage meter. This is the same `Billing::UsageCounter` used for SDK events — one pool, one overage calculation, no new Stripe meters.

### Data Freshness

Google Ads data for a given day is considered final after **48 hours**. For the most recent 2 days:
- Mark data as "Preliminary" in UI
- Re-sync last 3 days on each daily run to capture corrections

---

## Implementation Tasks

### Phase 1: Data Foundation ✓ (+ 1b: Hourly Dimensions)

- [x] **1.1** Run `bin/rails db:encryption:init` and add keys to credentials (first use of `encrypts` in codebase)
- [x] **1.2** Create `ad_platform_connections` migration (integer enums, plain text columns for encrypted fields)
- [x] **1.3** Create `ad_spend_records` migration (bigint micros, network_type, is_test)
- [x] **1.4** Create `ad_spend_sync_runs` migration (sync tracking)
- [x] **1.5** Create `AdPlatformConnection` model with concerns (Validations, Relationships, StatusManagement) + `encrypts :access_token, :refresh_token`
- [x] **1.6** Create `AdSpendRecord` model with concerns (Validations, Relationships, Scopes)
- [x] **1.7** Create `AdSpendSyncRun` model with concerns (Validations, Relationships)
- [x] **1.8** Create `AdPlatformChannels` constant module (campaign type + network type maps)
- [x] **1.9** Add `has_many :ad_platform_connections` and `has_many :ad_spend_records` to Account
- [x] **1.10** Write model tests (58 tests, all passing)
- [x] **1.11** Migration: add `spend_hour` (integer, not null) and `device` (string) columns to `ad_spend_records`
- [x] **1.12** Migration: update unique index `idx_spend_unique` to include `spend_hour`, `device`, `network_type`
- [x] **1.13** Migration: add `ad_platform_connection_limit` (integer, nullable) to `plans` table
- [x] **1.14** Add `DEVICES` constant to `AdSpendRecord`, add `spend_hour` (0-23) and `device` validations
- [x] **1.15** Add `for_device` and `for_hour` scopes to `AdSpendRecord::Scopes`
- [x] **1.16** Add `AD_PLATFORM_CONNECTION_LIMITS` to `Billing` constants
- [x] **1.17** Add `can_connect_ad_platform?` to `Account::Billing` concern
- [x] **1.18** Update fixtures and tests for new columns + billing checks (16 new tests, 2701 total passing)

> **Implementation notes**: ActiveRecord Encryption keys configured in `config/environments/test.rb` (inline, not in credentials) with `support_unencrypted_data = true` for fixture compatibility. Settings JSONB limit uses explicit `MAX_SETTINGS_BYTES = 51_200` constant. TimescaleDB calls removed from `db/schema.rb` after migration auto-dump.

### Phase 2: Google Ads OAuth

- [x] **2.1** Register OAuth application with Google (developer token, OAuth client)
- [x] **2.2** Create `AdPlatforms::BaseAdapter` interface (abstract: `fetch_spend`, `refresh_token`, `validate_connection`)
- [x] **2.3** Create `AdPlatforms::Google::Adapter` implementing BaseAdapter
- [x] **2.4** Create OAuth services (split from monolithic OauthService per SRP): `AdPlatforms::Google::OauthUrl`, `TokenClient`, `TokenExchanger`, `TokenRefresher` + shared constants in `AdPlatforms::Google` module + `AdPlatforms::Registry`
- [x] **2.5** Create `Oauth::GoogleAdsController` (connect with CSRF state + plan limit check, callback with state verification + token exchange, disconnect with `mark_disconnected!`) — routes at `/oauth/google_ads/*`
- [x] **2.6** Create account selection flow (list accessible customers via `ListAccessibleCustomers`) — `ListCustomers` service written, controller actions `select_account` + `create_connection` complete.
  - **BUG FIX (session pinning)**: `current_account` switched to wrong account after OAuth redirect because callback URLs are fixed (no `account_id` param) and `primary_account` resolves by `last_accessed_at` — any concurrent request to another account changed resolution. Fixed: `connect` pins `session[:oauth_account_id]`, `require_oauth_account` guard validates on `callback`/`select_account`/`create_connection`, `oauth_account` resolves from session (not `current_account`), `clear_oauth_session!` cleans up all OAuth keys on completion. 4 new tests (23 total controller tests, 2759 suite).
- [x] **2.7** Create settings UI: "Integrations" page with Google Ads connection card
- [x] **2.8** Write controller + service tests (28 service tests + 13 controller tests passing, 2745 total)

> **Implementation notes (Phase 2)**: OauthService was split into 4 SRP classes: `OauthUrl` (authorization URL builder), `TokenClient` (shared HTTP client for Google token endpoint), `TokenExchanger` (code → tokens), `TokenRefresher` (refresh token → new access token). All use memoized methods, no procedural variable assignment. Constants (URIs, scopes, grant types, API field names, headers) in `AdPlatforms::Google` module — no magic strings. `AdPlatforms::Registry` maps `google_ads:` symbol → adapter class. Tests stub `Google.credentials` since test env has no Google OAuth creds configured. **Session pinning**: OAuth callback URLs are fixed (Google-registered, no account context), so `connect` pins `session[:oauth_account_id]` and all subsequent OAuth actions (`callback`, `select_account`, `create_connection`) resolve the account from session via `oauth_account` instead of `current_account`. This prevents `primary_account` (ordered by mutable `last_accessed_at`) from silently switching accounts mid-flow. `require_oauth_account` guard rejects requests with missing/invalid pinned account. `disconnect` remains on `current_account` (settings page context, not OAuth flow).

### Phase 3: Spend Sync

- [x] **3.1** Create `AdPlatforms::Google::SpendSyncService` (two GAQL queries: standard + PMax, hourly × device × network_type, upsert via `upsert_all`, meter usage)
- [x] **3.2** Create `AdPlatforms::Google::CampaignChannelMapper` (campaign type → channel, PMax network type splitting)
- [x] **3.3** Create `AdPlatforms::SpendSyncSchedulerJob` (iterates `AdPlatformConnection.active_connections.find_each`, enqueues per-connection jobs)
- [x] **3.4** Create `AdPlatforms::SpendSyncJob` (thin wrapper → `Google::ConnectionSyncService`); `ConnectionSyncService` handles token refresh, sync run lifecycle, connection status
- [x] **3.5** Add entry to `config/recurring.yml`: `ad_spend_sync: { class: AdPlatforms::SpendSyncSchedulerJob, schedule: at 6am every day }`
- [x] **3.6** Implement 90-day historical backfill on first connect (enqueued from `create_connection`, counts toward usage meter)
- [x] **3.7** Implement incremental daily sync (last 3 days for corrections — `ConnectionSyncService::INCREMENTAL_LOOKBACK_DAYS`)
- [x] **3.8** Add `account.increment_usage!(records_synced)` call after each sync in `SpendSyncService`
- [x] **3.9** Connection limit check already enforced in `Oauth::GoogleAdsController#connect` (calls `account.can_connect_ad_platform?`)
- [x] **3.10** Add manual "Refresh" button on integrations page (enqueues `SpendSyncJob`)
- [x] **3.11** Write sync service tests with mocked API responses (including metering assertions)

> **Implementation notes (Phase 3)**: Sync pipeline decomposed into 4 SRP classes: `ApiClient` (shared HTTP client with auth headers), `RowParser` (API row → upsert hash), `CampaignChannelMapper` (campaign type → mbuzz channel, PMax network splitting), `SpendSyncService` (orchestrate: fetch, parse, `upsert_all`, meter). All use memoized methods. Jobs are thin wrappers: `SpendSyncSchedulerJob` iterates `active_connections`, `SpendSyncJob` delegates to `ConnectionSyncService`. `ConnectionSyncService` handles lifecycle: token refresh (memoized `token_refresh`), sync run creation/completion, connection status transitions. Campaign types and network types use `AdPlatformChannels` constants — no magic strings. 90-day backfill enqueued from `create_connection` via `SpendSyncJob` with custom `date_range:`. Daily incremental sync covers last 3 days for Google Ads correction window. Manual refresh via `IntegrationsController#refresh` (scoped to `current_account`). Schedule: 6am daily via `recurring.yml`. 40 new tests (2809 suite total).

### Phase 4: Core Metrics

- [x] **4.1** Create `SpendIntelligence::Scopes::SpendScope` (account, date_range, channels, devices, hours, test_mode)
- [x] **4.2** Create `SpendIntelligence::Queries::ChannelMetricsQuery` (ROAS, blended ROAS as methods on one consolidated query class)
- [x] **4.3** Create `SpendIntelligence::Queries::PaybackPeriodQuery` (integrates with CLV data, NCAC per channel, cumulative CLV curve)
- [x] **4.4** Create `channel_revenue_daily` materialized view migration (with `return if Rails.env.test?`)
- [x] **4.5** Create `SpendIntelligence::MetricsService` (aggregates all metrics for dashboard, delegates to scope + queries, caches 5 min)
- [x] **4.6** Write comprehensive metric tests (27 tests: 9 SpendScope, 11 ChannelMetrics, 7 MetricsService)

### Phase 5: Dashboard UI

- [ ] **5.1** Create `Dashboard::SpendIntelligenceController`
- [ ] **5.2** Create `_spend_hero_metrics.html.erb` partial (5 KPI cards)
- [ ] **5.3** Create `_spend_trend_chart.html.erb` (ROAS + spend time-series via Highcharts)
- [ ] **5.4** Create `_channel_performance_table.html.erb` (sortable table)
- [ ] **5.5** Create `_hourly_device_breakdown.html.erb` (spend-by-hour chart + device table)
- [ ] **5.6** Create `_payback_period.html.erb` (chart + table)
- [ ] **5.7** Create empty state with onboarding CTA (upgrade CTA for Free accounts)
- [ ] **5.8** Add data freshness badges ("Last synced", "Preliminary" labels)
- [ ] **5.9** Add "Attributed vs Platform" ROAS comparison column with tooltip
- [ ] **5.10** Write controller + view tests

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

### Phase 7b: Request Integration

- [ ] **7b.1** Create `IntegrationRequestSubmission` model (STI subclass of `FormSubmission`, `store_accessor` for `platform_name`, `platform_name_other`, `monthly_spend`, `notes`, `account_id`, `plan_name`)
- [ ] **7b.2** Add `request_integration` action to `Accounts::IntegrationsController` (form submission, duplicate check, auto-populate email/account/plan from session)
- [ ] **7b.3** Add route: `post "request"` inside existing `resource :integrations` block
- [ ] **7b.4** Create `_request_integration_card.html.erb` partial (platform dropdown, monthly spend dropdown, notes textarea, submit button)
- [ ] **7b.5** Render request card below coming-soon cards in `integrations/show.html.erb`
- [ ] **7b.6** Add `IntegrationRequestSubmission` to `Admin::SubmissionsHelper` `TYPE_BADGES` and `submission_details_preview`
- [ ] **7b.7** Create `Admin::IntegrationRequestsController` (index with filter, show, update status)
- [ ] **7b.8** Create admin index view with demand summary bar chart + filterable request table (All / Visible / Hidden)
- [ ] **7b.9** Create admin show view with full request detail
- [ ] **7b.10** Add admin routes: `resources :integration_requests, only: [:index, :show, :update]`
- [ ] **7b.11** Add link to integration requests from admin billing/submissions nav
- [ ] **7b.12** Write model + controller + admin tests

### Phase 8: Platform Expansion (Future)

Priority order based on market share, customer demand signals (from Notify Me / Request Integration), and build complexity.

**Tier 1 — Core platforms (covers ~90% of paid spend):**
- [ ] **8.1** Meta Ads integration (API approval in progress — see `platform_api_approvals_spec.md`)
- [ ] **8.2** TikTok Ads integration (deferred — fast approval when ready)
- [ ] **8.3** LinkedIn Ads integration (API access submitted 5 Mar 2026)
- [ ] **8.4** CSV Import (manual spend upload for any platform — zero API overhead)

**Tier 2 — Secondary platforms:**
- [ ] **8.5** Microsoft Ads / Bing (similar API to Google, easy build)
- [ ] **8.6** Pinterest Ads (high value for e-commerce/DTC)
- [ ] **8.7** Snapchat Ads
- [ ] **8.8** Reddit Ads (growing for SaaS/tech audiences)

**Tier 3 — Long tail:**
- [ ] **8.9** X (Twitter) Ads
- [ ] **8.10** Apple Search Ads
- [ ] **8.11** Amazon Ads

**Different category (spec separately):**
- [ ] **8.12** Phone/Call Tracking (CallRail, etc. — inbound call attribution)

All platform adapters follow the same `AdPlatforms::BaseAdapter` interface. See `platform_api_approvals_spec.md` for API approval status and timelines.

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
| OauthUrl | `test/services/ad_platforms/google/oauth_url_test.rb` | Auth URL with state param, scope, offline access, consent prompt |
| TokenClient | `test/services/ad_platforms/google/token_client_test.rb` | HTTP POST to Google token endpoint, credential merging, error parsing |
| TokenExchanger | `test/services/ad_platforms/google/token_exchanger_test.rb` | Code → access_token + refresh_token, error passthrough, blank code guard |
| TokenRefresher | `test/services/ad_platforms/google/token_refresher_test.rb` | Refresh → new access_token, missing token guard, error passthrough |
| ListCustomers | `test/services/ad_platforms/google/list_customers_test.rb` | List accessible customers, exclude managers, error handling |
| Oauth::GoogleAdsController | `test/controllers/oauth/google_ads_controller_test.rb` | Connect (CSRF + limit), callback (state verify + exchange), disconnect (scoped) |
| SpendSyncService | `test/services/ad_platforms/google/spend_sync_service_test.rb` | GAQL parsing, PMax network splitting, upsert logic, sync run tracking |
| CampaignChannelMapper | `test/services/ad_platforms/google/campaign_channel_mapper_test.rb` | All campaign types, PMax by network, user overrides |
| SpendScope | `test/services/spend_intelligence/scopes/spend_scope_test.rb` | Date range, channel filter, device filter, hour filter, test_mode filter |
| ChannelMetricsQuery | `test/services/spend_intelligence/queries/channel_metrics_query_test.rb` | ROAS, CAC, MER calculations, zero-spend guard |
| PaybackPeriodQuery | `test/services/spend_intelligence/queries/payback_period_query_test.rb` | CLV integration, cohort grouping |
| ResponseCurveService | `test/services/spend_intelligence/response_curve_service_test.rb` | Hill function fit, marginal ROAS calc, insufficient data guard |
| RecommendationService | `test/services/spend_intelligence/recommendation_service_test.rb` | Scale/Maintain/Reduce thresholds |
| ScenarioService | `test/services/spend_intelligence/scenario_service_test.rb` | Prediction accuracy, confidence intervals |
| BudgetOptimizerService | `test/services/spend_intelligence/budget_optimizer_service_test.rb` | Optimal allocation, constraints |
| IntegrationRequestSubmission | `test/models/integration_request_submission_test.rb` | Validations (platform inclusion, conditional other), store accessors, duplicate detection |
| IntegrationsController#request | `test/controllers/accounts/integrations_controller_test.rb` | Form submission, duplicate blocking, auto-populated fields, redirect with notice |
| Admin::IntegrationRequestsController | `test/controllers/admin/integration_requests_controller_test.rb` | Index filters (all/visible/hidden), demand summary, show detail, hide/unhide (status toggle) |

### Integration Tests

| Test | Verifies |
|------|----------|
| OAuth flow | Full connect → callback → account selection → redirect |
| Connection limits | Free blocked, Starter allows 1, Growth allows 3, Pro unlimited |
| Sync job | Scheduled execution, idempotency, error handling |
| Sync metering | `account.increment_usage!` called with correct count after sync |
| Dashboard render | All states (empty, loading, error, populated) |
| Multi-tenancy | Account A cannot see Account B's spend data |
| Integration request form | Submit → creates `IntegrationRequestSubmission`, duplicate blocked, notification email sent |
| Admin integration requests | Filter toggles (All/Visible/Hidden), hide/unhide updates status, demand summary excludes hidden |

### Manual QA

1. Connect a Google Ads test account
2. Verify historical sync completes with correct data
3. Verify daily sync captures new spend
4. Compare Attributed ROAS with manual calculation
5. Disconnect and verify data retained
6. Reconnect and verify no duplicate data
7. Submit integration request from Integrations page — verify submission created, notice shown
8. Submit duplicate request — verify "already requested" notice
9. Admin: verify demand summary counts, filter toggles, hide/unhide flow

---

## Definition of Done

- [ ] Google Ads OAuth connect/disconnect working
- [ ] Connection limits enforced by plan tier (Free: 0, Starter: 1, Growth: 3, Pro: unlimited)
- [ ] Hourly spend sync running reliably (date × hour × device × network_type)
- [ ] Synced rows counted toward account usage meter
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
- [ ] Request Integration form submits from Integrations page, duplicates blocked
- [ ] Admin integration requests page shows demand summary, filter (All/Visible/Hidden), hide/unhide
- [ ] Spec updated with final state

---

## Out of Scope

- **Click-level GCLID cost matching** -- Google Ads API does not expose per-click CPC. The `click_view` resource returns GCLIDs but zero cost metrics. Hourly × device × campaign is the finest cost granularity available.
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
