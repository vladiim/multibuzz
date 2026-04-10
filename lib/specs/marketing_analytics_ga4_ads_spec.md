# Marketing Analytics: GA4 + Google Ads + Meta Ads via GTM Specification

**Date:** 2026-04-10
**Priority:** P1
**Status:** Draft
**Branch:** `feature/marketing-analytics-gtm`

---

## Summary

mbuzz currently dogfoods itself for analytics on its own marketing site, firing a `page_view` event from `ApplicationController#track_page_view` on every successful GET. mbuzz is built for multi-touch attribution, not session/engagement analytics — there is no dashboard for bounce rate, scroll depth, time on page, or path exploration, and using the attribution event store as a behavioural analytics tool inflates event counts and obscures the data we actually care about. This spec migrates marketing-site behavioural analytics to **GA4** while keeping mbuzz as the source of truth for **multi-touch attribution** (sessions, channel resolution, conversions, identity). It also adds **Google Ads** and **Meta Pixel** for the platform-side optimisation/audience signals those ad networks require even when attribution is measured elsewhere. All three are loaded through a single **client-side Google Tag Manager (GTM) web container**, gated by **Google Consent Mode v2** and a first-party cookie banner. The legal surface (privacy, cookie, terms) is rewritten to reflect the new processors, cookies, and lawful bases.

---

## Current State

### What Exists

| Surface | File | Behaviour |
|---|---|---|
| mbuzz Ruby SDK initializer | `config/initializers/mbuzz.rb` | `Mbuzz.init(api_key:, debug:)` — boots middleware |
| Page-view dogfooding | `app/controllers/application_controller.rb:8,59-66` | `after_action :track_page_view` calls `Mbuzz.event("page_view", path: request.path)` on every successful, non-XHR GET |
| Signup conversion | `app/controllers/signup_controller.rb:35-36` | `Mbuzz.identify(...)` + `Mbuzz.conversion("signup", is_acquisition: true, ...)` |
| Login event | `app/controllers/sessions_controller.rb:38-39` | `Mbuzz.identify(...)` + `Mbuzz.event("login")` |
| `<head>` | `app/views/layouts/_head.html.erb` | SEO meta + OG tags + favicons + asset tags. **No GTM, GA4, gtag, fbq, or dataLayer.** |
| Privacy policy | `app/views/pages/privacy.html.erb` | States: "no tracking cookies, no advertising cookies, no third-party cookies"; processors listed are Stripe, Postmark, DigitalOcean only; "We use mbuzz to track analytics on our own website. We practice what we preach — privacy-respecting, server-side tracking with no third-party cookies." |
| Cookie policy | `app/views/pages/cookies.html.erb` | TL;DR: "We use only essential cookies", "No tracking cookies, no advertising cookies, no third-party cookies", "Our analytics are server-side" |
| Terms of service | `app/views/pages/terms.html.erb` | Last updated 2025-11-29; references the privacy policy |

### Data Flow (Current)

```
Browser GET /
  → Rails ApplicationController
    → after_action :track_page_view
      → Mbuzz.event("page_view", path: …)   [server-side HTTP to mbuzz API]
    → Mbuzz Ruby middleware (auto)
      → POST /api/v1/sessions                [server-side, sets _mbuzz_vid]
  → HTML response
    → No client-side analytics, no pixels, no dataLayer
```

### Problems With Current State

1. **Wrong tool for the job.** mbuzz models Visitors → Sessions → Events → Conversions for attribution. It does not compute engagement metrics (bounce, scroll, dwell, exit pages, demographics, search-console linkage, audience overlap). Stakeholders asking "how is the marketing site performing?" get nothing useful.
2. **Event-volume pollution.** Every marketing pageview is an attribution event consuming plan budget on mbuzz's own account, and dilutes the conversion-relevant events on the dashboard the team actually uses.
3. **No ad-platform optimisation signal.** Google Ads and Meta cannot optimise bidding or build remarketing/lookalike audiences from server-side mbuzz data. They need first-party pixel hits with their own click IDs (`gclid`, `fbclid`, `wbraid`, `gbraid`) to attribute their own platform conversions and feed Smart Bidding / Advantage+. Even with mbuzz as the MTA truth, the platforms still need their pixels for **bid optimisation** and **audience targeting**, which are upstream of attribution.
4. **Legal copy will lie the moment a pixel lands.** Privacy and cookie pages currently make absolute claims about no third parties, no tracking cookies, no advertising cookies. Adding GA4/Ads/Meta without rewriting these is a compliance liability and a brand-voice problem.

---

## Proposed Solution

Add a single **client-side GTM web container** to the marketing layout. GTM loads three tags: **GA4 configuration**, **Google Ads conversion tracking + remarketing**, and **Meta Pixel**. All three are gated by **Google Consent Mode v2** signals, which default to `denied` until the user accepts via a first-party cookie banner. mbuzz keeps doing what it is designed for — server-side session resolution, channel attribution, conversion tracking — but the explicit `page_view` dogfood event is removed.

This is a **client-side GTM** decision, not server-side GTM. Server-side GTM is the right architecture for our **product** (covered by `lib/specs/old/sgtm_integration_spec.md`), but for our own marketing site the question is "how do we ship pixels to three ad/analytics vendors with consent and minimal code?" — and the entire industry-standard answer to that is a client-side GTM container. Reasons:

| Option | Why not |
|---|---|
| Hand-roll GA4 + Ads + Meta `<script>` tags in `_head.html.erb` | Three vendor SDKs in HTML, no central consent gating, every change is a deploy, team can't iterate without engineering. |
| Server-side GTM only | sGTM still needs a client-side dataLayer source. Solving consent and tag orchestration server-side adds infrastructure for no marketing-site benefit. Reserve sGTM for the product integration. |
| Segment / RudderStack | Another processor, another vendor in the privacy policy, monthly cost, and none of the things we need that GTM doesn't do for free. |
| GTM web container (chosen) | Single snippet, tag changes happen in GTM UI without deploys, native Consent Mode v2 support, free, every marketer already knows it. |

### Data Flow (Proposed)

```
Browser GET /
  → Rails ApplicationController
    → Mbuzz Ruby middleware (auto)
      → POST /api/v1/sessions          [server-side session/visitor — UNCHANGED]
    → ❌ track_page_view REMOVED
  → HTML response with:
    → Consent Mode v2 default: all denied
    → GTM container snippet (head + body)
    → Cookie banner (first-party Stimulus controller)

Browser:
  → Cookie banner renders
  → User clicks Accept / Reject / Customise
    → consent state written to first-party cookie `mbuzz_consent`
    → gtag('consent', 'update', { … })
  → GTM fires tags whose triggers + consent gating are satisfied:
    ├─ GA4 config tag       → google-analytics.com (analytics_storage)
    ├─ Google Ads remarketing → googleadservices.com (ad_storage, ad_user_data)
    ├─ Google Ads conversion → googleadservices.com (ad_storage)
    └─ Meta Pixel            → connect.facebook.net (ad_storage)

User signs up:
  → SignupController#create
    → Mbuzz.identify + Mbuzz.conversion("signup", ...)   [UNCHANGED]
    → Renders success page that pushes to dataLayer:
        dataLayer.push({ event: 'signup_complete', user_id_hashed: <SHA256> })
      → GTM fires GA4 'signup' event, Google Ads conversion, Meta Pixel CompleteRegistration
```

