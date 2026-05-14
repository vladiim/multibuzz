# Shopify App Hardening Specification

**Date:** 2026-05-15
**Priority:** P1 (finding C1 is P0 — fix before driving any install traffic)
**Status:** Parked (2026-05-15)
**Branch:** `fix/shopify-app-hardening`

> **PARKED 2026-05-15.** The Shopify App Store channel was killed on focus
> grounds before this spec was actioned. It is retained for if/when the channel
> is reopened. The decision, rationale, and revisit trigger are in
> `mbuzz-org/memory/long_term/key_decisions.md` (2026-05-15 entry). Do not action
> these tasks unless the channel is formally reopened.

> **Cross-repo spec.** The Shopify app lives in a separate repo (`../mbuzz-shopify`).
> The mbuzz backend lives here (`multibuzz`). Every task below is tagged
> `[mbuzz-shopify]` or `[multibuzz]`. Findings C1, H3 and L5 require coordinated
> changes in both.

---

## Summary

mbuzz has a published Shopify App Store app ("mbuzz Attribution") that tracks the
customer journey on a merchant's storefront and attributes orders back to
acquisition touchpoints. An end-to-end review on 2026-05-15 found the core
attribution architecture sound but surfaced one security issue, one false value
claim, and a set of review-blocking and robustness gaps. This spec records the
findings and the work to clear them before the listing is promoted or install
traffic is driven to it. The app currently has near-zero installs ("early days"),
so blast radius is small now — that is the window to fix this in.

---

## Current State

Two repos cooperate:

- **`mbuzz-shopify`** — Remix app. Handles OAuth install, the embedded settings
  page, a Theme App Extension (`mbuzz-tracking`) and a Web Pixel Extension
  (`mbuzz-pixel`). Deployed via Kamal. App URL `shopify.mbuzz.co`.
- **`multibuzz`** — receives `orders/paid` and `customers/create` webhooks at
  `mbuzz.co/webhooks/shopify` (`Webhooks::ShopifyController`), verifies the HMAC
  with a per-account `shopify_webhook_secret`, and creates attributed
  conversions via `Shopify::WebhookHandler`.

### Data Flow (Current)

```
Visitor lands on storefront
  → mbuzz-tracking theme extension generates 64-char hex visitor_id
  → stored in cookie (_mbuzz_vid) + localStorage
  → written to Shopify cart attributes (_mbuzz_visitor_id) via /cart/update.js
  → page/session/add_to_cart events POSTed to api.mbuzz.co with the API key
Visitor checks out
  → mbuzz-pixel (sandboxed) tries to read _mbuzz_vid, sends identify on email
  → Shopify fires orders/paid webhook → mbuzz.co/webhooks/shopify
  → Webhooks::ShopifyController matches note_attributes[_mbuzz_visitor_id]
  → Shopify::WebhookHandler creates the attributed conversion
```

The attribute name matches on both sides (`_mbuzz_visitor_id` in the theme JS =
`Shopify::NOTE_ATTR_VISITOR_ID` in `app/constants/shopify.rb`). Visitor ID format
matches the server-side SDKs (64-char hex). The cart-attribute mechanism is the
correct way to carry attribution data into a Shopify order. The app already
respects server-side session resolution (session cookies removed in v0.7.0).

---

## Findings

