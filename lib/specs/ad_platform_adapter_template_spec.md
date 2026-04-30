# Ad Platform Adapter — Standard Template

**Date:** 2026-04-30
**Status:** Living template — copy when adding any new ad-platform adapter
**Reference implementations:** `app/services/ad_platforms/google/`, `app/services/ad_platforms/meta/`

---

## How to use this template

1. Copy this file to `lib/specs/ad_platform_{platform}_integration_spec.md`.
2. Replace `{platform}` and `{Platform}` placeholders with the new platform's slug (e.g. `linkedin_ads`, `LinkedinAds`, `Linkedin`).
3. Fill the **Current State** and **API Specifics** sections with platform-specific values.
4. Walk the seven phases in order. Each sub-phase is one or two atomic commits — RED test → GREEN code → run all tests → next.
5. Tick the Definition of Done before merging.

The point of this template: every adapter ships with the same shape, the same test posture, the same billing visibility, and the same metadata story. Reviewers and operators only need to learn the pattern once.

---

## Why this exists

We have two adapters live (Google, Meta). Both took longer than expected and drifted in subtly different directions during build. This template pins the contract so the third, fourth, and fifth adapters cost a fraction of the time and a reviewer can verify completeness against a single checklist.

The non-negotiables across every adapter:

- **Global `AdPlatforms::ApiUsageTracker` wired up.** Billing visibility is not optional. The tracker is shared across all adapters; new adapters add their key to `LIMITS` and `DISPLAY_NAMES` and call `AdPlatforms::ApiUsageTracker.increment!(:platform_name)` from their `ApiClient`. Never create a per-platform tracker class.
- **Per-connection `metadata` is plumbed end-to-end.** Connection metadata merges onto every `AdSpendRecord` row at sync time so multi-location dashboards work without joins. Dashboard surfacing of that metadata (filter + breakdown card) is owned by `lib/specs/spend_dashboard_metadata_breakdown_spec.md` — new adapters get the dashboard slicing automatically once the data lands, no per-adapter dashboard work.
- **No mocks in tests.** Pure parsers test against fixture JSON. Orchestrators test through real HTTP via VCR cassettes. See `feedback_no_mocks.md`.
- **Feature flag at the entry point.** Every new adapter gates on `current_account.feature_enabled?(FeatureFlags::{PLATFORM}_INTEGRATION)` until it's stable enough for general release.
- **`skip_marketing_analytics` on the OAuth controller.** OAuth pages render tokens and identifiers; GA4 / Meta Pixel must not load.
- **Account-scoped queries everywhere.** `account.ad_platform_connections.find_by_prefix_id!` — never `AdPlatformConnection.find`.

---

## Current State (fill in per platform)

| Surface | State |
|---|---|
| API approval / dev tier | _e.g. "Approved 2026-03-05, scopes: r_ads"_ |
| Credentials present | `Rails.application.credentials.dig(:{platform}, :app_id)` and `:app_secret` in dev + prod |
| `AdPlatformConnection` enum | Already lists `{platform}` (`app/models/ad_platform_connection.rb`) — verify before starting |
| Plan-limit gate | Inherited from `account.can_add_ad_platform_connection?` — no per-platform work |
| Coming-soon UI | Card already renders as "Soon / Notify Me" — Phase 5 swaps in the live card |
| Feature flag scaffolding | `Account::FeatureFlags` and `FeatureFlags` constants module already exist |

---

## API Specifics (fill in per platform)

| Concern | Value |
|---|---|
| OAuth authorization URL | _e.g. `https://www.facebook.com/v19.0/dialog/oauth`_ |
| Token exchange URL | _e.g. `https://graph.facebook.com/v19.0/oauth/access_token`_ |
| Required scopes | _e.g. `ads_read`, `r_ads_reporting`_ |
| Access token lifetime | _e.g. "2h short-lived → 60d long-lived via re-exchange"_ |
| Refresh model | _OAuth2 refresh token | Re-exchange long-lived | Re-OAuth on expiry_ |
| List ad accounts endpoint | _e.g. `GET /me/adaccounts?fields=...`_ |
| Insights / spend endpoint | _e.g. `GET /{ad_account_id}/insights?level=campaign&...`_ |
| Currency source | _e.g. "ad account level, captured at connect time"_ |
| Spend unit | _e.g. "string in account currency, multiply by 1_000_000 for micros"_ |
| Conversion fields | _e.g. "actions[].value where action_type == 'purchase'"_ |
| Channel mapping default | _e.g. `Channels::PAID_SOCIAL`_ |
| Rate-limit shape | _e.g. "per-app, daily" or "per-ad-account, hourly"_ |
| Auth proof requirement | _e.g. Meta's `appsecret_proof` HMAC, or none_ |

---

## Phase 0 — Verify external prerequisites