### Key Decisions

| Decision | Choice | Why |
|---|---|---|
| Tag manager architecture | Client-side GTM web container | Industry default for marketing-site pixels, free, consent-mode-native, marketer-friendly. |
| Number of GTM containers | One (`GTM-XXXXXXX` for mbuzz.co) | One container per property is GTM convention. Subdomains stay in the same container. |
| Where the snippet lives | `app/views/layouts/_head.html.erb` only (`<script>` block) | The GTM `<noscript>` iframe fallback is **omitted**. It only fires image pixels, GA4/Meta/Ads need JS, and no-JS visitors can't use the site or sign up anyway. |
| Which layouts get the snippet | **Every layout, public and authenticated** | Owner wants product-side journeys instrumented in GA4/Ads/Meta too. One snippet, one container, one consent decision per visitor across the whole site. |
| Consent default — EEA/UK/CH/CA | All non-essential **denied** until user accepts | Required by GDPR/UK GDPR/Swiss FADP and California CPRA "right to opt out of sharing for cross-context behavioural advertising". |
| Consent default — rest of world | All non-essential **granted** (no banner shown) | No legal requirement to gate; banner friction would tank conversion rates everywhere else for no compliance benefit. |
| Geo detection | Server-rendered, in priority order: (1) `CF-IPCountry` header if present, (2) MaxMind GeoLite2 via `geocoder` gem, (3) fail-open to "show banner" | Server-side decision means no flash of banner for non-EEA visitors. Fail-open errs on the side of more consent prompts when geo is unknown. |
| Consent UI | Roll-our-own popover via a new Stimulus controller (`consent_banner_controller.js`) + a `consent_logs` DB table for proof-of-consent | Cheaper than Cookiebot/Termly, controllable design, no extra processor. The two things vendors do that we don't get for free (auto-cookie-scan, IAB TCF) we don't need at our scale. We replace their proof-of-consent storage by writing our own consent records (timestamp, IP-hash, country, choices). |
| Why not Cookiebot/Termly | Skipped | ~$10–$50/mo, another processor disclosed in our privacy policy, vendor script that loads before our content, fights our brand. The auto-scan and IAB TCF features are not worth those costs for one marketing site with three pixels. |
| Loading strategy | **Async, deferred to `requestIdleCallback` with a setTimeout fallback** | GTM's stock snippet is already `async`, but it still blocks main thread on parse. We defer the entire snippet injection until the browser is idle (or 2s, whichever first). LCP/INP unaffected. |
| IAB TCF v2.2 | **Not in v1** | Required only if we sell Meta Audience Network or Google AdMob inventory. We don't. Document the limitation. Revisit if the legal team flags an EU-specific need. |
| GA4 measurement ID | Stored in Rails credentials (`ga4.measurement_id`) and exposed via a helper, not hardcoded in the GTM snippet | The GTM container ID is the only client-side ID needed; vendor IDs (GA4 measurement ID, Google Ads conversion ID, Meta Pixel ID) live inside GTM, not in our codebase. |
| GTM container ID storage | Rails credentials (`gtm.container_id`), rendered into the snippet via a layout helper | Allows env-specific containers (dev/staging/prod). Never hardcoded. |
| Page view tracking via mbuzz | **Removed** (`after_action :track_page_view` deleted) | This is the whole point of the migration. mbuzz keeps creating sessions automatically via the SDK middleware; only the dogfood event is dropped. |
| mbuzz signup/login conversions | **Kept as-is** | These are MTA conversions and identity links, not behavioural pageviews. Removing them would break attribution. |
| Conversion duplication to ad platforms | dataLayer push from server-rendered success pages (signup, contact submitted, trial activated) | Simpler than wiring client-side hooks into Turbo navigations. The success page is rendered exactly once per conversion. |
| Hashing PII before sending to GA4/Ads/Meta (Enhanced Conversions) | SHA-256 in JavaScript before pushing to dataLayer | Required by Google's Enhanced Conversions and Meta's Advanced Matching. Never push raw email/phone. |
| Cookie banner copy | Plain English, mbuzz brand voice, lists exact cookies with purpose and provider | Matches the existing Privacy/Cookie page tone. |
| "We use mbuzz on our own website" claim | **Rewritten** to "We use mbuzz for multi-touch attribution and Google Analytics 4 for engagement analytics on our own website" | The current claim becomes false. Honesty matters more than the marketing line. |

---

## Tag Inventory

These are the tags GTM will host. The list is what we configure in the GTM UI; nothing in the codebase references vendor-specific IDs except the GTM container ID.

| Tag | Vendor | Purpose | Triggers | Consent gate |
|---|---|---|---|---|
| GA4 Configuration | Google Analytics 4 | Pageview, scroll, outbound click, file download (auto events) | All Pages | `analytics_storage` |
| GA4 Event — `signup` | GA4 | Signup conversion to GA4 | Custom event `signup_complete` | `analytics_storage` |
| GA4 Event — `lead` | GA4 | Contact form / demo request | Custom event `lead_submitted` | `analytics_storage` |
| Google Ads Remarketing | Google Ads | Audience building for Smart Bidding / RLSA | All Pages | `ad_storage`, `ad_user_data`, `ad_personalization` |
| Google Ads Conversion — Signup | Google Ads | Bid optimisation signal for signup | `signup_complete` | `ad_storage`, `ad_user_data` |
| Google Ads Conversion — Lead | Google Ads | Bid optimisation for lead form | `lead_submitted` | `ad_storage`, `ad_user_data` |
| Meta Pixel — PageView | Meta | Audience building, Advantage+ optimisation | All Pages | `ad_storage` |
| Meta Pixel — CompleteRegistration | Meta | Conversion event for Meta Ads | `signup_complete` | `ad_storage` |
| Meta Pixel — Lead | Meta | Lead conversion event | `lead_submitted` | `ad_storage` |

**Out of GTM, into the codebase:** only the GTM container snippet, the dataLayer push helper, the consent banner, and the consent log endpoint. Nothing else.

---

## Sensitive Route Exclusion

GTM must **never** load on routes that render secrets, credentials, raw PII, or visitor identifiers in URLs or page content. URL paths reach GA4 / Ads / Meta as `page_location` regardless of consent state, so a leaked API key in a URL is a leaked API key in three vendor systems.

### Two-layer defence

**Layer 1 — explicit class-level opt-out** (the rule). Controllers handling sensitive content declare `skip_marketing_analytics`. This is the load‑bearing mechanism — every sensitive controller must opt out explicitly.

