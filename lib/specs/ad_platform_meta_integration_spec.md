# Meta Ads Adapter

**Date:** 2026-04-28
**Priority:** P1
**Status:** Drafting — awaiting approval to begin TDD
**Branch:** `feature/ad-platforms-meta-linkedin-rollout`
**Parent spec:** `lib/specs/ad_platforms_meta_linkedin_rollout_spec.md` (Phase 2)

---

## Summary

Build a Meta Ads adapter end-to-end on top of the proven `AdPlatforms` adapter pattern. Mirrors Google's tree under `app/services/ad_platforms/meta/`, but designed from day one to satisfy `feedback_no_mocks.md`: pure parsers with real-fixture tests, HTTP shells with no business logic. Gated behind `FeatureFlags::META_ADS_INTEGRATION` (Phase 1 already shipped this).

---

## Current State (verified 2026-04-28)

- **Phase 0 Meta complete** — Business Verification ✅ (Forebrite Pty Ltd), credentials in dev + prod (`Rails.application.credentials.meta_ads.{app_id, app_secret}`), `ads_read` "Ready for testing", live API smoke test returned 25+ ad accounts (including the pet-resort multi-location case).
- **Phase 1 complete** — feature-flag scaffolding usable (`account.feature_enabled?(:meta_ads_integration)`, admin UI, rake task).
- **Adapter pattern proven by Google** — `BaseAdapter`, `Registry`, full Google tree at `app/services/ad_platforms/google/*`. Existing tests heavily mock HTTP — Phase 2 will not.
- **Integrations UI already lists** `ad_platform_connections` regardless of platform; Meta connections will appear automatically once the model rows are written.

---

## Meta API Specifics

### OAuth flow (Facebook Login)

| Step | Endpoint | Inputs | Returns |
|---|---|---|---|
| 1. User consent | `https://www.facebook.com/v19.0/dialog/oauth` | `client_id`, `redirect_uri`, `state`, `scope=ads_read`, `response_type=code` | redirect to `redirect_uri?code=...&state=...` |
| 2. Exchange code → short-lived token | `GET https://graph.facebook.com/v19.0/oauth/access_token` | `client_id`, `client_secret`, `redirect_uri`, `code` | `{ access_token, token_type, expires_in: 7200 }` (~2h) |
| 3. Exchange short → long-lived | `GET https://graph.facebook.com/v19.0/oauth/access_token` | `grant_type=fb_exchange_token`, `client_id`, `client_secret`, `fb_exchange_token=SHORT` | `{ access_token, token_type, expires_in: 5184000 }` (~60 days) |
| 4. Refresh (when expiring) | Same as Step 3 with current long-lived as `fb_exchange_token` | — | New 60-day token |

**No refresh token in OAuth2 sense.** Re-exchange the long-lived token to extend it. If it ever fully expires, user must re-OAuth.

### App Secret Proof

Meta-recommended for server-side calls. Every API request includes `appsecret_proof = HMAC-SHA256(access_token, app_secret).hex` to prove the call originated from the app, not a stolen token.

```ruby
proof = OpenSSL::HMAC.hexdigest("SHA256", app_secret, access_token)
```

Send as query param `appsecret_proof=<hex>` on every `graph.facebook.com` call.

### List ad accounts

```
GET /v19.0/me/adaccounts?fields=id,name,currency,account_status,timezone_name
    &access_token=...&appsecret_proof=...
```

