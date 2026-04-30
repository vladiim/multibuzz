# Homepage + Landing Repositioning — Marketer ICP

**Date:** 2026-05-01
**Priority:** P1
**Status:** Draft
**Branch:** `feat/homepage-marketer-repositioning`

---

## Summary

The homepage and landing surfaces currently sell to developers ("Server-Side Multi-Touch Attribution", "Attribution DSL", SDK grid front-and-centre, comparison table benchmarked against Segment/Amplitude). Our actual ICP — performance / growth / lifecycle marketers and marketing technologists at $10k-$1m/mo media spend, mostly online sales — bounces because the messaging doesn't pattern-match. They are evaluating Dreamdata, Rockerbox, Northbeam, Triple Whale, HockeyStack, and "should we just keep using GA4". We have 24 comparison articles, a built-but-hidden Measurement Maturity Assessment, and a "Meta over-reports 134%" stat sitting in articles — and none of it reaches the homepage. This spec rewrites the hero, comparison block, pillars, and top nav so a $10k-$1m/mo marketer says **"this is me, and that's a problem I have"** within one second of landing.

---

## The ICP — Who We're Writing For

**Primary:** Performance Marketer / Growth Marketer / Marketing Technologist at a DTC ecom or SaaS company spending **$10k-$1m/month on paid acquisition**.

**Their day:**
- Logs into Meta Ads Manager. Sees 3.2x ROAS.
- Logs into Google Ads. Sees 4.1x ROAS.
- Adds them up. Compares to Shopify revenue. Numbers don't match. Off by 30-50%.
- Their CFO asks "where's the actual money coming from?"
- They open GA4. It shows different numbers again.
- They've already tried Triple Whale (too ecom-only) or Northbeam (too expensive) or Dreamdata (B2B-only) or are stuck in a 6-month Rockerbox sales cycle.

**The 1-second "this is me" trigger:** Lead with the **double-counting / platform-overreporting** villain. Every marketer in this segment has felt it. It is the most viscerally recognised pain in the category — Attribution.app's hero ("Ad platforms double-count revenue. Your CFO sees a loss while your marketer sees a profit") is the cleanest articulation we found in 16 competitors researched.

**The 1-second "and a problem I have" trigger:** Quantify it. We already have the stat: **Meta over-reports by 134%** (sourced in `app/content/articles/fundamentals/roas-inflation-platform-over-reporting.md.erb`). This number does the work.

---

## Current State

### Hero (`app/views/pages/home/_hero.html.erb`)

```
Eyebrow: "Server-Side Multi-Touch Attribution"  ← reads as developer jargon
H1:      "See what's actually driving revenue."  ← fine, keep
Subhead: "Independent attribution that captures 30-40% more of your customer
          journey. Server-side accuracy. Full transparency. Your data."
CTAs:    "Start" | "Try Demo"
Footnote:"SDKs for your favourite stack →"  ← developer signal
```

### Comparison (`app/views/pages/home/_comparison.html.erb`)

Compares mbuzz against **GA4, Segment, Amplitude** on rows: Server-side tracking, Custom attribution models (DSL), Compare models side-by-side, Real-time event debugging, Export raw data. **Wrong axis.** Marketers don't shortlist Segment vs Amplitude vs mbuzz — they shortlist Dreamdata vs Rockerbox vs Triple Whale vs Northbeam vs HockeyStack.

### Top Nav (`app/views/pages/home/_navigation.html.erb`)

`Demo · Features · Pricing · Docs · Login | Start` — no entry point to comparisons or the maturity assessment.

### Maturity Assessment

Built (`app/controllers/score/assessments_controller.rb`, route `GET /measurement-maturity-assessment`), but reachable only from inside one article's footer. Zero homepage / nav presence.

### Comparison Content

24 articles in `app/content/articles/comparisons/` (mbuzz vs GA4, Dreamdata, Cometly, Northbeam, HockeyStack, Triple Whale; alternatives + pricing pages for each). All exist for SEO; none are surfaced on the homepage.