```ruby
class Accounts::ApiKeysController < Accounts::BaseController
  skip_marketing_analytics
end
```

Implemented in `ApplicationController`:

```ruby
class_attribute :marketing_analytics_skipped, default: false

def self.skip_marketing_analytics
  self.marketing_analytics_skipped = true
end

helper_method :marketing_analytics_enabled?

def marketing_analytics_enabled?
  return false if self.class.marketing_analytics_skipped
  return false if SENSITIVE_PATH_PATTERNS.any? { |re| re.match?(request.path) }
  true
end
```

**Layer 2 — path-pattern deny-list** (the safety net). A frozen array of regexes catches anything the explicit opt-out missed and anything where a sub-route of a non-sensitive controller happens to expose IDs:

```ruby
SENSITIVE_PATH_PATTERNS = [
  %r{\A/admin(/|\z)},
  %r{\A/accounts/[^/]+/api_keys},
  %r{\A/accounts/[^/]+/billing},
  %r{\A/accounts/[^/]+/integrations},
  %r{\A/accounts/[^/]+/team},
  %r{\A/onboarding/install},
  %r{\A/dashboard/identities},
  %r{\A/dashboard/conversion_detail},
  %r{/edit\z},
  %r{sk_(live|test)_},   # any URL containing an API key
  %r{(vis|sess|evt|user)_[a-z0-9]{8,}}  # any URL containing a prefixed ID
].freeze
```

The path-pattern check runs on every request. The regex list is short, so cost is negligible.

### Helper rendering rule

`_head.html.erb` and the layouts gate **both** the GTM head loader and the consent banner partial on `marketing_analytics_enabled?`. If a controller opts out, neither renders — the page is GTM-free.

```erb
<% if gtm_enabled? && marketing_analytics_enabled? %>
  <%= consent_default_script %>
  <%= gtm_deferred_loader %>
<% end %>
```

### Controllers that must declare `skip_marketing_analytics`

| Controller | Why |
|---|---|
| `Accounts::ApiKeysController` | Renders raw API keys |
| `Accounts::BillingController` | Card last-4, invoice details, billing email |
| `Accounts::IntegrationsController` | OAuth tokens, webhook secrets |
| `Accounts::TeamController` / `Accounts::Team::*` | User emails |
| `Admin::BaseController` (covers all `Admin::*`) | Cross-tenant data, customer emails, admin tooling |
| `OnboardingController` | Install snippets contain API keys |
| `Dashboard::IdentitiesController` | Visitor PII, identity strings |
| `Dashboard::ConversionDetailController` | Conversion-level data, often with user identifiers |
| `Dashboard::ExportsController` | CSV download URLs may reveal data shape |
| `Api::Internal::ConsentController` (new) | Doesn't render HTML, but belt-and-braces |
| `Webhooks::*` | Webhook configuration UIs |
| `Invitations::*` | Invite tokens in URLs |
| `Oauth::*` | OAuth flows |

The list lives in code (the `skip_marketing_analytics` calls), not in config. Adding a new sensitive controller is a one-line code change discoverable via grep.

### Test that this stays correct

A controller test sweeps every route in `Rails.application.routes.routes`, makes a request to a representative path for each, and asserts that any controller in the sensitive list returns HTML **without** the GTM container ID anywhere in the body. This is the regression net — if someone adds a new admin controller and forgets `skip_marketing_analytics`, the test fails.

```ruby
test "sensitive controllers never render GTM" do
  SENSITIVE_CONTROLLERS.each do |controller_class|
    sample_path = sample_path_for(controller_class)
    get sample_path
    refute_match(/GTM-[A-Z0-9]+/, response.body,
      "#{controller_class} leaked GTM snippet at #{sample_path}")
  end
end
```

Plus a path-pattern test: hand-crafted URLs containing `sk_live_xxx`, `vis_abc123`, etc. assert the pattern deny-list catches them.

---

## Deferred GTM Loading (Stimulus-only)

**No inline JavaScript anywhere.** All client-side behaviour lives in Stimulus controllers. Three controllers cover the entire feature: `gtm-loader` (boots dataLayer + sets consent defaults + schedules deferred GTM load), `consent-banner` (banner UI + consent updates), `gtm-event` (server-rendered dataLayer pushes for conversions).

GTM's stock snippet is `async`, but the script still parses + executes during initial page load and pulls in vendor SDKs that block the main thread. The `gtm-loader` controller defers the actual `gtm.js` injection until `requestIdleCallback` (or 2s `setTimeout` fallback).

### `gtm-loader` controller

Renders from a partial `app/views/shared/_gtm_loader.html.erb` mounted near the top of `<body>` in every layout that opts in:

```erb
<% if gtm_enabled? && marketing_analytics_enabled? %>
  <div data-controller="gtm-loader"
       data-gtm-loader-container-id-value="<%= gtm_container_id %>"
       data-gtm-loader-consent-default-value="<%= consent_default_state %>"
       hidden></div>
<% end %>
```

`consent_default_state` returns the string `"denied"` if `requires_consent_banner?(request)` is true, else `"granted"`. The controller reads it via Stimulus values, sets `gtag('consent', 'default', …)` accordingly, then schedules the GTM script injection.

```javascript
// app/javascript/controllers/gtm_loader_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    containerId: String,
    consentDefault: String  // "denied" | "granted"
  }

  connect() {
    this.initDataLayer()
    this.setConsentDefaults()
    this.scheduleGtmLoad()
  }

  initDataLayer() {
    window.dataLayer = window.dataLayer || []
    window.gtag = window.gtag || function () { window.dataLayer.push(arguments) }
  }

  setConsentDefaults() {
    const denied = this.consentDefaultValue === "denied"
    const value = denied ? "denied" : "granted"
    window.gtag("consent", "default", {
      ad_storage: value,
      ad_user_data: value,
      ad_personalization: value,
      analytics_storage: value,
      functionality_storage: "granted",
      security_storage: "granted",
      wait_for_update: 500
    })
  }

  scheduleGtmLoad() {
    const load = () => {
      const s = document.createElement("script")
      s.async = true
      s.src = `https://www.googletagmanager.com/gtm.js?id=${this.containerIdValue}`
      document.head.appendChild(s)
    }
    if ("requestIdleCallback" in window) {
      requestIdleCallback(load, { timeout: 2000 })
    } else {
      setTimeout(load, 2000)
    }
  }
}
```

### `gtm-event` controller (for server-rendered conversion pushes)

Replaces inline `<script>dataLayer.push(...)</script>` blocks on signup/lead success pages. The view renders a single empty `<div>` with data attributes; the controller reads them on `connect()` and pushes to `dataLayer`.

```erb
<%# app/views/signup/_success.html.erb (or wherever post-signup renders) %>
<div data-controller="gtm-event"
     data-gtm-event-name-value="signup_complete"
     data-gtm-event-properties-value='<%= { user_id_hashed: Digest::SHA256.hexdigest(current_user.email.downcase.strip) }.to_json %>'></div>
