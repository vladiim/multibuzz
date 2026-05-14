# Conversion Feedback (Meta CAPI + Google Enhanced Conversions for Leads)

**Date:** 2026-05-10
**Priority:** P1
**Status:** Phase 4 (Meta CAPI) wired end-to-end with narrow retry semantics (2026-05-11 fix: dispatcher raises `RetryableDispatchError` on 401/429/5xx; job retries `attempts: 3` on that class only). Phase 2A (SDK fbp/fbc capture) deferred — EMQ target reachable on current SDK via `external_id` + hashed PII + server-derived `fbc`. Awaiting BSA Pixel token (Phase 0B) for Phase 4 production go-live. Phase 5 (Google EC) blocked on Tool Change Form. Phase 7 (admin) next on the build queue, then Phase 8 (BSA wire-up).
**Branch:** `feat/conversion-feedback`

---

## Summary

Add an outbound layer to mbuzz that fires conversion events back to Meta (Conversions API) and Google Ads (Enhanced Conversions for Leads) on the customer's behalf. mbuzz today captures conversions server-side and stitches them into journeys, but does not feed them back to the platforms — meaning bidder algorithms can't optimise against real downstream outcomes, only clicks. This is mbuzz's primary feature gap vs Stape, Tracklution, and Elevar, and the immediate blocker for shipping mbuzz as the demand-side data plane for BSA's marketing-ops architecture.

The spec ships **BSA-tenant-scoped first** (single customer, hardcoded destinations in a per-account record, no self-serve UX) then graduates to a multi-tenant productised feature in a later spec.

Two non-trivial gates were under-stated in the prior draft and now sit in front of any code:

1. **Google Ads use-case extension.** mbuzz's existing developer token (Basic Access, approved 11 Mar 2026) was scoped to **read-only spend reporting**. Server-side conversion uploads are a different permissible use, requires submitting the **Google Ads API Tool Change Form**. Per the **February 2026 conversion-data rules**, NEW developers cannot use IP / session attributes in conversion imports anyway. mbuzz uses **Enhanced Conversions for Leads (hashed user data) plus click IDs only**. The OAuth scope is unchanged (single `auth/adwords` scope already covers read + write); only the developer token's permissible use needs extending.

2. **Match-key capture gap.** mbuzz captures `fbclid` from URL params but not `_fbp` or `_fbc` cookies; identities store an arbitrary `traits` JSONB but no normalised hashed email / phone; sessions don't persist country / postal code. Without these, Meta EMQ caps low and Google EC has nothing to match on. A pre-dispatcher phase is needed to close the gap.

**API integration alignment in one sentence:** Meta CAPI is independent of all other Meta App work (per-Pixel customer-issued tokens, no App Review, no Business Verification dependency); Google EC reuses the existing OAuth scope and developer token, requires only a Tool Change Form to extend permissible use to "Server-side conversion uploads / Enhanced Conversions for Leads". See "API Integration Alignment" below for the full per-layer breakdown.

**No IP, no UA, ever.** Symmetric with both platforms. Google forbids them for new developers. Meta accepts them but mbuzz declines: Sessions store only `device_fingerprint = SHA256(ip|ua)[0:32]`, so feeding Meta raw IP would mean changing the data flow for ~0.5 EMQ points. mbuzz's privacy-respecting brand position would also be compromised. The primary Meta match key is `external_id` = `SHA-256(Identity#external_id)`, which links to the advertiser's own Custom Audience uploads and Pixel events.

**Attribution model is configurable per destination.** mbuzz has multiple attribution models (`last_touch`, `first_touch`, `linear`, `u_shaped`, `time_decay`, `position_based`, `markov`, `data_driven`). Each `ConversionDestination` carries `attribution_model_id`. For each landing conversion, the dispatcher looks up the destination platform's credit share under the chosen model and fires only when credit > 0 (default threshold; configurable). This is the whole point of "feeding back": telling Meta and Google "here's what mbuzz credits you for under the model the customer trusts", not "here's every conversion, you sort it out". A customer can run `last_touch` for Meta (defensible, simple) and `markov` for Google (data-driven probabilistic credit) on the same account if they want different views per platform.

---

## Current State (verified 2026-05-10 against schema and code)

### What mbuzz has

- **Inbound ad-platform adapters** at `app/services/ad_platforms/{google,meta}/`. OAuth + spend pull, read-only. `AdPlatforms::Registry` (`app/services/ad_platforms/registry.rb`) registers `google_ads` and `meta_ads`.
- **`AdPlatformConnection` model** holds OAuth tokens, refresh state, per-connection metadata for inbound spend sync.
- **`Conversion` model** stores conversions with FK `event_id` (bigint to events table), `account_id`, `identity_id`, `idempotency_key` (string, unique per account, used today for inbound dedup), `properties` (JSONB), `is_acquisition`, `revenue`, `currency`, `converted_at`. **No `consent_marketing` column.**
- **`ConversionPropertyKey` model** stores discovered custom keys per account.
- **Identity model** is `account_id + external_id + traits JSONB`. **No `email_sha256` / `phone_e164_sha256` / `first_name` / `last_name` / `canonical_id` columns.** Whatever PII lives there is under arbitrary keys in `traits`.
- **Session model** has `device_fingerprint = SHA256(ip|user_agent)[0:32]`, `click_ids` JSONB, `user_agent`, `landing_page_host`. **No `ip` (only fingerprint), `country`, `postal_code`, `fbp`, `fbc` columns.** `gclid` lives inside `click_ids` JSONB.
- **`ClickIdentifiers` constants** capture URL-param click IDs: `gclid`, `gbraid`, `wbraid`, `dclid`, `gclsrc`, `msclkid`, `fbclid`, `ttclid`, `li_fat_id`, `twclid`. The actual `_fbp` / `_fbc` browser cookies (different from `fbclid`) are not read by the SDK.
- **`AdPlatforms::ApiUsageTracker`** (`app/services/ad_platforms/api_usage_tracker.rb`) is the global per-platform usage tracker. Outbound calls must increment this so billing visibility is preserved.
- **Solid Queue** for background jobs (Postgres-backed; no Redis per the Solid Stack convention).
- **`FeatureFlags`** module at `app/constants/feature_flags.rb` with three platform flags: `google_ads_integration`, `meta_ads_integration`, `linkedin_ads_integration`. `CONVERSION_FEEDBACK` not yet added.

### What's missing

| Gap | Impact | Phase that closes it |
|---|---|---|
| No outbound destination model / migration | Nothing tracks "where does this account send conversions" | Phase 3 |
| No CAPI / EC client classes | Existing `ApiClient` classes are GET-shaped | Phases 4, 5 |
| No conversion-to-destination mapping | Nothing maps `Conversion` → platform event | Phase 3 |
| No dispatch tracking model | No record of attempts, retries, or failures | Phase 3 |
| No `_fbp` / `_fbc` capture in SDK | Meta EMQ caps below 6.0 (target 7.0+); fbc must be derived from `fbclid` per Meta formula | Phase 2 |
| No normalised hashed email / phone on Identity | Google EC for Leads has nothing to match on; Meta EMQ low | Phase 2 |
| No country / postal_code on Session | Meta EMQ secondary match keys missing | Phase 2 |
| No `consent_marketing` on Conversion | Future deletion-propagation flow blocked. Out of scope for v1 (see Out of Scope). | Future spec |

### API Integration Alignment (verified 2026-05-10 against `platform_api_approvals_spec.md`)

What conversion feedback needs vs what mbuzz already has, broken down per integration layer. This determines what's blocking and what can ship in parallel.

#### Meta CAPI