---

## Competitor Pattern Library (Stolen Goods)

Researched 16 competitor homepages. The recurring patterns we should adopt:

| Pattern | Best example | What we steal |
|---------|--------------|---------------|
| **Villain naming** | Attribution.app: *"Ad platforms double-count revenue. Your CFO sees a loss while your marketer sees a profit."* | Lead the hero subhead with platform over-reporting as the villain. |
| **Pixel-blindness frame** | Hyros: *"Your pixel misses sales. We don't."* | Use as a pillar header. |
| **Anti-luck framing** | Motion: *"Make ads that win without getting lucky."* | Steal "without getting lucky" / "without guessing" verb pattern. |
| **Confidence as core emotion** | Triple Whale: *"Confidence unlocks everything."* / Mixpanel: *"instant answers on what's working"* | Use "confidence" / "know" / "stop guessing" in subheads. |
| **Specific dollar deltas** | Northbeam: *"37% increase in ROAS, 20% decrease in CAC, 14% increase in CVR"* | Anchor pillars in % deltas not features. Use our 134% Meta over-report stat. |
| **Trusted-by-N** | AppsFlyer 15k, Mixpanel 12k, Triple Whale 50k brands | We don't have these numbers yet. Skip until we do. Use "Built by ex-marketers" or specific case-study quote instead. |
| **Demo-first CTA** | Universal — Dreamdata, Rockerbox, Northbeam, HockeyStack, Cometly, Hyros all lead with Demo | Keep "Try Demo" but flip it primary; secondary becomes "Score your attribution (3 min)". |
| **Maturity quiz wedge** | Gartner Marketing Score, Marketing Alchemists Maturity Assessment, LiveRamp's 4-stage model | **None of the 9 direct attribution competitors own a Maturity Scorecard on their homepage.** This is open whitespace. |

The single biggest takeaway from the research: **no attribution platform is leading with a measurement maturity assessment on the homepage.** We have one built. Surfacing it is a category wedge, not just a UX tweak.

---

## Proposed Solution — Section by Section

### 1. Hero (`_hero.html.erb`)

Three variants. Recommendation: **Variant A**. All three lead with the double-counting villain.

#### Variant A — "Bank Account" *(recommended)*

```
Eyebrow:  FOR MARKETERS SPENDING $10K-$1M/MONTH
H1:       Attribution that matches your bank account.
Subhead:  Meta says you made $134K. Google says you made $98K. Your bank
          says $147K. mbuzz reconciles all three — so you stop guessing
          where the next dollar should go.
CTA1:     Score your attribution (3 min)  →  /measurement-maturity-assessment
CTA2:     Try the demo                    →  /demo
Footnote: No credit card. No signup to score.
```

*Why:* steals Attribution.app's killer line (the most visceral hero in the category) and pairs it with concrete numbers any marketer recognises. The maturity assessment as primary CTA is a no-friction first step that still qualifies the lead. "No signup to score" kills the "is this another gated demo trap?" objection.

#### Variant B — "Three Dashboards" *(close runner-up)*

```
Eyebrow:  STOP RECONCILING DASHBOARDS BY HAND
H1:       Three dashboards. Three different numbers. One source of truth.
Subhead:  Meta over-reports by 134%. Google double-counts. GA4 lost half
          your cookied users. mbuzz gives marketers spending $10k-$1m/mo
          one number they can take to the CFO.
CTA1:     Score your attribution (3 min)
CTA2:     Try the demo
```

*Why:* leads with the daily ritual every marketer in this segment recognises. Heavier on numbers, weaker on punchline.

#### Variant C — "Without Guessing" *(short, brand-forward)*

