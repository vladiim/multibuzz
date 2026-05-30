# Closed-Loop Attribution — Positioning & Surfacing Specification

**Date:** 2026-05-30
**Priority:** P1
**Status:** Draft
**Branch:** `feature/closed-loop-attribution`

---

## Summary

mbuzz can already attribute a conversion posted with **only a `user_id`** — no cookie, no
browser, no live session. That single capability lets a customer map an **offline conversion**
(a closed-won deal in Salesforce, a Stripe webhook, a CRM record, a phone order) back to the
**online journey** that produced it, across every device, even weeks later — and it re-runs
attribution automatically if the offline conversion arrives before the online journey is linked.

The capability ships. The **positioning does not exist.** Today it's a buried line in the
"Identity Profiles" pillar. This spec names the capability **"closed-loop attribution"**, makes
it a first-class story on the homepage, and builds a supporting content cluster. Strategically,
it graduates mbuzz from a performance-marketing ROAS reconciler into the attribution tool that
works **whether revenue closes online or offline** — which is the structural unlock for the
entire B2B / sales-assisted ICP that the comparison grid already claims ("Works ecom AND B2B").

This is a **positioning + content** spec. No new product code is required for the core claim;
the work is messaging, homepage surfaces, and articles. A small set of optional product
hardening items is listed in Out of Scope.

---

## Positioning Thesis (the decision this spec commits to)

**Question raised:** Does *"Attribution that matches your bank account"* line up with the whole
product, and is it the meatiest problem?

**Decision:** Keep the bank-account hero line as the **primary acquisition hook** — it is
concrete, emotionally charged, and converts the ecom/performance ICP. But it is a **segment
hook, not the product thesis.** It frames mbuzz as a reconciliation tool and is nearly
meaningless to B2B buyers (whose revenue closes in a CRM, not on the website).

The **meatiest universal problem** sits one level up:

> Your revenue and your marketing data live in different worlds. The sale closes in your bank,
> Stripe, or CRM; the marketing that earned it is scattered across devices, channels, and weeks —
> and nothing connects the two.

- *"Matches your bank account"* is the **ecom face** of that problem.
- *"Closed-loop attribution"* is the **B2B / offline face** of the same problem.

**Consequence for this spec:** closed-loop attribution is positioned as a **co-equal pillar**
to ROAS reconciliation, not a sub-bullet. A candidate umbrella line both ladder up to —
*"Connect every dollar of revenue back to the marketing that earned it, wherever it closes"* —
is proposed for the hero eyebrow / meta, but the existing H1 stays. Final umbrella wording is a
stakeholder decision (see Open Questions).

---

## Current State

### The capability (already shipping)

| Flow | File | Behavior |
|------|------|----------|
| Conversion with `user_id` only | `app/services/conversions/tracking_service.rb:54-66, 108-138` | Accepts `user_id` as a sole identifier; finds-or-creates the identity and a visitor; stamps `identity_id` on the conversion. |
| Identity → prior sessions | `app/services/identities/identification_service.rb:24-92` | `/identify` links a browser visitor to an identity (`external_id = user_id`); merges traits; hashes PII. |
| Auto re-attribution | `app/services/identities/identification_service.rb:99-115` + `app/services/conversions/reattribution_service.rb` | When a journey links to an identity that already has conversions, attribution is recomputed (`trigger: :identity_merge`). |
| Cross-device journey | `app/services/attribution/cross_device_journey_builder.rb:28-48` | Builds one journey from **all** visitors linked to the identity, within the lookback window. |
| PII hashing | `app/services/identities/normaliser.rb:54-64` | Email / phone / name normalized + SHA-256 before storage and ad-platform sync. |
| Docs reference | `lib/docs/BUSINESS_RULES.md` (conversion identifiers), `lib/specs/conversion_user_id_identifier.md` | The `user_id`-as-sole-identifier rule. |

### The positioning gap

- Homepage (`app/views/pages/home/`): no dedicated closed-loop / offline section. The
  capability is implied only by the "Identity Profiles" column in `_pillars.html.erb`.
- Comparison grid (`_comparison.html.erb`): claims "Works ecom AND B2B" with **no row that
  proves it**. Triple Whale is marked ecom-only but we never show *why we're different*.
- Content: `dark-funnel-untrackable-attribution` and `b2b-attribution-long-sales-cycles`
  articles describe the problem but point to **no feature** as the answer.
- No article owns the search terms "offline conversion tracking", "closed-loop attribution",
  "salesforce attribution", "hubspot closed-won attribution".

---

## How It Works (the accurate, plain-English claim)