| ID | Severity | Finding | Repo |
|----|----------|---------|------|
| C1 | Critical | Merchant's `sk_` **secret** key is rendered into storefront page source (`window.mbuzzConfig.apiKey`) and used as a `Bearer` token in client-side `fetch`. Anyone can view-source and steal it. `app._index.tsx` validation enforces the `sk_` prefix. | both |
| C2 | Critical | "No technical setup required" is not true. The settings page itself lists: enter the API key twice (app + theme extension), manually create webhooks in Shopify admin, copy the webhook signing secret into `mbuzz.co/dashboard/settings`. Root cause: `orders/paid` carries PII, so webhooks cannot be auto-subscribed without Shopify Protected Customer Data (PCD) approval. | process |
| H3 | High | The Web Pixel runs sandboxed. `mbuzz-pixel` reads `_mbuzz_vid` via `browser.cookie.get`, which may not see the storefront cookie the theme extension set. Commit `d4e8059` added localStorage "for pixel access" but the pixel still uses cookies — an unfinished migration. If broken, checkout identity linking silently fails. | mbuzz-shopify |
| H4 | High | `APP_UNINSTALLED` cleanup is commented out (`webhooks.tsx:22-23`). Uninstalling leaves `shopSettings` (including the API key) and `session` rows in the database. | mbuzz-shopify |
| H5 | High | Shopify's mandatory GDPR webhooks (`customers/data_request`, `customers/redact`, `shop/redact`) are not found in repo config. A published app without them can be pulled. Needs verification against the Partner Dashboard. | mbuzz-shopify |
| H6 | High | `shopify.app.mbuzz.toml` contains placeholder URLs (`shopify.dev/apps/default-app-home`). If that named config is activated, OAuth breaks. | mbuzz-shopify |
| M7 | Medium | Add-to-cart tracking monkey-patches `window.fetch` (`mbuzz-shopify.js:281`). Misses themes using XHR or form-POST, silently fails on non-AJAX `/cart/add`, and global `fetch` override is a Built-for-Shopify anti-pattern. The Web Pixel's standard `product_added_to_cart` event is the correct source. | mbuzz-shopify |
| M8 | Medium | `write_script_tags` scope is requested but no `ScriptTag` API call exists. Legacy, discouraged, incompatible with Built-for-Shopify, widens the merchant consent screen. | mbuzz-shopify |
| M9 | Medium | `auto_page_view` defaults to `false`. For a multi-touch attribution product, page views are the touchpoints. The default ships behavior closer to last-touch. | mbuzz-shopify |
| L10 | Low | API key entered twice (app settings page → Prisma `shopSettings`; theme extension settings). The tracking JS only uses the theme value, so the Prisma copy looks unused by the tracking path. | mbuzz-shopify |
| L11 | Low | `multibuzz` still ships the pre-app manual integration: `app/views/onboarding/_install_shopify.html.erb` and `app/views/docs/_platforms_shopify.html.erb` describe manual webhook creation. A merchant who installs the App Store app then reads these docs gets contradictory instructions. | multibuzz |
| L12 | Low | `README.md` stale: says deploy to Fly.io (repo moved to Kamal), omits the Web Pixel extension. `storeInCart()` fires on every page load; express checkouts (Shop Pay) bypass the cart, so those orders carry no attribute and are not attributed. | mbuzz-shopify |

### Verified vs. unknown

C1, C2, H4, H6, M7, M8, M9, L10, L11, L12 were verified by reading the code and
config. **H3 and H5 are unknowns** — they need a live check (H3 on a real
checkout, H5 against the Partner Dashboard) before the fix is scoped. They are
written as discovery tasks below, not assertions.

---

## Proposed Solution

Three phases, ordered by severity. Phase 1 must clear before the listing is
promoted or install traffic is driven to it. Phases 2 and 3 can land in parallel
with the PCD approval wait (C2).

### Data Flow (Proposed — the C1 change)

```
Theme extension + pixel use a publishable, write-scoped key (pk_...)
  → key can ONLY write to /sessions, /events, /conversions, /identify
  → cannot read attribution data, cannot reach admin/dashboard endpoints
  → safe to render in storefront page source
Secret sk_ keys never leave the server / dashboard.
```

### Key Files