```
Eyebrow:  ATTRIBUTION FOR PERFORMANCE MARKETERS
H1:       Know what's working. Without guessing.
Subhead:  See real ROAS across Meta, Google, TikTok, and 40+ channels.
          Compare 8 attribution models side-by-side. Built for marketers
          spending $10k-$1m/mo who are done trusting platform reports.
CTA1:     Score your attribution (3 min)
CTA2:     Try the demo
```

*Why:* steals Motion's "without getting lucky" cadence. Less visceral than A/B but stronger brand line for ad reuse.

**Decision:** Variant A unless user picks otherwise. Variants B and C live in this spec as deliberate alternates the user can override.

---

### 2. New Section: "Sound familiar?" Problem Validation Block

Inserted **directly below the dashboard preview** (which sits under the hero). Three columns, each a quoted thought from the ICP's actual day:

```
"My Meta dashboard says 4.1x ROAS. My Shopify says it's barely 2x. Which one
is real?"
                                          — Every performance marketer, monthly

"GA4 attribution dropped from 7 models to 1. Now I can't compare anything."
                                          — Anyone migrating from UA, ongoing

"Dreamdata wants $750/mo. Rockerbox wants a 6-month sales cycle. Triple Whale
is e-com only. There's nothing in between."
                                          — Mid-market marketers, the gap
```

Below: a soft CTA — *"If any of those sound like your week, the 3-minute score will tell you exactly where you sit."* → maturity assessment.

*Pattern source:* problem-validation blocks on Common Room, Northbeam, and Cometly. Quoted-thought format is original.

---

### 3. Comparison Block (`_comparison.html.erb`) — Full Rewrite

Replace the GA4/Segment/Amplitude axis with the actual marketer shortlist.

```
HOW MBUZZ STACKS UP

                       mbuzz          GA4    Dreamdata  Rockerbox  Triple Whale  Northbeam
Starting price         $0 free,$29    Free   $750/mo    Custom     $129/mo       $999/mo
Attribution models     8              1      6          5          3             4
Models shown side-by-  ✓       ✗      ✓          ~          ✗             ✓
side
Multi-channel (not     ✓       ✓      ✓ (B2B)    ✓          ✗ (ecom)      ✓
just ecom or just B2B)
Self-serve onboarding  ✓       ✓      ✗          ✗          ✓             ✗
(no sales call)
Independent of ad      ✓       ✗      ✓          ✓          ✓             ✓
platforms
Compare to platform    ✓       ✗      ~          ✓          ~             ✓
ROAS
Time to first insight  Minutes Days   Weeks      Months     Hours         Weeks
```

Footer of table: *"Comparison sources: vendor pricing pages and our own [head-to-head reviews](/articles/comparisons). Last verified [DATE]."* — link to comparisons hub.

CTA below: `See the full breakdown →` → `/articles/comparisons`

*Notes for implementation:*
- Numbers must be sourced from the 24 existing comparison articles. Spot-check before shipping; vendors update pricing.
- 6 columns is wide. On mobile, collapse to a swipeable card-per-competitor with mbuzz fixed left.
- Use "~" (tilde) consistently for "partial / depends on plan" — matches existing convention in `_comparison.html.erb`.

*Pattern source:* category convention (every comparison page in our `/articles/comparisons` already uses this format). Bringing it to the homepage is the change.

---

### 4. Pillars Reframe (`_pillars.html.erb` / `_features.html.erb`)

Current pillars lead with: *Eight models, one view · Attribution DSL · Spend Intelligence · LTV mode.* Two of those four are tech-flexes.

Reframed pillars (marketer-language, problem-first headers):