The one honest constraint that shapes all copy: **the same `user_id` must appear in both
worlds.** A login/signup/`identify` call ties a browser session to an ID online; the offline
system posts the conversion keyed by that **same** ID. mbuzz does the stitching. It does **not**
auto-match an anonymous stranger by email/phone — identity must be declared at least once.

Both timelines work:

```
ONLINE-FIRST
  Day 1   Visitor browses (Google Paid Search), logs in → identify(user_id, visitor_id)
  Day 45  Deal closes in CRM → POST /conversions { user_id, conversion_type, revenue }
          → journey already linked; Paid Search credited immediately

OFFLINE-FIRST
  Day 1   Importer posts conversion { user_id } → recorded, 0 credit (no sessions yet)
  Day 3   Visitor browses + logs in → identify(user_id, visitor_id)
          → reattribution runs automatically; the Day-1 conversion is re-credited
```

---

## Proposed Solution

### Naming

- **Concept / brand term:** "Closed-loop attribution" (industry-recognized; B2B buyers search it).
- **Feature / SEO label:** "Offline conversions" / "offline conversion tracking".
- **Avoid in marketing copy:** "identity resolution" (too CDP-coded / technical).

### A. Homepage

| # | Surface | File | Change |
|---|---------|------|--------|
| A1 | New section | `app/views/pages/home/_closed_loop.html.erb` (new) | Dedicated closed-loop story: headline, 3-step flow, the literal 2-field POST snippet, demo CTA + docs link. Rendered in `home.html.erb` between `_problem_validation` and the feature showcase. |
| A2 | Comparison row | `app/views/pages/home/_comparison.html.erb` | Add row **"Attributes offline / CRM conversions"** → mbuzz ✓, Triple Whale ✗, GA4 ✗, Northbeam ~. Highlight row (blue). |
| A3 | Problem validation | `app/views/pages/home/_problem_validation.html.erb` | Add a 4th quote in the existing blockquote style: *"Our deals close in HubSpot six weeks after the last click. GA4 shows 'direct/none' and Triple Whale doesn't even try."* |
| A4 | Hero eyebrow | `app/views/pages/home/_hero.html.erb` | Broaden the eyebrow to signal online **and** offline revenue so B2B self-identifies. H1 unchanged. |
| A5 | Copy | `config/locales/en.yml` | Any new homepage strings follow the existing locale pattern. |

**Frontend approach (per GUIDE decision tree):** server-rendered ERB partials only. Reuse the
existing demo **modal** pattern (`modal_frame_id` / `modal_partial`) and the `scroll-reveal`
Stimulus controller already used across the homepage. **No new Stimulus controller.** Match the
existing Tailwind system (max-w-7xl, blue-600 primary, `prose-pre` dark for the code card,
3-col grid for the steps).

### B. Content cluster

New articles (frontmatter + AEO pattern per existing `app/content/articles/**`):

| # | Slug | Section | Schema | Target query |
|---|------|---------|--------|--------------|
| B1 | `closed-loop-attribution` | fundamentals | Article | "what is closed-loop attribution" |
| B2 | `offline-conversion-tracking` | fundamentals | Article | "offline conversion tracking" |
| B3 | `crm-attribution-salesforce-hubspot` | implementation | HowTo (`has_code_examples: true`) | "salesforce attribution", "hubspot closed-won attribution" |
| B4 | `b2b-offline-conversion-attribution` | fundamentals | Article | "b2b offline conversion attribution" |

Rewire existing articles to link **into** the cluster (add an internal-link section + update
`related_articles` frontmatter):

- `dark-funnel-untrackable-attribution` → "how to actually capture it"
- `b2b-attribution-long-sales-cycles` → the CRM-close walkthrough (B3)
- `server-side-vs-client-side-tracking` → cookieless conversion as the payoff
- `mbuzz-vs-triple-whale`, `mbuzz-vs-northbeam` → "ecom-only vs. closes-the-loop" angle

**Voice:** problem-first opener, one specific metric, balanced full-disclosure framing, a code
block (the 2-field POST), FAQ schema — matching the existing 56-article house style.

### C. Business docs

- `lib/docs/PRODUCT.md`: add closed-loop attribution as a named capability (new major capability
  → required per GUIDE "Business Documentation").
- `lib/docs/BUSINESS_RULES.md`: ensure the offline-conversion / reattribution rule is stated in
  plain language with the online+offline same-`user_id` constraint and the lookback note.

---

## Claims & Constraints (what marketing MAY and MUST NOT say)

