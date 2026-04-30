# mbuzz — Google Ads API Standard Access Application

**Submitted by:** Forebrite Pty Ltd (operator of mbuzz)
**Product URL:** https://mbuzz.co
**API contact:** hello@mbuzz.co
**Manager Account ID:** 652-093-6525
**Developer token tier requested:** Standard Access
**OAuth scope requested:** `https://www.googleapis.com/auth/adwords` (read-only use only)
**Document version:** 1.0 — 2026-04-30

---

## 1. Company Overview

Forebrite Pty Ltd operates **mbuzz**, a marketing-attribution SaaS at https://mbuzz.co. Customers are marketing, growth, and analytics teams running paid acquisition across multiple channels (search, social, display, email, affiliate). mbuzz tells those teams which channels and campaigns are actually driving revenue, so they can shift budget to what works.

The product replaces last-click and first-click reports with multi-touch attribution: every customer touchpoint (ad click, organic visit, email open, etc.) is recorded and credit is mathematically distributed across the touchpoints that contributed to a conversion. To compute return on ad spend (ROAS) and customer-acquisition cost (CAC) accurately, mbuzz needs the spend side of that equation — what each customer's ad accounts spent, by channel, by day. That is what we use the Google Ads API for.

---

## 2. How mbuzz Uses the Google Ads API

### 2.1 Use case

**Read-only daily spend reporting for ROAS attribution.** mbuzz never creates, modifies, pauses, or budgets campaigns. We do not place ads. We do not bid. We pull historical spend reports for the customer's own Google Ads accounts so we can attribute their revenue back to those campaigns.

### 2.2 What we read

For each Google Ads account a customer connects to mbuzz, we issue daily `googleAds:search` queries via the Google Ads REST API to retrieve aggregated spend metrics, scoped by date range (default rolling 30 days, with customer-initiated backfills up to 12 months). The fields we read are:

- `customer.id`, `customer.descriptive_name`, `customer.currency_code`, `customer.manager`
- `customer_client.id`, `customer_client.descriptive_name`, `customer_client.currency_code`, `customer_client.level` — for sub-account discovery on MCC connections
- `campaign.id`, `campaign.name`, `campaign.advertising_channel_type`
- `segments.date`, `segments.hour`, `segments.device`, `segments.ad_network_type`
- `metrics.cost_micros`, `metrics.impressions`, `metrics.clicks`, `metrics.conversions`, `metrics.conversions_value`

We do not read keyword-level performance, ad-creative content, audience composition, conversion-action settings, billing details, or any other field outside this list.

### 2.3 What we do with it

The retrieved metrics are transformed into mbuzz's internal `AdSpendRecord` schema and stored in our PostgreSQL database. The records power:

- **ROAS dashboards** (per channel, per device, per hour, per campaign)
- **Customer-acquisition cost (CAC)** rollups
- **Marketing efficiency ratio (MER)** computation
- **Payback-period analysis**
- **Attribution rebalancing recommendations** (e.g. "shift 15% of paid_search spend to display based on observed marginal ROAS")

Every metric in our product that involves the word "spend" is computed against this data. No data is sold, shared with third parties, or used for advertising targeting. mbuzz is a per-customer measurement tool; data stays scoped to the customer's mbuzz account.

### 2.4 What we never do

To make this explicit:

- **No campaign creation, modification, pause, or removal.** Read-only.
- **No bid changes.** Read-only.
- **No budget changes.** Read-only.
- **No conversion-action changes.** Read-only.
- **No data sharing with third parties.** Customer's data is theirs.
- **No use of Google Ads data for advertising targeting** on other platforms or channels.
- **No reselling Google Ads data** as a product or feature.

The `adwords` scope grants write access in principle; we use only the read pathways. This is enforced in our codebase by routing every Google Ads API call through a single `AdPlatforms::Google::ApiClient` class that issues `googleAds:search` (read) requests exclusively.

---

## 3. System Architecture

### 3.1 OAuth flow

The customer initiates the connection from mbuzz's Integrations page (`https://mbuzz.co/account/integrations/google_ads`):

1. Customer clicks "Connect" → mbuzz redirects to Google's OAuth consent screen with `scope=https://www.googleapis.com/auth/adwords` and `access_type=offline` (so we receive a refresh token for daily syncs).
2. Customer reviews the consent screen and approves. Google redirects back to mbuzz with an authorization code.
3. mbuzz exchanges the code for `access_token` + `refresh_token` via Google's token endpoint.
4. mbuzz lists the customer's accessible Google Ads accounts (`customers:listAccessibleCustomers`) and renders an account picker.
5. Customer picks one account (or one MCC, in which case we recursively list sub-accounts) and confirms.
6. mbuzz persists the connection to its database with platform=`google_ads`, the chosen account ID, the encrypted tokens, and the customer's mbuzz account ID for multi-tenant isolation.

### 3.2 Daily sync

Every 24 hours, an `AdPlatforms::SpendSyncSchedulerJob` enqueues per-connection sync jobs. Each `SpendSyncJob`:

1. Refreshes the access token via the refresh token if expired.
2. Issues a `googleAds:search` request scoped to the connection's customer ID and the previous day's date range.
3. Parses the response into `AdSpendRecord` rows and upserts them into PostgreSQL.
4. Increments mbuzz's internal API usage counter (visible to operators) so we stay within the Standard Access daily ops budget.

### 3.3 Data storage and security

