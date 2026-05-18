# Platform API Approvals

**Date:** 2026-03-05 (last updated 2026-05-15)
**Priority:** P1
**Status:** In Progress

---

> **Context**: Google Ads Basic Access was approved 11 Mar 2026, OAuth consent screen published 15 May 2026 (read-only, awaiting incognito confirmation). UAT for Ad Spend Intelligence is unblocked (see `ad_spend_intelligence_spec.md`). To avoid similar bottlenecks for future platforms, we're preemptively starting approval processes that don't require working code.

---

## Summary

Pre-register for ad platform API access across Meta Ads, LinkedIn Ads, and TikTok Ads ahead of building their adapters. Each platform has different approval gates, timelines, and requirements. LinkedIn and Meta Business Verification can start immediately (no code needed). TikTok deferred, fast approval but requires a working demo.

---

## Platform Comparison

| | Google Ads | Meta Ads | TikTok | LinkedIn |
|---|---|---|---|---|
| **Access needed** | Basic Access | Advanced Access (`ads_read`) | Production | Development tier |
| **Timeline** | 3-7 biz days | 2-4 weeks (multi-step) | 1-3 weeks | 2-4 weeks |
| **Requires working demo?** | Yes (design doc PDF) | Yes (screencast) | Yes (demo video) | No |
| **Can apply before building?** | Partially | Business Verification: yes | No | Yes |
| **Blocking risk** | HIGH | HIGH — two sequential gates | Medium | Low |

---

## Step 0: Google Ads — Status Snapshot (2026-05-15)

Google Ads has two independent approval tracks. Both must clear before general availability.

### 0.1 Developer token (Google Ads API quota)

- ✅ **Basic Access** granted 11 Mar 2026 (15,000 ops/day, sufficient for read-only spend reporting)
- ❌ **Standard Access** denied 30 Apr 2026 (auto-rejection: account not hitting `RESOURCE_EXHAUSTED` yet). Reapply when daily volume regularly hits the 15k cap. Not blocking.
- Application details, MCC ID, contact email: see Rails credentials and `lib/docs/google_ads_api_application.md`.

### 0.2 OAuth consent screen verification (`adwords` sensitive scope)

- ✅ **Verification submitted** 6 May 2026 (demo video, scope justification, Branding verified)
- ✅ **Published "In production" / External** 15 May 2026 (3 weeks earlier than the 4-6 week ETA)
- ⚠️ **Unverified-app warning not yet confirmed cleared.** Per Google's docs, sensitive-scope apps can publish without verification but show the "Google hasn't verified this app" interstitial and cap at 100 users. Need to walk a fresh OAuth flow in incognito with a non-test-user Google account to confirm the warning is gone.

### 0.3 What Standard denial does NOT block

Read-only spend reporting works fully on Basic. Conversion push (offline conversion imports / Enhanced Conversions) is also technically allowed on Basic up to the 15k ops/day cap. Conversion push is gated separately on:
1. Amending the API Center application to declare conversion-management capability (Q11) and a write-intent business description (Q6)
2. Privacy policy update at `mbuzz.co/privacy` covering server-to-server conversion uploads

Tracked in `lib/specs/future/google_ads_conversion_push_spec.md`. Not in scope for the current GA rollout, which stays read-only.

### 0.4 Next actions for Google

| Action | When | Spec |
|---|---|---|
| Incognito confirmation that consent screen is verified (no warning) | Immediately | `lib/specs/google_ads_rollout_spec.md` Phase 0 |
| Flip view-card gate from `Rails.env.production?` to feature flag | After 0.4 row 1 | `lib/specs/google_ads_rollout_spec.md` Phase 1 |
| Bulk-enable `GOOGLE_ADS_INTEGRATION` for paid accounts | After 0.4 row 2 | `lib/specs/google_ads_rollout_spec.md` Phase 2 |
| Pet-resort production E2E | After 0.4 row 3 | `ad_platforms_meta_rollout_spec.md` Phase 5 |
| Reapply for Standard when volume warrants | When daily ops hit 15k cap | This spec |

---

## Step 1: LinkedIn — Apply for Advertising API (Development Tier)

**Time:** ~15 min. No code required.
**Status:** Submitted 5 Mar 2026. Awaiting review (expect 2-4 weeks).

