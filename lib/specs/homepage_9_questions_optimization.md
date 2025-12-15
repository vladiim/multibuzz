# Homepage Optimization Spec: The 9 Questions Framework

## Overview

This spec outlines a comprehensive homepage optimization strategy based on the "9 Questions" framework that every visitor silently asks. The goal is to improve each question's score from current levels to 8/10.

---

## Part 1: Competitor & Market Research

### Key Competitors

| Tool | Target | Pricing | Key Differentiator |
|------|--------|---------|-------------------|
| **Northbeam** | $40M+ DTC brands | $400+/mo | ML-based attribution, "Northbeam Apex" for Meta |
| **Triple Whale** | Shopify stores | $300/mo | eComOS, Shopify-native, easier UX |
| **Rockerbox** | Enterprise B2C | $150+/mo | Podcast/TV/influencer tracking, customizable models |
| **Hyros** | Info products | $379+/mo (invite-only) | Call tracking, high-ticket funnels |
| **Funnel** | Enterprise | Custom | MTA + MMM + incrementality combined |
| **Segment** | Developers | $120+/mo | CDP focus, not attribution-first |
| **Amplitude** | Product teams | $61+/mo | Product analytics focus |

### Competitor Positioning Gaps mbuzz Can Exploit

1. **Price**: Northbeam/Hyros require $10K+ ad spend minimums. mbuzz free tier is unique.
2. **Transparency**: Most use black-box ML. mbuzz's AML editor is genuinely novel.
3. **Lock-in**: Competitors don't emphasize data export. mbuzz's "own it" angle is differentiated.
4. **Complexity**: Rockerbox/Northbeam have steep learning curves. mbuzz can win on simplicity.
5. **Server-side**: Only mentioned as add-on by competitors. mbuzz leads with it.

---

## Part 2: Reddit & Industry Pain Points

### GA4 Removal Backlash (Major Opportunity)

Google removed first-click, linear, time-decay, and position-based models in September 2023. Only last-click and data-driven remain.

