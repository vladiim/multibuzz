# Server-Side Google Tag Manager (sGTM) Integration Specification

**Date:** 2026-02-09
**Priority:** P1
**Status:** Draft
**Branch:** `feature/sgtm-integration`

---

## Summary

Agencies and businesses using platforms without backend access (Webflow, Squarespace, WordPress) can't install server-side SDKs. Server-side GTM (sGTM) is the industry-standard bridge: it runs on the customer's cloud, makes server-to-server HTTP calls, and sets first-party cookies that survive ad blockers and Safari ITP. This spec adds an sGTM tag template that sends data to mbuzz's existing API — no new endpoints needed. The tag template ships to GTM's Community Template Gallery, making every sGTM setup a discovery channel.

---

## Current State

### What Exists

mbuzz has a complete server-side ingest API and five SDKs (Ruby, Node, Python, PHP, Shopify). All SDKs implement the 4-Call Model:

| Call | Endpoint | Purpose |
|------|----------|---------|
| Session | `POST /api/v1/sessions` | Create visitor + session, capture UTM/referrer/channel |
| Event | `POST /api/v1/events` | Track custom events with properties |
| Conversion | `POST /api/v1/conversions` | Track conversions, trigger attribution |
| Identify | `POST /api/v1/identify` | Link visitor to known user |

Server-side session resolution is built: device fingerprint via `SHA256(ip|user_agent)[0:32]`, 30-minute sliding window, UTM extraction, channel attribution — all server-side.

Source: `lib/docs/sdk/api_contract.md`

### What's Missing

No integration exists for sites that can't run server-side middleware. GTM is not listed in:
- `config/sdk_registry.yml` — no `sgtm` entry
- `app/views/pages/home/_sdks.html.erb` — no sGTM logo on homepage
- `app/views/onboarding/` — no sGTM install flow
- `app/views/docs/` — no sGTM documentation tab
- `lib/docs/sdk/sdk_registry.md` — no sGTM section
- `sdk_integration_tests/` — no sGTM e2e tests

### Data Flow (Current — SDK)

```
Browser request
  → SDK middleware intercepts
    → Reads/sets _mbuzz_vid cookie
    → Detects navigation (Sec-Fetch-*)
    → POST /api/v1/sessions (visitor_id, session_id, url, referrer, fingerprint)
    → POST /api/v1/events (visitor_id, ip, user_agent, properties)
    → POST /api/v1/conversions (visitor_id, conversion_type, revenue)
```

---

## Proposed Solution

Build an sGTM tag template that acts as a thin client to mbuzz's existing API. The tag runs inside the customer's sGTM container (their cloud, their domain) and makes HTTP calls identical to what our server-side SDKs make. No new API endpoints. No backend changes.

### Data Flow (Proposed — sGTM)

```
Browser (Webflow / any site with GTM)
  → Client-side GTM container
    → dataLayer.push({ event: 'page_view', ... })
    → GTM sends to sGTM endpoint (e.g. gtm.customer.com)
      → sGTM mbuzz tag template:
        ├─ getCookieValues('_mbuzz_vid') → reads visitor ID
        ├─ If absent: generateRandom(32) → hex visitor_id
        ├─ setCookie('_mbuzz_vid', ..., { maxAge: 63072000 })
        ├─ On page_view trigger:
        │   POST /api/v1/sessions
        │   { visitor_id, session_id, url, referrer, device_fingerprint }
        ├─ On custom event triggers:
        │   POST /api/v1/events
        │   { events: [{ event_type, visitor_id, ip, user_agent, properties }] }
        ├─ On conversion triggers:
        │   POST /api/v1/conversions
        │   { conversion: { visitor_id, conversion_type, revenue, properties } }
        └─ On identify triggers:
            POST /api/v1/identify
            { user_id, visitor_id, traits }
```

### Why This Works Without API Changes

sGTM is functionally a server-side SDK. It has access to:

