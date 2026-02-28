# SME Customer: sGTM Implementation Runbook

**Date:** 2026-02-27
**Customer type:** Media owner (no backend access — content site on CMS)
**Integration:** Server-Side Google Tag Manager (sGTM)
**Template repo:** `mbuzz-sgtm` (GitHub: mbuzzco/mbuzz-sgtm)

---

## Context

First potential customer implementing sGTM. Media owner — small business, content site. No backend access, so server-side SDKs aren't an option. sGTM is the bridge: runs on their infrastructure, makes server-to-server calls to the mbuzz API, sets first-party cookies.

The `mbuzz-sgtm` template was recently updated with critical fixes:
- `7bb2869` — Added `session_id` to session payload (was causing 422 errors)
- `431493d` — Removed Tag Sequencing references (web-only feature, doesn't exist in sGTM)
- `f1a08db` — Added `user_agent` to session payload (enables bot detection)

### Customer's Container Setup (GTM-K82HNR58, "SME Server")

**Clients:**
- **GA4** — Standard GA4 (Web) client. Regular GTM container sends all sessions to sGTM.
- **Data Client** — Accepts JSON POST requests triggered from phone clicks (enables phone click conversion tracking).

**Templates:**
- **JSON HTTP request** (Gallery) — Used for the Data Client to accept JSON POSTs for phone click tracking. Document this pattern in mbuzz sGTM docs.
- **mbuzz — Server-Side Attribution** — Updated to latest (2026-02-27).

**Tags:**
- `mbuzz - Session` → All Pages trigger — verified working, 202 responses
- `mbuzz - Event - Form Submit` → Custom Event trigger on `.*_form_submission` (regex) — **actually configured as Call Type: conversion** (intentional for small business). Verified working, 201 responses.
- `mbuzz - Conversion - Phone Click` → Phone Click Trigger on `GA4-phone-link-click` — verified working, 201 responses.

**Trigger fixes applied during UAT (2026-02-28):**
- Form Submit: changed event name from `form-submit` to `.*_form_submission` (regex), removed broken `{{Request Path}} contains thank-you` filter (Request Path is the collect endpoint path, not page URL)
- Phone Click: changed event name from `phone_click` to `GA4-phone-link-click` (matching actual event name from client-side GTM)

**Template fixes applied (2026-02-28):**
- Updated to latest template.tpl with `session_id` fix and `user_agent` payload
- Added `getVisitorIp()` / `getVisitorUa()` helpers: prefer `ip_override` and `user_agent` from GA4 event data over transport-layer values (`getRemoteAddress()` / `getRequestHeader()`). Verified fingerprint matches real visitor IP.

**Notes:**
- Neither form submit nor phone click is a "real" conversion in the traditional sense, but customer is small so tracking these as conversions for attribution purposes.
- Phone click conversion pattern: client-side GTM catches `tel:` link click → sends GA4 event `GA4-phone-link-click` through sGTM → GA4 Client processes → Phone Click Trigger fires → mbuzz Conversion tag sends to `/api/v1/conversions`. Document this pattern in sGTM docs.
- Data Client (Stape) + JSON HTTP request template used to accept phone click events. Document this in mbuzz sGTM docs as an alternative pattern.

---

## Prerequisites

Before starting, confirm the customer has:

- [ ] **Client-side GTM** — Standard `<script>` snippet installed on their site
- [ ] **sGTM server** — Running via Stape (~$10/mo), Addingwell, TAGGRS, or GCP
- [ ] **Custom subdomain** — Mapped to sGTM via **A/AAAA DNS records** (NOT CNAME)
  - Example: `data.theirdomain.com` or `sgtm.theirdomain.com`
  - CNAME causes Safari ITP to cap cookies at 7 days
- [ ] **mbuzz account** — Created with `sk_test_*` and `sk_live_*` API keys
- [ ] **HTTPS** — sGTM subdomain must be over HTTPS (required for Secure cookies)

### Why A/AAAA records matter

Safari ITP checks whether the first two octets of the sGTM server IP match the main site IP. If they don't match (common with CNAME setups), cookies get capped at 7 days. Most sGTM hosting providers (Stape, Addingwell) handle this with their custom domain setup — but worth verifying.

---

## Step-by-Step Implementation

### Step 1: Upload the sGTM Template

The template in `mbuzz-sgtm/template.tpl` must be imported into the customer's **server-side** GTM container.

**If template already exists (updating):**
1. Open sGTM container → **Templates** → **Tag Templates**
2. Click the existing "mbuzz — Server-Side Attribution" template
3. Click the three-dot menu (⋮) → **Import**
4. Select the latest `template.tpl` from the mbuzz-sgtm repo
5. Click **Save**

**If template is new (first time):**
1. Open sGTM container → **Templates** → **Tag Templates**
2. Click **New**
3. Click the three-dot menu (⋮) → **Import**
4. Select `template.tpl`
5. Click **Save**

**From Gallery (when approved):**
1. Templates → Search Gallery → search "mbuzz" → Add to workspace

### Step 2: Web-to-Server Linking

Route the client-side GTM data stream through the sGTM server. **Without this, no data reaches server-side.**

1. Open the customer's **web** GTM container (not the server container)
2. Find the **Google Tag** (GA4 Configuration tag)
3. Under **Configuration settings**, click **Add Row**
4. Set parameter name: `server_container_url`
5. Set value: `https://sgtm.theirdomain.com` (their sGTM URL)
6. **Save** the tag
7. **Publish** the web container

### Step 3: Create the Session Tag

The Session tag is the foundation. It creates the visitor, sets the `_mbuzz_vid` cookie, and captures UTM/referrer/channel data. **Must fire on every page view.**

1. In the sGTM container: **Tags** → **New**
2. Tag Configuration → choose **mbuzz — Server-Side Attribution**
3. Configure:

| Field | Value |
|-------|-------|
| API Key | `sk_test_xxxxx` (use test key during UAT) |
| Call Type | **Session** |

4. Expand **Advanced Settings** → check **Enable debug logging**
5. Trigger: click **Triggering** → select (or create) **All Pages**
   - If no "All Pages" trigger exists: New Trigger → type **Custom** → fire on **All Events** where `Event Name equals page_view`
6. Name the tag: `mbuzz — Session`
7. **Save**

### Step 4: Create the Conversion Tag

For a media owner, the primary conversion is likely a lead/contact/signup form.

1. **Tags** → **New** → **mbuzz — Server-Side Attribution**
2. Configure:

| Field | Value |
|-------|-------|
| API Key | `sk_test_xxxxx` |
| Call Type | **Conversion** |
| Conversion Type | `lead` (or `contact_form`, `signup` — match their business) |
| Revenue | (blank unless they have a dollar value per lead) |
| Currency | `USD` (or their currency) |

3. Trigger: depends on how their form reports:
   - If GA4 fires `generate_lead`: trigger on `Event Name equals generate_lead`
   - If custom dataLayer push: trigger on that event name
   - If form plugin (e.g. Webflow form): trigger on the form submission event
4. Name: `mbuzz — Conversion (Lead)`
5. **Save**

### Step 5: Create Event Tags (optional)

For mid-funnel engagement tracking:

| Scenario | Event Type | Trigger |
|----------|-----------|---------|
| Article scroll | `scroll_depth` | Scroll depth trigger (25%, 50%, 75%, 100%) |
| Video play | `video_play` | YouTube/Vimeo video event |
| CTA click | `cta_click` | Click trigger on CTA elements |
| Newsletter signup | `newsletter_signup` | Form submission on newsletter form |

### Step 6: Create Identify Tag (optional)

Only if users log in / create accounts on their site.

| Field | Value |
|-------|-------|
| Call Type | **Identify** |
| User ID | `{{User ID}}` (GTM variable from their auth system) |
| Custom Properties | email, name, plan — whatever traits they want |
| Trigger | Login or signup event |

---

## UAT Process

### Phase 1: Preview Mode (The "Three-Tab Dance")

This is the primary debugging tool. Order matters.

1. **Tab 1** — Open sGTM container → click **Preview**
2. **Tab 2** — Open web GTM container → click **Preview** (Tag Assistant opens)
3. **Tab 3** — Visit the customer's website

**Verify in the sGTM preview panel:**

| Check | Where to look | Expected |
|-------|--------------|----------|
| Session tag fires | Tags tab | Green checkmark on every page view |
| Outgoing HTTP request | Click the tag → Outgoing HTTP Requests | `POST https://mbuzz.co/api/v1/sessions` |
| Response status | Same area | `200` or `201` |
| Event data populated | Event Data tab | `page_location`, `page_referrer` have values |
| Debug logs | Console tab | `[mbuzz] session → https://mbuzz.co/api/v1/sessions` |
| Cookie set | Response headers | `Set-Cookie: _mbuzz_vid=...` |

**If tags don't fire at all:**
- Confirm web-to-server linking (Step 2) is published
- Check that the GA4 Client in sGTM is claiming requests
- Disable VPN / ad blocker (NordVPN's Web Protection blocks preview cookies)

**If tags fire but get 4xx:**
- `422` → Missing required field. Check debug logs for the response body.
- `401` → Bad API key. Verify `sk_test_*` key is correct.
- `400` → Malformed payload. Check debug log output for the body being sent.

### Phase 2: Data Verification in mbuzz Dashboard

With `sk_test_*` key active:

1. **Browse 3-4 pages** on the customer's site
2. **mbuzz dashboard → Visitors**: New visitor should appear with the `_mbuzz_vid` value
3. **Sessions**: Should see sessions with correct page URLs and referrers
4. **UTM test**: Visit with `?utm_source=google&utm_medium=cpc&utm_campaign=test`
   - Channel should resolve to **Paid Search**
5. **Referrer test**: Click through from Google search results (or simulate with referrer)
   - Channel should resolve to **Organic Search**
6. **Trigger a conversion** → verify it appears in the Conversions view
7. **Device fingerprint**: Confirm populated on sessions (needed for bot detection)

### Phase 3: Cookie Verification

In the browser DevTools on the customer's site:

1. **Application tab → Cookies** → look for the sGTM domain
2. Find `_mbuzz_vid` and verify:

| Property | Expected |
|----------|----------|
| Value | 64-character hex string |
| Domain | `.theirdomain.com` (leading dot = covers subdomains) |
| Expires | ~2 years from now |
| HttpOnly | `true` |
| Secure | `true` |
| SameSite | `Lax` |

3. Navigate to another page → same cookie value (visitor persists)
4. Incognito window → different cookie value (new visitor)

### Phase 4: Safari ITP Check

Media sites get significant Safari traffic. This matters.

1. Open the site in **Safari**
2. Verify `_mbuzz_vid` cookie is set
3. Check cookie expiry — should be 2 years, NOT 7 days
4. If 7 days: the sGTM server IP doesn't match the main site IP (first two octets)
   - Fix: work with their sGTM provider to align IPs or use their custom domain setup correctly

### Phase 5: Cross-Session Persistence

1. Visit site → note visitor ID in dashboard
2. Close browser completely
3. Reopen browser → visit site again
4. Same visitor ID should appear → session count increments, not a new visitor

### Phase 6: Go Live

1. Edit all mbuzz tags → change API key from `sk_test_*` to `sk_live_*`
2. Uncheck **Enable debug logging** in Advanced Settings (on all tags)
3. Click **Submit** in the sGTM container to publish
4. Monitor mbuzz dashboard for 24 hours:
   - Traffic volume should match their analytics (GA4, etc.) roughly
   - No spike of bot traffic (bot detection filters on `user_agent`)
   - Sessions have correct URLs, referrers, channels
   - Conversions flowing when forms are submitted

---

## Common Gotchas

| Problem | Cause | Fix |
|---------|-------|-----|
| No data at all | Web-to-server linking missing | Add `server_container_url` to Google Tag in web container (Step 2) |
| Events/conversions rejected (422) | No visitor exists yet | Session tag must have All Pages trigger — `require_existing_visitor` is enabled |
| Cookie not setting | sGTM not on customer's subdomain | Map a subdomain via A/AAAA DNS to sGTM server |
| Cookie expires in 7 days (Safari) | IP mismatch between site and sGTM | Align IPs via sGTM provider's custom domain setup |
| Duplicate visitors | Cookie domain wrong | Leave cookie domain blank (auto-detects eTLD+1) or set explicitly to `.theirdomain.com` |
| High bot traffic | No bot filtering | `user_agent` is now sent — server-side bot detection filters these (see `feature/session-bot-detection` branch) |
| Tags fire but `gtmOnFailure` | API returning errors | Enable debug logging → check console for response body with error details |
| Preview mode not working | VPN or browser extension | Disable VPN (especially NordVPN Web Protection), try incognito with no extensions |

---

## Architecture Reference

```
Browser (visitor's device)
  │
  │  gtag.js / client-side GTM fires GA4 events
  │
  ▼
sGTM Server (sgtm.theirdomain.com)
  │
  │  GA4 Client claims request, parses into event data
  │  mbuzz tag reads event data + cookies
  │
  ├─── Session tag ──→ POST /api/v1/sessions
  │      • visitor_id (from _mbuzz_vid cookie)
  │      • session_id (deterministic: SHA256(vid + fingerprint + 30min_bucket))
  │      • url, referrer, device_fingerprint, user_agent
  │
  ├─── Event tag ──→ POST /api/v1/events
  │      • event_type, visitor_id, ip, user_agent, properties
  │
  ├─── Conversion tag ──→ POST /api/v1/conversions
  │      • conversion_type, visitor_id, revenue, currency, ip, user_agent
  │
  └─── Identify tag ──→ POST /api/v1/identify
         • user_id, visitor_id, traits
  │
  ▼
mbuzz API (mbuzz.co)
  • Creates/updates Visitor, Session records
  • Extracts UTMs, classifies channel
  • Triggers multi-touch attribution on conversions
  • Links visitor to user identity
```

---

## mbuzz Tag Template Reference

| Field | Required | Call Types | Notes |
|-------|----------|------------|-------|
| API Key | Yes | All | `sk_test_*` for UAT, `sk_live_*` for production |
| Call Type | Yes | All | session, event, conversion, identify |
| Event/Conversion Type | Conditional | event, conversion | The event name or conversion type string |
| Revenue | No | conversion | Numeric value |
| Currency | No | conversion | ISO 4217, default USD |
| User ID | Conditional | identify | Required for identify calls |
| Custom Properties | No | event, conversion, identify | Key-value table, supports GTM variables |
| API URL | No | All | Default: `https://mbuzz.co/api/v1` |
| Cookie Domain | No | All | Auto-detects. Override only if needed. |
| Cookie Path | No | All | Default: `/` |
| Debug | No | All | Enable during UAT, disable in production |