| Layer | Conversion feedback needs | mbuzz current state | Aligned? |
|---|---|---|---|
| OAuth scope on mbuzz's Meta App | None. CAPI tokens are issued by the customer's BM, not by mbuzz's App. | mbuzz's App `1572699803993069` is configured for `ads_read` (Standard Access today, Advanced Access pending and blocked on Business Verification → entity registration). | ✓ **Independent.** mbuzz's App scope and approval status do not gate CAPI. |
| App Review | None. Meta auto-creates a Conversions API "app" + system user behind each per-Pixel token in the customer's BM. No mbuzz-side App Review. | mbuzz's `ads_read` Advanced Access submission (Step 4 in `platform_api_approvals_spec.md`) is not started. | ✓ **Independent.** Phase 4 (Meta CAPI dispatcher) can ship before any mbuzz Meta App Review work. |
| Business Verification | None. BSA's BM has its own verification; mbuzz piggybacks on BSA's customer relationship. | mbuzz's Business Verification (Step 2) is BLOCKED on entity registration (no Mbuzz ABN yet). | ✓ **Independent.** Not a blocker for Phase 4. |
| Per-customer setup | Customer's BM admin generates a per-Pixel CAPI access token from Events Manager → Pixel → Settings → Conversions API → Generate Access Token. Token is long-lived (~60 days). | Not done for any customer yet. | ⏳ **Phase 0B.** Per-customer manual step. |
| `appsecret_proof` HMAC hardening | Optional. Needs the secret of the *auto-created* CAPI app (NOT mbuzz's own app secret). Customer's BM admin would have to share it. | n/a | ⏳ **Defer to v2.** Skip in v1; bare token works. |

**Net delta:** zero changes to mbuzz's Meta App. Per-customer Phase 0B token setup is the only new step.

#### Google Ads API (Conversion Upload + Enhanced Conversions for Leads)

| Layer | Conversion feedback needs | mbuzz current state | Aligned? |
|---|---|---|---|
| OAuth scope (per-customer refresh token) | `https://www.googleapis.com/auth/adwords`. Single scope covers read + write across the entire Ads API surface. | mbuzz already requests this scope for spend pull (Basic Access approved 11 Mar 2026). Customer refresh tokens are stored on `AdPlatformConnection`. | ✓ **Aligned.** Same OAuth, same refresh token, no re-consent. The customer who already linked Google Ads for spend pull can have conversion uploads enabled with no new OAuth flow. |
| Developer token tier | Basic Access (15K ops/day). For BSA's volume that's plenty. | Basic Access. | ✓ **Aligned.** No need to apply for Standard Access. RMF (Required Minimum Functionality) is Standard-only. |
| Developer token permissible use | "Server-side conversion uploads / Enhanced Conversions for Leads". Per the Feb 2026 rule, NEW developers cannot use IP / session attributes. | Current permissible use: read-shaped (reporting). Conversion uploads require the use-case extension. | ⏳ **Phase 0A.** Submit the **Google Ads API Tool Change Form** to extend the existing developer token's permissible use. Same token, no re-application, no Standard Access upgrade. Approval typically 48 hours to 3 weeks. |
| Manager link / `login_customer_id` | If BSA's account is under a manager (MCC), mbuzz includes `login-customer-id: <MCC_ID>` header on uploads. | mbuzz already handles `login_customer_id` in the spend-pull adapter. | ✓ **Aligned.** Reuse existing handling. |
| Enhanced Conversions for Leads on each conversion action | BSA toggles "Enhanced conversions for leads → Set up via API" per conversion action in Google Ads UI. | Not done. | ⏳ **Phase 0C.** Per-customer config in Google Ads UI. No mbuzz code change. |

**Net delta:** Tool Change Form submission (Phase 0A) is the only mbuzz-side change. Per-customer Phase 0C is BSA UI clicks. OAuth, dev token tier, manager-link plumbing all reuse existing infrastructure.

#### Other platforms (LinkedIn, TikTok, etc.)

Out of scope for this spec. Each gets its own conversion feedback adapter when prioritised. The destination model is platform-shaped from the start, so adding TikTok Events API or LinkedIn Conversions API later means a new `AdDestinations::TikTok::*` namespace, not a refactor.

#### Implications for shipping order

- **Phase 4 (Meta CAPI) is unblocked TODAY.** It does not depend on Meta Business Verification, mbuzz's `ads_read` approval, or any other Meta App Review milestone. Phase 4 can run in parallel with Step 2-4 of `platform_api_approvals_spec.md`.
- **Phase 5 (Google EC for Leads) is gated on Phase 0A approval** (Tool Change Form). Submit early so it's not the critical path. While we wait, Phases 1, 2, 3, 4, 6, 7 can all proceed.

The rewrite of `platform_api_approvals_spec.md` should reflect this alignment by adding a note at the top: "Conversion feedback (`conversion_feedback_spec.md`) requires (a) Google Ads Tool Change Form submission and (b) per-customer Meta CAPI tokens. Neither blocks nor is blocked by the existing Step 1-5 work-streams."

---

## Proposed Solution

### Architectural shape

Two distinct namespaces:

- `app/services/ad_platforms/{platform}/` for inbound (existing): OAuth + spend pull. Read.
- `app/services/ad_destinations/{platform}/` for outbound (new): conversion event dispatch. Write.

Parallel namespacing makes the inbound/outbound distinction unmistakable in code and prevents the existing inbound adapter pattern from being polluted with write semantics. A platform like Meta can have both an inbound adapter (`ad_platforms/meta/`) and an outbound destination (`ad_destinations/meta/`) without coupling. Auth tokens may be shared (a single connection used for both directions) but that is a runtime concern handled by the `ConversionDestination` model, not a code-organisation concern.

### Data flow

```
Conversion lands (Conversions::TrackingService completes)
  ↓
Conversions::DispatchService.call(conversion) finds enabled ConversionDestinations
for (account, conversion_type)
  ↓
For each destination → enqueue OutboundConversionJob(dispatch_id) on Solid Queue
  ↓
OutboundConversionJob:
  1. Build platform payload via AdDestinations::{Platform}::PayloadBuilder
  2. POST via AdDestinations::{Platform}::ApiClient
  3. AdPlatforms::ApiUsageTracker.increment!(:meta_capi | :google_ec)
  4. Update ConversionDispatch with status / response / fired_at
  5. On retryable error, raise → Solid Queue retry policy (3 retries, exponential backoff, max 1h)
  6. On permanent error, mark failed_permanent + surface in admin UI
```

### Key files

| File | Purpose | Status |
|---|---|---|
| `db/migrate/{ts}_capture_match_keys_on_sessions.rb` | Add `country`, `postal_code`, `fbp`, `fbc` columns to sessions; backfill `gclid` from `click_ids` JSONB to a top-level column for index efficiency | New (Phase 2) |
| `db/migrate/{ts}_add_normalised_hashed_pii_to_identities.rb` | Add `email_sha256`, `phone_e164_sha256`, `first_name_sha256`, `last_name_sha256` (all `varchar(64)`, NULLable) to identities; index on `email_sha256` | New (Phase 2) |
| `app/services/identities/normaliser.rb` | Pure module: `normalise_email(str)`, `normalise_phone_e164(str)`, `normalise_name(str)`, `sha256(str)`. Lowercase + trim per Meta + Google specs. | New (Phase 2) |
| `app/services/sessions/match_key_capture_service.rb` | Reads `_fbp` and `_fbc` from request cookies; derives `_fbc` from `fbclid` if cookie absent (`fb.1.{ts_ms}.{fbclid}`); writes to session | New (Phase 2) |
| `db/migrate/{ts}_create_conversion_destinations.rb` | New table | New (Phase 3) |
| `db/migrate/{ts}_create_conversion_dispatches.rb` | New table | New (Phase 3) |
| `app/models/conversion_destination.rb` | Per-account, per-platform outbound destination config | New (Phase 3) |
| `app/models/conversion_dispatch.rb` | One row per (conversion × destination); tracks status, response, retries | New (Phase 3) |
| `app/services/ad_destinations/base_dispatcher.rb` | Shared interface: build payload, fire, record outcome | New (Phase 3) |
| `app/services/ad_destinations/registry.rb` | Maps `platform` → dispatcher class. Mirrors `ad_platforms/registry.rb`. | New (Phase 3) |
| `app/services/ad_destinations/meta/api_client.rb` | POST to `https://graph.facebook.com/v{N}/{pixel_id}/events` with bearer token (no `appsecret_proof` in v1; see Phase 0B.3) | New (Phase 4) |
| `app/services/ad_destinations/meta/payload_builder.rb` | Build CAPI event payload from `Conversion` + `Identity` + `Session` | New (Phase 4) |
| `app/services/ad_destinations/meta/dispatcher.rb` | Orchestrator (build → post → record) | New (Phase 4) |
| `app/services/ad_destinations/google/api_client.rb` | Wraps `ConversionUploadService.UploadClickConversions` via `google-ads-googleads` gem | New (Phase 5) |
| `app/services/ad_destinations/google/payload_builder.rb` | Build EC for Leads payload (hashed user identifiers + `gclid`/`gbraid`/`wbraid` + conversion action resource name) | New (Phase 5) |
| `app/services/ad_destinations/google/dispatcher.rb` | Orchestrator | New (Phase 5) |
| `app/services/conversions/dispatch_service.rb` | Find destinations, enqueue jobs, idempotency guard | New (Phase 6) |
| `app/services/conversions/platform_credit_calculator.rb` | Pure function: `(conversion, destination) → credit_share`. Uses destination registry's `source_match` predicate to identify platform-attributable touchpoints. | New (Phase 6) |
| `app/jobs/outbound_conversion_job.rb` | Solid Queue worker. Loads credit share, applies threshold, dispatches with `revenue_mode`-adjusted value | New (Phase 6) |
| `app/services/ad_platforms/api_usage_tracker.rb` | Add `:meta_capi`, `:google_ec` keys to `LIMITS` + `DISPLAY_NAMES` | Modify (Phase 4, 5) |
| `config/initializers/ad_destinations.rb` | Register dispatchers in the registry on boot | New (Phase 4) |
| `app/controllers/admin/conversion_dispatches_controller.rb` | Admin view of recent dispatches per account | New (Phase 7) |
| `app/views/admin/conversion_dispatches/index.html.erb` | List + filter dispatches; show payload + response on click | New (Phase 7) |
| `lib/tasks/conversion_feedback.rake` | `conversion_feedback:meta:smoke ACCT=... PIXEL=...` etc. | New (Phase 4, 5) |

### Why a new model rather than reusing `AdPlatformConnection`

`AdPlatformConnection` is shaped around OAuth + ad-account selection for spend pull. Conflating it with outbound destination config (Pixel ID, conversion action mapping, event-type mapping) muddies a model already doing real work. A separate `ConversionDestination` keeps responsibilities clean and lets a single `AdPlatformConnection` (the customer's Google Ads OAuth, say) be referenced by zero, one, or many destinations as needed. Meta CAPI does not even use `AdPlatformConnection` because its tokens come from a different place (per-Pixel system user, not customer OAuth).

### Identity payload assembly

Match keys only. mbuzz does not send raw IP or user agent to either platform.

**Why no IP / UA, ever**

- **Google**: `ip_address` and `user_agent` are forbidden for new developers per the Feb 2026 rule. Sending them returns `CUSTOMER_NOT_ALLOWLISTED_FOR_THIS_FEATURE`.
- **Meta**: Meta still accepts `client_ip_address` / `client_user_agent` and EMQ improves marginally (~0.5 point) with them. mbuzz declines on principle: (1) Sessions store `device_fingerprint = SHA256(ip|user_agent)[0:32]`, not raw IP; we'd have to re-derive IP at request time just to feed Meta. (2) mbuzz's brand position is privacy-respecting / vendor-neutral; sending raw IP to Meta contradicts that and complicates GDPR / Children's Code reviews. (3) The same matching is achievable with `external_id` + hashed PII + fbc/fbp without leaking IP.

`external_id` is the primary match key for Meta. mbuzz hashes `Identity#external_id` (the customer's CRM user ID supplied via the identify call) and Meta matches it against the advertiser's other data sources: Custom Audience CSV uploads, Pixel `external_id` events the customer's site already fires. Hashing mbuzz's own `prefix_id` (`idt_abc123`) would match nothing because the customer's other data sources don't know that ID.

| Field | mbuzz source (after Phase 2) | Meta CAPI key | Google EC for Leads key | Notes |
|---|---|---|---|---|
| **External ID (primary)** | `SHA-256(Identity#external_id)` | `external_id` | `user_identifiers.third_party_user_id` (Standard Access only; skip for Basic) | Customer's CRM user ID, normalised + hashed. Single most useful key for Meta because it links to the advertiser's own data sources. |
| Hashed email | `Identity#email_sha256` | `em` | `hashed_email` | SHA-256, lowercase + trim before hash. Single value, not array. |
| Hashed phone E.164 | `Identity#phone_e164_sha256` | `ph` | `hashed_phone_number` | E.164 format with `+` prefix, then SHA-256. |
| First name (hashed, lowercased) | `Identity#first_name_sha256` | `fn` | `address_info.hashed_first_name` | Lowercase, strip diacritics, SHA-256. |
| Last name (hashed, lowercased) | `Identity#last_name_sha256` | `ln` | `address_info.hashed_last_name` | Same. |
| Country (lowercase ISO-2) | `Session#country` | `country` (hashed) | `address_info.country_code` (NOT hashed for Google) | Meta hashes country; Google does not. |
| Postal code | `Session#postal_code` | `zp` (hashed for non-US, lowercased and stripped of spaces for US) | `address_info.postal_code` (NOT hashed for Google) | Meta hashes; Google does not. |
| Click ID (Meta) | `Session#fbc` (cookie) or derived `fb.1.{ts_ms}.{fbclid}` | `fbc` | n/a | **Do not hash.** Do not fabricate when no real fbclid exists. |
| Browser ID (Meta) | `Session#fbp` (`_fbp` cookie) | `fbp` | n/a | **Do not hash.** |
| Click ID (Google) | `Session#click_ids['gclid' \| 'gbraid' \| 'wbraid']` | n/a | `gclid` / `gbraid` / `wbraid` (one of, top-level on `ClickConversion`) | gbraid for iOS app; wbraid for web-to-app. |
| ~~IP address~~ | not stored (only fingerprint) | **NOT SENT** | **Forbidden** | See "Why no IP / UA" above. |
| ~~User agent~~ | `Session#user_agent` (kept for bot detection) | **NOT SENT** | **Forbidden** | Same. |

All hashed values use SHA-256 against the **trimmed lowercased** input. fbp and fbc must NOT be hashed. Country and postal code must NOT be hashed for Google but MUST be hashed for Meta.

**EMQ target without IP/UA: ≥ 6.5.** Meta's published EMQ scoring weights `external_id` and hashed email heavily. With both present plus fbc/fbp, real-world EMQ commonly lands between 6.5 and 8.0. The ≥ 7.0 target some sources cite assumes IP + UA are also sent. We accept the tradeoff. The 4.0 floor where Meta's bidder treats a signal as "low quality" is comfortably above what we'll produce.

### Attribution model selection

Each `ConversionDestination` requires an `attribution_model_id` FK to `AttributionModel`. The dispatcher's decision tree per landing conversion:

```
1. Find destination's attribution model
2. Compute platform credit share for this conversion under that model
   - meta_capi  destination → sum credits over touchpoints where click_ids['fbclid'] present
                              OR session.channel == 'paid_social' AND source matches 'meta' family
   - google_ec  destination → sum credits over touchpoints where click_ids has gclid/gbraid/wbraid
                              OR session.channel == 'paid_search' AND source == 'google'
3. If credit > destination.minimum_credit_threshold (default 0.0):
     → fire to platform with revenue (full or scaled, per destination.revenue_mode)
   Else:
     → status = skipped_no_credit, no platform call
```

**Why model-aware filtering and not "fire all + dedup"**

The "fire all" pattern (used by Stape, Tracklution) sends every conversion to every destination with `event_id` for dedup, then lets the platforms self-attribute. mbuzz exists because platform self-attribution is the problem we're solving. Sending all conversions and letting Meta and Google self-attribute defeats the spec's purpose. The customer trusts mbuzz's model; we feed back what that model credits each platform.

**Revenue mode (`destination.revenue_mode`)**

| Mode | Behaviour | When to choose |
|---|---|---|
| `full` (default) | Send full `Conversion#revenue` to every platform that crosses the threshold | The platform's bidder optimises against full conversion signals. mbuzz tells the platform "you drove this conversion under our model"; the platform learns full value. |
| `scaled` | Send `revenue × platform_credit_share` | Multi-touch conversions where multiple platforms are credited. Sends fractional revenue per touchpoint, accurately reflecting the model's view. |

Default is `full` because Meta's and Google's bidder algorithms expect full-conversion signals. `scaled` is available for customers who want platform values that sum to the conversion total.

**Threshold (`destination.minimum_credit_threshold`)**

Default `0.0` (any positive credit fires). Customers can raise to e.g. `0.1` to suppress dispatches where the platform got <10% credit (low-confidence touchpoints).

**Choosing a model per destination**

| Model | When to use |
|---|---|
| `last_touch` | Default. Defensible, aligned with how most platforms self-report. Fires to platform when it was the last paid touchpoint. |
| `first_touch` | Awareness-stage attribution. Fires to platform when it was the first paid touchpoint. Less aligned with conversion-window biddability. |
| `linear` | Spreads credit equally across touchpoints. Likely to fire to multiple destinations per conversion. Pair with `revenue_mode: scaled` to avoid overstating. |
| `u_shaped` / `position_based` | 40-20-40 (or similar) split between first, middle, last. Same multi-fire concern as linear. |
| `time_decay` | Recent touchpoints weighted more heavily. Good middle ground for short consideration cycles. |
| `markov` / `data_driven` | Probabilistic credits learned from the account's own conversion paths. Best when you have ≥ 1000 conversions in the lookback window for stable estimates. Requires more volume than BSA may have on day one. |

For BSA's v1, `last_touch` is the recommended starting point. Easy to explain, defensible to BSA's leadership ("we credit Meta when Meta was the last paid touchpoint before conversion"), and produces clean platform feedback signals.

### Deduplication

- **Meta-side dedup.** Meta CAPI accepts `event_id`. If the Pixel fires the same `event_id` client-side and mbuzz fires it server-side via CAPI within ~48h, Meta dedupes. Use `Conversion#idempotency_key` (already canonical and unique per account) as the CAPI `event_id`. The `Conversion#event_id` FK column is unrelated despite the name collision.
- **Google-side dedup.** `order_id` plays an analogous role for Google EC for Leads. Use `Conversion#idempotency_key` here too.
- **mbuzz-side dispatch dedup.** Unique index on `conversion_dispatches(conversion_id, conversion_destination_id)`. The job is idempotent: if a dispatch already exists with `status=delivered`, no-op.

### Token + credential storage

| Platform | Token type | Storage | Refresh |
|---|---|---|---|
| Meta CAPI | Per-Pixel access token from Events Manager → Settings → CAPI → Generate Access Token. Long-lived (~60 days). | `ConversionDestination#meta_access_token` via Rails 7+ `encrypts :meta_access_token` (built-in, uses `ActiveRecord::Encryption`). No external gem. | Manual rotation reminder at 50 days (open question: automate rotation flow in v2). |
| Google EC | Customer's OAuth refresh token from `AdPlatformConnection`. | Reference existing `AdPlatformConnection#refresh_token` via FK on `ConversionDestination#ad_platform_connection_id`. | Existing `AdPlatforms::Google::TokenRefresher`. |

For BSA-first scope: tokens are seeded via a rake task or admin form. No customer-facing OAuth UI for Meta CAPI until a future spec.

---

## All States

| State | Condition | Expected behaviour |
|---|---|---|
| Happy path | Conversion lands, destination exists, payload builds, platform returns 2xx | `ConversionDispatch` row written with `status=delivered`, `response`, `fired_at`, `payload` snapshot |
| No destination configured | Conversion lands, no `ConversionDestination` rows for (account, type) | No-op. No dispatch row. |
| Destination disabled | `ConversionDestination#enabled = false` | Skip, no dispatch row. |
| Already delivered | Existing dispatch with `status=delivered` for (conversion, destination) | No-op. Idempotent re-enqueue is safe. |
| Match-key insufficient (Meta) | Conversion has neither `external_id`, `em`, `ph`, `fbc`, nor `fbp` | `status=skipped_no_identity`. Surface in admin. Don't waste a platform call. Meta would accept it but EMQ would be ~1.0. |
| Match-key insufficient (Google EC for Leads) | Conversion has neither hashed email/phone nor `gclid`/`gbraid`/`wbraid` | `status=skipped_no_identity`. |
| Platform got no credit under chosen model | Destination's `attribution_model_id` credits this platform with 0% (or below `minimum_credit_threshold`) | `status=skipped_no_credit`, `platform_credit_share=0.0`. Surface in admin. The conversion happened but mbuzz's model says this platform didn't drive it; we don't feed back something the model doesn't credit. |
| Token expired | Platform returns auth-failure (401 / `OAUTH_TOKEN_INVALID`) | Row persisted with `status=token_failed`; dispatcher raises `RetryableDispatchError`; job retries up to `attempts: 3`. v1 Meta: no auto-refresh (per-Pixel tokens rotate manually); v2 / Google: existing token refresher. After final retry, alert admin via `InternalNotifications`. |
| Rate limited | Platform returns 429 | Row persisted with `status=failed_transient`; dispatcher raises `RetryableDispatchError`; job retries with `:polynomially_longer` backoff up to `attempts: 3`. `ApiUsageTracker` increments per attempt. |
| Transient 5xx | Platform returns 5xx or network timeout | Same as 429 — row in `failed_transient`, dispatcher raises, job retries up to 3 attempts. Final failure leaves row in `failed_transient` for admin follow-up. |
| Permanent 4xx | Platform returns 400 with schema error | `status=failed_permanent`. Capture full request + response in `dispatch.error` and `dispatch.response`. Surface in admin. No retry. |
| Account suspended | mbuzz account suspended mid-dispatch | `status=skipped_account_suspended`. No dispatch sent. |
| Destination misconfigured | First call returns 4xx (wrong Pixel ID, wrong conversion action resource name) | `status=failed_permanent`. Surface. Manual fix required. |
| Consent withdrawn after fire | Customer revokes consent post-fire | Out of scope for v1. Separate "outbound deletion" workflow in a later spec. |

---

## Implementation Tasks

### Phase 0 — Approvals & external prerequisites

No code. Confirms the path is clear before cutting a line.

#### 0A — Google Ads API Tool Change Form (BLOCKING for Phase 5)

- [x] **0A.1** In Google Ads UI: go to **Tools → Setup → API Center**. Confirm current developer token + access tier (Basic, approved 11 Mar 2026).
- [x] **0A.2** Submit the **Google Ads API Tool Change Form** (linked from the API Center "Update access" CTA) to extend permissible use of the existing developer token.
  - Tool name: `mbuzz`
  - Change requested: "Add server-side conversion upload functionality. mbuzz will use `ConversionUploadService.UploadClickConversions` to upload click conversions and Enhanced Conversions for Leads (hashed user-provided data) on behalf of advertisers. mbuzz will NOT use IP / session attributes (per the February 2026 conversion-data policy update for new developers)."
  - Use case: "Reporting + Server-side Conversion Upload" (multi-select if available)
  - RMF: not applicable (Basic Access)
- [ ] **0A.3** Document submission in `lib/specs/platform_api_approvals_spec.md` with date and reference number.
- [ ] **0A.4** Approval timeline: 48 hours to 3 weeks per recent threads. Block Phase 5 on approval. **Phase 4 (Meta) is independent and can ship in parallel.**

#### 0B — Meta CAPI per-Pixel access token (BLOCKING for Phase 4)

- [ ] **0B.1** Ask BSA's Business Manager admin to open **Events Manager → BSA's Pixel → Settings → Conversions API → Generate Access Token**. Meta auto-creates a system user behind the token. **No App Review required, no special permissions.**
- [ ] **0B.2** Receive token + Pixel ID. Store in 1Password (`Conversion Feedback / BSA / Meta`). Never commit. Rotation reminder at 50 days (cookies expire ~60).
- [ ] **0B.3** Defer `appsecret_proof` to v2. The auto-created CAPI app (created behind the per-Pixel token) is owned by the customer's BM, not by mbuzz. Computing `appsecret_proof` would require BSA's BM admin to share that auto-created app's secret. v1 ships with bare token auth, which Meta supports. Revisit in a hardening pass.
- [ ] **0B.4** Smoke-test manually:
  ```
  curl -X POST 'https://graph.facebook.com/v22.0/{PIXEL_ID}/events?access_token={TOKEN}' \
    -H 'Content-Type: application/json' \
    -d '{
      "data": [{
        "event_name": "Lead",
        "event_time": <unix_ts>,
        "event_id": "test_smoke_001",
        "action_source": "website",
        "user_data": {
          "external_id": ["<sha256_of_test_user_id>"],
          "em": ["<sha256_lowercased_email>"]
        }
      }],
      "test_event_code": "TEST123"
    }'
  ```
  Note: deliberately omits `client_ip_address` and `client_user_agent`. The production dispatcher does the same.
  Confirm event appears in **Events Manager → Test Events** within 30 seconds.

#### 0C — BSA Google Ads conversion actions (BLOCKING for Phase 5)

- [ ] **0C.1** With BSA's Google Ads UI: confirm conversion actions exist for `Lead`, `Tour Booked`, `Registered`, `Enrolled`. If any are missing, BSA marketing creates them at **Tools → Conversions → New conversion action → Import → Other data sources or CRM**.
- [ ] **0C.2** Capture each conversion action's resource name (`customers/{CID}/conversionActions/{CONV_ID}`). Store in 1Password.
- [ ] **0C.3** In Google Ads UI, enable **Enhanced Conversions for Leads** for each conversion action: **Conversion action → Settings → Enhanced conversions for leads → Set up via API**.
- [ ] **0C.4** Smoke-test EC for Leads in the Google Ads UI's "Click conversions" preview tool with a sample row.

#### 0D — Domain & policy compliance

- [ ] **0D.1** Verify mbuzz privacy policy (`mbuzz.co/privacy`) covers: outbound conversion data sharing with ad platforms; the customer's responsibility to obtain user consent before the conversion fires; that hashed PII is shared with platforms for matching. Add language if missing before the first BSA dispatch.
- [ ] **0D.2** BSA's privacy policy must also mention conversion data sharing with Meta and Google. Confirm before enabling for BSA.

**Exit criteria for Phase 0:**
- Google Ads Tool Change Form submitted (track ticket); `lib/specs/platform_api_approvals_spec.md` updated.
- Meta CAPI token + Pixel ID in 1Password.
- BSA Google Ads conversion actions + EC for Leads enabled; resource names captured.
- Privacy policy compliance confirmed.
- Both Meta and Google smoke tests landed events in their respective preview tools.

### Phase 1 — Feature flag

- [x] **1.1** Add `CONVERSION_FEEDBACK = "conversion_feedback"` to `app/constants/feature_flags.rb`; append to `FeatureFlags::ALL`.
- [ ] **1.2** Smoke-test enable for BSA's mbuzz account: `bin/rails feature_flags:enable ACCT=acct_xxx FLAG=conversion_feedback`.
- [x] **1.3** Tests: `feature_flags_test.rb` already covers the toggle pattern; add an assertion that the new flag is recognised.

### Phase 2 — Match-key capture (NEW; gates dispatcher quality)

The dispatcher payload is only as good as the inputs. mbuzz captures `fbclid` and stores `traits` JSONB but lacks normalised hashed PII and `fbp` / `fbc` cookies. Close that gap first.

#### 2A — SDK enhancement (DEFERRED, not required for Phase 8 go-live)

**Status:** All five items deferred. Decision recorded 2026-05-11.

`_fbc` is already derived server-side from `fbclid` in `Sessions::CreationService#derived_fbc_from_fbclid` (via `Identities::FbcCookie`), so 2A.2's browser-side derivation is redundant. `_fbp` is the only key that requires browser-side capture, and EMQ projections with `external_id` + hashed email/phone + server-derived `fbc` land at 6.5–7.5 for BSA-shaped accounts (above the ≥ 6.5 target). The cost of skipping `_fbp` is roughly 0.3–0.6 EMQ points.

Revisit if the Phase 7.6 match-quality diagnostic shows EMQ plateauing below 6.5 in production. The lever then is more likely "increase `identify(email:, external_id:)` coverage on the customer's site" than "ship `_fbp` capture".

- [ ] ~~**2A.1** Browser SDK reads `_fbp` cookie on every event.~~ Deferred.
- [ ] ~~**2A.2** Browser SDK reads `_fbc` cookie and derives from `fbclid` if absent.~~ Redundant — done server-side in `Sessions::CreationService`.
- [ ] ~~**2A.3** Server-side SDKs accept `fbp` and `fbc` as optional fields.~~ Deferred.
- [ ] ~~**2A.4** Update `api_contract.md` for new SDK fields.~~ Deferred with 2A.1/2A.3.
- [ ] ~~**2A.5** SDK version bump.~~ Deferred.

#### 2B — Server: persist match keys

- [x] **2B.1** Migration: add `country` (varchar 2), `postal_code` (varchar 16), `fbp` (varchar 64), `fbc` (varchar 256), `gclid` (varchar 256, denormalised from `click_ids` JSONB for index efficiency) to `sessions`. Indexes on `(account_id, gclid)` and `(account_id, fbp)`.
- [x] **2B.2** Migration: add `email_sha256` (varchar 64), `phone_e164_sha256` (varchar 64), `first_name_sha256` (varchar 64), `last_name_sha256` (varchar 64) to `identities`. Index on `email_sha256` (account-scoped lookup for ad-platform match-rate diagnostics).
- [x] **2B.3** Service: `Identities::Normaliser` (pure module, no AR). Methods: `normalise_email`, `normalise_phone_e164`, `normalise_name`, `sha256`. Tests on canonical fixtures from Meta and Google docs.
- [x] **2B.4** Service: `Identities::IdentificationService` accepts canonical raw fields (`email`, `phone`, `first_name`, `last_name`) in `traits`, normalises and hashes server-side, writes to the new columns. Existing arbitrary `traits` JSONB stays untouched for backwards compatibility (customers may already write to `traits.email`).
- [x] **2B.5** Service: `Sessions::TrackingService` accepts `fbp`, `fbc`, `country`, `postal_code` from session create payloads. Persist on the session row.
- [ ] **2B.6** Backfill task: `bin/rails conversion_feedback:backfill_hashed_pii ACCT=...` reads existing identities' `traits["email"]` / `traits["phone"]` (best-effort by common key names: `email`, `Email`, `e_mail`, `phone`, `mobile`) and populates the new hashed columns. Surfaces a report of identities with no recoverable email or phone.
- [x] **2B.7** Tests: column round-trip, normaliser correctness against Meta + Google fixture vectors, backfill idempotency.

#### 2C — Conversion match-key resolver

- [x] **2C.1** `Conversions::MatchKeyResolver.call(conversion)` returns a struct with `external_id` (= `SHA-256(Identity#external_id)`), `em`, `ph`, `fn`, `ln`, `country`, `zp`, `fbp`, `fbc`, `gclid`, `gbraid`, `wbraid`. Pulls from the conversion's `Identity` (PII, external_id) and `Session` (cookies, country, postal). Returns nil values where data is absent. **No `client_ip_address` or `client_user_agent` fields** — mbuzz declines to send these.
- [x] **2C.2** Predicate: `MatchKeyResolver#meta_sufficient?` (at least one of `external_id`, `em`, `ph`, `fbc`, `fbp`). `#google_sufficient?` (at least one of `email_sha256`, `phone_e164_sha256`, `gclid`, `gbraid`, `wbraid`).
- [x] **2C.3** Tests: resolver pulls correct fields, sufficiency predicates per platform.

### Phase 3 — Models + migrations for dispatch tracking

- [x] **3.1** Migration: `conversion_destinations`
  - `id`, `account_id` (FK), `platform` (string: `meta_capi` | `google_ec`), `name` (string), `enabled` (bool, default false)
  - **`attribution_model_id`** (FK to `attribution_models`, NOT NULL): which model credits decide whether to fire and how to value the dispatch
  - **`revenue_mode`** (string, default `full`; one of `full` | `scaled`): full-conversion revenue to every platform credited, or `revenue × credit_share`
  - **`minimum_credit_threshold`** (decimal, default `0.0`): suppress dispatch when platform credit below this fraction (0.0 = any positive credit fires)
  - `meta_pixel_id` (string, nullable), `meta_access_token` (text, encrypted via `encrypts :meta_access_token`). No `appsecret_proof` secret column in v1.
  - `google_customer_id` (string, nullable), `google_login_customer_id` (string, nullable; manager link)
  - `google_conversion_action_resource_name` (string, nullable; can also live in event_type_mapping if multiple events map to different actions)
  - `ad_platform_connection_id` (FK to `ad_platform_connections`, nullable; used for Google's OAuth refresh)
  - `event_type_mapping` (jsonb, default `{}`): `{ "Lead" => { "meta_event" => "Lead", "google_resource_name" => "customers/123/conversionActions/456" }, ... }`
  - `created_at`, `updated_at`
  - Indexes: `(account_id, platform)`, `(account_id, enabled)`, `(attribution_model_id)`
- [x] **3.2** Migration: `conversion_dispatches`
  - `id`, `conversion_id` (FK), `conversion_destination_id` (FK), `account_id` (FK, denormalised for fast admin queries)
  - `status` (enum-as-string): `pending`, `delivered`, `skipped_no_identity`, `skipped_no_credit`, `skipped_account_suspended`, `token_failed`, `failed_transient`, `failed_permanent`
  - **`attribution_model_id`** (FK, denormalised snapshot of which model decided this dispatch — destinations may change models over time, dispatch row records what was used)
  - **`platform_credit_share`** (decimal, nullable): credit fraction this platform got under the chosen model at dispatch time (0.0 to 1.0). Surfaces in admin for diagnosing why a conversion did or didn't fire.
  - `payload` (jsonb), `response` (jsonb, nullable), `error` (text, nullable), `retries_count` (int, default 0)
  - `fired_at` (datetime, nullable), `created_at`, `updated_at`
  - Indexes: unique `(conversion_id, conversion_destination_id)`, `(account_id, status, created_at)` for admin queries
- [x] **3.3** Models with associations + scopes (`account.conversion_destinations`, `conversion.conversion_dispatches`, `ConversionDispatch#delivered?`, `ConversionDestination#meta?` / `#google?`).
- [x] **3.4** Tests: model validations, scopes, encryption round-trip on `meta_access_token` (verify `Rails 7+ encrypts` works; do NOT reach for `attr_encrypted` gem).
- [ ] **3.5** Update `lib/docs/BUSINESS_RULES.md` with new entities + dispatch status semantics (new section 13).

### Phase 4 — Meta CAPI dispatcher

Independent of Google. Can ship after Phases 0B + 1 + 2 + 3, no Phase 5 dependency.

- [x] **4.1** `AdDestinations::Meta::PayloadBuilder` — pure function, takes `Conversion` + `ConversionDestination` + `MatchKeyResolver` output, returns CAPI event hash. Tested against fixture conversions, no HTTP. Builder follows Meta's CAPI payload spec (`event_name`, `event_time`, `event_id`, `event_source_url`, `action_source: "website"`, `user_data: {...}`, optional `custom_data: { value, currency }`). **`user_data` excludes `client_ip_address` and `client_user_agent` by design** (see "Why no IP / UA" in the architecture section).
- [x] **4.2** Hashing: reuse `Identities::Normaliser` from Phase 2. Re-hash safety: if input is already 64 lowercase hex chars, treat as already hashed. Country lowercased ISO-2 then SHA-256. Postal hashed for Meta. **fbp / fbc never hashed.** `external_id` is `SHA-256(Identity#external_id)`.
- [x] **4.3** `AdDestinations::Meta::ApiClient` — POST to `https://graph.facebook.com/v22.0/{pixel_id}/events` with bearer-style `access_token` query param. **No `appsecret_proof` in v1** (would require the customer's BM admin to share the auto-created CAPI app's secret; deferred to v2 hardening pass per Phase 0B.3). Calls `AdPlatforms::ApiUsageTracker.increment!(:meta_capi)` per request. Uses Rails `Net::HTTP` (no new gem dependency).
- [x] **4.4** `AdDestinations::Meta::Dispatcher` — orchestrator: build payload → POST → write dispatch row. Maps platform response codes to dispatch statuses per the All States table.
- [x] **4.5** Register in `AdDestinations::Registry`.
- [ ] **4.6** VCR cassettes: success (`Lead` event), 400 (bad payload), 401 (token expired), 429 (rate limited), 500 (transient).
- [ ] **4.7** Rake task `conversion_feedback:meta:smoke ACCT=... DEST=... CONV=...` builds + sends a single dispatch end-to-end against Meta's Test Events endpoint. Includes a `test_event_code` field so events land in Test Events tab, not production.
- [ ] **4.8** Manual QA: fire one BSA conversion against Test Events. Verify EMQ ≥ 6.5 (target without IP/UA; 6.0 minimum acceptable). If EMQ is low, the lever is broader match-key coverage (more identifies with email/phone/external_id), not adding IP/UA.

### Phase 5 — Google EC for Leads dispatcher

**Gated on Phase 0A approval.**

- [ ] **5.1** Add `google-ads-googleads` gem to `Gemfile`. Pin to current `>= 26.0`.
- [ ] **5.2** `AdDestinations::Google::PayloadBuilder` — pure function. Builds `ClickConversion` with:
  - `conversion_action`: resource name from destination
  - `conversion_date_time`: ISO 8601 with timezone
  - `conversion_value`: from `Conversion#revenue` (nil-safe)
  - `currency_code`: from `Conversion#currency`
  - `order_id`: `Conversion#idempotency_key`
  - `gclid` / `gbraid` / `wbraid`: from `Session#click_ids` (top-level field on `ClickConversion` per Google API)
  - `user_identifiers`: array of `{ hashed_email }`, `{ hashed_phone_number }`, `{ address_info: { hashed_first_name, hashed_last_name, country_code, postal_code } }`. **Do NOT hash country / postal for Google.**
  - `consent`: `ad_user_data: GRANTED` (BSA assumption; revisit when consent management lands)
- [ ] **5.3** `AdDestinations::Google::ApiClient` — wraps `ConversionUploadService#upload_click_conversions`. Reuses OAuth refresh from `AdPlatforms::Google::TokenRefresher`. Calls `ApiUsageTracker.increment!(:google_ec)`. **MUST NOT include `user_agent` or `ip_address` fields** (Feb 2026 rule for new developers).
- [ ] **5.4** `AdDestinations::Google::Dispatcher` — orchestrator. Handles `partial_failure_error` from Google's response: per-conversion status reporting (some succeed, some fail in a single batch).
- [ ] **5.5** Register in `AdDestinations::Registry`.
- [ ] **5.6** VCR cassettes: success, partial failure, auth failure (`OAUTH_TOKEN_INVALID`), quota exceeded, conversion_action not found.
- [ ] **5.7** Rake task `conversion_feedback:google:smoke`.
- [ ] **5.8** Manual QA: fire one BSA conversion. Verify it appears in Google Ads Conversions report (24-48h delay typical) and that EC for Leads coverage > 0% in the conversion action's "Diagnostics" tab.

### Phase 6 — Trigger from conversion lifecycle + dispatch service

- [x] **6.1** `Conversions::DispatchService.call(conversion)` finds enabled `ConversionDestinations` for the account + maps `conversion_type` via `event_type_mapping`, then enqueues `OutboundConversionJob` per (conversion × destination) where no `delivered` dispatch already exists. Does NOT compute attribution credit shares — that happens inside the job so retries can re-read fresh credits if the model recalculates between attempts.
- [x] **6.2** `OutboundConversionJob` — Solid Queue worker. Steps:
  1. Load conversion + destination + destination's `attribution_model`
  2. **Compute platform credit share via `Conversions::PlatformCreditCalculator.call(conversion, destination)`**: returns the fraction (0.0 to 1.0) of credit assigned to the destination's platform under the model. Touchpoint matching uses the destination registry's `source_match` predicate (Meta = fbclid present OR paid_social with meta-family source; Google = gclid/gbraid/wbraid present OR paid_search with google source).
  3. **If credit_share < destination.minimum_credit_threshold → mark `skipped_no_credit`, record `platform_credit_share`, return.**
  4. Build payload via `AdDestinations::Registry.dispatcher_for(destination)`. Pass `revenue` adjusted per `destination.revenue_mode`: `full` sends `Conversion#revenue` unchanged; `scaled` sends `revenue × credit_share`.
  5. POST. Increment `ApiUsageTracker`. Update dispatch row.
  6. Idempotent on retry. Status transitions: `pending` → `delivered` | `failed_*` | `skipped_*`.
- [x] **6.3** Hook `Conversions::DispatchService.call` into the conversion creation lifecycle. **Open question 2 below decides where**: an `after_commit` on `Conversion` keeps it implicit; a direct call from `Conversions::TrackingService#run` keeps it explicit (preferred per CLAUDE.md "no callbacks for cross-aggregate side effects" pattern in `feedback_global_processor_pattern.md`). Verify before wiring.
- [x] **6.4** Retry semantics. Dispatcher persists the row first, then raises `AdDestinations::Errors::RetryableDispatchError` for `token_failed` / `failed_transient` (auth + 429 + 5xx). `OutboundConversionJob` declares `retry_on AdDestinations::Errors::RetryableDispatchError, wait: :polynomially_longer, attempts: 3` so only the explicit retryable class triggers retries — `RecordInvalid` / `NoMethodError` / etc. surface as proper failures. Permanent 4xx and skipped statuses return normally (the row IS the outcome). `OutboundDispatchService` stamps `attribution_model_id` + `platform_credit_share` on the row BEFORE invoking the dispatcher so the stamp survives a raise.
- [x] **6.5** Tests: dispatch service finds correct destinations, enqueues jobs, skips disabled, skips already-delivered, skips by event_type_mapping, skips when flag off. Dispatcher raises on 401/429/5xx and persists the row in token_failed/failed_transient. Dispatcher does NOT raise on 400 (failed_permanent stays terminal). Job re-enqueues on 503, does NOT re-enqueue on 400. Attribution stamp survives a raised dispatcher.

### Phase 7 — Admin surface + monitoring

- [ ] **7.1** `app/controllers/admin/conversion_dispatches_controller.rb#index` — paginated list, scoped to `current_account`. Filter by status, destination, date range. Default order: most recent first. (Confirm CLAUDE.md `skip_marketing_analytics` declaration on this admin controller.)
- [ ] **7.2** Show view: payload + response JSON pretty-printed. Retry button for failed dispatches (re-enqueues the job, increments retry count, but bypasses the "already delivered" guard).
- [ ] **7.3** Stat tile on admin dashboard: "Conversion dispatches last 24h: X delivered, Y failed."
- [ ] **7.4** Daily Slack digest of `failed_permanent` dispatches per account via existing `InternalNotifications`. One row per account, count per platform.
- [ ] **7.5** `ApiUsageTracker` admin view already surfaces per-platform call counts. Verify `:meta_capi` and `:google_ec` appear after Phases 4 + 5.
- [ ] **7.6** Match-quality diagnostic page: per-account, last 7d, count of dispatches with each match-key combination. Helps the customer identify which match keys are missing for low-EMQ events.
- [ ] **7.7** Attribution-model diagnostic: per-destination, distribution of `platform_credit_share` over last 7d (e.g. histogram of conversions where Meta got 0%, 0-25%, 25-50%, 50-100% credit). Surfaces "is the model crediting this platform reasonably?" without requiring a console query. Also shows `skipped_no_credit` count so customers can see how many conversions the model is filtering out.

### Phase 8 — Wire BSA + ship

- [ ] **8.1** Seed `ConversionDestination` rows for BSA via rake task `conversion_feedback:bsa:seed`:
  - Meta destination: BSA Pixel ID + System User token (from 1Password) + `attribution_model_id` = BSA's `last_touch` model + `revenue_mode` = `full` + `minimum_credit_threshold` = `0.0`
  - Google destination: BSA Customer ID + manager link's `login_customer_id` + reference to BSA's existing `AdPlatformConnection` (the Google OAuth from spend pull) + per-conversion-type resource names + `attribution_model_id` = BSA's `last_touch` model + `revenue_mode` = `full` + `minimum_credit_threshold` = `0.0`
  - Confirm with BSA marketing that `last_touch` is the right starting model. Doc the choice in the runbook so a future model swap is intentional, not a stealth change.
- [ ] **8.2** Map BSA conversion types to platform events in `event_type_mapping`:
  - `Lead` → Meta `Lead` + Google EC for Leads with the `Lead` conversion action resource name
  - `Tour Booked` → Meta `Schedule` + Google with `Tour Booked` resource name
  - `Registered` → Meta `CompleteRegistration` + Google with `Registered` resource name
  - `Enrolled` → Meta `Subscribe` + Google with `Enrolled` resource name
- [ ] **8.3** Enable feature flag for BSA account.
- [ ] **8.4** Monitor first 48h:
  - Dispatches fire with `status=delivered` or `status=skipped_no_credit` (the latter is expected and healthy: under last-touch, conversions whose last paid touchpoint was Google won't fire to Meta, and vice versa).
  - Meta Events Manager → real production events landing within 30s, EMQ ≥ 6.5.
  - Google Ads → conversions appearing within 24h, EC for Leads coverage > 0%.
  - Attribution-model diagnostic (Phase 7.7): credit-share distribution looks plausible; `skipped_no_credit` rate sits in the 30-60% range. If 90%+ of conversions skip, the model probably isn't crediting paid platforms (BSA may be very organic-heavy) — surface in a conversation, not a config change. If 0% skip, the model may not be filtering at all (bug).
- [ ] **8.5** Document the BSA setup in `lib/docs/runbook/bsa_conversion_feedback.md` (new file): destination IDs (placeholders only — real IDs in 1Password), conversion-action resource names, token rotation reminders, monitoring dashboards to check.

---

## Testing Strategy

### Unit tests

| Test | File | Verifies |
|---|---|---|
| Identity normaliser email | `test/services/identities/normaliser_test.rb` | Lowercase + trim + SHA-256 matches Meta + Google fixture vectors |
| Identity normaliser phone E.164 | same | Variants normalise to canonical form before hashing |
| Identity normaliser name | same | Strips diacritics, lowercases |
| Match-key resolver assembles fields | `test/services/conversions/match_key_resolver_test.rb` | Pulls `em`, `ph`, `fbc`, `fbp`, etc. from Identity + Session |
| Match-key resolver sufficiency predicates | same | `meta_sufficient?` and `google_sufficient?` correctly identify minimum match keys |
| Meta payload builder happy path | `test/services/ad_destinations/meta/payload_builder_test.rb` | Full match keys → correct CAPI hash |
| Meta payload builder skips fbc when no fbclid | same | No fabricated fbc |
| Meta payload builder excludes IP and UA | same | `user_data` never contains `client_ip_address` or `client_user_agent`, regardless of input |
| Meta hashing | same | external_id / em / ph / fn / ln / country / zp hashed; fbc / fbp NOT hashed; ip / ua NOT sent at all |
| Google payload builder happy path | `test/services/ad_destinations/google/payload_builder_test.rb` | `ClickConversion` with `user_identifiers` array |
| Google payload builder excludes IP/UA | same | Per Feb 2026 rule, no IP / session attributes |
| Dispatch service finds destinations | `test/services/conversions/dispatch_service_test.rb` | Correct destinations matched per (account, conversion_type) via event_type_mapping |
| Dispatch service idempotency | same | No duplicate dispatch rows on re-enqueue |
| Platform credit calculator: last-touch + Meta | `test/services/conversions/platform_credit_calculator_test.rb` | Last touchpoint had fbclid → Meta credit = 1.0 |
| Platform credit calculator: last-touch + Google | same | Last touchpoint had gclid → Google credit = 1.0 |
| Platform credit calculator: last-touch + organic conversion | same | Last touchpoint was organic → both Meta and Google credit = 0.0 |
| Platform credit calculator: linear with mixed touchpoints | same | 4 touchpoints, 1 Meta + 1 Google + 2 organic → Meta credit = 0.25, Google credit = 0.25 |
| Platform credit calculator: markov with no Meta touchpoints | same | Conversion's path has no Meta touchpoint → Meta credit = 0.0 |
| Job: skipped_no_credit when below threshold | `test/jobs/outbound_conversion_job_test.rb` | Credit share 0.05, threshold 0.1 → status=skipped_no_credit, no platform call, dispatch row records share |
| Job: revenue_mode=scaled sends fractional value | same | Conversion revenue $100, credit share 0.4, mode=scaled → platform receives $40 in custom_data.value |
| Job: revenue_mode=full sends full value when credited | same | Conversion revenue $100, credit share 0.4, mode=full → platform receives $100 |
| Job — happy path | `test/jobs/outbound_conversion_job_test.rb` | VCR cassette → `delivered` |
| Job — token expired retries once | same | First call 401 → refresh → retry → success |
| Job — permanent 4xx fails out | same | Marks `failed_permanent`, captures response, no retry |
| Job — 429 retries with backoff | same | Solid Queue retry policy invoked |
| ApiUsageTracker increments | `test/services/ad_platforms/api_usage_tracker_test.rb` | `:meta_capi` and `:google_ec` increment per request |

### Integration tests

| Test | File | Verifies |
|---|---|---|
| End-to-end Meta dispatch | `test/integration/conversion_feedback_meta_test.rb` | Conversion created → DispatchService called → Job runs → VCR-replayed CAPI returns 2xx → dispatch row reflects success |
| End-to-end Google dispatch | `test/integration/conversion_feedback_google_test.rb` | Same shape for Google EC for Leads |
| Match-key insufficiency path | `test/integration/conversion_feedback_skipped_test.rb` | Conversion with no usable identifiers → `skipped_no_identity`, no platform call |

### VCR cassette discipline

Per `feedback_no_mocks.md`: pure parsers tested against fixture JSON, HTTP via VCR cassettes recorded against real (or sandbox) APIs with sensitive data filtered. Cassettes named per orchestrator + scenario:

```
test/vcr_cassettes/ad_destinations/meta/dispatcher_success.yml
test/vcr_cassettes/ad_destinations/meta/dispatcher_token_expired.yml
test/vcr_cassettes/ad_destinations/meta/dispatcher_rate_limited.yml
test/vcr_cassettes/ad_destinations/google/dispatcher_success.yml
...
```

Cassettes filter: access tokens, refresh tokens, app secrets, customer IDs, pixel IDs, real email hashes (regex match `[a-f0-9]{64}` → `<hashed_pii>`).

### Manual QA

1. Configure BSA with one Meta destination + one Google destination.
2. Submit a test form on BSA's site with a known email (test mode if available).
3. Verify `ConversionDispatch` rows created with `status=delivered` for both destinations.
4. Meta Events Manager → Test Events: event appears within ~30s. EMQ ≥ 6.5.
5. Google Ads UI: conversion appears within 24h, EC for Leads coverage > 0%.
6. Force-fail one destination (rotate token) and verify the dispatch retries then surfaces in admin.
7. Send a conversion with no identity at all → verify `skipped_no_identity`, no platform call.

---

## Definition of Done

- [ ] Phases 0–8 completed
- [ ] All unit + integration tests pass
- [ ] VCR cassettes committed, no token leaks (`bin/rails vcr:audit` if available, otherwise grep)
- [ ] BSA account seeded with destinations + feature flag enabled
- [ ] First production dispatches landed: Meta visible in Events Manager with EMQ ≥ 6.5; Google visible in conversions report with EC coverage > 0%
- [ ] Each `ConversionDestination` has an `attribution_model_id` set; `skipped_no_credit` rate looks reasonable in admin (BSA expectation: ~30-60% skip rate under last_touch, since most conversions credit either Meta OR Google but not both)
- [ ] Admin UI surfaces dispatches + failure states + match-quality diagnostics
- [ ] `lib/docs/BUSINESS_RULES.md` updated with new entities + status semantics (new section 13)
- [ ] `lib/docs/PRODUCT.md` updated to mention conversion feedback as a capability
- [ ] `lib/docs/sdk/api_contract.md` updated for new `fbp` / `fbc` / `country` / `postal_code` SDK fields (Phase 2A)
- [ ] `lib/specs/platform_api_approvals_spec.md` updated to reflect Google Ads Tool Change Form submission + outcome
- [ ] Runbook for BSA setup committed (`lib/docs/runbook/bsa_conversion_feedback.md`)
- [ ] Spec moved to `lib/specs/old/` once stable in production for ≥ 14 days

---

## Out of Scope (deferred to later specs)

- **Multi-tenant self-serve config UX.** v1 ships BSA-tenant-scoped via rake task / admin form. Productised connect flow ("click to connect Meta CAPI") deferred to `lib/specs/future/conversion_destinations_oauth_spec.md`.
- **Other platforms.** TikTok Events API, LinkedIn Conversions API, Microsoft UET, Pinterest Conversions API. Each gets its own spec when prioritised.
- **Outbound deletion / right-to-delete propagation.** When a customer revokes consent or requests deletion, mbuzz should re-fire to platforms instructing them to delete the conversion event. Separate spec, blocked on Children's Code legal review for BSA's needs anyway.
- **Batch upload modes.** Google Ads supports CSV upload via UI and Offline Conversion Imports via API. v1 only does the API path. Batch import deferred unless a customer needs it.
- **Server-side audience activation.** Different surface (Custom Audiences API, Customer Match). Spec separately if mbuzz pursues this.
- **Attribution-feedback variants.** Meta supports `EnhancedConversion` and other event-source variants. v1 picks one (CAPI for Web). Other source codes deferred.
- **Standard Access for Google Ads.** Basic Access (15K ops/day) is sufficient for BSA's volume and most early customers. Standard Access requires RMF and a separate compliance review. Defer until usage approaches the 15K daily cap.
- **`Conversion#consent_marketing` column.** Adds a customer-facing "did this user consent to ad-platform sharing" gate. Out of scope until the deletion-propagation flow needs it.
- **IP / user-agent fallback for Google EC.** Per Feb 2026 rule, NEW developers cannot use IP / session attributes. mbuzz is in the "new" cohort. No workaround.

---

## Open questions to resolve before Phase 1

1. **Storage for `meta_access_token`.** Confirmed: Rails 7+ built-in `encrypts :meta_access_token`. mbuzz already uses this for `ApiKey#key_digest` and `AdPlatformConnection#refresh_token`. No new gem.
2. **Where the conversion-creation callback lives.** Two options:
   - `after_commit on: :create` on `Conversion` model. Implicit, easy to forget when a new conversion creation path lands.
   - Direct call from `Conversions::TrackingService#run` after the conversion saves. Explicit, matches the codebase's existing global-processor pattern (per `feedback_global_processor_pattern.md`).
   - **Recommendation: explicit call from `TrackingService`.** Verify there are no other paths creating conversions (Shopify webhook handler, internal jobs, reattribution). If so, factor into a single point.
3. **Conversion-type → platform-event mapping shape.** JSONB on `ConversionDestination` (recommended) or separate `ConversionDestinationEventMap` table. JSONB simpler for v1; extract if it gets unwieldy or needs per-mapping toggles.
4. **Solid Queue retry semantics.** Confirm default retry count + backoff. `Conversion::OutboundJob` may need a different policy than the default (longer max delay for ad-platform recovery).
5. ~~IP for Meta CAPI.~~ **Resolved: no IP, no UA, ever.** Sessions don't store raw IP (only `device_fingerprint = SHA256(ip|ua)[0:32]`), and re-deriving IP at request time just to feed Meta would change the data flow for marginal EMQ gain (~0.5 point). mbuzz's brand position is privacy-respecting / vendor-neutral; sending raw IP to Meta would contradict that and complicate GDPR / Children's Code reviews. Lean on `external_id` (hashed customer CRM ID) as the primary match key plus hashed PII + fbc/fbp.
6. **`fbclid` URL stripping in Safari.** iOS 17+ strips `fbclid` in Messages, Mail, Safari Private. The `_fbc` cookie set on landing survives this for that session, but a user who lands directly without ever seeing `fbclid` has no fbc. Not a fix-now problem; document in match-quality diagnostic UI.
7. **Touchpoint → platform matching predicate.** `Conversions::PlatformCreditCalculator` decides "did this touchpoint count as Meta?" The cleanest signal is click ID presence (`fbclid` for Meta, `gclid`/`gbraid`/`wbraid` for Google) but for organic conversions or self-referred channels, the predicate falls back to channel + source. Define the exact rules in the destination registry (`AdDestinations::Meta::Dispatcher.source_match` and `AdDestinations::Google::Dispatcher.source_match`) so they live with the dispatcher, not in `PlatformCreditCalculator`. Open: edge cases like Facebook organic referrals (channel=organic_social, source=facebook) — does mbuzz credit Meta for the conversion? Probably not via CAPI feedback; CAPI is paid-side. Keep the rule strict: click ID present, OR channel is `paid_social`/`paid_search` with a source in the platform's family.
8. **Attribution recalculation timing.** mbuzz recalculates attribution credits asynchronously after conversion creation (via existing `AttributionCalculationJob`). The dispatch job needs FRESH credits. Either: (a) `OutboundConversionJob` waits for `AttributionCalculationJob` to finish (via Solid Queue dependency or polling), or (b) `OutboundConversionJob` runs `Conversions::PlatformCreditCalculator` synchronously, which under the hood ensures credits are calculated. (b) is simpler. Verify the calculator handles the case where credits don't exist yet — synthesize them on demand or block until they do.

---

## References

- [Google Ads API Access Levels](https://developers.google.com/google-ads/api/docs/api-policy/access-levels) — Basic vs Standard, RMF
- [Google Ads API Developer Token policy](https://developers.google.com/google-ads/api/docs/api-policy/developer-token) — Tool Change Form
- [Google Ads API: Manage offline conversions](https://developers.google.com/google-ads/api/docs/conversions/upload-offline) — `ConversionUploadService.UploadClickConversions`
- [Google Ads API February 2026 stricter conversion rules](https://almcorp.com/blog/google-ads-api-conversion-data-changes-2026/) — IP / session attributes restricted for new developers
- [Meta Conversions API: fbp / fbc parameters](https://developers.facebook.com/docs/marketing-api/conversions-api/parameters/fbp-and-fbc) — cookie format, fbc derivation from fbclid
- [Meta CAPI 2026 setup guide](https://www.dataally.ai/blog/how-to-set-up-meta-conversions-api) — System User token via Events Manager (no App Review)
- [mbuzz `feedback_global_processor_pattern.md`](file:./feedback_global_processor_pattern.md) — explicit global processor over per-platform callbacks
- [mbuzz `feedback_no_mocks.md`](file:./feedback_no_mocks.md) — VCR for HTTP, no stubs for business logic