| Capability | sGTM API | mbuzz API Expects |
|-----------|----------|------------------|
| Client IP | `getRemoteAddress()` | `ip` field or `X-Forwarded-For` header |
| User-Agent | Request headers | `user_agent` field or `X-Mbuzz-User-Agent` header |
| Cookies | `getCookieValues()` / `setCookie()` | `_mbuzz_vid` cookie |
| HTTP calls | `sendHttpRequest()` | `POST /api/v1/*` with JSON body |
| Page URL | Event data `page_location` | `url` field |
| Referrer | Event data `page_referrer` | `referrer` field |

### Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| New API endpoints? | **No** | Existing API covers all sGTM needs. Adding endpoints would fragment the contract. |
| New SDK category? | **Yes** — `tag_manager` | sGTM isn't server-side middleware or a platform plugin. It's a new category. |
| Visitor ID generation | **sGTM tag generates** | No client-side JS needed. sGTM `setCookie()` sets a server-set first-party cookie — better than client-side for ITP. |
| Session ID generation | **sGTM tag generates** | Deterministic: `SHA256(visitor_id + fingerprint + time_bucket)[0:64]`. Matches server-side resolution pattern. |
| Navigation detection | **GTM trigger config** (not tag logic) | GTM triggers already gate when tags fire. Document trigger setup instead of reimplementing Sec-Fetch-* logic. |
| Tag template language | **sGTM sandboxed JS** | Only option. sGTM uses a restricted JavaScript API (`templateDataStorage`, `sendHttpRequest`, etc.) |
| Distribution | **GTM Community Template Gallery** | Free organic discovery. Every sGTM setup sees available tags. |
| Onboarding install flow | **New `_install_sgtm` partial** | sGTM setup is different from server-side SDKs (no package manager, no middleware). Needs its own instructions. |

---

## sGTM Tag Template Design

### Template Metadata

```
Name: mbuzz — Server-Side Attribution
Description: Send pageviews, events, and conversions to mbuzz for multi-touch attribution.
Category: Analytics
Icon: mbuzz logo
```

### Template Fields (User Configuration)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `apiKey` | Text | Yes | mbuzz API key (`sk_live_*` or `sk_test_*`) |
| `apiUrl` | Text | No | API base URL (default: `https://mbuzz.co/api/v1`) |
| `callType` | Dropdown | Yes | `session`, `event`, `conversion`, or `identify` |
| `eventType` | Text | If event/conversion | Event type or conversion type |
| `revenue` | Text | No | Revenue amount (conversions only) |
| `currency` | Text | No | Currency code (default: USD) |
| `userId` | Text | No | User ID for identify calls |
| `customProperties` | Key-Value Table | No | Custom event/conversion properties |
| `cookieDomain` | Text | No | Cookie domain (default: auto-detect) |
| `cookiePath` | Text | No | Cookie path (default: `/`) |
| `debug` | Checkbox | No | Log requests to sGTM console |

### Template Logic (Pseudocode)

```javascript
// 1. Read or generate visitor ID
const visitorId = getCookieValues('_mbuzz_vid')[0] || generateVisitorId();
setCookie('_mbuzz_vid', visitorId, {
  domain: data.cookieDomain || 'auto',
  path: data.cookiePath || '/',
  'max-age': 63072000,  // 2 years
  secure: true,
  httpOnly: true,
  sameSite: 'lax'
});

// 2. Compute device fingerprint
const ip = getRemoteAddress();
const userAgent = getRequestHeader('user-agent');
const fingerprint = sha256Hex(ip + '|' + userAgent).substring(0, 32);

// 3. Build request based on call type
switch (data.callType) {
  case 'session':
    // Generate deterministic session ID
    const sessionId = generateSessionId(visitorId, fingerprint);
    sendToMbuzz('/sessions', {
      session: {
        visitor_id: visitorId,
        session_id: sessionId,
        url: getEventData('page_location'),
        referrer: getEventData('page_referrer'),
        device_fingerprint: fingerprint,
        started_at: new Date().toISOString()
      }
    });
    break;

  case 'event':
    sendToMbuzz('/events', {
      events: [{
        event_type: data.eventType || getEventData('event_name'),
        visitor_id: visitorId,
        ip: ip,
        user_agent: userAgent,
        properties: buildProperties(),
        timestamp: new Date().toISOString()
      }]
    });
    break;

  case 'conversion':
    sendToMbuzz('/conversions', {
      conversion: {
        visitor_id: visitorId,
        conversion_type: data.eventType,
        revenue: data.revenue ? parseFloat(data.revenue) : undefined,
        currency: data.currency || 'USD',
        ip: ip,
        user_agent: userAgent,
        properties: buildProperties()
      }
    });
    break;

  case 'identify':
    sendToMbuzz('/identify', {
      user_id: data.userId,
      visitor_id: visitorId,
      traits: buildProperties()
    });
    break;
}
```