```

```javascript
// app/javascript/controllers/gtm_event_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    name: String,
    properties: { type: Object, default: {} }
  }

  connect() {
    window.dataLayer = window.dataLayer || []
    window.dataLayer.push({ event: this.nameValue, ...this.propertiesValue })
  }
}
```

### Ordering guarantee

Stimulus controllers connect after DOM parse, before window-load. The order is:

```
1. HTML parsed, layouts mount _gtm_loader partial in body
2. importmap loads Stimulus, registers controllers
3. gtm-loader#connect()
   ├─ initDataLayer()           ← window.dataLayer + window.gtag exist
   ├─ setConsentDefaults()      ← gtag('consent','default',…) recorded
   └─ scheduleGtmLoad()         ← requestIdleCallback queued
4. consent-banner#connect()     ← reads cookie, may call gtag('consent','update',…)
5. gtm-event#connect() (if present) ← pushes 'signup_complete' / 'lead_submitted'
6. Browser idle → GTM script loads → GTM reads queued dataLayer + consent state
```

Multiple `gtm-*` controllers initialise `dataLayer` defensively (`= dataLayer || []`) so connect order doesn't matter. GTM itself reads all queued pushes when it boots.

### What's NOT inline

- No `<script>` tags in `_head.html.erb`
- No `<script>` tags in any layout
- No `<script>` tags in conversion success views
- No `<noscript>` fallback (already removed)

### What stays in `_head.html.erb`

Nothing. The head partial gains zero new lines for this feature. The entire mount happens in `<body>` via partials.

### Verification

Lighthouse on `/`, `/pricing`, and the signup success page — LCP/INP within 5% of the pre-change baseline. If not, raise the idle timeout or move the GTM load behind a user-interaction trigger (still inside the controller).

---

## Consent Mode v2 Defaults

GTM snippet runs `gtag('consent', 'default', …)` **before** the GTM `<script>` loads. Defaults vary by visitor country, computed server-side.

### EEA / UK / Switzerland / California

| Consent type | Default | Purpose |
|---|---|---|
| `ad_storage` | `denied` | Ad cookies (Google Ads, Meta) |
| `ad_user_data` | `denied` | Sending user data to Google for ads (CMv2) |
| `ad_personalization` | `denied` | Personalised ads (CMv2) |
| `analytics_storage` | `denied` | Analytics cookies (GA4) |
| `functionality_storage` | `granted` | Essential UI state |
| `security_storage` | `granted` | Anti-abuse |
| `wait_for_update` | `500` (ms) | Give the banner time to read the existing cookie before tags fire |

### Rest of world

All consent types default to `granted`. No banner is shown. The user can still withdraw via the Manage Preferences button on `/cookies`, which downgrades consent and persists the choice.

### Country detection

Server-side, computed in `app/helpers/consent_helper.rb#requires_consent_banner?`:

```
1. If request header `CF-IPCountry` is present → use it
2. Else if Geocoder.search(request.remote_ip).first&.country_code → use it
3. Else → fail open and treat as EEA (show banner)
```

The list of countries that trigger the banner: all 27 EU member states + GB + IS + LI + NO + CH + US-CA. (US-CA needs request region, not just country — `CF-IPCountry` returns `US`, so we additionally check `CF-Region-Code` or `request.location.region` for `CA`.) This list lives in a frozen constant in `ConsentHelper`.

---

## Cookie Banner

Roll-our-own popover, shipped as a Stimulus controller. **Not** a third-party CMP.

### Why not Cookiebot/Termly

| What they do | Do we need it? |
|---|---|
| Auto-scan the site to keep cookie inventory current | No — we have three pixels. The inventory is hand-maintainable. |
| Cryptographic proof-of-consent storage (GDPR Art. 7(1)) | Yes — we replicate this with our own `consent_logs` table (cheap). |
| IAB TCF v2.2 framework | No — we don't sell ad inventory. |
| Pre-built UI translations | Marginal — we serve English and our EEA traffic is small. Can ship en-only and add languages later. |
| Geo detection | We do this ourselves with `CF-IPCountry` / MaxMind. |
| Monthly cost / extra processor in privacy policy | Avoided. |

### Behaviour

| State | Condition | Behaviour |
|---|---|---|
| First visit, EEA/UK/CH/CA | No `mbuzz_consent` cookie, geo matches | Banner visible. All non-essential denied. GTM defers tags. |
| First visit, rest of world | No cookie, geo does not match | **No banner.** All non-essential granted by default. GTM fires normally. A `mbuzz_consent` cookie is still written so a returning user gets a stable record. |
| Accept all | User clicks Accept | Cookie `mbuzz_consent={"ad":1,"analytics":1,"v":1,"ts":<unix>}` written, `max-age=31536000`. `gtag('consent','update',…)`. Banner hides. Server logs to `consent_logs`. |
| Reject all | User clicks Reject | Cookie written with zeros. `gtag('consent','update',…)`. Banner hides. No pixels fire. Logged to `consent_logs`. |
| Customise | User clicks Customise | Modal with toggles for Analytics and Advertising (essential non-toggleable). Saving writes the cookie + log. |
| Returning visitor (consented) | Cookie present, < 12mo | Banner hidden. Stimulus reads cookie on `connect()`, calls `gtag('consent','update',…)` synchronously before deferred tags. |
| Returning visitor (expired) | Cookie > 12mo | Treated as no cookie. Banner re-shown if geo matches; otherwise re-granted. |
| Withdrawal | User visits `/cookies` and clicks "Manage preferences" | Re-opens the modal regardless of geo. Allows downgrading consent. New `consent_logs` row. |

### Proof-of-consent storage

GDPR Art. 7(1) requires the data controller to be able to **demonstrate** that consent was given. We replace Cookiebot's audit log with our own table:

```
consent_logs
  id              bigint primary key
  account_id      bigint nullable    # null for anonymous marketing visits
  visitor_id      string             # _mbuzz_vid if available
  consent_payload jsonb              # { ad: 1, analytics: 0, v: 1 }
  ip_hash         string             # SHA256 of IP, never raw
  country         string(2)          # CF-IPCountry value
  region          string(8) nullable # for US-CA detection
  user_agent      string
  banner_version  string             # bumps when copy/options change → re-prompt required
  created_at      timestamp
```

Indexed by `visitor_id` and `created_at`. Retained as long as the privacy policy retention window (matches account data — 90d after deletion).

A new endpoint `POST /api/internal/consent` accepts the choice from the Stimulus controller and writes the row. Rate-limited (existing limiter). Multi-tenant note: this is **not** scoped to a specific tenant account because consent is collected from anonymous marketing-site visitors before they sign up. It's a global table.

### Files

