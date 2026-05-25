# Google Ads OAuth Verification — Demo Video Script

For the Google Cloud Console **Verification Center → Data access → Demo video** field. The `https://www.googleapis.com/auth/adwords` scope is on Google's "sensitive scopes" list, so verification requires:

- A YouTube **Unlisted** video (Vimeo / Loom / Drive links are rejected)
- Narrated walkthrough of the OAuth flow + how the scope's data is used
- **Real data** — mock/empty demos are a documented rejection reason

Target length: ~2:30. Real ad spend data must already be syncing in the connected mbuzz account *before* recording.

---

## Pre-recording checklist

- [ ] OAuth consent screen → Audience → **Test users** includes the Google account being used in the demo
- [ ] That Google account has admin/standard access on a Google Ads customer with cost > $0
- [ ] Branding has been verified in Verification Center (green check)
- [ ] mbuzz account being demoed has `FeatureFlags::GOOGLE_ADS_INTEGRATION` enabled
- [ ] At least one daily sync has populated `dashboard/spend` with real numbers

---

## Script

### [0:00–0:15] Identity & context

*Screen: `mbuzz.co` homepage*

> "Hi, this is the OAuth verification demo for mbuzz. mbuzz is a multi-touch attribution platform that helps marketing teams understand the true return on their ad spend by joining ad-platform spend data with first-party conversion events. I'll walk through how we use the Google Ads `adwords` scope, end to end."

### [0:15–0:30] Sign in & navigate

*Screen: log into mbuzz, click Account → Integrations. Land on `/account/integrations`. Cursor on the Google Ads row.*

> "I'm logged in to a customer account. Settings → Integrations. Google Ads is one of several ad platforms we connect. I'll click Connect."

*Click the Connect button on the Google Ads card.*

### [0:30–1:00] OAuth flow & explicit scope callout

*Screen: Google's consent screen. Hover the cursor over the "See, edit, create, and delete your Google Ads accounts and data" line.*

> "This is the standard Google consent screen. The user-facing description here says 'see, edit, create, and delete' — that's Google's canonical scope label. **In practice mbuzz only reads.** We never create, edit, or delete a single campaign, ad group, ad, keyword, or budget. The Google Ads API requires the `adwords` scope for any read access — there is no read-only equivalent."

*Click Allow.*

### [1:00–1:30] Customer selection (`select_account.html.erb`)

*Screen: mbuzz select-account page, list of Google Ads customers from `customers:listAccessibleCustomers`.*

> "We're back in mbuzz. This list comes from one API call — `customers:listAccessibleCustomers` — which returns the Google Ads customer IDs the user already has access to. Nothing else. The user picks which account to connect."

*Pick one account, click Connect.*

### [1:30–2:00] Connection detail page (`google_ads_account.html.erb`)

*Screen: Google Ads account detail page. Point cursor at: Data coverage, Total records, Last synced, Sync History.*

> "Connection's live. mbuzz immediately runs an initial sync — we hit the `googleAds:search` endpoint via GAQL to pull campaign-level performance metrics: cost, impressions, clicks, conversions, at daily granularity. That's it — no PII, no audience data, no creative assets. The Sync History shows each daily pull. After the first run, this happens automatically once a day."

### [2:00–2:30] Where the data lives (`dashboard/spend/show.html.erb`)

*Screen: navigate to Spend dashboard. Show the green "Google Ads connected" indicator, hero KPI cards, trend chart, channel breakdown.*

> "And here's where it goes. The cost data we just pulled is joined with conversions tracked via mbuzz's own SDK on the customer's site, to compute attributed ROAS, CAC, and budget recommendations. Refresh tokens are encrypted at rest, scoped per tenant. Data is retained for the lifetime of the customer's account and deleted within thirty days of offboarding. We do not sell, share, or transfer this data. Thanks for reviewing."

---

## Recording tips

- **Capture tool**: OBS or QuickTime → MP4 → upload to YouTube. Loom direct links don't pass the form's URL validation.
- **Visibility**: Unlisted (not Private — reviewer needs to view without sign-in; not Public — no need to expose).
- **Mouse cursor visible**, no keyboard shortcuts.
- **No music**, clean narration only.
- **Hide**: dev tools, terminal, IDE, browser bookmarks bar with anything personal.
- **Real ad account** with cost > $0. Even own account is fine if it has live spend.

---

## Two non-obvious moves that improve approval odds

1. **Call out the scope-label mismatch at 0:45.** Google's canonical "See, edit, create, and delete" label scares reviewers into thinking apps want write access. Pre-empting that with "we only read" reduces back-and-forth.
2. **Show real spend numbers landing in the dashboard at 2:15.** Reviewers explicitly check this. Empty/mock dashboards are flagged.

---

## Form fields to populate alongside the video

### Scope justification (1000 char limit)

```
mbuzz is a multi-touch attribution platform. We join ad-platform spend
with first-party conversion events tracked via our own SDK to compute
attributed ROAS, CAC, and budget recommendations.

Why we request /auth/adwords:
The Google Ads API requires this scope for any read access. We use it
exclusively read-only via:
- customers:listAccessibleCustomers — at OAuth time, to let the user
  pick which Google Ads account(s) to connect.
- googleAds:search (GAQL) — daily, to pull campaign-level performance
  metrics: cost, impressions, clicks, conversions.

What we do NOT do:
We never create, edit, or delete campaigns, ad groups, ads, keywords,
audiences, budgets, or any other entity. We never write to the user's
Google Ads account in any form. We do not access user PII — only
campaign performance metrics tied to the user's own account.

Storage and retention:
OAuth refresh tokens are encrypted at rest, scoped per tenant.
Campaign data is retained for the lifetime of the customer's mbuzz
account and deleted within 30 days of offboarding or on request.
We do not sell, share, or transfer this data to any third party.
```

### Additional info box

```
Test user for review: <add the test user email here at submit time —
already added under OAuth consent screen → Test users>.

OAuth client lives in GCC project: mbuzz-489003.

Note: the canonical scope description ("see, edit, create, delete")
overstates our usage — mbuzz is strictly read-only. See scope
justification above for endpoints used.
```

---

## Related files

- Adapter: `app/services/ad_platforms/google/`
- Controller: `app/controllers/oauth/google_ads_controller.rb`
- Connection detail view: `app/views/accounts/integrations/google_ads_account.html.erb`
- Spend dashboard: `app/views/dashboard/spend/show.html.erb`
- Feature flag: `app/constants/feature_flags.rb` (`GOOGLE_ADS_INTEGRATION`)
- Verify-token rake: `bin/rails ad_platforms:verify_basic_access`
- Sibling doc: `lib/docs/google_ads_api_application.md` (Basic Access developer-token application — already approved 2026-03-11)