- `id` format: `act_NNNNNNN` — keep the prefix; the Marketing API expects it as part of subsequent paths.
- `account_status`: `1=ACTIVE`, `2=DISABLED`, `3=UNSETTLED`, `7=PENDING_RISK_REVIEW`, `8=PENDING_SETTLEMENT`, `9=IN_GRACE_PERIOD`, `100=PENDING_CLOSURE`, `101=CLOSED`, `201=ANY_ACTIVE`, `202=ANY_CLOSED`. **Picker filters to `1`** (mirroring Google's exclusion of disabled accounts).
- Pagination: `paging.next` cursor URL — follow until exhausted.

### Insights endpoint (spend pull)

```
GET /v19.0/{ad_account_id}/insights
    ?level=campaign
    &fields=campaign_id,campaign_name,objective,spend,impressions,clicks,actions,action_values,date_start
    &time_range={"since":"2026-04-01","until":"2026-04-28"}
    &time_increment=1
    &breakdowns=device_platform
    &limit=500
    &access_token=...&appsecret_proof=...
```

- `time_increment=1` → daily rows. `time_increment=hourly` → hourly rows.
- `spend` is a **string** in account currency (`"12.34"`) — convert to micros via `(spend.to_f * 1_000_000).to_i`.
- `actions` is `[{action_type: "purchase", value: "5"}, {action_type: "add_to_cart", value: "12"}]` — count of attributed actions per type.
- `action_values` is `[{action_type: "purchase", value: "299.95"}]` — monetary value of those actions.
- For our `AdSpendRecord.platform_conversions_micros` we'll sum `actions.value` where `action_type == "purchase"` (configurable later).
- For `platform_conversion_value_micros`, sum `action_values.value` where `action_type == "purchase"`.
- Currency comes from the **ad account**, not the row — captured at connect time and stored on `AdPlatformConnection.currency`.

### Channel mapping

All Meta campaigns default to `Channels::PAID_SOCIAL`. Per-campaign overrides via existing `connection.settings.campaign_overrides` (the same pattern Google uses, in `google/campaign_channel_mapper.rb:18`).

### Rate limits

Meta enforces ad-account-level rate limits with HTTP 4 (rate limit) or 32 (page-level rate). At Standard Access ("Ready for testing") limits are tight; at Advanced Access they're production-grade. We'll add exponential backoff but defer fancy bucket tracking to a follow-up if needed.

---

## Design — Stub-Friendly, Mock-Free, VCR for HTTP

### The rule

- **No mocks.** No `Minitest::Mock`, no mocha, no fake objects implementing fake interfaces.
- **Stubs are fine.** `Object#stub` for narrowly-scoped value substitution (e.g. clock, a constant) is allowed.
- **HTTP calls go through VCR.** Record once against the real Meta API, replay forever after. Sensitive headers (Authorization, app_secret, appsecret_proof, access_token) filtered before commit. Cassettes are real shapes, not hand-rolled fakes.

This dissolves the orchestrator-test problem: `ListAdAccounts`, `SpendSyncService`, `TokenRefresher` all hit the real `ApiClient` in tests, with VCR replaying the real Meta response. No DI gymnastics needed.

### The split

| Kind | Examples | Test posture |
|---|---|---|
| **Pure** (no IO) | `OauthUrl`, `RowParser`, `CampaignChannelMapper`, `TokenExchanger` (parser), `LongLivedExchanger` (parser), `ListAdAccountsParser` | Real values in, asserted output. Hand-curated fixture JSON inputs (extracted from VCR cassettes). |
| **HTTP shell** | `TokenClient`, `ApiClient` | Smoke-tested via the orchestrators that compose them — VCR records the actual HTTP. |
| **Orchestrator** (DB + HTTP via shell) | `TokenRefresher`, `ListAdAccounts`, `AcceptConnectionService`, `SpendSyncService`, `Adapter` | Real ApiClient + VCR cassette. Real DB writes. Asserts on resulting state and return values. |

### Files

Mirror Google's tree under `app/services/ad_platforms/meta/`:

```
app/services/ad_platforms/meta.rb                       # constants module (analog of google.rb)
app/services/ad_platforms/meta/oauth_url.rb             # pure URL builder
app/services/ad_platforms/meta/token_client.rb          # HTTP shell — no test
app/services/ad_platforms/meta/token_exchanger.rb       # pure parser; takes response body, returns tokens
app/services/ad_platforms/meta/token_refresher.rb       # composes TokenClient + parser; orchestrator
app/services/ad_platforms/meta/list_ad_accounts.rb      # orchestrator (api_client kwarg)
app/services/ad_platforms/meta/list_ad_accounts_parser.rb  # pure parser; takes API response, returns filtered accounts
app/services/ad_platforms/meta/accept_connection_service.rb  # orchestrator (DB write)
app/services/ad_platforms/meta/api_client.rb            # HTTP shell with appsecret_proof — no test
app/services/ad_platforms/meta/spend_sync_service.rb    # orchestrator
app/services/ad_platforms/meta/row_parser.rb            # pure
app/services/ad_platforms/meta/campaign_channel_mapper.rb  # pure
app/services/ad_platforms/meta/api_usage_tracker.rb     # uses Rails.cache (real cache in test)
app/services/ad_platforms/meta/adapter.rb               # adapter, registered in Registry
```

Controller + views:

```
app/controllers/oauth/meta_ads_controller.rb
app/views/oauth/meta_ads/select_account.html.erb
app/views/accounts/integrations/_meta_ads_card.html.erb
app/views/accounts/integrations/_meta_ads_section.html.erb
app/views/accounts/integrations/meta_ads.html.erb
app/views/accounts/integrations/meta_ads_account.html.erb
```

Plus routes + Registry entry + a verify rake task analog.

---

## Sub-phases (TDD order)

Each sub-phase is one or two commits. RED test → GREEN code → run all tests → next.

### 2.0 — VCR + WebMock setup

- [ ] Add `vcr` and `webmock` to the `:test` group in `Gemfile`. `bundle install`.
- [ ] Configure VCR in `test/test_helper.rb`:
  - `cassette_library_dir = "test/fixtures/vcr_cassettes"`
  - `hook_into :webmock`
  - `default_cassette_options = { record: :once }`
  - `allow_http_connections_when_no_cassette = false` (catches accidental network hits in test)
  - `filter_sensitive_data` for: `Rails.application.credentials.dig(:meta_ads, :app_id)`, `:app_secret`, any captured `access_token` from auth headers, any `appsecret_proof` query param, any `act_NNNNN` ad account IDs (replace with `act_TEST`).
- [ ] Add `.gitignore` entry for cassettes if recording mode is local-only (we WILL commit cassettes after filtering, but block any unfiltered ones).
- [ ] Smoke test: a tiny `vcr_smoke_test.rb` that hits a public endpoint (e.g. `https://api.github.com/zen`) under VCR, confirms cassette is created and replays.

### 2.1 — Constants module + pure OauthUrl

- [ ] `app/services/ad_platforms/meta.rb` with API base, version, endpoints, scopes, redirect URIs, credentials accessor.
- [ ] `OauthUrl` — pure, takes `state:` + injected `client_id:` + `redirect_uri:`. Test asserts URL contains every expected param.
- [ ] No HTTP, no stubs.

### 2.2 — TokenClient (HTTP shell) + TokenExchanger (pure parser)

- [ ] `TokenClient` makes the HTTP call; no test (pure shell).
- [ ] `TokenExchanger` takes a response body hash, returns `{ success:, access_token:, expires_at: }` or error. Tests pass real Meta JSON shapes.
- [ ] **NB:** Meta returns short-lived. `TokenExchanger.call` returns the short-lived token; the controller calls `TokenExchanger` then `LongLivedExchanger` (or just chains via `.then`).

### 2.3 — TokenRefresher (orchestrator)

**Note:** `LongLivedExchanger` was originally specced as a separate class. Realised mid-2.2 that Meta's short-lived and long-lived token responses have identical shape (`{access_token, token_type, expires_in}`), so `TokenExchanger` already handles both — no separate parser needed. The controller will call `TokenExchanger` twice with different `TokenClient` invocations (one for code-exchange, one for fb_exchange_token).

- [ ] `TokenRefresher` orchestrator: takes a connection with an existing long-lived token, fires `TokenClient.new(params: { grant_type: "fb_exchange_token", client_id:, client_secret:, fb_exchange_token: current })`, parses with `TokenExchanger`, updates the connection in place. Tests use VCR cassette `meta/token_refresh/{success,expired}.yml`.

### 2.4 — ApiClient (HTTP shell with appsecret_proof)

- [ ] Single class wrapping `Net::HTTP` with auth, content-type, and appsecret_proof. No business logic. Pure shell.
- [ ] No unit test. Smoke-tested manually against the live API in Phase 5.

### 2.5 — ListAdAccountsParser (pure) + ListAdAccounts (orchestrator)

- [ ] Parser: takes Meta `/me/adaccounts` JSON, returns array of `{ id:, name:, currency:, status:, timezone: }` filtered to `account_status: 1`. Tests with hand-extracted fixture JSON (sanitized from the Phase 0 smoke-test response).
- [ ] Orchestrator: composes ApiClient + Parser, follows `paging.next`. Tests via VCR cassette `meta/list_ad_accounts/{single_page,multi_page,empty}.yml`.

### 2.6 — AcceptConnectionService

- [ ] DB-writer orchestrator. Inputs: account, selected ad-account params, validated tokens (already exchanged + long-lived). Creates `AdPlatformConnection` with `platform: :meta_ads`, kicks off backfill job.
- [ ] Tests with real DB. No HTTP (tokens passed in, not fetched).

### 2.7 — Adapter + Registry registration

- [ ] `Adapter` exposes `fetch_spend / refresh_token! / validate_connection`.
- [ ] Register in `AdPlatforms::Registry` under `:meta_ads`.
- [ ] Test: `Registry.adapter_for(meta_connection)` returns Meta adapter instance.

### 2.8 — Oauth::MetaAdsController (full surface)

- [ ] Routes for connect / callback / select_account / create_connection / reconnect / disconnect (mirror Google's `config/routes.rb:15-22`).
- [ ] Controller, `skip_marketing_analytics`, `before_action :require_login`.
- [ ] **Feature-flag gate at top of `#connect`** — redirect to integrations page with "feature not enabled" notice if flag off.
- [ ] Plan-limit gate (already platform-agnostic via `can_add_ad_platform_connection?`).
- [ ] Account-session pinning (re-use Google's `oauth_account_id` session key pattern).
- [ ] Token chain on callback: `TokenClient (code) → TokenExchanger → TokenClient (fb_exchange) → LongLivedExchanger`. Result stored in session for `select_account`.
- [ ] Race-safe re-check in `#create_connection`.
- [ ] Tests: feature flag gate, plan limit gate, OAuth state validation, account session pinning, race on save.

### 2.9 — RowParser + CampaignChannelMapper (pure)

- [ ] `RowParser` takes a single insights row + connection, returns `AdSpendRecord` attrs. Spend conversion (`spend.to_f * 1_000_000`), action sums, channel mapping.
- [ ] `CampaignChannelMapper` defaults to `paid_social`, honors per-campaign overrides via `connection.settings.campaign_overrides` (existing pattern).
- [ ] Tests with real Meta insights row fixtures.

### 2.10 — SpendSyncService (orchestrator)

- [ ] Pulls insights via ApiClient (with pagination), parses each row, upserts via `AdSpendRecord.upsert_all(unique_by: :idx_spend_unique)`. Increments usage meter.
- [ ] Tests via VCR cassette `meta/insights/{daily_single_campaign,daily_multi_campaign,paginated,empty}.yml`. Real DB writes asserted via `AdSpendRecord.count`, channel mapping, currency stamping, conversion sums.

### 2.11 — Integrations UI

- [ ] `_meta_ads_card.html.erb` (live state — shown only when flag enabled).
- [ ] `_meta_ads_section.html.erb` (list of connected Meta accounts).
- [ ] `meta_ads.html.erb` + `meta_ads_account.html.erb` (per-connection detail).
- [ ] Update `accounts/integrations/show.html.erb`: when `feature_enabled?(:meta_ads_integration)`, render the live Meta card; else keep the existing Coming Soon card.
- [ ] No tests for views beyond a controller-level smoke test (`get accounts_integrations_path` includes "Meta Ads" when flag on, doesn't when off).

### 2.12 — Verify rake task

- [ ] `lib/tasks/ad_platforms.rake` add `meta:verify_credentials` — make a live `me/adaccounts` call using the same pattern as `verify_basic_access` for Google.
- [ ] Smoke test only; no automated test.

---

## Tests

**Rule:** no mocks (no mock objects, no `Minitest::Mock`). `Object#stub` is allowed for narrow value substitution. HTTP goes through **VCR cassettes** recorded once against the real Meta API. Cassettes are committed (post-filter) and replayed deterministically.

**Cassette filtering checklist before commit:** `app_id`, `app_secret`, `access_token` (from `Authorization: Bearer …` and from query strings), `appsecret_proof`, real `act_NNNN` ad account IDs (replace with `act_TEST_001` etc.), real campaign IDs, real campaign names that contain customer info.

### Per-class test list (high-level)

| Class | Test count (target) | Notes |
|---|---|---|
| `OauthUrl` | 6 | pure |
| `TokenExchanger` (parser) | 5 | pure |
| `LongLivedExchanger` (parser) | 4 | pure |
| `TokenRefresher` (orchestrator) | 3 | VCR `meta/token_refresh/{success,expired,bad_token}.yml` |
| `ListAdAccountsParser` | 6 | pure |
| `ListAdAccounts` (orchestrator) | 3 | VCR `meta/list_ad_accounts/{single_page,multi_page,empty}.yml` |
| `AcceptConnectionService` | 5 | real DB; tokens passed in (no HTTP), so no VCR needed here |
| `Adapter` | 3 | unit-style; refresh_token! tested via VCR |
| `RowParser` | 8 | pure |
| `CampaignChannelMapper` | 4 | pure |
| `SpendSyncService` | 6 | VCR `meta/insights/{daily_single,daily_multi,paginated,empty}.yml` |
| `Oauth::MetaAdsController` | 10 | feature-flag gate (no HTTP), plan-limit gate, state validation, callback (VCR), account selection rendering (VCR), create_connection happy path, race re-check, reconnect (VCR), disconnect, cross-account isolation |
| Integration page rendering | 2 | flag on → "Meta Ads" rendered live; flag off → "Coming Soon" card |

### Fixtures

- `test/fixtures/vcr_cassettes/meta/**/*.yml` — recorded once against Meta API, sensitive data filtered, committed.
- `test/fixtures/files/meta_adaccounts_list.json` + `meta_insights_daily.json` — extracted from cassettes, used by *parser* tests so they don't depend on the cassette+VCR machinery.

**Recording protocol (one-off per cassette):**
1. Set `META_ACCESS_TOKEN=<live token>` in the shell.
2. Run the target test once with `VCR_RECORD_MODE=new_episodes` env var.
3. Inspect the resulting `.yml` for any unfiltered secrets — fix the filter list and re-record if found.
4. Commit the cassette.

### Manual QA (after Sub-phase 2.12)

1. `bin/rails feature_flags:enable ACCT=<dev-acct> FLAG=meta_ads_integration`
2. Visit `/account/integrations` — verify Meta Ads connect card renders.
3. Click Connect → grant consent on Meta → land on account picker.
4. Select an ad account → verify connection row created with status `connected`.
5. Verify backfill job enqueued and (after a minute) `AdSpendRecord` rows present.
6. Disconnect → verify status flips, plan-limit count drops, slot reclaimed.
7. Force token expiry (set `token_expires_at = 1.day.ago` in console) → reload page → "Re-authenticate" button appears → click through → tokens refresh in place.
8. As a non-flagged account, visit `/account/integrations` — verify Meta Ads card stays as Coming Soon, deep-link to `/oauth/meta_ads/connect` redirects with "feature not enabled".

---

## Definition of Done

- [ ] All 13 service classes shipped with passing tests (where applicable per the table above)
- [ ] `Oauth::MetaAdsController` ships with full surface mirroring Google's
- [ ] `AdPlatforms::Registry` registers `:meta_ads`
- [ ] `bin/rails test` passes (other than the pre-existing `Dashboard::ExportJobTest` flakes)
- [ ] Manual QA matrix above completes against the dev account
- [ ] No new uses of `.stub` or `Minitest::Mock`; existing Google `.stub` calls untouched (not in scope here)
- [ ] Rake `ad_platforms:meta:verify_credentials` smoke-tests live API against connected dev account
- [ ] Spec moved to `lib/specs/old/` after Phase 5 prod test passes

---

## Out of Scope

- **Hourly granularity sync** — Meta's `time_increment=hourly` works but doubles row count. Default to daily for now; hourly is a follow-up flag on the connection.
- **Custom conversion event mapping** — we hardcode `purchase` action sums. UI to pick which action types count as conversions is a follow-up.
- **Backfilling existing Google connections with Meta-style metadata** — Phase 4 territory.
- **App Review submission for Live access** — separate workstream, parallel to Phase 5.
- **Refactoring existing Google `.stub` tests** — out of scope; explicit non-goal of this branch.
- **Microsoft / Pinterest / TikTok adapters** — separate specs.

---

## Open Questions

1. **Test approach** — settled. VCR for HTTP, stubs for narrow value substitution, no mocks. `feedback_no_mocks.md` stays accurate; this branch updates it to clarify "VCR for real API recording is the preferred path for HTTP-touching tests."
2. **Long-lived exchange now or later.** Ship with Sub-phase 2.3. Connections breaking every 2h in prod is unacceptable.
3. **`appsecret_proof` everywhere or just on insights.** Everywhere — cheap, recommended by Meta, no downside.
4. **`paging.next` cursor URL handling.** Follow as-is. The URL already includes the auth params; no need to rebuild.
5. **Naming: `meta_ads_integration`** — settled in Phase 1.