### Permissions Required

sGTM templates declare permissions explicitly:

| Permission | Scope | Why |
|-----------|-------|-----|
| `read_event_data` | All event data keys | Read page_location, page_referrer, event_name |
| `get_cookies` | `_mbuzz_vid` | Read visitor ID |
| `set_cookies` | `_mbuzz_vid` | Set visitor ID |
| `send_http` | `mbuzz.co/*`, custom URL | Send data to mbuzz API |
| `read_request` | IP address, headers | Get client IP and User-Agent |
| `access_template_storage` | — | Cache session ID within request |
| `logging` | Console | Debug mode logging |

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Happy path — pageview | GTM page_view trigger fires | Tag creates visitor (if new), creates session, captures UTM/referrer/channel |
| Happy path — event | Custom event trigger fires | Tag sends event with visitor_id, ip, user_agent |
| Happy path — conversion | Conversion trigger fires | Tag sends conversion, attribution calculated async |
| Happy path — identify | User ID available | Tag links visitor to identity |
| New visitor | No `_mbuzz_vid` cookie | Tag generates visitor_id, sets cookie, calls `/sessions` |
| Returning visitor | `_mbuzz_vid` cookie exists | Tag reads visitor_id from cookie, creates new session |
| No session before event | Event fires before page_view | Event rejected — `require_existing_visitor`. Documentation must emphasize page_view trigger fires first. |
| Invalid API key | Wrong or missing key | 401 response logged. Tag calls `data.gtmOnFailure()`. |
| API down | mbuzz unreachable | HTTP timeout. Tag calls `data.gtmOnFailure()`. No retry. |
| Rate limited | 429 response | Logged. Tag calls `data.gtmOnFailure()`. |
| SPA navigation | dataLayer push without full reload | Multiple page_view triggers create multiple sessions. Document: use a single session tag per real navigation. |
| Ad blocker | Blocks client-side GTM | sGTM tag never fires. This is the client-side GTM limitation, not sGTM. Users must ensure client-side GTM loads. |
| Cookie consent | User declines cookies | Tag should respect consent mode. Skip `setCookie` if consent not granted. Document consent integration. |

---

## Implementation Tasks

### Phase 1: sGTM Tag Template

The tag template lives in a separate repository (`mbuzz-sgtm`) following GTM Community Template Gallery conventions.

- [ ] **1.1** Create `mbuzz-sgtm` repository with GTM template structure:
  ```
  mbuzz-sgtm/
  ├── template.tpl          # sGTM tag template (sandboxed JS)
  ├── metadata.yaml         # Template gallery metadata
  ├── template.js           # Extracted JS for testing
  ├── test/
  │   ├── template_test.js  # Unit tests (GTM template tester)
  │   └── fixtures/         # Test event data fixtures
  ├── README.md
  ├── CHANGELOG.md
  └── LICENSE
  ```