| File | Repo | Purpose | Changes |
|------|------|---------|---------|
| `app/models/api_key.rb` (or equivalent) | multibuzz | API key model | Add a write-scoped publishable key type, or confirm one exists |
| `app/controllers/api/v1/*_controller.rb` | multibuzz | Ingestion endpoints | Accept the publishable key; reject it on read/admin endpoints |
| `app/controllers/webhooks/shopify_controller.rb` | multibuzz | Webhook ingestion | No change expected; confirm matching logic |
| `app/views/onboarding/_install_shopify.html.erb` | multibuzz | Onboarding | Replace manual flow with "install from App Store" |
| `app/views/docs/_platforms_shopify.html.erb` | multibuzz | Docs | Same |
| `config/sdk_registry.yml` | multibuzz | SDK registry | Update Shopify entry to reflect the published app |
| `extensions/mbuzz-tracking/blocks/tracking.liquid` | mbuzz-shopify | Theme extension | Use publishable key |
| `extensions/mbuzz-tracking/assets/mbuzz-shopify.js` | mbuzz-shopify | Tracking JS | Use publishable key; replace fetch monkey-patch |
| `extensions/mbuzz-pixel/src/index.js` | mbuzz-shopify | Web Pixel | Use publishable key; fix visitor_id read; add add-to-cart event |
| `app/routes/app._index.tsx` | mbuzz-shopify | Settings page | Update key validation; resolve double entry |
| `app/routes/webhooks.tsx` | mbuzz-shopify | Webhook handler | Implement `APP_UNINSTALLED`; add GDPR topics |
| `shopify.app.toml` / `shopify.app.mbuzz.toml` | mbuzz-shopify | App config | Remove scope M8; delete/fix placeholder config |

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Happy path | Visitor lands, browses, adds to cart, checks out via standard checkout | visitor_id rides cart attributes → order `note_attributes` → conversion attributed |
| Express checkout | Visitor uses Shop Pay / dynamic checkout button, bypassing the cart | No cart attribute set. Order is **not** attributed. Document as a known limitation; consider pixel-side fallback |
| Pixel cannot read visitor_id | Sandboxed pixel fails to access `_mbuzz_vid` (H3) | Checkout identify is skipped. Conversion still attributes via cart attributes if present; identity linking is lost |
| No API key | Merchant has not entered a key in the theme extension | Tracking JS logs a warning and sends nothing. No errors surfaced to the storefront |
| Stolen key (current C1 state) | Third party lifts the `sk_` key from page source | Full API access under the merchant's account. **This is the bug.** After C1, a stolen `pk_` key can only write events |
| App uninstalled | Merchant removes the app | After H4: `shopSettings` + `session` rows deleted. Before H4: data retained indefinitely |
| GDPR redaction request | Shopify sends `customers/redact` / `shop/redact` | After H5: handled. Before H5: unhandled, compliance gap |

---

## Implementation Tasks

### Phase 1: Critical — clear before promoting the listing

- [ ] **1.1** `[multibuzz]` Discovery: does mbuzz already issue a publishable, write-scoped key? If not, design one. It must write only to `/api/v1/sessions`, `/events`, `/conversions`, `/identify` and be rejected on read and admin endpoints.
- [ ] **1.2** `[multibuzz]` Implement the publishable key type and endpoint authorization. Multi-tenancy: the key resolves to exactly one account, same as the existing secret key.
- [ ] **1.3** `[multibuzz]` Confirm `/dashboard/api-keys` and `/dashboard/settings` controllers declare `skip_marketing_analytics` (they render keys). See guide § mbuzz-Specific Conventions.
- [ ] **1.4** `[mbuzz-shopify]` Replace `sk_` usage with the publishable key in `tracking.liquid`, `mbuzz-shopify.js`, `mbuzz-pixel/src/index.js`. Update the `app._index.tsx` validation to expect the publishable prefix.
- [ ] **1.5** `[process]` Submit the app for Shopify Protected Customer Data approval (C2). Until granted, the manual webhook flow remains; document it honestly in the settings page rather than claiming zero setup.
- [ ] **1.6** Write tests (see Testing Strategy).

### Phase 2: High — review-blocking and correctness

- [ ] **2.1** `[mbuzz-shopify]` Discovery (H3): on a live dev-store checkout, confirm whether the Web Pixel can read `_mbuzz_vid`. If it cannot, switch to the passing mechanism the v0.7.0 commit intended and reconcile cookie vs. localStorage.
- [ ] **2.2** `[mbuzz-shopify]` Implement `APP_UNINSTALLED` cleanup in `webhooks.tsx` — delete `shopSettings` and `session` rows for the shop.
- [ ] **2.3** `[mbuzz-shopify]` Discovery (H5): confirm whether the mandatory GDPR webhooks are configured in the Partner Dashboard. If not, implement `customers/data_request`, `customers/redact`, `shop/redact`.
- [ ] **2.4** `[mbuzz-shopify]` Delete `shopify.app.mbuzz.toml`, or fix its placeholder URLs to match `shopify.app.toml`.
- [ ] **2.5** Write tests.