| File | Purpose |
|---|---|
| `app/javascript/controllers/consent_banner_controller.js` | Stimulus — read/write cookie, call `gtag('consent','update',…)`, POST to `/api/internal/consent`, toggle banner visibility |
| `app/views/shared/_consent_banner.html.erb` | Banner HTML, rendered from `application.html.erb` |
| `app/views/shared/_consent_modal.html.erb` | Customise modal HTML |
| `app/helpers/consent_helper.rb` | `gtm_container_id`, `gtm_enabled?`, `requires_consent_banner?(request)`, `visitor_country(request)`, `consent_default_script` |
| `app/controllers/api/internal/consent_controller.rb` | Receives consent choices, writes `consent_logs` row |
| `app/models/consent_log.rb` | ActiveRecord model |
| `db/migrate/<ts>_create_consent_logs.rb` | Migration |

### Why a Stimulus controller, not a new framework

The mbuzz frontend rules in CLAUDE.md / GUIDE.md say: prefer Turbo, then existing Stimulus controllers, then extend existing, then new controller as a last resort. A consent banner is genuinely interactive (toggles, modal, state persistence to cookie + window.gtag) and there is no existing controller doing anything close. New controller is justified.

---

## Legal Surface Updates

Privacy, cookie, and terms pages all need rewrites. The current copy is built around a "no third parties, no tracking cookies, server-side everything" promise that becomes false the moment GA4 ships.

### Privacy Policy (`app/views/pages/privacy.html.erb`)

| Section | Current | After |
|---|---|---|
| TL;DR — "Your tracking data belongs to you. We never sell it" | Keep (still true for **customer** data) | Keep, but add: "On our own website (mbuzz.co) we use Google Analytics 4, Google Ads, and Meta to measure marketing — separate from the customer data we process for you" |
| "Who we share data with" — Stripe, Postmark, DigitalOcean | Add subsection "Third parties on mbuzz.co (our marketing site only)" listing Google (Analytics + Ads) and Meta (Pixel) with link to their privacy policies and links to opt out (Google Ads Settings, Meta Ad Preferences) |
| "Cookies" subsection | "We use minimal cookies… We don't use tracking cookies or third-party advertising cookies." | Rewrite: "On the mbuzz dashboard (logged-in app) we use only essential first-party cookies. On mbuzz.co (our marketing site) we use Google Analytics, Google Ads, and Meta cookies, which load only after you give consent." |
| "Analytics on this website" | "We use mbuzz to track analytics on our own website. We practice what we preach — privacy-respecting, server-side tracking with no third-party cookies." | Rewrite: "We use mbuzz for multi-touch attribution on our own website (server-side, first-party, the same product we sell). For engagement analytics — bounce rate, page paths, content performance — we use Google Analytics 4, because mbuzz is built for attribution, not behavioural analytics. For ad campaign optimisation we use Google Ads and Meta Pixel. All of these are gated by your consent and load only if you accept on the cookie banner." |
| GDPR section | Add: "Lawful basis for ad/analytics cookies on mbuzz.co is **consent** (Art. 6(1)(a)). You can withdraw at any time via the cookie banner or the /cookies page." |
| CCPA section | Keep "we do not sell personal information". Add: "We share limited identifiers with Google and Meta for measurement and advertising on mbuzz.co. Under California law, sharing for cross-context behavioural advertising is treated like a sale — you may opt out via the cookie banner." |
| Last updated | Bump to deploy date |

### Cookie Policy (`app/views/pages/cookies.html.erb`)

| Section | Current | After |
|---|---|---|
| TL;DR | "We use only essential cookies", "No tracking cookies, no advertising cookies, no third-party cookies", "Our analytics are server-side" | Rewrite all four bullets. New TL;DR: essential cookies always on; analytics + ad cookies only after consent; full list below; manage anytime. |
| Cookie list | (presumed minimal — verify) | Add a table: cookie name, provider, purpose, duration, type (essential/analytics/ad). Include `_ga`, `_ga_*`, `_gid`, `_gcl_au`, `_fbp`, `fr`, `IDE`, `mbuzz_consent`, `_mbuzz_vid`. |
| "Manage preferences" | (does not exist) | Add a button that calls `consent_banner_controller#openModal` |

### Terms of Service (`app/views/pages/terms.html.erb`)

| Section | Change |
|---|---|
| Top reference to privacy policy | Verify the link still resolves; no rewording needed. |
| "Third-party services" or equivalent (verify) | Add a one-line note that the marketing site uses GA4, Google Ads, and Meta, with cross-link to the privacy policy. |
| Last updated | Bump |

### Where we **do not** change anything

- Customer-data processing terms (DPA boilerplate). The product still does not share customer data with Google or Meta. Only the marketing site does, and only for visitors of mbuzz.co.
- The `_mbuzz_vid` server-side cookie. It remains essential and first-party.

---

## Key Files

| File | Purpose | Changes |
|---|---|---|
| `app/views/layouts/_head.html.erb` | `<head>` partial | **No changes.** Zero inline JS for this feature. |
| `app/views/shared/_gtm_loader.html.erb` | New partial | Mounts the `gtm-loader` Stimulus controller via a hidden `<div>` with data attributes |
| `app/views/layouts/application.html.erb` | App layout | Render `shared/_gtm_loader` near top of `<body>`, render `shared/_consent_banner` near bottom. Both gated on `marketing_analytics_enabled?` (the partials self-check geo). |
| `app/views/layouts/landing_page.html.erb` | Landing page layout | Same |
| `app/views/layouts/article.html.erb` | Articles layout | Same |
| `app/views/layouts/score.html.erb` | Score landing layout | Same |
| `app/views/layouts/docs.html.erb` | Docs layout | Same |
| Authenticated app layout(s) | Dashboard layout | Same — owner wants product journeys instrumented in GA4/Ads/Meta too. |
| `app/javascript/controllers/gtm_loader_controller.js` | New | Boots dataLayer, sets consent defaults, schedules deferred GTM load |
| `app/javascript/controllers/gtm_event_controller.js` | New | Pushes a server-rendered event to dataLayer on connect — replaces inline `<script>dataLayer.push(...)</script>` on conversion success pages |
| `app/views/shared/_consent_banner.html.erb` | New | First-party banner markup |
| `app/views/shared/_consent_modal.html.erb` | New | Preferences modal |
| `app/javascript/controllers/consent_banner_controller.js` | New Stimulus controller | Read/write `mbuzz_consent` cookie, call `gtag('consent','update',…)`, toggle banner visibility |
| `app/helpers/consent_helper.rb` | New | `gtm_container_id`, `gtm_head_snippet`, `gtm_body_snippet`, `consent_default_script` |
| `config/credentials.yml.enc` | Rails credentials | Add `gtm.container_id` per env (placeholder — see Rails credentials). **Do not commit IDs to git.** |
| `app/controllers/application_controller.rb` | App controller | Remove `after_action :track_page_view`, `track_page_view`, `should_track_page_view?` |
| `app/views/signup/_success.html.erb` (or wherever post-signup renders) | Signup success | Add `dataLayer.push({ event: 'signup_complete', user_id_hashed: '<%= sha256(current_user.email) %>' })` |
| `app/views/pages/privacy.html.erb` | Privacy page | Rewrites per "Legal Surface Updates" |
| `app/views/pages/cookies.html.erb` | Cookie page | Rewrites + cookie table + manage button |
| `app/views/pages/terms.html.erb` | Terms page | Minor reference + last-updated |