- [ ] **1.2** Implement visitor ID management (read/generate/set `_mbuzz_vid` cookie)
- [ ] **1.3** Implement device fingerprint computation (`SHA256(ip|user_agent)[0:32]`)
- [ ] **1.4** Implement session call (`POST /sessions` with visitor_id, session_id, url, referrer, fingerprint)
- [ ] **1.5** Implement event call (`POST /events` with batch format)
- [ ] **1.6** Implement conversion call (`POST /conversions` with revenue, currency, properties)
- [ ] **1.7** Implement identify call (`POST /identify` with user_id, visitor_id, traits)
- [ ] **1.8** Implement error handling (`gtmOnSuccess` / `gtmOnFailure`, debug logging)
- [ ] **1.9** Write unit tests for all call types using GTM template tester
- [ ] **1.10** Write unit tests for cookie management (new visitor, returning visitor)
- [ ] **1.11** Write unit tests for error states (401, 422, 429, 500, timeout)

### Phase 2: mbuzz Backend — SDK Registry + Category

- [ ] **2.1** Add `TAG_MANAGER = "tag_manager"` to `SdkCategories` constant (`app/constants/sdk_categories.rb`)
- [ ] **2.2** Add `tag_manager?` predicate to `SdkRegistry::Sdk` (`app/models/sdk_registry.rb`)
- [ ] **2.3** Add `sgtm` entry to `config/sdk_registry.yml`:
  ```yaml
  sgtm:
    key: sgtm
    name: Google Tag Manager
    display_name: Server-Side GTM
    icon: gtm
    package_name: null
    package_manager: GTM Community Template Gallery
    package_url: null  # Set after gallery submission
    github_url: https://github.com/mbuzzco/mbuzz-sgtm
    docs_url: /docs/integrations-sgtm
    status: live  # or beta initially
    released_at: null  # Set on release
    category: tag_manager
    sort_order: 5  # After PHP (4), before Shopify (6)
    install_command: null
    init_code: null  # sGTM uses template fields, not code
    event_code: null
    conversion_code: null
    identify_code: null
    middleware_code: null
    verification_command: null
  ```
- [ ] **2.4** Add GTM SVG icon to `app/assets/images/sdks/` or icon helper
- [ ] **2.5** Write test for `SdkRegistry.find('sgtm')` and category predicate

### Phase 3: Homepage Logo

- [ ] **3.1** Add GTM logo/icon to homepage SDK grid. `SdkRegistry.for_homepage` already renders all entries — adding to `sdk_registry.yml` handles this automatically.
- [ ] **3.2** Verify visual rendering: icon displays correctly in 4-column grid, status badge shows correctly
- [ ] **3.3** Manual QA on dev

### Phase 4: Onboarding Flow

- [ ] **4.1** Create `app/views/onboarding/_install_sgtm.html.erb` partial with sGTM-specific setup instructions:
  1. Prerequisites (sGTM container running)
  2. Import mbuzz tag template
  3. Configure API key
  4. Create triggers (page_view → session tag, custom events → event tag)
  5. Test in preview mode
- [ ] **4.2** Update `app/views/onboarding/install.html.erb` to render `_install_sgtm` for `tag_manager?` category (currently handles `platform?` and falls back to `_install_server_side`)
- [ ] **4.3** Manual QA: walk through full onboarding flow selecting sGTM

### Phase 5: API Documentation

- [ ] **5.1** Create `app/views/docs/_integrations_sgtm.html.erb` documentation page:
  - Architecture diagram (browser → client GTM → sGTM → mbuzz API)
  - Step-by-step sGTM setup with screenshots
  - Trigger configuration guide
  - Tag configuration for each call type
  - Consent mode integration
  - Troubleshooting guide
- [ ] **5.2** Add "sGTM" tab to docs navigation in `app/views/layouts/docs.html.erb`
- [ ] **5.3** Add sGTM code examples to `app/views/docs/_getting_started.html.erb` code tabs (show the equivalent REST API calls that the tag makes)

### Phase 6: SDK Registry Documentation