| # | Header | Subhead | Maps to existing feature |
|---|--------|---------|--------------------------|
| 1 | **Where should your next $10k go?** | Spend Intelligence shows marginal ROAS, payback period, and the channel that's about to hit diminishing returns — before you scale into a wall. | Spend Intelligence |
| 2 | **Reconcile platform ROAS in one view.** | Meta over-reports by 134%. Google double-counts assisted conversions. mbuzz shows you the platform number, the mbuzz number, and the gap — for every channel, every week. | Attribution + ROAS reconciliation |
| 3 | **Eight models. One screen. Your call.** | First-touch, last-touch, linear, time-decay, position-based, U-shape, W-shape, data-driven. GA4 shows you one. We show all eight, side-by-side, so you can stop arguing about which one is "right". | 8-model comparison |
| 4 | **Rank channels by LTV, not first conversion.** | A channel that brings 6-month customers beats one that brings one-and-dones. LTV mode re-ranks every channel by cohort lifetime value. | LTV mode |

Demote the **Attribution DSL** pillar to a smaller "For advanced teams" footer block under the pillars: *"Need to express custom attribution logic? mbuzz has a SQL-like Attribution DSL. Most teams never need it. [Read the DSL docs →]"* — preserves the developer story without leading with it.

*Pattern source:* Northbeam's reduce-wasted-spend framing, Hyros's "your pixel misses" framing, Mixpanel's "instant answers on what's working".

---

### 5. Top Nav (`_navigation.html.erb`)

Current: `Demo · Features · Pricing · Docs · Login | Start`

Proposed: `Score Your Attribution · Compare · Demo · Pricing · Docs · Login | Start`

- **Score Your Attribution** → `/measurement-maturity-assessment` — links to the maturity assessment
- **Compare** → `/articles/comparisons` (or `/compare` if we want a real hub page later, see Out of Scope) — comparison hub
- Drop **Features** anchor link (the homepage flow IS the features tour now)
- Keep **Demo / Pricing / Docs / Login / Start** unchanged

Mobile menu mirrors the same order.

---

### 6. Maturity Assessment Surfacing — Beyond the Nav Link

Three placements, in order of importance:

1. **Hero secondary CTA** (covered in Variant A).
2. **Top nav link** (covered above).
3. **Dedicated homepage section** below pillars: *"Where does your team sit on the attribution maturity ladder?"*
   - Visual: 4-rung ladder (Level 1 Ad Hoc → Level 2 Operational → Level 3 Analytical → Level 4 Leader) using the existing `ScoreAssessment` framework.
   - One-liner per rung.
   - Soft stat (when we have it): *"47% of teams that take the score are at Level 2."* Until we have data, omit the stat — don't fabricate.
   - CTA: *"Score yourself in 3 minutes — no signup."*

The assessment landing page itself (`app/views/score/assessments/show.html.erb` and `app/views/score/dashboard/no_assessment.html.erb`) is **not** in scope for copy changes here — it converts at the rates it converts at. Driving traffic is the win.

---

### 7. SDK Grid — Demote, Don't Remove

Keep the SDK grid (it converts the developer who still ends up on the site), but move it below the pillars + maturity section. Section header changes from current developer framing to:

> **Already have a tag manager? You're ten minutes from data.**
> Drop one snippet via GTM, Shopify, or any of 12 SDKs. Server-side capture starts immediately.

This keeps the install story discoverable for marketing technologists (who often own GTM) without leading with it.

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Hero variant | A ("Bank Account") | Most visceral category-wide. Steals the strongest line we found. User can override. |
| Primary CTA | Maturity assessment | Lower friction than demo; qualifies + gates the email; nobody else in category does it. |
| Secondary CTA | Demo | Industry default. Don't fight it. |
| Comparison axis | Marketer shortlist (Dreamdata, Rockerbox, Triple Whale, Northbeam) | This is what they're actually evaluating. |
| GA4 in comparison | Yes, kept | Most visitors are migrating from / supplementing GA4. |
| Segment / Amplitude | Removed from homepage comparison | Wrong buyer. Move them to a `/compare/analytics-tools` page if needed later. |
| ICP qualifier in hero ($10k-$1m/mo) | Yes, in eyebrow or subhead | Self-qualifying. Keeps wrong-fit visitors from converting and clogging support. |
| Trusted-by-N social proof | Skip until we have a number we're proud to print | Don't fake / inflate / use a soft claim. The maturity score IS our differentiation, not logo count. |
| Maturity ladder section uses real % stat | No, until we have one | Memory + CLAUDE.md prohibit fabrication. Ship without; backfill when data exists. |
| Existing dashboard preview section | Keep | It's strong proof. No change. |
| Attribution DSL | Demoted to footer block | Was tech-flex; preserve for the few who need it. |
| New routes | None required | All targets exist (`/measurement-maturity-assessment`, `/articles/comparisons`, `/demo`, `/pricing`). |