---

## All States

| State | Condition | Expected Behaviour |
|---|---|---|
| First pageview, EEA/UK/CH/CA, no cookie | Geo matches, no `mbuzz_consent` | Consent defaults all denied; banner shown; GTM loaded async on idle; tags wait for consent; mbuzz session created server-side |
| First pageview, rest of world, no cookie | Geo does not match | Consent defaults all granted; **no banner**; GTM fires normally on idle; `mbuzz_consent` written with all-granted; `consent_logs` row written by server (banner-version `auto-grant`) |
| Accept all (EEA/CA) | User clicks Accept | Cookie set granted; `gtag('consent','update',…)`; POST `/api/internal/consent`; banner hides; deferred tags fire |
| Reject all (EEA/CA) | User clicks Reject | Cookie set zeros; consent stays denied; POST `/api/internal/consent`; banner hides; GA4 may still send modeled hits; Ads/Meta silent |
| Customise — analytics only | Toggle analytics on, ads off | GA4 fires, Ads and Meta do not |
| Returning visitor (consented) | Cookie present, < 12mo | Banner hidden; Stimulus reads cookie on `connect()` and updates consent before deferred tags |
| Returning visitor (expired) | Cookie > 12mo | Treated as new visitor — banner shown if geo matches, otherwise auto-granted |
| Signup conversion (consented) | User completes signup | `Mbuzz.conversion("signup", …)` server-side **and** dataLayer `signup_complete` push client-side; GA4/Ads/Meta record conversion |
| Signup conversion (no consent) | Same, consent denied | mbuzz records the conversion; GA4 records modeled conversion (no cookies); Google Ads and Meta receive no client-side hit. **Intentional.** |
| Authenticated dashboard pageview, non-sensitive route | Logged-in user, geo non-EEA, controller not in sensitive list | GTM loaded async; pixels fire; mbuzz still tracks via SDK middleware. |
| Authenticated dashboard pageview, EEA user | Logged-in user, geo matches, non-sensitive route | If user has prior `mbuzz_consent`, that decision applies. If not, banner shows. |
| Sensitive route — explicit opt-out | Controller declares `skip_marketing_analytics` (e.g. `/accounts/abc/api_keys`) | **No GTM loader, no consent banner.** Page is GTM-free regardless of geo or consent state. |
| Sensitive route — pattern match | Path matches `SENSITIVE_PATH_PATTERNS` (e.g. URL contains `sk_live_` or a `vis_*` ID) | Same — fully suppressed. Catches sub-routes the explicit list missed. |
| Sensitive route — both layers fail | Hypothetical regression: new admin controller without `skip_marketing_analytics` and no pattern match | Sweep test in CI fails before merge. |
| LCP / page speed impact | Any page | GTM injection deferred to `requestIdleCallback` (or `setTimeout(2000)` fallback). LCP unaffected. Verify with Lighthouse before/after. |
| Bot / no-JS visit | curl, headless without JS | Nothing fires. No fallback. Acceptable — no-JS visitors can't sign up or use the dashboard either. |
| Ad blocker | uBlock blocks GTM | mbuzz still tracks server-side. GA4/Ads/Meta silently absent. Acceptable. |
| Consent withdrawal | User opens `/cookies` → Manage → toggles off | Cookie rewritten with zeros; `gtag('consent','update',…)` denied; new `consent_logs` row; existing GA/Ads/Meta cookies **not** auto-deleted (browser limitation); no new data collected. Documented. |
| Geo lookup fails | No `CF-IPCountry`, MaxMind miss | Fail open: treat as EEA, show banner. |
| Privacy page rendered | GET `/privacy` | New copy reflects GA4/Ads/Meta processors |

---

## Implementation Tasks

### Phase 1: Remove mbuzz Page-View Dogfooding

- [ ] **1.1** Delete `after_action :track_page_view`, `track_page_view`, and `should_track_page_view?` from `app/controllers/application_controller.rb`.
- [ ] **1.2** Verify mbuzz Ruby SDK middleware still creates sessions automatically (it does — see `lib/docs/sdk/api_contract.md`). No change to `Mbuzz.init` in `config/initializers/mbuzz.rb`.
- [ ] **1.3** Confirm `Mbuzz.identify` / `Mbuzz.event("login")` / `Mbuzz.conversion("signup", …)` calls in `sessions_controller.rb` and `signup_controller.rb` remain untouched.
- [ ] **1.4** Update controller test for `ApplicationController` to remove the `track_page_view` assertion if one exists.
- [ ] **1.5** Sanity-check the mbuzz dashboard one day after deploy: pageview event volume on the mbuzz.co account should drop sharply; sessions and conversions should be stable.

### Phase 2: GTM Container + Geo-Aware Consent Defaults + Deferred Loader

- [ ] **2.1** Create the GTM container in the team Google account. Container ID stored in Rails credentials, never in git.
- [ ] **2.2** Add `gtm.container_id` to Rails credentials per environment (dev = empty/disabled, staging = staging container, production = production container).
- [ ] **2.3** Add `geocoder` gem if not present, configure with MaxMind GeoLite2 free DB (downloaded to `db/geolite2/`, gitignored, fetched in deploy).
- [ ] **2.4** Create `app/helpers/consent_helper.rb`:
  - `gtm_container_id` — reads credentials
  - `gtm_enabled?` — true if container ID present
  - `visitor_country(request)` — `CF-IPCountry` → MaxMind → nil
  - `visitor_region(request)` — for US-CA detection
  - `requires_consent_banner?(request)` — true if country in `CONSENT_COUNTRIES` or (country == "US" and region == "CA"), or fail-open on nil
  - `consent_default_script` — renders `gtag('consent','default',…)` with denied/granted based on `requires_consent_banner?`
  - `CONSENT_COUNTRIES` — frozen array of EU27 + GB, IS, LI, NO, CH
- [ ] **2.5** Add the sensitive-route exclusion mechanism to `ApplicationController`:
  - `class_attribute :marketing_analytics_skipped, default: false`
  - `self.skip_marketing_analytics` class method that flips the flag
  - `helper_method :marketing_analytics_enabled?` that checks the class flag **and** runs the path against `SENSITIVE_PATH_PATTERNS`
  - Define `SENSITIVE_PATH_PATTERNS` as a frozen constant in `ApplicationController` (or `app/constants/sensitive_path_patterns.rb` if it grows)
