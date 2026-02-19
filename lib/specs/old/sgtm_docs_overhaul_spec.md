# sGTM Documentation Overhaul Specification

**Date:** 2026-02-20
**Priority:** P1
**Status:** Complete
**Branch:** `feature/sgtm-docs-overhaul`

---

## Summary

Our sGTM docs assume people already have a server-side GTM container running. They don't. Step 1 says "Get an sGTM server" with three link cards and zero actual guidance. The onboarding page is one sentence: "You need a server-side GTM container running on your own domain." This is the hardest part of the entire sGTM process and we hand-wave over it. People bounce before they ever see the mbuzz tag setup (which is actually good).

This spec rewrites the sGTM setup documentation to be honest about complexity, walk people through the real steps, explain domain mapping (critical for attribution), add video resources, and introduce an interactive checklist so people can track progress across sessions.

---

## Problem

### What's broken

1. **Step 1 is empty.** Three link cards (Stape, Addingwell, Google Cloud) with no walkthrough. The hardest step has the least guidance.

2. **No domain mapping guidance.** Without a custom domain (`gtm.yoursite.com`), cookies are third-party and Safari ITP kills them in 7 days. For an attribution product, this isn't optional — it's the entire point of sGTM. Not mentioned anywhere.

3. **False "5 minute" claim.** Our docs (and Stape's marketing) imply this is quick. Reality: container spin-up is fast, but DNS/domain config takes hours to days. Cloudflare proxy conflicts, duplicate DNS records, SSL verification waits — all undocumented.

4. **No video resources.** sGTM setup is visual and procedural. Text-only docs don't work for this. Good YouTube tutorials exist and we don't link any.

5. **No progress tracking.** sGTM setup spans multiple sittings — DNS propagation alone can take 72 hours. People lose their place. Linear numbered steps with no state don't cut it.

6. **GCP automatic provisioning not mentioned.** The most common GTM entry point ("Automatically provision tagging server" button) isn't referenced. People see it, click it, get a non-production setup locked to us-central1 with no custom domain, and wonder why their cookies die after 7 days.

### Who's affected

Every mbuzz user who doesn't have backend access — the exact audience sGTM is designed for. Webflow, Squarespace, WordPress sites. Agencies setting up clients. This is potentially our largest integration surface and the docs are our weakest.

### Research: What actually sucks about each provider

| Provider | Setup Time (Real) | Starting Price | The Catch |
|----------|-------------------|----------------|-----------|
| **Stape** | 2-4 hours (DNS is the bottleneck) | $20/mo (500K req) | "5 minutes" is marketing. DNS/domain setup trips up non-technical users. Cloudflare proxy conflicts are the #1 support issue. |
| **TAGGRS** | 2-4 hours | EUR 22/mo (750K req) | Cluttered UI, no logs for debugging, same GTM expertise required as Stape. |
| **Addingwell** | 1-2 hours | EUR 90/mo (2M req) | Best onboarding UX but 4.5x Stape's price. Extra charges for advanced configs. |
| **Tracklution** | 15 minutes | EUR 31/mo | Genuinely simple — copy-paste pixel, no GTM needed. But least customizable, locked to their supported networks. |
| **GCP Auto-Provision** | 2 minutes + hours for domain | ~$120/mo (3 instances) | Locked to us-central1. Not production-grade. No custom domain included. Hidden logging costs (~$100/mo). |
| **GCP Manual** | 50-120 developer hours | ~$120/mo minimum | Full control but massive upfront investment. Load balancer, SSL cert, DNS, all manual. |

Source: Stape Trustpilot reviews, Seresa.io cost analysis, Simo Ahava technical guides, Stape community forum DNS threads, MeasureSchool comparison guides.

### The honest truth about sGTM complexity

sGTM has a documented 40-80 hour learning curve for beginners. Content is created by experts for experts. The vocabulary is confusing ("Client" in sGTM means server-side code that *receives* data, not a browser). You manage two GTM containers (web + server) with non-obvious data flow between them.

We can't fix this industry-wide problem, but we can:
- Be honest about time investment upfront
- Provide the clearest possible guided path
- Link to the best external resources
- Make progress trackable

---

## Solution

### Approach

Rewrite the sGTM server setup section (Step 1 in docs, prerequisite in onboarding) with:

1. **Two clear paths** with honest time estimates — Stape (recommended, 2-4 hours) and GCP (DIY, half a day+)
2. **Actual step-by-step walkthroughs** for each path, including the domain/DNS setup that currently isn't documented
3. **A "Why custom domains matter" section** explaining the first-party cookie requirement
4. **Video resources section** linking to the best free YouTube tutorials
5. **Interactive checklist** in onboarding using Stimulus + localStorage so people can track progress across sessions
6. **Honest time expectations** — no more "5 minutes"

### What we're NOT doing

- Building our own sGTM hosting (that's someone else's business)
- Recording our own video yet (link to existing good ones first, record ours later)
- Changing the mbuzz tag template setup docs (Steps 3-4 are already good)

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Recommended provider | **Stape** (still, but honestly) | Best value at $20/mo. Largest community, most docs. But we drop the "5 minutes" lie and document the real DNS pain. |
| Secondary provider | **Addingwell** for premium, **TAGGRS** for EU | Different audiences need different options. |
| Alternative for non-technical | **Mention Tracklution** as a simpler alternative | Genuinely easier (15 min), but less customizable. Worth mentioning for teams without GTM expertise. |
| GCP coverage | **Document but discourage for most users** | Auto-provision is tempting but not production-ready. Manual is too complex for our audience. Cover it for completeness. |
| Checklist implementation | **Stimulus controller + localStorage** | Persists across sessions. No backend needed. Reuses existing Stimulus patterns. |
| Video approach | **Link to Analytics Mania + Simo Ahava for now** | Best free resources available. Record our own later — it's a separate content effort. |

---

## Current State

### Files to modify

| File | Current State | What Changes |
|------|---------------|-------------|
| `app/views/docs/_integrations_sgtm.html.erb` | Step 1 is three link cards with no walkthrough. No domain mapping. No video resources. | Full rewrite of Step 1. New sections for domain mapping, video resources. |
| `app/views/onboarding/_install_sgtm.html.erb` | One-sentence prerequisite with Stape link. Linear steps with no state tracking. | Add interactive checklist with localStorage persistence. Expand prerequisite into guided setup. |

### Files that DON'T change

| File | Why |
|------|-----|
| `app/views/docs/_integrations_sgtm.html.erb` Steps 2-4 | Tag setup docs are well-structured. Leave them alone. |
| `lib/specs/sgtm_integration_spec.md` | That spec covers the tag template and backend integration. This spec covers the docs gap it explicitly called out of scope. |
| `config/sdk_registry.yml` | No registry changes needed. |

---

## Proposed Changes

### 1. Docs page: Rewrite Step 1 — "Get an sGTM server"

Replace the current three link cards with a tabbed interface showing two paths:

**Tab A: Stape.io (Recommended — allow 2-4 hours)**

Actual walkthrough:
1. Create a Stape account at stape.io
2. Create a new sGTM container in Google Tag Manager (Admin > Create Container > Server)
3. Copy the container config string from GTM
4. In Stape, create a new container and paste the config string
5. **Set up your custom domain** (this is the critical step):
   - In Stape container settings, add your subdomain (e.g. `sgtm.yoursite.com`)
   - Stape gives you DNS records (A record or CNAME)
   - Add these records in your DNS provider (Cloudflare, GoDaddy, Namecheap, etc.)
   - **Cloudflare users:** disable the orange proxy cloud for this record (most common mistake)
   - **Remove any existing AAAA records** for the subdomain
   - Wait for verification (30 min to 72 hours depending on DNS provider)
   - SSL certificate provisions automatically after verification
6. Verify: visit `https://sgtm.yoursite.com/healthy` — should return 200

Include callouts for common DNS pitfalls:
- Cloudflare proxy must be disabled (grey cloud, not orange)
- No duplicate A records for the same subdomain
- Remove AAAA (IPv6) records that interfere with verification
- SSL/TLS mode must be "Full" if using Cloudflare

**Tab B: Google Cloud (DIY — allow half a day)**

Cover the automatic provisioning flow honestly:
1. In GTM, create Server container → "Automatically provision tagging server"
2. Select GCP billing account → container deploys to Cloud Run (us-central1, cannot change)
3. **This is NOT production-ready** — Google's own docs say "recommended for testing limited traffic volumes only"
4. For production: need 3+ instances (~$120/mo), disable default logging (adds ~$100/mo)
5. **Custom domain setup** (required for first-party cookies):
   - Create an external Application Load Balancer in GCP Console
   - Create a Serverless Network Endpoint Group (NEG) pointing to Cloud Run
   - Create a Backend Service using the NEG
   - Create a URL Map for routing
   - Create a Google-managed SSL certificate for your subdomain
   - Create an HTTPS frontend linking cert + URL map
   - Add DNS A record pointing subdomain to load balancer IP
   - Wait for SSL provisioning (minutes to hours after DNS propagation)
6. Link to Simo Ahava's Cloud Run guide for the definitive walkthrough

**Collapsed section: Other providers**

Brief mention of:
- **Addingwell** — Best onboarding UX, EUR 90/mo, good for teams who want hand-holding
- **TAGGRS** — EU infrastructure, EUR 22/mo, good for GDPR data residency
- **Tracklution** — Genuinely simpler (15 min, no GTM knowledge needed), EUR 31/mo, but less customizable

### 2. Docs page: New section — "Why you need a custom domain"

Add between current "What is sGTM?" and "What You Need" sections. Content:

- Without a custom domain: your sGTM runs on `xxx.run.app` or `xxx.stape.io` — third-party context
- Safari ITP limits third-party cookies to 7 days (or less if IP doesn't match)
- Ad blockers can block known third-party domains
- With a custom domain (`sgtm.yoursite.com`): first-party cookies last 2 years, can't be blocked
- **For attribution, this isn't optional** — 7-day cookie expiry means you lose visitors who take longer than a week to convert (most B2B, most considered purchases)
- Show a simple comparison:

| | No Custom Domain | Custom Domain |
|---|---|---|
| Cookie duration | 7 days (Safari) | 2 years |
| Ad blocker bypass | No | Yes |
| Setup time | 5 minutes | 2-4 hours |
| **Attribution accuracy** | **Poor** | **Full** |

### 3. Docs page: New section — "Video Resources"

Add after the troubleshooting section. Link to the best free tutorials:

| Resource | What It Covers | Best For |
|----------|---------------|----------|
| **Analytics Mania** — "Server-Side Tagging Tutorial" (45 min) | Full setup walkthrough: container creation, GCP provisioning, domain setup, GA4 connection | Beginners starting from zero |
| **MeasureSchool** — "How to Set Up Server-Side Tagging" | Step-by-step written + video guide | Visual learners who want written companion |
| **Simo Ahava** — "Cloud Run with Server-Side Tagging" | Deep technical architecture, Cloud Run specifics, debugging | Technical teams self-hosting on GCP |
| **Stape Academy** — Free courses on stape.io | Stape-specific setup, platform-specific guides (Shopify, WooCommerce) | Stape users |

Note: Link to actual URLs for Analytics Mania (analyticsmania.com), MeasureSchool (measureschool.com), Simo Ahava (simoahava.com).

### 4. Onboarding page: Interactive checklist

Replace the current linear steps with a Stimulus-powered checklist that persists to localStorage.

**Stimulus controller:** `checklist_controller.js`

Behaviour:
- Each step has a checkbox that toggles completion state
- State persists to `localStorage` keyed by `mbuzz-sgtm-checklist`
- Completed steps get a visual strikethrough/dimming
- Progress indicator at top shows "3 of 7 complete"
- "Reset progress" link to start over

**Checklist steps:**

```
[ ] sGTM server running
    Your server URL: _________________ (e.g. https://sgtm.yoursite.com)
    [ ] Custom domain verified (HTTPS working)

[ ] Client-side GTM installed on website
    [ ] Server Container URL configured in GTM

[ ] mbuzz tag template imported
    Via Gallery search or manual GitHub import

[ ] Session tag created
    Trigger: All Pages
    This is the foundation — all other tags depend on it

[ ] Conversion tag created
    Trigger: Your conversion event
    Tag Sequencing: Session fires first

[ ] Event tags created (optional)
    Trigger: Custom events
    Tag Sequencing: Session fires first

[ ] Tested in Preview Mode
    [ ] Session tag fires with green checkmark
    [ ] Data appears in mbuzz dashboard
    [ ] Published via Submit
```

### 5. Docs page: Honest time expectations

Add a callout at the very top of the setup guide, before Step 1:

> **Time estimate:** If you already have sGTM running, adding mbuzz takes ~15 minutes (Steps 3-4 only). If you're setting up sGTM from scratch, allow 2-4 hours — most of that is DNS/domain configuration, which can take up to 72 hours for verification depending on your DNS provider. This is a one-time setup.

---

## Implementation Tasks

### Phase 1: Quick wins (docs content)

- [ ] **1.1** Add "Why you need a custom domain" section to `_integrations_sgtm.html.erb` between "What is sGTM?" and "What You Need" sections
- [ ] **1.2** Add honest time estimate callout at the top of the setup guide
- [ ] **1.3** Add "Video Resources" section after troubleshooting in `_integrations_sgtm.html.erb`
- [ ] **1.4** Update the onboarding prerequisite from one-sentence to expanded guidance with Stape/GCP links

### Phase 2: Step 1 rewrite (the big one)

- [ ] **2.1** Replace Step 1 link cards with tabbed interface (Stape / Google Cloud / Other Providers)
- [ ] **2.2** Write Stape walkthrough with actual steps including DNS/domain setup and common pitfalls (Cloudflare proxy, duplicate records, AAAA records, SSL mode)
- [ ] **2.3** Write GCP automatic provisioning walkthrough with honest limitations (us-central1 lock, not production-ready, domain mapping via load balancer)
- [ ] **2.4** Write collapsed "Other Providers" section (Addingwell, TAGGRS, Tracklution)
- [ ] **2.5** Add Stape DNS troubleshooting to the existing troubleshooting section (new accordion items)

### Phase 3: Interactive checklist (onboarding)

- [ ] **3.1** Create `app/javascript/controllers/checklist_controller.js` Stimulus controller with localStorage persistence
- [ ] **3.2** Rewrite `app/views/onboarding/_install_sgtm.html.erb` using checklist format with `data-controller="checklist"` wiring
- [ ] **3.3** Add progress indicator ("3 of 7 complete") at top of checklist
- [ ] **3.4** Add text input for sGTM server URL (persists to localStorage, helps user track their own setup state)
- [ ] **3.5** Manual QA: verify localStorage persistence across page refreshes and browser sessions

---

## Testing Strategy

### Manual QA

This is primarily a docs/UX change. Testing is manual:

1. Walk through the docs page end-to-end as someone with no sGTM experience
2. Verify all external links resolve (Stape, Addingwell, TAGGRS, Tracklution, Analytics Mania, MeasureSchool, Simo Ahava)
3. Verify the tabbed interface works (Stape tab, GCP tab, Other tab)
4. Verify the onboarding checklist:
   - Check/uncheck items → state persists on page refresh
   - Progress indicator updates correctly
   - "Reset progress" clears all state
   - Text input for server URL persists
5. Verify responsive layout on mobile (checklist, tabs, tables)
6. Verify the existing mbuzz tag setup steps (3-4) are untouched and still work

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Checklist controller initializes | `test/javascript/checklist_controller_test.js` | Controller connects, reads localStorage |
| Check persists to localStorage | `test/javascript/checklist_controller_test.js` | Checking item writes to `mbuzz-sgtm-checklist` key |
| Reset clears state | `test/javascript/checklist_controller_test.js` | All items unchecked, localStorage cleared |

### System Tests

| Test | File | Verifies |
|------|------|----------|
| Docs page renders sGTM section | `test/system/docs_test.rb` | Page loads without errors, key sections present |
| Onboarding sGTM checklist renders | `test/system/onboarding_test.rb` | Checklist items visible, checkboxes interactive |

---

## Definition of Done

- [ ] Step 1 rewritten with actual provider walkthroughs (Stape, GCP, others)
- [ ] DNS/domain setup documented with common pitfalls
- [ ] "Why custom domains matter" section added
- [ ] Honest time estimates at top of guide
- [ ] Video resources section with links to Analytics Mania, MeasureSchool, Simo Ahava
- [ ] Interactive checklist in onboarding with localStorage persistence
- [ ] All external links verified
- [ ] Manual QA on desktop + mobile
- [ ] No regressions in existing doc pages
- [ ] Spec updated with final state

---

## Out of Scope

- **Recording our own video tutorial** — Link to existing good ones first. Our own video is a separate content project (and should happen, but not as part of this docs rewrite).
- **Building sGTM hosting** — We document how to set it up, not host it ourselves.
- **Changing the mbuzz tag setup docs (Steps 3-4)** — Those are already well-structured. This spec only covers the server setup gap and the onboarding UX.
- **Stape/Addingwell/TAGGRS affiliate partnerships** — Worth exploring separately but doesn't affect the docs work.
- **sGTM integration spec changes** — That spec (`sgtm_integration_spec.md`) covers the tag template and backend. This spec fills the docs gap it explicitly called out of scope.

---

## Future Considerations

- **Own video tutorial** — 10-minute screencast: Stape signup → domain setup → mbuzz tag → first data in dashboard. Would dramatically reduce support burden.
- **In-app domain verification** — After user enters their sGTM URL in onboarding, ping `{url}/healthy` to confirm it's live before proceeding.
- **Stape partnership** — Co-branded setup guide or template pre-installed in Stape's marketplace.
- **sGTM setup status in dashboard** — Show whether the sGTM integration is actively sending data, with troubleshooting hints if not.