- [ ] **6.1** Add sGTM section to `lib/docs/sdk/sdk_registry.md` under a new "Tag Manager Integrations" heading
- [ ] **6.2** Update version compatibility matrix
- [ ] **6.3** Add sGTM to `lib/docs/sdk/api_contract.md` "SDK Feature Requirements" section, noting which features apply

### Phase 7: End-to-End Integration Tests

Tests live in `sdk_integration_tests/` and verify the sGTM tag template works against the real mbuzz API. Since sGTM tests can't use a real GTM container in CI, the test app simulates what the sGTM tag does: makes the same HTTP calls with the same data shapes.

- [ ] **7.1** Create `sdk_integration_tests/apps/mbuzz_sgtm_testapp/` — a minimal Node.js app that simulates sGTM tag behavior:
  ```
  apps/mbuzz_sgtm_testapp/
  ├── server.js          # Express app simulating sGTM tag calls
  ├── package.json
  └── views/
      └── index.html     # Test UI with visitor-id, event-form, etc.
  ```
  The test app:
  - Generates visitor IDs (64 hex chars), stores in cookie
  - Computes device fingerprints (`SHA256(ip|user_agent)[0:32]`)
  - Makes HTTP calls to mbuzz API in the same format the sGTM tag would
  - Renders a test UI matching existing test app conventions (`#visitor-id`, `#event-form`)
- [ ] **7.2** Add `sgtm` to `TestConfig::SDK_PORTS` (port `4006`)
- [ ] **7.3** Add `sdk:sgtm` rake task and `sdk:app_sgtm` task to `sdk_integration_tests/Rakefile`
- [ ] **7.4** Write test: `sgtm_session_creation_test.rb`
  - Verify session created with correct visitor_id, url, referrer
  - Verify UTM params captured from URL
  - Verify channel derived correctly
- [ ] **7.5** Write test: `sgtm_event_tracking_test.rb`
  - Verify events tracked with correct event_type, visitor_id, properties
  - Verify events linked to correct session
- [ ] **7.6** Write test: `sgtm_conversion_test.rb`
  - Verify conversions tracked with revenue, currency, conversion_type
  - Verify attribution calculation queued
- [ ] **7.7** Write test: `sgtm_visitor_persistence_test.rb`
  - Verify visitor ID persists across simulated "requests"
  - Verify returning visitor gets new session (not duplicate visitor)
- [ ] **7.8** Write test: `sgtm_utm_capture_test.rb`
  - Verify UTM params from page URL captured in session
  - Verify channel derived from UTM (e.g. `utm_medium=cpc` → `paid_search`)
  - Verify referrer-based channel attribution
- [ ] **7.9** Write test: `sgtm_ordering_test.rb`
  - Verify events sent before session creation are rejected (`require_existing_visitor`)
  - Verify events succeed after session creation

### Phase 8: GTM Community Template Gallery Submission