No code. Confirms we can build before we cut a single line.

- [ ] **0.1** `bin/rails credentials:show` — confirm `{platform}.app_id`, `{platform}.app_secret` set for development AND production.
- [ ] **0.2** Confirm API access tier (Standard vs Advanced, Development vs Live) on the platform's developer console. Note the approved scopes and rate-limit posture.
- [ ] **0.3** Smoke-test the credentials against the live API with a one-off rake / curl: list ad accounts, confirm at least one row returned.
- [ ] **0.4** Update `lib/specs/platform_api_approvals_spec.md` with current status. If not approved, document the blocker and pause this spec.
- [ ] **0.5** Confirm any production account IDs we plan to onboard. Record in 1Password — never commit IDs to git per CLAUDE.md hard rule.

**Exit criteria:** working credentials + confirmed API access, OR a documented decision to proceed against sandbox / dev tier with explicit limitations recorded.

---

## Phase 1 — Feature flag

`Account::FeatureFlags` already exists. This phase is a one-line constant addition.

- [ ] **1.1** Add `{PLATFORM}_INTEGRATION = "{platform}_integration"` to `app/constants/feature_flags.rb` and append to `FeatureFlags::ALL`.
- [ ] **1.2** Smoke-test: `bin/rails feature_flags:enable ACCT=acct_xxx FLAG={platform}_integration` in the dev console.

No tests added — covered by existing `Account::FeatureFlags` concern tests.

---

## Phase 2 — Adapter tree

Mirror the Google tree under `app/services/ad_platforms/{platform}/`. Every file below must exist.

| File | Purpose | Test posture |
|---|---|---|
| `app/services/ad_platforms/{platform}.rb` | Constants module — endpoints, version, scopes, redirect URIs, credentials accessor | n/a |
| `oauth_url.rb` | Pure URL builder for the consent redirect | Pure unit test, real values in, asserted output |
| `token_client.rb` | HTTP shell for `POST /oauth/access_token` | No unit test — exercised through orchestrators via VCR |
| `token_exchanger.rb` | Pure parser — response body → `{ success:, access_token:, expires_at: }` | Pure unit test against fixture JSON |
| `token_refresher.rb` | Orchestrator — composes TokenClient + TokenExchanger, updates connection | VCR cassette `{platform}/token_refresh/{success,expired,bad_token}.yml` |
| `list_ad_accounts_parser.rb` | Pure parser — API list response → filtered ad-account hashes | Pure unit test against fixture JSON |
| `list_ad_accounts.rb` | Orchestrator — composes ApiClient + Parser, follows pagination | VCR cassette `{platform}/list_ad_accounts/{single_page,multi_page,empty}.yml` |
| `accept_connection_service.rb` | DB-writer — creates `AdPlatformConnection`, kicks off backfill job, accepts `metadata:` kwarg | Real DB; tokens passed in (no HTTP) — no VCR needed |
| `api_client.rb` | HTTP shell with platform's auth/proof requirements; calls `AdPlatforms::ApiUsageTracker.increment!(:platform)` on every request | No unit test — smoke-tested through orchestrators |
| `spend_sync_service.rb` | Orchestrator — pulls insights, parses rows, upserts via `AdSpendRecord.upsert_all`, increments billing meter | VCR cassette `{platform}/insights/{daily_single,daily_multi,paginated,empty}.yml` |
| `row_parser.rb` | Pure — single insights row + connection → `AdSpendRecord` attrs; merges connection + per-campaign metadata | Pure unit test against fixture JSON |
| `campaign_channel_mapper.rb` | Pure — channel default + `connection.settings.campaign_overrides` lookup | Pure unit test |
| `adapter.rb` | Implements `BaseAdapter` interface — `fetch_spend / refresh_token! / validate_connection`. Registered in `AdPlatforms::Registry` | Unit test asserts registry returns this adapter for the platform |

### Sub-phase order (TDD)