- [ ] **2.6** Add `skip_marketing_analytics` to every controller in the "Controllers that must declare" table:
  - `Accounts::ApiKeysController`
  - `Accounts::BillingController`
  - `Accounts::IntegrationsController`
  - `Accounts::TeamController` (covers `Accounts::Team::*` if it inherits)
  - `Admin::BaseController` (inherited by all `Admin::*`)
  - `OnboardingController`
  - `Dashboard::IdentitiesController`
  - `Dashboard::ConversionDetailController`
  - `Dashboard::ExportsController`
  - `Webhooks::*` base controller
  - `Invitations::*`, `Oauth::*` base controllers
- [ ] **2.7** Create `app/javascript/controllers/gtm_loader_controller.js` per the spec — initialises `dataLayer`, sets consent defaults from a Stimulus value, schedules `requestIdleCallback` GTM load. Register in `app/javascript/controllers/index.js`.
- [ ] **2.8** Create `app/views/shared/_gtm_loader.html.erb` — hidden `<div data-controller="gtm-loader" …>` mount. Self-checks `gtm_enabled?` and `marketing_analytics_enabled?`; renders nothing otherwise.
- [ ] **2.9** Render `shared/_gtm_loader` near top of `<body>` and `shared/_consent_banner` near bottom of `<body>` in `application.html.erb`. Repeat for `landing_page`, `article`, `score`, `docs`, and the authenticated dashboard layout(s). **`_head.html.erb` gets zero changes for this feature.**
- [ ] **2.10** Create `app/javascript/controllers/gtm_event_controller.js` — pushes `{ event: nameValue, ...propertiesValue }` to `dataLayer` on connect. Register in controllers index. Used in Phase 4 for conversion success pages.
- [ ] **2.11** Helper tests: `requires_consent_banner?` returns true for FR, DE, GB, US+CA region; false for US (non-CA), AU, JP; true on nil (fail-open).
- [ ] **2.12** Helper tests: `marketing_analytics_enabled?` is false when `skip_marketing_analytics` is set on the class; false when path matches a `SENSITIVE_PATH_PATTERNS` regex (test each: `/admin/anything`, `/accounts/abc/api_keys`, `/foo/sk_live_abc`, `/dashboard/identities/vis_abc123`, `/onboarding/install`, any path ending `/edit`); true otherwise.
- [ ] **2.13** Sweep test: iterate `Rails.application.routes.routes`, identify routes whose controller is in the sensitive list, GET a representative path for each, assert the response body contains no `data-controller="gtm-loader"` and no `googletagmanager`. Regression net for new sensitive controllers.
- [ ] **2.14** Layout test: GET `/` with `CF-IPCountry: FR` → `gtm-loader` mount present with `consent-default-value="denied"`. GET `/` with `CF-IPCountry: AU` → mount present with `consent-default-value="granted"`. GET `/admin/accounts` (as admin) → no `gtm-loader` mount, no banner. GET `/onboarding/install` → no `gtm-loader` mount.
- [ ] **2.15** Lighthouse baseline: capture LCP/INP for `/`, `/pricing`, signup page **before** Phase 2 deploys.
- [ ] **2.16** Lighthouse post-deploy: verify LCP/INP within 5% of baseline. If regression, raise the idle timeout or move to interaction-trigger loading.
- [ ] **2.17** Configure GA4 property in the GTM container (GA4 Configuration tag, All Pages trigger, `analytics_storage` consent gate).

### Phase 3: Cookie Banner + Consent Log

- [ ] **3.1** Migration `create_consent_logs` per the schema in "Proof-of-consent storage". Indexed by `visitor_id`, `created_at`.
- [ ] **3.2** `app/models/consent_log.rb` — minimal model, validates presence of `consent_payload`, `country`, `banner_version`, `ip_hash`.
- [ ] **3.3** `app/controllers/api/internal/consent_controller.rb#create` — accepts `{ payload, banner_version }`, hashes `request.remote_ip` to SHA256, reads country/region from helper, writes row, returns 201. Rate-limited.
- [ ] **3.4** Route: `post '/api/internal/consent', to: 'api/internal/consent#create'`. Internal namespace, no API key required (anonymous endpoint).
- [ ] **3.5** Create `app/views/shared/_consent_banner.html.erb`. Tailwind, mbuzz brand voice, three buttons: Accept all, Reject all, Customise. Partial self-checks `requires_consent_banner?(request)` and renders nothing for non-EEA/CA visitors.
- [ ] **3.6** Create `app/views/shared/_consent_modal.html.erb`. Toggles: Analytics, Advertising. Essential is non-toggleable.
- [ ] **3.7** Render `shared/_consent_banner` from `application.html.erb` (and any other public + dashboard layouts) immediately before `</body>`.
- [ ] **3.8** Create `app/javascript/controllers/consent_banner_controller.js`:
  - `connect()` — reads `mbuzz_consent` cookie. If present and `< 12mo` old, calls `gtag('consent','update',…)` and hides banner. Otherwise, if banner exists in DOM, shows it.
  - Targets: `banner`, `modal`, `analyticsToggle`, `adsToggle`
  - Actions: `acceptAll`, `rejectAll`, `openModal`, `closeModal`, `savePreferences`
  - On any save: write cookie (`max-age=31536000`, `SameSite=Lax`, `Secure`, path `/`), POST to `/api/internal/consent`, call `gtag('consent','update',…)`, hide banner
  - On `connect()` for non-EEA visitors with no cookie: server-side renders no banner, but the controller still POSTs an `auto-grant` consent log row once per session (sessionStorage flag)
- [ ] **3.9** Add `data-action="click->consent-banner#openModal"` button to `app/views/pages/cookies.html.erb` for withdrawal — visible to all geos.
- [ ] **3.10** Controller tests for `Api::Internal::ConsentController` — happy path, rate-limit, IP-hash never stores raw IP.
- [ ] **3.11** Manual QA for the Stimulus controller — cookie read/write, `gtag` invocation, consent log POST.

### Phase 4: Conversion Events to GA4 / Ads / Meta

- [ ] **4.1** Locate the post-signup success render in `app/controllers/signup_controller.rb` and its view. Add a `<div data-controller="gtm-event" data-gtm-event-name-value="signup_complete" data-gtm-event-properties-value="<%= { user_id_hashed: Digest::SHA256.hexdigest(current_user.email.downcase.strip) }.to_json %>"></div>`. Must render exactly once. **No inline `<script>`.**
- [ ] **4.2** Locate the contact form success render. Add a matching `<div data-controller="gtm-event" data-gtm-event-name-value="lead_submitted"></div>`.
- [ ] **4.3** In GTM, create:
  - Custom Event trigger `signup_complete`
  - Custom Event trigger `lead_submitted`
  - GA4 Event tags wired to those triggers (events: `sign_up`, `generate_lead`)
  - Google Ads Conversion tags wired to those triggers
  - Meta Pixel CompleteRegistration / Lead tags wired to those triggers
  - Google Ads Remarketing tag on All Pages
  - Meta Pixel PageView on All Pages