- [ ] **8.1** Ensure template meets [Gallery requirements](https://developers.google.com/tag-platform/tag-manager/templates/gallery)
- [ ] **8.2** Add template tests that pass GTM's automated validator
- [ ] **8.3** Submit to Community Template Gallery
- [ ] **8.4** Update `config/sdk_registry.yml` with `package_url` once approved

---

## Testing Strategy

### Unit Tests (sGTM Tag Template)

| Test | File | Verifies |
|------|------|----------|
| New visitor creates cookie | `mbuzz-sgtm/test/template_test.js` | `setCookie` called with 64-hex visitor_id |
| Returning visitor reads cookie | `mbuzz-sgtm/test/template_test.js` | `getCookieValues` returns existing ID |
| Session call sends correct payload | `mbuzz-sgtm/test/template_test.js` | POST body matches API contract |
| Event call sends batch format | `mbuzz-sgtm/test/template_test.js` | `{ events: [{ ... }] }` structure |
| Conversion call sends revenue | `mbuzz-sgtm/test/template_test.js` | Revenue parsed as float, currency included |
| Identify call sends user_id + traits | `mbuzz-sgtm/test/template_test.js` | Correct body structure |
| 401 response triggers failure | `mbuzz-sgtm/test/template_test.js` | `gtmOnFailure()` called |
| Fingerprint computed correctly | `mbuzz-sgtm/test/template_test.js` | `SHA256(ip\|ua)[0:32]` matches expected |
| Debug mode logs to console | `mbuzz-sgtm/test/template_test.js` | `logToConsole` called when debug enabled |

### Unit Tests (mbuzz Backend)

| Test | File | Verifies |
|------|------|----------|
| SdkRegistry finds sgtm | `test/models/sdk_registry_test.rb` | `SdkRegistry.find('sgtm')` returns correct entry |
| tag_manager category works | `test/models/sdk_registry_test.rb` | `sdk.tag_manager?` returns true |
| SdkCategories includes TAG_MANAGER | `test/constants/sdk_categories_test.rb` | Constant exists in ALL array |

### End-to-End Tests (`sdk_integration_tests/`)

| Test | File | Verifies |
|------|------|----------|
| Session creation | `scenarios/sgtm_session_creation_test.rb` | Visitor + session created, UTM captured |
| Event tracking | `scenarios/sgtm_event_tracking_test.rb` | Events stored with correct type + properties |
| Conversion tracking | `scenarios/sgtm_conversion_test.rb` | Conversion created, attribution queued |
| Visitor persistence | `scenarios/sgtm_visitor_persistence_test.rb` | Same visitor_id across requests |
| UTM + channel attribution | `scenarios/sgtm_utm_capture_test.rb` | UTM params → correct channel |
| Ordering constraint | `scenarios/sgtm_ordering_test.rb` | Events fail without prior session |

### Manual QA

1. Install tag template in a real sGTM container
2. Configure with test API key
3. Visit test site — verify session appears in mbuzz dashboard
4. Trigger custom event — verify event appears
5. Trigger conversion — verify attribution calculated
6. Check cookies: `_mbuzz_vid` is set, HttpOnly, first-party
7. Test with ad blocker enabled — verify sGTM calls still arrive (client GTM must load)
8. Test in GTM preview mode — verify tag fires and API calls succeed
9. Walk through onboarding flow selecting sGTM
10. Verify homepage shows GTM logo with correct status badge

---

## Definition of Done

- [ ] sGTM tag template repository created with all call types
- [ ] Tag template unit tests pass
- [ ] sGTM entry in `sdk_registry.yml` with correct category and sort order
- [ ] GTM icon renders on homepage SDK grid
- [ ] Onboarding flow works for sGTM selection (install partial, setup guide)
- [ ] API docs include sGTM tab with setup guide
- [ ] `sdk_registry.md` updated with sGTM section
- [ ] E2E integration tests pass (`sdk_integration_tests/scenarios/sgtm_*`)
- [ ] Manual QA with real sGTM container
- [ ] Spec updated with final state
- [ ] No regressions in existing SDK tests

---

## Out of Scope

- **Client-side GTM tag**: This spec covers server-side GTM only. A client-side GTM tag (browser → mbuzz directly) would bypass the server-side session resolution that is mbuzz's core value. Could revisit if demand exists, but sGTM is the right architecture.
- **Consent management platform (CMP) integration**: Document how to respect consent mode, but don't build a CMP integration. That's the GTM container's responsibility.
- **GA4 event format translation**: The sGTM tag sends data in mbuzz's native format, not GA4 format. If someone wants to forward GA4 events to mbuzz, that's a separate "client" template (receives GA4, translates to mbuzz), not a "tag" template.
- **Automatic ecommerce tracking**: GA4 enhanced ecommerce data layer events (`purchase`, `add_to_cart`) could be auto-mapped to mbuzz events. Out of scope for v1 — users configure explicit triggers.
- **Backfilling historical GTM data**: No mechanism to import past GTM data into mbuzz.
- **sGTM hosting setup**: We document "you need an sGTM container" but don't help set one up. That's Google Cloud / Stape / Addingwell territory.