---

## Acceptance Criteria

- [ ] Homepage hero uses Variant A copy (or user-selected variant) — verified by request to `/`
- [ ] Hero primary CTA links to `/measurement-maturity-assessment`
- [ ] Hero secondary CTA links to `/demo`
- [ ] "Sound familiar?" problem-validation block renders directly below hero with three quoted thoughts
- [ ] Comparison block columns are: mbuzz, GA4, Dreamdata, Rockerbox, Triple Whale, Northbeam (Segment + Amplitude removed)
- [ ] Comparison block "See full breakdown" link points to `/articles/comparisons`
- [ ] Pillars block leads with "Where should your next $10k go?" pillar; Attribution DSL demoted to a smaller advanced-teams footer
- [ ] Top nav contains in order: Score Your Attribution, Compare, Demo, Pricing, Docs, Login, Start (logged-out)
- [ ] Top nav "Score Your Attribution" links to `/measurement-maturity-assessment`
- [ ] Top nav "Compare" links to `/articles/comparisons`
- [ ] Mobile nav mirrors the same items in the same order
- [ ] Maturity ladder section renders below pillars with 4 rungs (Level 1-4) and CTA to `/measurement-maturity-assessment`
- [ ] SDK grid section moved below the maturity ladder section (currently above pillars)
- [ ] SDK grid section header updated to GTM/marketing-technologist framing
- [ ] No fabricated stats — every number on the page is sourced (existing articles, vendor pricing pages, our own data)
- [ ] All copy strings extracted to `config/locales/en.yml` under `pages.home.*` keys (matches existing convention; current `_navigation.html.erb` already uses i18n)
- [ ] Lighthouse / accessibility: comparison table is keyboard-navigable; mobile collapse uses semantic `<table>` not divs
- [ ] No regression in dashboard preview, footer, pricing page links

---

## Implementation Tasks

Ordered by leverage. Each row is a separate commit.

### Phase 1 — Highest Leverage (ship first, in order)

- [ ] **1.1** Hero rewrite (`_hero.html.erb` + `config/locales/en.yml`) — Variant A copy, primary CTA → maturity assessment, secondary → demo
- [ ] **1.2** Top nav rewrite (`_navigation.html.erb` + locales) — add "Score Your Attribution" + "Compare" links, drop Features anchor
- [ ] **1.3** "Sound familiar?" problem-validation partial (`_problem_validation.html.erb`) inserted in `home.html.erb` directly under hero

### Phase 2 — Comparison + Pillars

- [ ] **2.1** Rewrite `_comparison.html.erb` with marketer-axis columns; verify every cell against our own `/articles/comparisons/*` pages
- [ ] **2.2** Add mobile-collapse responsive treatment (swipeable cards)
- [ ] **2.3** Pillars rewrite — four marketer-language pillars; demote Attribution DSL to footer block

### Phase 3 — Maturity Surfacing

- [ ] **3.1** Add maturity ladder partial (`_maturity_ladder.html.erb`) below pillars with Level 1-4 visual + CTA
- [ ] **3.2** Move SDK grid section below maturity ladder; update section header copy

### Phase 4 — Verification