### Steps

- [x] 1.1 Go to [linkedin.com/developers](https://developer.linkedin.com/) — sign in with LinkedIn account
- [x] 1.2 Click **Create App**
  - App name: `mbuzz`
  - LinkedIn Page: created new company page ("Multi-touch attribution for modern marketing teams.")
  - App logo: mbuzz logo
  - Legal agreement: accept
- [x] 1.3 Verify company association (Page Admin approval via verification URL)
- [x] 1.4 On the app's **Products** tab, find **Advertising API** and click **Request Access**
- [x] 1.5 Submitted 5 Mar 2026

### Notes

- Development tier gives **unlimited read access** — sufficient for read-only spend reporting. No upgrade to Standard needed unless we add campaign management (we won't).
- OAuth credentials and redirect URIs configured later when building the adapter.
- No demo video required.
- Company Page admins are not publicly visible — no personal linkage concern.

---

## Step 2: Meta — Business Verification

**Time:** ~30 min. No code required.
**Status:** BLOCKED — waiting on mbuzz entity registration. See note below.
**Prerequisite:** Registered ABN or business entity for mbuzz

> **BLOCKED 5 Mar 2026**: Business Verification requires a document (ABN, incorporation cert) whose legal name matches the portfolio name "Mbuzz". No mbuzz ABN exists yet. Planned entity structure: Mehakovic Investments → Timzen (IP) → mbuzz. **Action: discuss entity structure with accountant, then register ABN, then complete verification.** The Meta developer app and Business Portfolio are already created — verification can be triggered at any time from Security Centre.

### Completed So Far

- [x] 2.1 Created Meta Business Portfolio "Mbuzz" (ID: `1084802053831776`)
- [x] 2.2 Created developer app "mbuzz" (ID: `1572699803993069`) at [developers.facebook.com](https://developers.facebook.com/)
  - Use case: "Measure ad performance data with Marketing API"
  - Registered as Tech Provider (unlocks Business Verification + Access Verification + App Review)
- [ ] 2.3 **Start Business Verification** (Settings > Security Centre > Start verification)
  - Requires: legal business name matching documents, address, phone, website
  - Document: ABN registration or incorporation certificate
  - Domain verification: DNS TXT record or meta tag on `mbuzz.co`
  - Expect 1-14 business days after submission (typically 2-5)

### Gotchas

- Legal name on documents must match **exactly** what's entered in Business Manager — #1 rejection reason
- Meta's portfolio name validator rejects lowercase-only names (had to use "Mbuzz" not "mbuzz")
- Business Verification only appears after registering as Tech Provider (not visible on fresh portfolios)

---

## Step 3: Meta — App Configuration + OAuth Setup

**Time:** ~20 min.
**Status:** Partially complete (app created, OAuth not configured yet)
**Prerequisite:** Step 2 (Business Verification) must be complete for Advanced Access

### Steps

- [x] 3.1 Developer app created (see Step 2)
  - App type: **Business**
  - App name: `mbuzz`
  - Link to verified Business Manager
- [ ] 3.2 Under **App Settings > Basic**, configure:
  - Privacy Policy URL: `https://mbuzz.co/privacy`
  - App Domain: `mbuzz.co`
  - Platform: Website, Site URL: `https://mbuzz.co`
- [ ] 3.3 Under **Add Products**, add **Marketing API**
  - This grants **Standard Access** — read your own test ad account with throttled rate limits
- [ ] 3.4 Configure OAuth:
  - Note App ID + App Secret from **Settings > Basic**
  - **Facebook Login > Settings**: add redirect URIs:
    - `https://mbuzz.co/oauth/meta_ads/callback`
    - `http://localhost:3000/oauth/meta_ads/callback`
  - Required scope: `ads_read`
- [ ] 3.5 Add credentials to Rails:
  ```bash
  bin/rails credentials:edit
  # meta_ads:
  #   app_id: "xxx"
  #   app_secret: "xxx"
  ```
- [ ] 3.6 Build Meta adapter against own test ad account using Standard Access

### Notes

- Standard Access rate limits are heavily throttled — Airbyte/Fivetran warn it's "infeasible" for production syncs. Fine for development only.
- Do not submit for Advanced Access until the adapter works end-to-end.

---

## Step 4: Meta — Advanced Access (`ads_read`)

**Time:** ~30 min to prepare submission.
**Status:** Not started
**Prerequisite:** Step 3 complete + working Meta adapter

### Steps

- [ ] 4.1 In app dashboard, go to **App Review > Permissions and Features**
- [ ] 4.2 Find `ads_read` → click **Request Advanced Access**
- [ ] 4.3 Record screencast video (upload to YouTube or similar):
  - Show full OAuth flow — user connects Meta ad account
  - Show data syncing and spend dashboard displaying real metrics
  - Narrate what's happening
  - Use real data (not mock/dummy)
- [ ] 4.4 Write detailed use case description:
  > "mbuzz connects to Meta Ads to pull read-only spend data (campaign spend, impressions, clicks). This data is joined with our multi-touch attribution models to calculate attributed ROAS, CAC, and budget recommendations. We never write to ad accounts or modify campaigns."
- [ ] 4.5 Ensure privacy policy at `mbuzz.co/privacy` specifically mentions how Meta data is handled
- [ ] 4.6 Submit for review (expect 2-7 business days)
- [ ] 4.7 If rejected: read feedback, fix issues, resubmit (each round adds 3-5 days)
- [ ] 4.8 Once approved, switch app to **Live** mode (Settings > Basic > toggle at top)

### Common Rejection Reasons

- Screencast doesn't clearly show how `ads_read` data is used
- Privacy policy is generic / doesn't address Meta data specifically
- Requested permissions beyond what's needed
- No narration in screencast
- Demo uses mock/dummy data

---

## Step 5: TikTok — Deferred

**Status:** Deferred until Meta + LinkedIn adapters are underway
**Reason:** Fast approval (days not weeks) but requires a working demo. No long blocking step to preemptively clear.

### When ready:

- [ ] 5.1 Create developer account at [developers.tiktok.com](https://developers.tiktok.com/)
- [ ] 5.2 Create app and develop against **Sandbox** (no approval needed)
- [ ] 5.3 Record demo video showing working integration
- [ ] 5.4 Submit for Production review (expect 2-5 business days)

### Notes

- Binary access: Sandbox (test data) or Production (live). No tiered system.
- Single approval process — no separate OAuth or business verification gates.
- Demo video domain must match the website URL in the application.
- Remove unnecessary scopes/products before submitting (common rejection reason).

---

## All Platforms — Approval Status

| Platform | Status | API Complexity | Notes |
|---|---|---|---|
| **Google Ads** | Basic Access ✅ (11 Mar 2026), Standard denied (30 Apr 2026, auto, reapply when 15k cap hit), OAuth published 15 May 2026 (verification of unverified-warning clearance pending) | High | OAuth + developer token + consent screen verification |
| **Meta Ads** | App created, Business Verification blocked on entity | High | Tech Provider path, Business + Access Verification + App Review |
| **LinkedIn Ads** | Submitted 5 Mar 2026 (expect 2-4 weeks) | Medium | Development tier sufficient for read-only |
| **TikTok Ads** | Deferred | Low | Sandbox → Production, single approval, fast |
| **Microsoft Ads (Bing)** | Not started | Low | Similar to Google, no tiered access — just register app |
| **Pinterest Ads** | Not started | Low | Standard OAuth, no multi-step approval |
| **Snapchat Ads** | Not started | Low | Standard OAuth |
| **Reddit Ads** | Not started | Low | Standard OAuth |
| **X (Twitter) Ads** | Not started | Medium | Elevated access needed for ads endpoints |
| **Apple Search Ads** | Not started | Medium | Uses Apple's own auth (not OAuth), certificates |
| **Phone/Call Tracking** | Not started | Varies | CallRail, etc. — spec separately |
| **CSV Import** | Not started | None | No API approval needed |

## Action Plan

| Action | When | Time | Starts Clock |
|---|---|---|---|
| LinkedIn: Create app + request Advertising API | ~~This week~~ Done | 15 min | 2-4 week review |
| Meta: Business Verification | After entity registration (accountant) | 30 min | 1-14 day review |
| Meta: Advanced Access submission | After adapter works | 30 min | 2-7 day review |
| TikTok: Full process | When ready to build adapter | 1 hour | 2-5 day review |