- [ ] **2.0** VCR + WebMock setup if not already wired. `test/test_helper.rb` already has VCR config — only add platform-specific filters for `app_id`, `app_secret`, `access_token`, and any platform-specific identifiers (e.g. Meta's `appsecret_proof`).
- [ ] **2.1** Constants module + pure `OauthUrl`.
- [ ] **2.2** `TokenClient` (no test) + pure `TokenExchanger`.
- [ ] **2.3** `TokenRefresher` orchestrator + VCR cassette.
- [ ] **2.4** `ApiClient` HTTP shell (no test).
- [ ] **2.5** `ListAdAccountsParser` + `ListAdAccounts` orchestrator + VCR cassette.
- [ ] **2.6** `AcceptConnectionService` (DB writer, takes tokens + metadata, builds connection).
- [ ] **2.7** Wire global `AdPlatforms::ApiUsageTracker`: add `{platform}` key to its `LIMITS` and `DISPLAY_NAMES` hashes; have `ApiClient` call `AdPlatforms::ApiUsageTracker.increment!(:{platform})` on every successful request. The tracker class itself is shared infrastructure — do not create a per-platform copy.
- [ ] **2.8** `RowParser` + `CampaignChannelMapper` (pure).
- [ ] **2.9** `SpendSyncService` orchestrator + VCR cassette.
- [ ] **2.10** `Adapter` + register in `AdPlatforms::Registry`.

---

## Phase 3 — OAuth controller, views, routes

Mirror `app/controllers/oauth/google_ads_controller.rb`.

- [ ] **3.1** `app/controllers/oauth/{platform}_controller.rb` — actions: `connect`, `callback`, `select_account`, `create_connection`, `reconnect`, `disconnect`. First three lines: `skip_marketing_analytics`, `before_action :require_login`, `before_action :require_feature_flag, only: [...]`. Plus `require_paid_plan` and `require_connection_slot` on `connect`.
- [ ] **3.2** `app/views/oauth/{platform}/select_account.html.erb` — ad account picker with metadata key/value capture (KnownMetadata-driven dropdowns + free-form fallback).
- [ ] **3.3** Routes for connect / callback / select_account / create_connection / reconnect / disconnect.
- [ ] **3.4** `app/views/accounts/integrations/_{platform}_card.html.erb` — live state card.
- [ ] **3.5** `app/views/accounts/integrations/{platform}.html.erb` + `{platform}_account.html.erb` — index and per-connection detail.
- [ ] **3.6** `Accounts::IntegrationsController#{platform}` and `#{platform}_account` actions, both gated on the feature flag.
- [ ] **3.7** Update `accounts/integrations/show.html.erb` — when `feature_enabled?` true, render the live card; else keep the Coming Soon card.
- [ ] **3.8** Routes: `get "{platform}"` and `get "{platform}/:id"` on `accounts/integrations`.

### Controller test matrix (target ~10 tests)

- Feature-flag gate: redirected when off, allowed when on
- Plan-limit + connection-slot gates trip on `connect`
- State validation: missing state, mismatched state both reject
- `select_account` requires pinned `oauth_account_id` session key
- `create_connection` requires session tokens
- `disconnect` happy path + cross-account isolation
- `reconnect` login + flag gates

---

## Phase 4 — Connect-time metadata

Per-connection metadata plumbing should work for free if the shared services are reused.

- [ ] **4.1** `select_account.html.erb` exposes `@known_metadata_keys = AdPlatforms::KnownMetadata.keys_for(account)` and `@known_metadata_values = AdPlatforms::KnownMetadata.values_by_key_for(account)` for autocomplete.
- [ ] **4.2** Controller's `create_connection` extracts metadata via `AdPlatforms::ConnectMetadataExtractor.call(params)`.
- [ ] **4.3** `AcceptConnectionService` accepts `metadata:` kwarg, normalizes via `AdPlatforms::MetadataNormalizer.call(metadata)`, persists onto `AdPlatformConnection.metadata`.
- [ ] **4.4** `RowParser` merges `connection.metadata` (and any per-campaign overrides under `connection.settings.campaign_overrides`) onto the returned `AdSpendRecord` attrs so `ad_spend_records.metadata` is stamped at sync time.

No new infrastructure — these helpers (`KnownMetadata`, `ConnectMetadataExtractor`, `MetadataNormalizer`) live in `app/services/ad_platforms/` and are platform-agnostic. Tests for the shared services live next to them and apply to all adapters.

---

## Phase 5 — Integrations UI

Already covered by Phase 3.4–3.8 above. Quick sanity check:

- [ ] Live card renders only when flag is on; Coming Soon card when flag is off
- [ ] Connection detail page renders the metadata panel (`_metadata_panel.html.erb`) showing whether the tagged metadata links to any conversions in the last 90 days
- [ ] "Edit metadata" CTA exposes the post-connect editor (see `ad_platforms_meta_rollout_spec.md` Phase 3)

---

## Phase 6 — Tests

**Rule (from `feedback_no_mocks.md`):** no mock objects. `Object#stub` is allowed for narrow value substitution (clock, constants). HTTP goes through VCR.

### Per-class targets

| Class | Test count | Notes |
|---|---|---|
| `OauthUrl` | ~6 | pure |
| `TokenExchanger` | ~5 | pure |
| `TokenRefresher` | ~3 | VCR `{platform}/token_refresh/*` |
| `ListAdAccountsParser` | ~6 | pure |
| `ListAdAccounts` | ~3 | VCR `{platform}/list_ad_accounts/*` |
| `AcceptConnectionService` | ~5 | real DB; no HTTP |
| `Adapter` | ~3 | unit-style; refresh_token! tested via VCR |
| `RowParser` | ~8 | pure; covers metadata merge + per-campaign overrides |
| `CampaignChannelMapper` | ~4 | pure |
| `SpendSyncService` | ~6 | VCR `{platform}/insights/*` |
| `AdPlatforms::ApiUsageTracker` | already covered in `test/services/ad_platforms/api_usage_tracker_test.rb` | Add a regression test only if the new platform exposes a unique tracking quirk — otherwise the existing global tests cover the new key once added to `LIMITS` |
| `Oauth::{Platform}Controller` | ~10 | full surface — see Phase 3 matrix |
| Integration page rendering | ~2 | flag on → live card; flag off → Coming Soon |

### VCR cassette filtering checklist (before commit)

- `app_id`, `app_secret` (filtered by name in `test_helper.rb`)
- Bearer access tokens (Authorization header)
- Platform-specific signed proofs (e.g. Meta's `appsecret_proof`)
- Real ad account IDs — replace with `act_TEST_001` style placeholders
- Real campaign IDs and any campaign names containing customer info
- Use `VcrFilters.scrub` regex pass — extend the pattern list if a new identifier shape appears

### Recording protocol

1. Set `{PLATFORM}_ACCESS_TOKEN=<live token>` in shell
2. Run target test once with `VCR_RECORD_MODE=new_episodes`
3. Inspect resulting `.yml` for unfiltered secrets — extend the filter list and re-record if found
4. Run `bin/rails vcr:audit` (if available) to scan for leaks
5. Commit the cassette

---

## Phase 7 — Verify rake task

- [ ] `lib/tasks/ad_platforms.rake` adds `ad_platforms:{platform}:verify_credentials` — refreshes token if expired, hits the list-ad-accounts endpoint, prints active accounts via the parser. Mirrors Google's `verify_basic_access` and Meta's verify task.
- [ ] Smoke test only — no automated test required.

---

## Definition of Done

- [ ] Phase 0 verification recorded in `platform_api_approvals_spec.md`
- [ ] Phase 1 flag added to `FeatureFlags::ALL`
- [ ] All 13 service classes shipped with passing tests where applicable per the table above
- [ ] **Global `AdPlatforms::ApiUsageTracker` wired** — `{platform}` added to `LIMITS` + `DISPLAY_NAMES`; `ApiClient` increments on every call; warning email fires at threshold via `SpendSyncSchedulerJob`
- [ ] `Oauth::{Platform}Controller` ships with full surface and `skip_marketing_analytics`
- [ ] `AdPlatforms::Registry` registers `:{platform}`
- [ ] Connect-time metadata picker captures `KnownMetadata` keys; `RowParser` merges metadata onto records
- [ ] `bin/rails test` passes (other than pre-existing flakes)
- [ ] Manual QA matrix completed against a dev account with the flag enabled
- [ ] No new mock objects; only `Object#stub` for narrow value substitution
- [ ] Rake `ad_platforms:{platform}:verify_credentials` smoke-tests live API
- [ ] Spec moved to `lib/specs/old/` after pet-resort prod E2E pass

---

## Out of Scope (per adapter — defer to follow-up specs)

- Hourly granularity sync — default to daily
- Custom conversion-event mapping UI — hardcode `purchase` action sums initially
- App-review submission for live access — separate workstream parallel to Phase 7
- Backfilling existing connections with Meta-style metadata — covered in `ad_platforms_meta_rollout_spec.md` Phase 4

---

## Common Pitfalls (from Google + Meta build experience)

1. **Token column reuse.** Some platforms have no OAuth2 refresh token (e.g. Meta). Don't stamp the access token into the `refresh_token` column — leave it null and rely on `token_expires_at` + re-exchange. (Caught and fixed mid-Meta build.)
2. **VCR cassettes never recorded.** Spec calls for them, build skips them, "we'll record in Phase 5 prod" becomes the running excuse. Record at least one cassette per orchestrator during build, even if it's against a sandbox / dev account — the assertion shape is what matters, the data can be re-recorded later.
3. **Adapter skips `ApiUsageTracker` wiring.** It's not glamorous, but without it we're flying blind on billing and rate-limit pressure. Wire it in Phase 2.7 — add the platform key to `LIMITS`/`DISPLAY_NAMES` and call `increment!` from `ApiClient`. Don't create a per-platform tracker class — see `feedback_global_processor_pattern` for why.
4. **Forgetting `skip_marketing_analytics`.** Token strings end up in `page_location` URLs which GA4 / Meta Pixel exfiltrate. Add the directive on day one.
5. **Cross-account isolation tests.** Every controller test that creates a connection must include a "second account doesn't see this" assertion. Add it as you write the happy path, not after.
6. **Connect-time metadata vs edit-anytime.** Connect-time is the minimum — capture metadata during the OAuth account picker. Edit-anytime UI is a separate spec.