- [ ] **4.4** Test in GTM Preview mode end-to-end on staging.
- [ ] **4.5** In GA4 → Admin → Events, mark `sign_up` as a key event.
- [ ] **4.6** In Google Ads, create the conversion actions and link them to the GTM tag (GTM provides the conversion ID + label).
- [ ] **4.7** In Meta Events Manager, verify Pixel events arrive and set up Aggregated Event Measurement priorities.

### Phase 5: Legal Surface Rewrites

- [ ] **5.1** Rewrite `app/views/pages/privacy.html.erb` per the "Privacy Policy" table above. Update the "Last updated" date.
- [ ] **5.2** Rewrite `app/views/pages/cookies.html.erb` per the "Cookie Policy" table above. Add the cookie inventory table. Add the Manage Preferences button.
- [ ] **5.3** Update `app/views/pages/terms.html.erb` references and last-updated date.
- [ ] **5.4** Have the founder review the rewrites before deploy (legal copy, not a tech review).
- [ ] **5.5** Optional but recommended: post a short changelog entry on the marketing site about the policy update, dated.

### Phase 6: Verification

- [ ] **6.1** GTM Preview mode: walk every public layout and confirm the container loads, the consent default is denied, and pixels do **not** fire pre-consent.
- [ ] **6.2** Click Accept all: confirm GA4 sends a pageview, Google Ads remarketing fires, Meta Pixel PageView fires.
- [ ] **6.3** Click Reject all on a fresh session: confirm no analytics/ad cookies are set, no network requests to google-analytics.com / googleadservices.com / connect.facebook.net.
- [ ] **6.4** Sign up from a clean browser with consent granted: confirm GA4 `sign_up`, Google Ads conversion, Meta CompleteRegistration all fire **and** mbuzz records the conversion.
- [ ] **6.5** Sign up from a clean browser with consent denied: confirm mbuzz still records the conversion; ad/analytics platforms either silent or modeled.
- [ ] **6.6** Browse the authenticated dashboard: confirm GTM is not loaded.
- [ ] **6.7** Verify privacy/cookie/terms render correctly and read accurately.
- [ ] **6.8** mbuzz dashboard 24h after deploy: pageview event count drops; sessions and conversions stable.

---

## Testing Strategy

### Unit / Integration Tests

| Test | File | Verifies |
|---|---|---|
| Marketing layout renders GTM snippet when container ID set | `test/views/layouts/_head_test.rb` (new) | `gtm_enabled?` true → snippet present |
| Marketing layout omits GTM when container ID blank | Same | `gtm_enabled?` false → no snippet |
| Application controller no longer fires `track_page_view` | `test/controllers/application_controller_test.rb` | No call to `Mbuzz.event("page_view", …)` on GET |
| Signup still records mbuzz conversion | `test/controllers/signup_controller_test.rb` | `Mbuzz.conversion("signup", …)` invoked |
| Login still records mbuzz event + identify | `test/controllers/sessions_controller_test.rb` | Calls present |
| Consent helper returns env-specific container ID | `test/helpers/consent_helper_test.rb` (new) | Reads from credentials |
| Cookie banner partial renders on marketing layouts | Layout test | Banner present on `/`, absent on `/dashboard` |

### Manual QA

| # | Step | Expected |
|---|---|---|
| 1 | Visit `/` in incognito | Banner visible, no GA/Ads/Meta network requests |
| 2 | Accept all | Banner hides, network requests to google-analytics.com and friends, cookies appear |
| 3 | Open `/cookies`, click Manage, toggle ads off, save | New cookie value, no further network requests to googleadservices.com / facebook.net (existing cookies persist until expiry — document this) |
| 4 | Visit again with the cookie present | Banner does not reappear |
| 5 | Sign up | mbuzz dashboard shows the conversion **and** GA4 / Google Ads / Meta show the conversion |
| 6 | Visit `/dashboard` after login | No GTM snippet in source |
| 7 | Read privacy, cookie, terms | All accurate, no contradictions |
| 8 | curl `/` | No GTM in source (deferred loader is JS-only). Acceptable. |

---

## Definition of Done

- [ ] `track_page_view` removed from `ApplicationController`
- [ ] mbuzz Ruby SDK still creates sessions and records signup/login conversions
- [ ] GTM container ID stored in Rails credentials, helper renders snippet conditionally
- [ ] GTM head loader renders on **all** layouts (public and authenticated) **except sensitive routes**
- [ ] Every controller in the sensitive list declares `skip_marketing_analytics`
- [ ] `SENSITIVE_PATH_PATTERNS` deny-list catches API-key-bearing and prefixed-ID-bearing URLs as a safety net
- [ ] Sweep test asserts no sensitive controller's response body contains the GTM container ID — runs in CI
- [ ] GTM injection deferred to `requestIdleCallback` (or 2s fallback); Lighthouse LCP/INP within 5% of pre-deploy baseline
- [ ] Consent Mode v2 defaults computed server-side from `CF-IPCountry` / MaxMind: denied for EEA/UK/CH/CA, granted elsewhere
- [ ] Roll-our-own cookie banner ships with Accept / Reject / Customise, only renders for EEA/UK/CH/CA visitors
- [ ] `consent_logs` table records every consent decision (including auto-grants) with hashed IP, country, banner version
- [ ] `mbuzz_consent` cookie read on subsequent visits to skip banner
- [ ] `/cookies` exposes a Manage Preferences button visible to all geos
- [ ] GA4, Google Ads (remarketing + signup conversion + lead conversion), Meta Pixel (PageView + CompleteRegistration + Lead) configured in GTM
- [ ] Signup and lead success pages push to `dataLayer`
- [ ] Privacy, Cookie, Terms pages rewritten and reviewed
- [ ] Manual QA checklist passed end to end
- [ ] mbuzz dashboard verifies pageview volume drop and stable sessions/conversions 24h post-deploy
- [ ] Spec updated with anything that changed during implementation

---

## Out of Scope

- **Server-side GTM (sGTM).** Covered by `lib/specs/old/sgtm_integration_spec.md` for the **product** integration. The marketing site does not need sGTM in v1; revisit only if Safari ITP / ad blockers materially degrade marketing measurement.
- **IAB TCF v2.2 / full CMP.** We do not sell ad inventory and the geo-gated consent banner satisfies our exposure. Revisit only if legal flags a specific need.
- **Google Ads Enhanced Conversions API or Meta Conversions API (CAPI).** Server-side conversion forwarding is the natural next step for measurement durability under ITP/ATT, but it adds backend work and is not required to launch ad campaigns. Future spec.
- **Removing the mbuzz Ruby SDK from the app.** mbuzz remains the MTA source of truth and continues to record sessions/conversions/identity. This spec narrows mbuzz's role on our own site, it does not eliminate it.
- **A/B testing tooling.** Out of scope.
- **Cookie auto-deletion on consent withdrawal.** Browsers do not let JS reliably clear third-party cookies set by other origins. We document the limitation.
- **Linking GA4 to Search Console / BigQuery.** Useful, separate task.
- **Migrating historical mbuzz pageview data into GA4.** Not feasible and not useful.