- **Tokens at rest:** `access_token` and `refresh_token` columns on the `ad_platform_connections` table use Rails 8 ActiveRecord encryption (AES-256-GCM) with keys stored in Rails encrypted credentials, never in source control.
- **Multi-tenancy:** every database query is scoped to the customer's mbuzz account. Cross-account access is blocked at the ORM layer; this is enforced by static patterns in the codebase plus integration tests that explicitly verify "Account A cannot see Account B's data."
- **TLS:** all Google API requests use `https://googleads.googleapis.com` over TLS 1.2+ (Ruby's `Net::HTTP` with `use_ssl: true`).
- **Logging:** API request/response payloads are not logged. Only metadata (URL, status code, sync run ID, customer ID) is recorded for operational debugging.
- **Disconnect:** customers can disconnect their Google Ads account from mbuzz at any time via `https://mbuzz.co/account/integrations/google_ads/{connection_id}` → "Disconnect" button. On disconnect, the OAuth tokens are wiped from mbuzz's database and the connection is marked inactive (no further API calls). Historical `AdSpendRecord` rows are retained for the customer's own reporting continuity but no further data is fetched.
- **Customer data deletion:** on customer account deletion, all associated `AdPlatformConnection` rows, `AdSpendRecord` rows, and OAuth tokens are deleted via cascading destroy.

### 3.4 Rate-limit handling

mbuzz tracks Google Ads API operations via a global `AdPlatforms::ApiUsageTracker` (one daily counter, app-wide). At Basic Access this is capped at 15,000 ops/day. At Standard Access we'd raise the cap. We send an internal alert at 80% of the daily budget so we can throttle or pause syncs before hitting the hard limit.

---

## 4. User Experience and Permissions

### 4.1 Customer-facing copy

The Google Ads card on the mbuzz Integrations page reads: *"Connect to track ad spend and ROAS."* Clicking through reveals an explainer that mbuzz pulls daily spend metrics read-only and does not modify the customer's Google Ads account.

### 4.2 OAuth consent screen

The consent screen (provided by Google) displays the requested scope (`adwords`) and the developer email (`hello@mbuzz.co`). The mbuzz application name and logo are registered with the OAuth consent screen in Google Cloud Console.

### 4.3 Privacy policy

The mbuzz privacy policy at https://mbuzz.co/privacy describes:
- What data we collect when a customer connects Google Ads (the spend metrics listed in §2.2)
- How we use it (only for the customer's own ROAS reporting)
- That we do not sell, share with third parties, or use for advertising targeting
- How to disconnect and delete the data
- How to contact us (`hello@mbuzz.co`)

### 4.4 Terms of Service

The mbuzz Terms of Service at https://mbuzz.co/terms include a section on third-party platform integrations specifically covering the Google Ads connection.

---

## 5. Why We Need Standard Access

At Basic Access (15,000 ops/day) we can support approximately 50-100 customer ad accounts at the current sync cadence. We are nearing that ceiling. Standard Access is required to scale customer onboarding without artificially throttling syncs, hitting daily-cap errors, or reducing the daily-sync frequency below the value our customers expect.

We have demonstrated low operational risk under Basic Access:
- Zero policy violations
- No write operations attempted
- Compliance with rate limits

---

## 6. Demonstration Materials

A demo video showing the OAuth flow, account picker, daily-sync result, and disconnect flow is available at: **[demo-video-url-to-be-attached-to-submission]**.

A test login to mbuzz's staging environment is available on request via `hello@mbuzz.co`. Test users will be granted via the OAuth consent screen's "Test users" allowlist for the duration of the review.

---

## 7. Contact

- **Company:** Forebrite Pty Ltd, Australia
- **Product:** mbuzz — https://mbuzz.co
- **Privacy policy:** https://mbuzz.co/privacy
- **Terms of service:** https://mbuzz.co/terms
- **API contact email:** hello@mbuzz.co
- **Developer:** vlad@petpro360.com.au

---

## Appendix A — Field-level data inventory

For each Google Ads field mbuzz reads, the table below documents the use:

| Field | Purpose |
|---|---|
| `customer.id` | Identifier for the customer's Google Ads account (stored on the connection row) |
| `customer.descriptive_name` | Display name shown in the mbuzz account picker |
| `customer.currency_code` | Currency for spend display in mbuzz dashboards |
| `customer.manager` | Whether the connected account is an MCC; routes us to sub-account enumeration |
| `customer_client.*` | Sub-account discovery for MCC connections |
| `campaign.id` | Internal grouping of `AdSpendRecord` rows by campaign |
| `campaign.name` | Display in dashboards (channel performance detail table) |
| `campaign.advertising_channel_type` | Maps Google's campaign types to mbuzz's normalized channel set (paid_search, display, video, etc.) |
| `segments.date` | Day-level rollups in dashboards |
| `segments.hour` | Hour-of-day analysis (when ROAS peaks) |
| `segments.device` | Device-segment analysis (mobile vs desktop ROAS) |
| `segments.ad_network_type` | Distinguishes Google search vs display vs YouTube |
| `metrics.cost_micros` | The spend itself, in micros |
| `metrics.impressions` | Display metric, dashboards |
| `metrics.clicks` | Display metric, dashboards |
| `metrics.conversions` | Reference for Google-side conversions vs mbuzz attribution |
| `metrics.conversions_value` | Reference for Google-side revenue vs mbuzz attribution |