### Phase 3: Medium / Low — robustness and consistency

- [ ] **3.1** `[mbuzz-shopify]` Replace the `window.fetch` monkey-patch (M7) with the Web Pixel `product_added_to_cart` event. The pixel currently subscribes to checkout events only.
- [ ] **3.2** `[mbuzz-shopify]` Remove the `write_script_tags` scope (M8) after confirming nothing uses it.
- [ ] **3.3** `[mbuzz-shopify]` Reconsider the `auto_page_view` default (M9).
- [ ] **3.4** `[mbuzz-shopify]` Resolve the double API-key entry (L10) — one entry point, one store.
- [ ] **3.5** `[multibuzz]` Update `_install_shopify.html.erb`, `_platforms_shopify.html.erb`, and the `config/sdk_registry.yml` Shopify entry to describe the App Store app, not the manual flow (L11). Follow guide § Integration / SDK Lifecycle Checklist — On Modify.
- [ ] **3.6** `[mbuzz-shopify]` Refresh `README.md` (Kamal not Fly.io, document the pixel). Document the express-checkout limitation (L12).
- [ ] **3.7** Write tests.

---

## Testing Strategy

### Unit / Integration Tests

| Test | Repo | File | Verifies |
|------|------|------|----------|
| Publishable key writes events | multibuzz | `test/controllers/api/v1/events_controller_test.rb` | `pk_` key creates an event, scoped to the right account |
| Publishable key rejected on read | multibuzz | `test/controllers/api/v1/*_test.rb` | `pk_` key returns 401/403 on read and admin endpoints |
| Webhook matches note_attributes | multibuzz | `test/controllers/webhooks/shopify_controller_test.rb` | `_mbuzz_visitor_id` from `note_attributes` produces an attributed conversion |
| App uninstall cleanup | mbuzz-shopify | app test suite | `APP_UNINSTALLED` deletes `shopSettings` + `session` |
| GDPR webhook handlers | mbuzz-shopify | app test suite | `customers/redact` / `shop/redact` respond correctly |

### Manual QA (dev store)

1. Install the app on a Shopify development store.
2. Enter the publishable key; enable the theme extension.
3. View storefront page source — confirm only a `pk_` key is present, never `sk_`.
4. Browse with UTM params, add to cart, complete a standard checkout.
5. Confirm the conversion appears in the mbuzz dashboard with full attribution.
6. Repeat checkout via Shop Pay express — confirm the documented non-attribution behavior.
7. Uninstall the app — confirm `shopSettings` and `session` rows are gone.

---

## Definition of Done

- [ ] All Phase 1 tasks complete; no `sk_` key reachable from storefront page source
- [ ] Phase 2 and 3 tasks complete or explicitly deferred with a reason
- [ ] Tests pass in both repos (unit + integration)
- [ ] Manual QA on a dev store, including the express-checkout and uninstall paths
- [ ] No regressions in `Webhooks::ShopifyController` or `Shopify::WebhookHandler`
- [ ] `lib/docs/PRODUCT.md` reviewed — Shopify App Store install is a new user-facing capability
- [ ] This spec updated with final decisions, then moved to `lib/specs/old/`

---

## Out of Scope

- The Protected Customer Data approval submission itself (C2) — an ops/legal process, tracked separately. This spec only notes the dependency.
- Built-for-Shopify certification — a later goal once the app is hardened.
- App Store listing copy, screenshots, and demo video — marketing work, separate from this engineering spec.
- Pricing or plan changes for Shopify-sourced accounts.
- Re-architecting the cart-attribute attribution mechanism. It is correct; only the express-checkout gap is documented, not solved here.