- [ ] **4.1** Manual QA on dev: visit `/`, verify all CTAs route correctly, mobile nav mirrors desktop, no broken anchor links
- [ ] **4.2** Cross-check every stat on the page against its source (Meta 134% over-report → article; competitor pricing → vendor pricing pages spot-checked the same week)
- [ ] **4.3** Update `lib/docs/PRODUCT.md` "Who it's for" section to reflect the explicit ICP ($10k-$1m/mo marketer)

---

## Out of Scope

- Dedicated `/compare` hub page (separate spec — for now we link the nav "Compare" item to `/articles/comparisons` index, which already lists every comp article).
- ICP-segmented landing pages (`/for-ecom`, `/for-saas`, `/for-agencies`) — separate spec; could come after this lands and we see which traffic sources convert.
- Pricing page rewrite — pricing copy can stay as-is; we're not repositioning the price.
- Maturity assessment internal copy / question rewording — driving traffic is the win; conversion-rate work on the assessment itself is a separate spec.
- Logo wall / "trusted by" social proof — skip until we have a number/logos we're proud to print. Adding fake/weak social proof reads worse than none.
- Case study insertion — when we have a public-named customer with a specific dollar delta ($X saved, Y% ROAS lift), drop it as a single banded testimonial above the comparison block. Until then, omit.
- Developer-focused `/developers` or `/install` split page — we're demoting, not removing, so a split page is premature.
- A/B test infrastructure — ship Variant A, watch the numbers, iterate. Don't pre-build A/B harness.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Repositioning loses developer-driven inbound (SDK searches, GitHub traffic) | Keep SDK grid + docs nav link. Demoted, not removed. Monitor `/docs` traffic for 4 weeks post-ship. |
| Marketer ICP doesn't convert better — just different | The Variant A primary CTA (3-min score, no signup) is the lowest-friction conversion in the category. If it doesn't move, the problem isn't the ICP — it's the assessment quality. Worth running. |
| Comparison numbers go stale (vendor pricing changes) | Add a "Last verified [DATE]" footer line on the table; calendar a quarterly review. |
| "Score Your Attribution" reads as spammy quiz-bait | Anchor it visually (small icon, professional treatment) and put "no signup" inline — the demo CTA is right next to it for serious buyers. |
| ICP qualifier in hero ($10k-$1m/mo) excludes legitimate smaller buyers | Eyebrow placement (small text) self-qualifies without slamming the door. Sub-$10k visitors who care will still scroll. |

---

## Internal Linking Map

Every quantified claim on the homepage links to the article that sources it. SEO bonus (homepage internal links to deep content) and credibility bonus (every number sourced). Use Rails route helpers — `article_path("slug")`, `academy_section_path("comparisons")`, `score_path` — never hardcode URLs.