| State | We CAN claim | We MUST NOT claim |
|-------|--------------|-------------------|
| Same `user_id` online + offline | "Connect offline conversions to the full online journey." | — |
| Cross-device | "Stitches desktop, mobile, and tablet sessions into one journey." (`cross_device_journey_builder.rb:28`) | — |
| Offline-first ordering | "Self-healing — attribution recomputes when the journey links later." (`reattribution_service.rb`) | "Real-time" for the offline-first case (it's async/eventual). |
| Anonymous, never identified | — | "Auto-match a stranger by email/phone." Identity must be declared once via `/identify`. |
| Lookback | Default 90-day window; configurable. | "Unlimited history." |
| No online sessions at all | "Recorded as a conversion." | "Attributed." (zero sessions → zero credit; must set this expectation.) |
| Privacy | "Email/phone/name are SHA-256 hashed before storage and ad-platform sync." (`normaliser.rb:54`) | "Anonymous" / "no PII stored" (raw traits persist in JSONB for compatibility). |

---

## Implementation Tasks

### Phase 1 — Homepage (highest leverage)
- [ ] **1.1** Build `_closed_loop.html.erb` (copy + 3-step flow + POST snippet + demo modal CTA).
- [ ] **1.2** Wire it into `home.html.erb` in the agreed position.
- [ ] **1.3** Add the comparison row (A2) and the 4th problem-validation quote (A3).
- [ ] **1.4** Broaden the hero eyebrow (A4); move any strings to `en.yml`.
- [ ] **1.5** Render test: homepage renders, section present, demo modal opens, mobile layout intact.

### Phase 2 — Pillar content
- [ ] **2.1** Write B1 `closed-loop-attribution` and B2 `offline-conversion-tracking`.
- [ ] **2.2** Write B3 `crm-attribution-salesforce-hubspot` (HowTo, code example = the 2-field POST).
- [ ] **2.3** Validate frontmatter parses and JSON-LD schema renders.

### Phase 3 — Rewire + B2B article
- [ ] **3.1** Write B4 `b2b-offline-conversion-attribution`.
- [ ] **3.2** Add inbound links + `related_articles` updates to the four existing articles.

### Phase 4 — Business docs
- [ ] **4.1** Update `PRODUCT.md` and `BUSINESS_RULES.md`.

---

## Testing Strategy

### Render / content tests
| Test | File | Verifies |
|------|------|----------|
| Homepage renders with closed-loop section | `test/controllers/pages_controller_test.rb` (or existing home test) | Section partial present; no template errors. |
| New articles load | `test/models/article_test.rb` / articles controller test | Frontmatter parses; slugs resolve; `related_articles` valid. |
| Schema validity | article render test | JSON-LD blocks well-formed for Article/HowTo. |

### Manual QA
1. Load `/` on desktop + mobile; confirm the closed-loop section, comparison row, and 4th quote.
2. Open the closed-loop demo modal.
3. Visit each new article; confirm TLDR, code block, FAQ, and inbound links from the rewired articles.

### Marketing-analytics sensitivity (per GUIDE)
These are **public marketing pages** — they **should** load GTM/GA4/Meta as normal. **No
`skip_marketing_analytics`** is required, and no new sensitive routes are introduced.

---

## Definition of Done
- [ ] Homepage surfaces closed-loop attribution as a co-equal pillar; comparison row + quote live.
- [ ] Four new articles published; four existing articles link inward.
- [ ] `PRODUCT.md` + `BUSINESS_RULES.md` updated.
- [ ] All copy passes the Claims & Constraints table (no overclaiming).
- [ ] Tests pass; no regressions; homepage renders on mobile.
- [ ] Spec updated with final wording decisions; moved to `old/` when complete.

---

## Open Questions
1. **Umbrella line:** adopt *"Connect every dollar of revenue back to the marketing that earned it, wherever it closes"* as hero eyebrow / meta thesis? (H1 stays regardless.) — stakeholder call.
2. **Comparison row label:** "Attributes offline / CRM conversions" vs "Closed-loop attribution" — which reads better cold?
3. **Demo asset:** reuse an existing dashboard screenshot, or produce a journey-stitching visual showing offline → online linkage?

---

## Out of Scope
- **No auto email/phone matching** of anonymous visitors — explicitly not building identity
  resolution beyond declared `user_id`. (Stated as a constraint, not a roadmap item.)
- **No reverse-ETL / warehouse / CDP** positioning — mbuzz is not a CDP; do not imply it.
- **No new SDK or ad-platform adapter** — uses the existing `/conversions` + `/identify` API.
- **Optional product hardening (separate spec if pursued):** native Salesforce/HubSpot
  connectors, a bulk offline-conversion CSV importer, configurable lookback in the UI. None are
  required for this positioning launch.