**Marketer complaints:**
- "Takes away necessary and valuable insights"
- "DDA model will favor Google Ads, giving it more credit than other channels"
- "Fewer than 3% used rules-based models" (Google's justification) - but vocal minority is angry

**mbuzz angle:** "GA4 killed your model choice. We brought them back."

### Attribution Fatigue

From Built In article:
- Amanda Nielsen: "The marketing attribution problem is one that will never be solved"
- Samuel Brealey: "It's a bit of a fantasy" - B2B journeys have 60+ touchpoints
- Gartner: "60% of CMOs plan to cut marketing analytics teams"

**mbuzz angle:** Don't promise perfect attribution. Promise transparency and control.

### Platform Trust Issues

- "Facebook says Facebook works. Google says Google works."
- 80% of marketers concerned about bias in AdTech reporting
- Platforms over-report conversions (each claims credit)

**mbuzz angle:** Already addressed in "Why attribution is broken" section. Strengthen it.

### Ad Blocker Reality

- 30-40% data loss from client-side tracking
- iOS 14 caused 25-30% data loss
- "Privacy updates and adblockers cause Meta to miss 40%+ of purchases"

**mbuzz angle:** Server-side tracking is the hero. Lead with this harder.

### Tool-Specific Complaints

**Hyros:**
- "Setup nightmare - spent 6 months and 5+ setup calls"
- "Dropped $7,000 upfront - they denied my refund"
- Steep learning curve, no mobile app

**Northbeam:**
- "Only makes sense for $40M+ brands"
- "We'll be the first to admit we're at an ugly dashboard"
- Higher entry price

**Triple Whale:**
- Limited to major channels only
- Shopify-only

**mbuzz angle:** Simple setup, transparent pricing, works for smaller brands too.

---

## Part 3: Current Homepage Evaluation

### Scoring Summary

| # | Question | Current Score | Gap |
|---|----------|---------------|-----|
| 1 | Is this for me? | 5/10 | No explicit persona callout |
| 2 | Why care now? | 3/10 | No urgency messaging |
| 3 | Right solution? | 8/10 | Strong (comparison table) |
| 4 | What's new? | 7/10 | AML editor good but buried |
| 5 | Where's proof? | 4/10 | No testimonials, no logos |
| 6 | How does it work? | 4/10 | No step-by-step setup |
| 7 | What do others say? | 0/10 | Zero testimonials |
| 8 | What if it fails? | 2/10 | Free tier not framed as risk reversal |
| 9 | What next? | 6/10 | CTAs exist but generic |

---

## Part 4: Recommendations to Reach 8/10

### Question 1: Is this for me? (5 -> 8)

**Current:** "Stop renting your attribution. Own it."

**Problems:**
- Doesn't identify WHO this is for
- "Attribution" is jargon - not everyone knows they need it

**Recommendations:**

1. Add persona subhead below hero:
   ```
   "For SaaS and ecommerce growth teams who are tired of
   guessing which channels actually drive revenue."
   ```

2. Add "Is this for you?" callout section after hero:
   ```
   mbuzz is built for:
   - Growth marketers running $5K-$500K/mo in ads
   - SaaS teams tracking subscription attribution
   - Ecommerce brands beyond Shopify-only tools
   - Anyone who's been burned by GA4's black box

   Not for you if:
   - You only run one channel
   - You're happy with last-click
   ```

3. Use specific numbers in hero:
   ```
   "Stop renting your attribution. Own it."
   -> "See which channels actually drive your $X in monthly revenue."
   ```

**Implementation:**
- Edit `_hero.html.erb` to add persona subhead
- Create new partial `_is_this_for_you.html.erb` after hero

---

### Question 2: Why care now? (3 -> 8)

**Current:** No urgency messaging at all.

**Problems:**
- Page reads as "nice to have" not "must have now"
- No cost of inaction
- No industry trigger events

**Recommendations:**

1. Add urgency subhead in hero:
   ```
   "Every day without proper attribution, you're optimizing
   for the wrong channels."
   ```

2. Add "The Attribution Crisis" mini-section after hero:
   ```
   The problem is getting worse:
   - GA4 removed 4 attribution models in 2023
   - iOS 14+ blocks 30% of your tracking
   - Cookie deprecation accelerates in 2025
   - Your competitors are already switching
   ```

3. Add cost calculator or stat:
   ```
   "The average ecommerce brand wastes $X,XXX/month
   on the wrong channels due to bad attribution."
   ```

4. Add social proof of momentum:
   ```
   "127 teams switched to mbuzz this month"
   ```

**Implementation:**
- Add urgency line to `_hero.html.erb`
- Create `_urgency_section.html.erb` or integrate into existing section

---

### Question 3: Right solution? (8 -> 9)

**Current:** Strong comparison table vs GA4, Segment, Amplitude.

**Recommendations to perfect:**

1. Add Northbeam/Triple Whale to comparison (real competitors)
2. Add pricing row showing mbuzz free tier vs $300-400/mo competitors
3. Add "switching from" section:
   ```
   "Switching from GA4? Here's what you get back..."
   "Switching from Northbeam? Here's what you save..."
   ```

**Implementation:**
- Update `_comparison.html.erb` to add competitors and pricing row

---

### Question 4: What's new? (7 -> 8)

**Current:** AML editor exists but comes late in page. LTV leaderboard is compelling.

**Recommendations:**

1. Move AML editor showcase higher (before features, not after)
2. Add explicit "What makes mbuzz different" section:
   ```
   Unlike other tools:
   - Write your own attribution rules (not just pick from presets)
   - Server-side first (not client-side with server-side add-on)
   - Compare any model side-by-side
   - Export raw data anytime (no enterprise upgrade required)
   ```

3. Emphasize the GA4 model recovery angle:
   ```
   "GA4 killed first-touch, linear, and time-decay.
   We brought them back. Plus you can build your own."
   ```

**Implementation:**
- Reorder partials in `home.html.erb`
- Add "What's different" callout to `_aml_editor.html.erb`

---

### Question 5: Where's proof? (4 -> 8)

**Current:** Dashboard mockup only. No real proof.

**Recommendations:**

1. **Add customer logos** (even 3-4 helps):
   ```
   "Trusted by growth teams at [Logo] [Logo] [Logo] [Logo]"
   ```

2. **Add metrics proof:**
   ```
   "Tracking 10M+ events monthly"
   "500+ accounts created"
   "95% data capture rate vs 70% industry average"
   ```

3. **Add case study snippets** (even before full testimonials):
   ```
   "Company X discovered their 'worst' channel
   delivered 21x more LTV than their 'best' one."
   ```

4. **Add integration proof:**
   ```
   "Works with Stripe, Shopify, WooCommerce..."
   ```

**Implementation:**
- Create `_social_proof.html.erb` partial (logos + metrics)
- Add below hero or after comparison table

---

### Question 6: How does it work? (4 -> 8)

**Current:** SDK section shows languages but no implementation journey.

**Recommendations:**

1. **Add 3-step setup section:**
   ```
   1. Sign up (2 minutes)
      "Create your account. No credit card required."

   2. Add our SDK (5 minutes)
      [Show 3-line code snippet]
      "Works with Rails, Node, Python, PHP..."

   3. See data flowing (instant)
      [Show live debugger screenshot]
      "Watch events arrive in real-time."
   ```

2. **Add time-to-value messaging:**
   ```
   "Most teams are tracking in under 10 minutes."
   ```

3. **Show the debugger:**
   Screenshot of real-time event stream in the dashboard.

**Implementation:**
- Create `_how_it_works.html.erb` partial with 3-step visual
- Place before SDKs section or replace it

---

### Question 7: What do others say? (0 -> 8)

**Current:** Zero testimonials.

**Recommendations (prioritized by effort):**

1. **Immediate (when you get testimonials):**
   - 3 testimonials with photo, name, company, role
   - Focus on specific outcomes: "Discovered our podcast ads drove 3x more LTV"
   - Place after "How it works" section

2. **Testimonial format:**
   ```
   "[Specific outcome achieved with mbuzz]"

   - Name, Role at Company
   [Photo]
   ```

3. **Types of testimonials to collect:**
   - "Switched from GA4" story
   - "Discovered hidden channel value" story
   - "Setup was easy" story
   - "Finally understand my attribution" story

4. **Fallback if no testimonials yet:**
   - Twitter/X embed of early user praise
   - G2/Capterra review snippets
   - "Beta user feedback" section

**Implementation:**
- Create `_testimonials.html.erb` partial
- Place prominently (after pillars or after how-it-works)

---

### Question 8: What if it doesn't work? (2 -> 8)

**Current:** Free tier exists but not framed as risk removal.

**Recommendations:**

1. **Reframe free tier as guarantee:**
   ```
   "Try free. Forever."

   Free up to 50K events/month. No credit card required.
   No setup fees. No contracts. Cancel anytime.

   If mbuzz doesn't show you insights you couldn't
   see before, you've lost nothing.
   ```

2. **Add explicit guarantees:**
   ```
   - No credit card required to start
   - 14-day free trial on paid plans
   - Export your data anytime (no lock-in)
   - Cancel in one click
   ```

3. **Add "What if" FAQ:**
   ```
   Q: What if I don't have enough traffic?
   A: Our free tier covers up to 50K events/month.
      Most small sites never need to upgrade.

   Q: What if I can't figure out the setup?
   A: We'll help. Book a free 15-minute setup call.

   Q: What if I want to leave?
   A: Export everything. We don't hold your data hostage.
   ```

**Implementation:**
- Update `_pricing.html.erb` to emphasize risk reversal
- Add guarantee badges/icons
- Create `_faq.html.erb` partial

---

### Question 9: What do I do next? (6 -> 8)

**Current:** Generic "Get Started Free" CTAs.

**Recommendations:**

1. **Make CTAs specific:**
   ```
   "Get Started Free" -> "Start tracking in 5 minutes"
   "Try It Free" -> "See your first attribution report today"
   ```

2. **Add multiple paths:**
   ```
   Primary: "Start Free" (for doers)
   Secondary: "See a Demo" (for researchers)
   Tertiary: "Book a Setup Call" (for hand-holders)
   ```

3. **Final CTA section rewrite:**
   ```
   Ready to own your attribution?

   [Start Free - No credit card required]

   Or: Book a 15-minute demo | Read the docs

   "Most teams are tracking in under 10 minutes."
   ```

4. **Add sticky header CTA:**
   After scrolling past hero, show persistent "Start Free" button.

**Implementation:**
- Update CTA text in all partials
- Update `_cta.html.erb` final section
- Consider adding sticky header CTA in `_navigation.html.erb`

---

## Part 5: Implementation Priority

### Phase 1: Quick Wins (1-2 hours each)
1. Update hero with persona subhead and urgency line
2. Reframe pricing section with risk reversal language
3. Update all CTA button text to be specific
4. Add "What's different" callout to AML editor section

### Phase 2: New Sections (2-4 hours each)
5. Create "How it works" 3-step section
6. Create social proof section (logos + metrics placeholders)
7. Add competitor pricing to comparison table

### Phase 3: Content Needs (Requires external input)
8. Testimonials section (waiting on testimonials)
9. Customer logos (need permission)
10. Case study snippets (need data)

### Phase 4: Advanced
11. Sticky header CTA
12. "Is this for you?" qualification section
13. FAQ section

---

## Part 6: Files to Modify

```
app/views/pages/home.html.erb          # Reorder partials
app/views/pages/home/_hero.html.erb    # Add persona + urgency
app/views/pages/home/_pricing.html.erb # Risk reversal framing
app/views/pages/home/_cta.html.erb     # Specific CTA text
app/views/pages/home/_comparison.html.erb # Add competitors
app/views/pages/home/_aml_editor.html.erb # "What's different" callout

# New partials to create:
app/views/pages/home/_how_it_works.html.erb
app/views/pages/home/_social_proof.html.erb
app/views/pages/home/_testimonials.html.erb (when ready)
app/views/pages/home/_faq.html.erb (optional)
```

---

## Part 7: Success Metrics

After implementation, measure:
- Signup conversion rate (current baseline needed)
- Time on page
- Scroll depth
- CTA click-through rates
- Signup -> first event tracked rate

---

## Part 8: Copy Bank (Ready-to-Use)

### Hero Options

**Option A (Persona-first):**
```
Server-Side Multi-Touch Attribution

Stop renting your attribution. Own it.

For SaaS and ecommerce growth teams who are tired of
guessing which channels actually drive revenue.
```

**Option B (Problem-first):**
```
Server-Side Multi-Touch Attribution

Your attribution tool is lying to you.

Black-box models. Inflated platform ROAS. Data you can't export.
mbuzz gives you the truth - and the tools to act on it.
```

**Option C (GA4 angle):**
```
Server-Side Multi-Touch Attribution

GA4 killed your attribution models.
We brought them back.

First-touch, linear, time-decay - all the models Google removed.
Plus: build your own with our simple editor.
```

### CTA Options

- "Start tracking in 5 minutes"
- "See your first attribution report today"
- "Try free - no credit card"
- "Get the truth about your channels"

### Urgency Lines

- "Every day without proper attribution, you're optimizing for the wrong channels."
- "Your competitors already switched. Here's why."
- "30% of your tracking data is missing. We fix that."

### Risk Reversal

```
Try free. Forever.

- Free up to 50K events/month
- No credit card required
- Export your data anytime
- Cancel in one click

If mbuzz doesn't show you something new, you've lost nothing.
```

---

## Sources

- [Funnel MTA Tools 2025](https://funnel.io/blog/top-mta-tools-2025)
- [Built In: Attribution Obsession](https://builtin.com/articles/multi-touch-marketing-attribution-problem)
- [SparkToro: Attribution is Dying](https://sparktoro.com/blog/attribution-is-dying-clicks-are-dying-marketing-is-going-back-to-the-20th-century/)
- [QRY: Northbeam vs Rockerbox vs Triple Whale](https://www.weareqry.com/blog/marketing-attribution-tools-northbeam-vs-rockerbox-vs-triple-whale)
- [Search Engine Land: GA4 Attribution Models Removed](https://searchengineland.com/google-when-retire-attribution-models-ads-analytics-428541)
- [Hyros Pricing Compared](https://segmetrics.io/articles/hyros-pricing-compared/)
- [SegmentStream: Rockerbox Alternatives](https://segmentstream.com/blog/articles/rockerbox-alternatives)