| Claim / phrase | Anchor text | Route helper | Slug / target |
|---|---|---|---|
| **Hero subhead — Variant A** | "platform numbers don't reconcile" (or wrap "Meta says…/Google says…/bank says…") | `article_path` | `roas-inflation-platform-over-reporting` |
| **Problem block — Quote 1** ("Meta says 4.1x, Shopify says 2x") | "Which one is real?" | `article_path` | `platform-reports-dont-match` |
| **Problem block — Quote 2** ("GA4 dropped from 7 models to 1") | "dropped from 7 models to 1" | `article_path` | `ga4-attribution-models-removed` |
| **Problem block — Quote 3** — "$750/mo" | "$750/mo" | `article_path` | `dreamdata-pricing` |
| **Problem block — Quote 3** — "6-month sales cycle" | "6-month sales cycle" | `article_path` | `rockerbox-alternatives` |
| **Problem block — Quote 3** — "e-com only" | "e-com only" | `article_path` | `mbuzz-vs-triple-whale` |
| **Comparison column — GA4** | "Compare in detail →" under column header | `article_path` | `mbuzz-vs-ga4-attribution` |
| **Comparison column — Dreamdata** | same | `article_path` | `mbuzz-vs-dreamdata` |
| **Comparison column — Rockerbox** | same (no head-to-head exists yet) | `article_path` | `rockerbox-alternatives` |
| **Comparison column — Triple Whale** | same | `article_path` | `mbuzz-vs-triple-whale` |
| **Comparison column — Northbeam** | same | `article_path` | `mbuzz-vs-northbeam` |
| **Comparison block footer** | "See the full breakdown →" | `academy_section_path` | `"comparisons"` |
| **Pillar 1 — "next $10k"** | "diminishing returns" | `article_path` | `diminishing-returns-ad-spend` |
| **Pillar 1 — "next $10k"** | "payback period" / "marginal ROAS" | `article_path` | `budget-reallocation-attribution` |
| **Pillar 2 — Reconcile** | "Meta over-reports by 134%" | `article_path` | `roas-inflation-platform-over-reporting` |
| **Pillar 2 — Reconcile** | "Google double-counts" | `article_path` | `why-google-ads-ga4-different-conversions` |
| **Pillar 3 — Eight models** | "GA4 shows you one" | `article_path` | `ga4-attribution-models-removed` |
| **Pillar 3 — Eight models** | "side-by-side" / "the spread" | `article_path` | `multi-touch-attribution-tools-compared` |
| **Pillar 4 — LTV** | "lifetime value" / "cohort LTV" | `article_path` | `mta-vs-mmm` *(closest existing)* — TODO: write a dedicated LTV-by-channel article and re-point |
| **Maturity ladder section** | "ladder" / "Level 1-4" | `article_path` | `measurement-maturity-map` |
| **Maturity ladder CTA** | "Score yourself in 3 minutes" | `score_path` | (no slug) |
| **Top nav — Score Your Attribution** | "Score Your Attribution" | `score_path` | (no slug) |
| **Top nav — Compare** | "Compare" | `academy_section_path` | `"comparisons"` |

**Implementation notes:**
- Use `link_to` with `class: "underline decoration-dotted underline-offset-4 hover:decoration-solid hover:text-blue-600"` (or equivalent existing utility) so source links read as scholarly footnotes, not pushy CTAs. They're *credibility*, not the *action*.
- Don't link the same article twice in the same block — pick one anchor.
- All article slugs above are confirmed to exist (verified `app/content/articles/`).
- One placeholder: there's no dedicated LTV-by-channel article yet. Pillar 4 link points to `mta-vs-mmm` as the closest existing piece. Flag for follow-up content task.

---

## References

- Current homepage: `app/views/pages/home.html.erb` + partials in `app/views/pages/home/`
- The four marketer pillars are inline in `home.html.erb` (lines 45-111) via `landing_pages/lp_feature_showcase` — that's where the cell rewrite happens, not in `_pillars.html.erb` (which is a different "Built to give you the real picture" block — keep, lightly retitled if at all).
- Maturity assessment: `app/controllers/score/assessments_controller.rb`, route helper `score_path` → `/measurement-maturity-assessment`
- Existing comparison content: `app/content/articles/comparisons/` (22 files; full list in section 2 of audit)
- Source for "Meta over-reports 134%": `app/content/articles/fundamentals/roas-inflation-platform-over-reporting.md.erb` (frontmatter + TLDR carry the stat)
- `Article::SECTIONS = %w[fundamentals models comparisons implementation forecasting]` — `comparisons` is a recognised section, so `academy_section_path("comparisons")` is valid.
- Stolen line attribution:
  - "Attribution that matches your bank account" — attribution.app
  - "Without guessing / without getting lucky" cadence — motionapp.com
  - "Confidence" framing — triplewhale.com
  - "Your pixel misses sales" cadence — hyros.com
  - "Reduce wasted spend" framing — northbeam.io
- Maturity-quiz UX patterns to mirror: Marketing Alchemists (no email required), Gartner Marketing Score (peer-benchmarked output), LiveRamp's 4-stage model (level framing)
