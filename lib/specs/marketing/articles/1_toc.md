# Multibuzz Knowledge Base: Article Table of Contents

**Purpose**: Comprehensive content library covering customer problems and Multibuzz's POV on multi-touch attribution (MTA).

**Status**: Research Complete | Prioritization Pending
**Last Updated**: 2025-11-29

---

## Executive Summary: MTA Issues & Pitfalls Discovered

### The Core Problems Customers Face

1. **Data Quality Crisis**: Pixels and cookies generate data that's ~80% incorrect. Traditional analytics platforms can't attribute it accurately.

2. **Privacy Apocalypse**: GDPR, CCPA, iOS ATT (25% opt-in rates), Safari/Firefox blocking cookies. The "$50 billion attribution problem."

3. **Platform Bias**: Google, Meta, Amazon self-report inflated ROAS. Walled gardens limit cross-platform visibility.

4. **Cross-Device Blindness**: Most visitors don't log in (<30% on ecommerce). Can't connect phone → laptop → tablet journeys.

5. **Ad Blocker Data Loss**: 25-30% of web traffic uses ad blockers. Client-side tracking captures only ~80% of events.

6. **Last-Click Tunnel Vision**: 56 touchpoints average before purchase, but credit goes to the final click.

7. **Model Selection Paralysis**: GA4 removed most models (May 2023). Only last-click and data-driven remain.

8. **B2B Complexity**: 211-day average sales cycles, 6-10 stakeholders per deal, 30-day attribution windows are useless.

9. **Dark Social Black Hole**: 84-95% of sharing happens in untrackable channels (WhatsApp, Slack, email, DMs).

10. **Measurement Fragmentation**: MTA, MMM, incrementality testing all solve different problems. No single source of truth.

---

## Multibuzz POV Summary

| Problem | Industry Status | Multibuzz Approach |
|---------|-----------------|-------------------|
| Ad blockers | Accept data loss | Server-side first (captures ~95%+) |
| Cross-device | Probabilistic guessing | Identity resolution via `identify()` |
| Platform bias | Trust self-reported data | Independent measurement |
| Model complexity | Black-box ML | Transparent, configurable models |
| GA4 limitations | Work around it | Purpose-built alternative |
| B2B long cycles | Ignore or estimate | Configurable lookback windows |
| Dark social | Call it "direct" | UTM best practices + self-reported |
| Privacy | Retrofitting consent | First-party by design |

---

## Content Roadmap

### Phase 0: Hygiene Pages (Pre-Launch)
Legal and trust-building pages required before any marketing.

### Phase 1: Foundation Content (Pre-Launch)
P0 articles that support product and SEO baseline.

### Phase 2: Competitor Pages (Post-Launch)
High-intent comparison landing pages.

### Phase 3: Landscape Survey (Post-Competitor Pages)
Industry research for outreach and authority.

### Phase 4: SEO Growth (Ongoing)
P1/P2 articles for organic traffic.

---

## Category 0: Hygiene Pages (Required Pre-Launch)

| # | Page | Purpose | Priority | Status | Location |
|---|------|---------|----------|--------|----------|
| 0.1 | **About Us** | Company story, mission, team | P0 | Done | `app/views/pages/about.html.erb` |
| 0.2 | **Privacy Policy** | Legal requirement, GDPR/CCPA compliance | P0 | Done | `app/views/pages/privacy.html.erb` |
| 0.3 | **Terms of Service** | Legal requirement, user agreement | P0 | Done | `app/views/pages/terms.html.erb` |
| 0.4 | **Cookie Policy** | Required for EU visitors | P0 | Done | `app/views/pages/cookies.html.erb` |
| 0.5 | **Acceptable Use Policy** | API/SDK usage terms | P1 | Planned | |
| 0.6 | **Data Processing Agreement (DPA)** | B2B/enterprise requirement | P1 | Planned | |
| 0.7 | **Security & Compliance** | Trust page (SOC2, encryption, etc.) | P1 | Planned | |
| 0.8 | **Contact Us** | Simple contact form | P0 | Done | `app/views/contacts/new.html.erb` |

**Notes:**
- Privacy Policy and Terms must be live before collecting any user data
- About page builds trust for cold outreach
- Security page important for enterprise sales

---

## Category 11: Landscape Survey & Research Report

**Purpose**: Outreach vehicle + content asset + lead generation

### Survey: "State of Marketing Attribution 2025"

| # | Asset | Description | Priority | Status |
|---|-------|-------------|----------|--------|
| 11.1 | **Survey Questions Document** | 10-12 questions, 5 min completion | P1 | Planned |
| 11.2 | **Survey Landing Page** | Typeform/Google Form embed + value prop | P1 | Planned |
| 11.3 | **Outreach Templates** | LinkedIn message, email sequences | P1 | Planned |
| 11.4 | **Results Report (Full)** | Gated PDF, 15-20 pages with analysis | P1 | Planned |
| 11.5 | **Results Report (Summary)** | Ungated blog post, key findings | P1 | Planned |
| 11.6 | **Infographic** | Visual summary for social sharing | P2 | Planned |
| 11.7 | **Press Release** | For PR outreach when results publish | P2 | Planned |

### Survey Strategy

**Outreach Flow:**
```
LinkedIn connect → Survey invite →
Results preview → "How does your data compare?" →
Soft pitch / demo offer
```

**Target Respondents:**
- Marketing managers/directors
- Growth leads
- Marketing ops / RevOps
- Agency strategists
- Ecommerce managers

**Incentives:**
- Early access to full report
- Benchmark comparison ("see how you compare")
- Optional: Free attribution audit / consultation

### Proposed Survey Questions

| # | Question | Type | Purpose |
|---|----------|------|---------|
| 1 | What's your primary role? | Multiple choice | Segmentation |
| 2 | Company size (employees)? | Multiple choice | Segmentation |
| 3 | Industry/vertical? | Multiple choice | Segmentation |
| 4 | What attribution tool(s) do you currently use? | Multi-select | Competitive intel |
| 5 | How satisfied are you with your current attribution? (1-10) | Scale | Pain identification |
| 6 | What's your biggest attribution challenge? | Multi-select | Content priorities |
| 7 | Which attribution model do you primarily use? | Multiple choice | Education gaps |
| 8 | How has GA4 transition affected your measurement? | Multiple choice | Timely pain point |
| 9 | How do you handle cross-device attribution? | Multiple choice | Feature validation |
| 10 | What % of your marketing budget do you confidently attribute? | Multiple choice | Problem quantification |
| 11 | What would make you switch attribution tools? | Open text | Sales intel |
| 12 | Want early access to results + a free attribution audit? | Email capture | Lead gen |

### Timeline (Post-Competitor Pages)

| Week | Activity |
|------|----------|
| 1 | Finalize questions, build survey |
| 2-4 | Outreach campaign (target: 200+ responses) |
| 5 | Analyze results, draft report |
| 6 | Publish summary blog, gate full report |
| 7+ | PR outreach, social promotion |

---

## Article Categories

### Category 1: MTA Fundamentals (Pillar Content)
*High SEO value, evergreen, link from product*

### Category 2: Attribution Model Deep-Dives
*Technical education, model selection guidance*

### Category 3: Platform & Tool Comparisons
*High-intent buyers, vs competitor searches*

### Category 4: Technical Implementation
*Developer audience, SDK adoption*

### Category 5: Industry-Specific Guides
*B2B, eCommerce, SaaS verticals*

### Category 6: Common Pitfalls & Mistakes
*Problem-aware audience, solution positioning*

### Category 7: Strategic & Business Impact
*C-suite, budget justification*

### Category 8: Privacy & Compliance
*Timely, trust-building*

### Category 9: Advanced Measurement
*MMM, incrementality, triangulation*

### Category 10: Glossary & Quick Reference
*SEO long-tail, featured snippets*

---

## Full Article List by Category

### Category 1: MTA Fundamentals (10 articles)

| # | Article Title | SEO Target | Priority | Status |
|---|--------------|------------|----------|--------|
| 1.1 | **What is Multi-Touch Attribution? The Complete 2025 Guide** | "multi-touch attribution" (2.4k/mo) | P0 | Draft |
| 1.2 | **Attribution Models Explained: First Touch to Data-Driven** | "attribution models" (1.9k/mo) | P0 | Draft |
| 1.3 | **The Customer Journey: Understanding Touchpoints, Sessions, and Conversions** | "customer journey touchpoints" | P1 | Planned |
| 1.4 | **Single-Touch vs Multi-Touch Attribution: When to Use Each** | "single touch vs multi touch" | P1 | Planned |
| 1.5 | **Marketing Attribution for Beginners: A Non-Technical Guide** | "marketing attribution guide" | P1 | Planned |
| 1.6 | **The Attribution Funnel: Awareness, Consideration, Conversion** | "attribution funnel" | P2 | Planned |
| 1.7 | **Understanding Attribution Windows and Lookback Periods** | "attribution window" | P1 | Planned |
| 1.8 | **Conversions vs Events: What's the Difference?** | "conversion tracking" | P2 | Planned |
| 1.9 | **Channel vs Source vs Medium: Taxonomy Explained** | "utm source medium" | P1 | Planned |
| 1.10 | **The History of Marketing Attribution: From Last-Click to AI** | "history of attribution" | P3 | Planned |

**Multibuzz POV for Category 1:**
- Attribution should be transparent, not a black box
- Server-side tracking is the foundation for accurate data
- Simple models often outperform complex ML when data is clean

---

### Category 2: Attribution Model Deep-Dives (12 articles)

| # | Article Title | SEO Target | Priority | Status |
|---|--------------|------------|----------|--------|
| 2.1 | **First-Touch Attribution: Measuring What Starts the Journey** | "first touch attribution" | P1 | Planned |
| 2.2 | **Last-Touch Attribution: The Default That's Costing You Money** | "last touch attribution" | P0 | Planned |
| 2.3 | **Linear Attribution: Giving Equal Credit to Every Touchpoint** | "linear attribution model" | P1 | Planned |
| 2.4 | **Time-Decay Attribution: Weighting Recency in the Journey** | "time decay attribution" | P1 | Planned |
| 2.5 | **Position-Based (U-Shaped) Attribution: First and Last Get More** | "position based attribution" | P1 | Planned |
| 2.6 | **Data-Driven Attribution: How Machine Learning Assigns Credit** | "data driven attribution" | P1 | Planned |
| 2.7 | **Custom Attribution Models: When Off-the-Shelf Doesn't Fit** | "custom attribution model" | P2 | Planned |
| 2.8 | **How to Choose the Right Attribution Model for Your Business** | "choose attribution model" | P0 | Planned |
| 2.9 | **Comparing Attribution Models: A Side-by-Side Analysis** | "attribution model comparison" | P1 | Planned |
| 2.10 | **Why GA4 Removed Most Attribution Models (And What to Do)** | "GA4 attribution models removed" | P0 | Planned |

**Multibuzz POV for Category 2:**
- No single model is "correct" — use multiple and compare
- Transparency matters: know exactly how credit is assigned
- Start simple (linear, position-based) before going data-driven
- GA4's model removal creates opportunity for independent tools

---

### Category 3: Platform & Tool Comparisons (10 articles)

| # | Article Title | SEO Target | Priority | Status |
|---|--------------|------------|----------|--------|
| 3.1 | **Google Analytics 4 Attribution: Limitations and Alternatives** | "GA4 attribution alternative" | P0 | Planned |
| 3.2 | **Segment vs Multibuzz: Customer Data Platform vs Attribution** | "segment alternative" | P1 | Planned |
| 3.3 | **Mixpanel vs Multibuzz: Product Analytics vs Marketing Attribution** | "mixpanel alternative" | P1 | Planned |
| 3.4 | **PostHog vs Multibuzz: Open Source Analytics Comparison** | "posthog alternative" | P2 | Planned |
| 3.5 | **HockeyStack vs Multibuzz: B2B Attribution Compared** | "hockeystack alternative" | P2 | Planned |
| 3.6 | **Triple Whale vs Multibuzz: Ecommerce Attribution Compared** | "triple whale alternative" | P2 | Planned |
| 3.7 | **Dreamdata vs Multibuzz: B2B Revenue Attribution** | "dreamdata alternative" | P2 | Planned |
| 3.8 | **The Best GA4 Alternatives for Marketing Attribution** | "best GA4 alternatives" | P1 | Planned |
| 3.9 | **Marketing Attribution Software Buyer's Guide 2025** | "marketing attribution software" | P1 | Planned |
| 3.10 | **Free vs Paid Attribution Tools: What You Actually Need** | "free attribution tools" | P2 | Planned |

**Multibuzz POV for Category 3:**
- GA4 is free but limited; you get what you pay for
- CDPs (Segment) collect data; attribution tools analyze it — different jobs
- Product analytics (Mixpanel/Amplitude) ≠ marketing attribution
- Server-side tracking is our key differentiator

---

### Category 4: Technical Implementation (12 articles)

| # | Article Title | SEO Target | Priority | Status |
|---|--------------|------------|----------|--------|
| 4.1 | **Server-Side vs Client-Side Tracking: Why We Chose Server** | "server side tracking" (1.2k/mo) | P0 | Planned |
| 4.2 | **The 4-Call SDK Pattern: Simplifying Analytics Integration** | "analytics SDK design" | P1 | Planned |
| 4.3 | **UTM Parameters: The Complete Reference Guide** | "utm parameters" (14k/mo) | P0 | Planned |
| 4.4 | **Cross-Device Attribution: How Identity Resolution Works** | "cross device tracking" | P1 | Planned |
| 4.5 | **Rails Attribution Tracking in 5 Minutes** | "rails analytics" | P1 | Planned |
| 4.6 | **Shopify Multi-Touch Attribution Setup Guide** | "shopify attribution" | P1 | Planned |
| 4.7 | **Magento Server-Side Tracking: Complete Setup** | "magento analytics" | P2 | Planned |
| 4.8 | **From GA4 to Multibuzz: Migration Guide** | "GA4 migration" | P1 | Planned |
| 4.9 | **Setting Up Conversion Tracking: Events, Goals, and Revenue** | "conversion tracking setup" | P1 | Planned |
| 4.10 | **Debugging Attribution: Common Issues and Fixes** | "attribution debugging" | P2 | Planned |
| 4.11 | **API Integration Guide: Sending Events Server-Side** | "server side events API" | P2 | Planned |
| 4.12 | **Testing Your Attribution Setup: QA Checklist** | "attribution testing" | P2 | Planned |

**Multibuzz POV for Category 4:**
- Server-side captures 25%+ more data than client-side
- Identity resolution is the key to cross-device accuracy
- Simple SDK = higher adoption = better data
- Start with UTMs; they're free and powerful

---

### Category 5: Industry-Specific Guides (9 articles)

| # | Article Title | SEO Target | Priority | Status |
|---|--------------|------------|----------|--------|
| 5.1 | **B2B Attribution: Long Sales Cycles & Multiple Stakeholders** | "B2B marketing attribution" | P0 | Planned |
| 5.2 | **Ecommerce Attribution: From First Click to Purchase** | "ecommerce attribution" | P0 | Planned |
| 5.3 | **SaaS Attribution: Trials, Subscriptions, and LTV** | "SaaS marketing attribution" | P1 | Planned |
| 5.4 | **D2C Brand Attribution: Paid Social to Checkout** | "DTC attribution" | P1 | Planned |
| 5.5 | **Agency Attribution: Proving Value to Clients** | "agency attribution reporting" | P2 | Planned |
| 5.6 | **Startup Attribution: Getting Data Right from Day One** | "startup analytics" | P2 | Planned |
| 5.7 | **Enterprise Attribution: Multi-Region, Multi-Brand** | "enterprise attribution" | P3 | Planned |
| 5.8 | **Marketplace Attribution: Seller vs Platform** | "marketplace attribution" | P3 | Planned |
| 5.9 | **Mobile App Attribution: Installs, Events, and Revenue** | "mobile app attribution" | P2 | Planned |

**Multibuzz POV for Category 5:**
- B2B needs account-level attribution, not just user-level
- Ecommerce: server-side tracking defeats cart abandonment data loss
- SaaS: connect marketing touchpoints to MRR, not just signups
- One tool should flex across business models

---

### Category 6: Common Pitfalls & Mistakes (15 articles)

| # | Article Title | SEO Target | Priority | Status |
|---|--------------|------------|----------|--------|
| 6.1 | **Why Last-Click Attribution is Costing You Money** | "last click attribution problems" | P0 | Planned |
| 6.2 | **18 UTM Tracking Mistakes That Ruin Your Data** | "utm mistakes" | P0 | Planned |
| 6.3 | **The Ad Blocker Problem: Why You're Missing 30% of Data** | "ad blockers analytics" | P1 | Planned |
| 6.4 | **Platform-Reported ROAS is Lying to You** | "facebook ROAS inflated" | P1 | Planned |
| 6.5 | **Dark Social: The 84% of Traffic You Can't See** | "dark social tracking" | P1 | Planned |
| 6.6 | **Why Your "Direct" Traffic Isn't Direct** | "direct traffic analytics" | P1 | Planned |
| 6.7 | **The Cross-Device Attribution Gap** | "cross device tracking problem" | P1 | Planned |
| 6.8 | **Attribution Window Mistakes: Too Short or Too Long** | "attribution window best practice" | P2 | Planned |
| 6.9 | **Why Your CAC Calculation is Wrong** | "customer acquisition cost mistakes" | P1 | Planned |
| 6.10 | **The "Black Box" Attribution Problem** | "attribution transparency" | P2 | Planned |
| 6.11 | **Data Silos: When Marketing and Sales Don't Match** | "marketing sales data silos" | P2 | Planned |
| 6.12 | **Over-Attributing to Branded Search** | "branded search attribution" | P2 | Planned |
| 6.13 | **Ignoring View-Through Conversions** | "view through attribution" | P2 | Planned |
| 6.14 | **The 30-Day Window Problem in B2B** | "B2B attribution window" | P1 | Planned |
| 6.15 | **Click Fraud and Attribution Pollution** | "click fraud attribution" | P3 | Planned |

**Multibuzz POV for Category 6:**
- Most attribution problems are data collection problems
- Server-side tracking solves the ad blocker issue
- Independent measurement eliminates platform bias
- Dark social needs manual solutions (UTMs, surveys)

---

### Category 7: Strategic & Business Impact (10 articles)

| # | Article Title | SEO Target | Priority | Status |
|---|--------------|------------|----------|--------|
| 7.1 | **Calculating True Customer Acquisition Cost with MTA** | "customer acquisition cost" | P1 | Planned |
| 7.2 | **Attribution-Driven Budget Allocation** | "marketing budget allocation" | P1 | Planned |
| 7.3 | **Proving Marketing ROI to the C-Suite** | "marketing ROI proof" | P1 | Planned |
| 7.4 | **Channel Optimization Using Attribution Data** | "channel optimization" | P2 | Planned |
| 7.5 | **When to Kill a Marketing Channel** | "marketing channel performance" | P2 | Planned |
| 7.6 | **Attribution and Customer Lifetime Value** | "CLV marketing attribution" | P2 | Planned |
| 7.7 | **Multi-Touch Attribution for Retention and Upsells** | "retention attribution" | P2 | Planned |
| 7.8 | **The True Cost of Bad Attribution** | "attribution ROI" | P1 | Planned |
| 7.9 | **Building an Attribution Culture in Your Organization** | "data driven marketing culture" | P3 | Planned |
| 7.10 | **Attribution Metrics That Actually Matter** | "attribution KPIs" | P2 | Planned |

**Multibuzz POV for Category 7:**
- Attribution is a means to better decisions, not an end
- ~30% of marketing budgets are misallocated due to bad attribution
- Start with understanding, then optimize
- Simple, consistent data beats complex, inconsistent data

---

### Category 8: Privacy & Compliance (8 articles)

| # | Article Title | SEO Target | Priority | Status |
|---|--------------|------------|----------|--------|
| 8.1 | **The Death of Third-Party Cookies: What Marketers Need to Know** | "cookieless tracking" | P0 | Planned |
| 8.2 | **GDPR and Marketing Attribution: A Practical Guide** | "GDPR analytics" | P1 | Planned |
| 8.3 | **First-Party Data Strategy for Attribution** | "first party data strategy" | P1 | Planned |
| 8.4 | **iOS App Tracking Transparency and Attribution** | "iOS ATT attribution" | P1 | Planned |
| 8.5 | **Privacy-First Attribution: No Cookies Required** | "privacy friendly analytics" | P1 | Planned |
| 8.6 | **Consent Management and Attribution** | "consent management analytics" | P2 | Planned |
| 8.7 | **Server-Side Tracking and Privacy Compliance** | "server side privacy" | P2 | Planned |
| 8.8 | **The Future of Attribution in a Privacy-First World** | "future of attribution" | P2 | Planned |

**Multibuzz POV for Category 8:**
- Privacy and good attribution aren't mutually exclusive
- First-party data + server-side = privacy-compliant + accurate
- Cookie deprecation creates competitive advantage for prepared companies
- Transparency with users builds trust and better data

---

### Category 9: Advanced Measurement (8 articles)

| # | Article Title | SEO Target | Priority | Status |
|---|--------------|------------|----------|--------|
| 9.1 | **MTA vs MMM vs Incrementality: When to Use Each** | "MTA vs MMM" | P1 | Planned |
| 9.2 | **Marketing Mix Modeling Explained** | "marketing mix modeling" | P2 | Planned |
| 9.3 | **Incrementality Testing: Measuring True Lift** | "incrementality testing" | P1 | Planned |
| 9.4 | **Triangulation: Combining Measurement Methods** | "unified marketing measurement" | P2 | Planned |
| 9.5 | **Predictive Attribution: AI and Machine Learning** | "AI attribution" | P2 | Planned |
| 9.6 | **Cohort Analysis for Attribution** | "cohort attribution" | P2 | Planned |
| 9.7 | **A/B Testing Your Attribution Model** | "attribution model testing" | P3 | Planned |
| 9.8 | **Building a Measurement Framework** | "marketing measurement framework" | P2 | Planned |

**Multibuzz POV for Category 9:**
- MTA = day-to-day optimization, real-time insights
- MMM = strategic planning, offline channels, long-term
- Incrementality = validation, causation vs correlation
- Use all three; they answer different questions

---

### Category 10: Glossary & Quick Reference (25 definitions)

| # | Term | SEO Snippet Target | Priority |
|---|------|-------------------|----------|
| 10.1 | Attribution Model | "what is an attribution model" | P1 |
| 10.2 | Touchpoint | "marketing touchpoint definition" | P1 |
| 10.3 | Conversion | "conversion marketing definition" | P1 |
| 10.4 | Lookback Window | "attribution lookback window" | P1 |
| 10.5 | First Touch | "first touch attribution definition" | P1 |
| 10.6 | Last Touch | "last touch attribution definition" | P1 |
| 10.7 | Linear Attribution | "linear attribution definition" | P2 |
| 10.8 | Time Decay | "time decay attribution definition" | P2 |
| 10.9 | U-Shaped / Position-Based | "position based attribution definition" | P2 |
| 10.10 | Cross-Device Tracking | "cross device tracking definition" | P1 |
| 10.12 | Identity Resolution | "identity resolution marketing" | P2 |
| 10.13 | Session | "session analytics definition" | P2 |
| 10.14 | Visitor vs User | "visitor vs user analytics" | P2 |
| 10.15 | Channel | "marketing channel definition" | P2 |
| 10.16 | Source | "utm source definition" | P2 |
| 10.17 | Medium | "utm medium definition" | P2 |
| 10.18 | Campaign | "utm campaign definition" | P2 |
| 10.19 | ROAS | "ROAS definition" | P1 |
| 10.20 | CAC | "customer acquisition cost definition" | P1 |
| 10.21 | LTV | "customer lifetime value definition" | P1 |
| 10.22 | Dark Social | "dark social definition" | P2 |
| 10.23 | Server-Side Tracking | "server side tracking definition" | P2 |
| 10.24 | First-Party Data | "first party data definition" | P2 |
| 10.25 | Data-Driven Attribution | "data driven attribution definition" | P2 |

---

## Priority Legend

| Priority | Meaning | Timeline |
|----------|---------|----------|
| P0 | Must have before launch | Phase 1 |
| P1 | High SEO value, core education | Phase 2 |
| P2 | Important but not urgent | Phase 3 |
| P3 | Nice to have | Backlog |

---

## Content Summary

| Category | Articles | P0 | P1 | P2 | P3 |
|----------|----------|----|----|----|----|
| 0. Hygiene Pages | 8 | 4 | 4 | 0 | 0 |
| 1. MTA Fundamentals | 10 | 2 | 5 | 2 | 1 |
| 2. Model Deep-Dives | 12 | 4 | 5 | 3 | 0 |
| 3. Comparisons | 10 | 1 | 4 | 5 | 0 |
| 4. Technical | 12 | 2 | 6 | 4 | 0 |
| 5. Industry Guides | 9 | 2 | 2 | 3 | 2 |
| 6. Pitfalls | 15 | 2 | 7 | 5 | 1 |
| 7. Strategic | 10 | 0 | 4 | 5 | 1 |
| 8. Privacy | 8 | 1 | 4 | 3 | 0 |
| 9. Advanced | 8 | 0 | 2 | 5 | 1 |
| 10. Glossary | 25 | 0 | 10 | 15 | 0 |
| 11. Survey | 7 | 0 | 5 | 2 | 0 |
| **Total** | **134** | **18** | **58** | **52** | **6** |

---

## Content Specifications

### Per Article Requirements

- **Length**: 1,500-3,000 words for pillar content; 800-1,500 for supporting
- **Structure**:
  - TL;DR summary
  - Problem statement
  - Deep explanation
  - Multibuzz solution/POV
  - Practical takeaways
  - Related articles
- **SEO**: Primary keyword in H1, 2-3 H2s with related keywords
- **Internal Links**: 3-5 links to other articles and product pages
- **CTA**: Contextual signup or demo request
- **Schema**: FAQ markup where applicable (glossary, how-to)

### Repurposing Matrix

Each pillar article should generate:
- LinkedIn carousel (5-7 slides)
- Twitter/X thread (8-12 tweets)
- Email course module
- In-app help tooltip
- Dev.to / HN version (technical articles)

---

## Research Sources Tally

### MTA Challenges & Problems
- [The State of Multi-Touch Attribution 2024 - MMA Global](https://mmaglobal.com/state-multi-touch-attribution-2024)
- [Challenges of Multi Touch Attribution - DemandJump](https://www.demandjump.com/blog/challenges-of-multi-touch-attribution)
- [Multi Touch Attribution from Provalytics](https://provalytics.com/news/multi-touch-attribution/)
- [Why Multi-Touch Attribution Still Matters - Stack Moxie](https://www.stackmoxie.com/blog/why-mutli-touch-attribution-still-matters/)
- [Complete Guide To Multi-Touch Attribution - Ruler Analytics](https://www.ruleranalytics.com/blog/click-attribution/multi-touch-attribution/)
- [The Evolution of Multi-Touch Attribution 2024 - LeadsRx](https://leadsrx.com/resources/blog/the-evolution-of-multi-touch-attribution-top-tips-for-2024/)

### Data Quality & Accuracy
- [Poor Quality Data Is Hurting Your Attribution - Corvidae](https://corvidae.ai/blog/poor-quality-data-is-hurting-your-attribution/)
- [The Real Reasons Marketing Attribution Is Failing - Corvidae](https://corvidae.ai/blog/the-real-reasons-attribution-is-failing/)
- [Why Is Marketing Attribution Broken? - Lifesight](https://lifesight.io/blog/marketing-attribution-problems/)
- [3 Most Common Attribution Challenges - The Drum](https://www.thedrum.com/open-mic/3-most-common-attribution-challenges-and-how-to-solve-them)
- [5 Common Marketing Attribution Mistakes - Pathmetrics](https://www.pathmetrics.io/attribution/5-common-marketing-attribution-mistakes-to-avoid/)
- [Why Your Marketing Attribution Data Is Wrong - Wizaly](https://www.wizaly.com/blog/marketing-attribution-mistakes/)

### Cookieless & Privacy
- [Cookieless Attribution: First-Party Data Strategies - Chariot Creative](https://chariotcreative.com/blog/cookieless-attribution-in-marketing-first-party-data-strategies/)
- [Cookieless Marketing Challenges - Keen](https://keends.com/blog/navigating-a-cookieless-world-challenges-and-opportunities-for-marketers/)
- [Rethinking Measurement in a Cookieless World - Basis Technologies](https://basis.com/blog/rethinking-measurement-in-a-cookieless-world)
- [First Party Data Strategy in a Cookieless Future - Teavaro](https://teavaro.com/blog/the-ideal-first-party-data-strategy-in-a-cookieless-future)
- [The Future of Attribution: Adapting to Cookie-Less - LeadsRx](https://leadsrx.com/blog/the-future-of-attribution-adapting-to-a-cookie-less-digital-world/)

### B2B Attribution
- [Attribution for B2B Marketers: Long Sales Cycle - LeadsRx](https://leadsrx.com/resources/blog/attribution-for-b2b-marketers-tracking-the-long-sales-cycle/)
- [Challenges with B2B Attribution - Factors.ai](https://www.factors.ai/blog/b2b-marketing-attribution-challenges-and-solutions)
- [B2B Marketing Attribution: Comprehensive Guide - BL.ink](https://www.bl.ink/blog/b2b-marketing-attribution-a-comprehensive-guide)
- [Common Attribution Challenges in B2B Marketing - Forank](https://www.forank.com/sem-blogs/common-attribution-challenges-in-b2b-marketing-resolved/)
- [Why Single Touch Attribution Fails B2B - UnboundB2B](https://www.unboundb2b.com/blog/why-single-touch-attribution-fails-b2b-marketers/)
- [Ultimate Guide To B2B Marketing Attribution - OrangeOwl](https://orangeowl.marketing/b2b-marketing/b2b-marketing-attribution-models/)

### Attribution Model Selection
- [A Beginner's Guide to Attribution Model Frameworks - Amplitude](https://amplitude.com/blog/attribution-model-frameworks)
- [How to Choose and Test an Attribution Model - OWOX](https://www.owox.com/blog/articles/how-to-choose-and-test-an-attribution-model)
- [The Definitive Guide to Marketing Attribution Models - AgencyAnalytics](https://agencyanalytics.com/blog/marketing-attribution-models)
- [Marketing Attribution Models: A Guide - Contentsquare](https://contentsquare.com/guides/customer-journey-map/attribution-model/)

### Last-Click Attribution Problems
- [Why Last-Click Attribution is Failing Marketers 2024 - LeadsRx](https://leadsrx.com/resource/why-last-click-attribution-is-failing-marketers-in-2024/)
- [Is Last-Click Attribution Still Relevant in 2025? - TrueProfit](https://trueprofit.io/blog/last-click-attribution)
- [Why Last-Click Attribution Isn't Effective - AdRoll](https://www.adroll.com/blog/why-last-click-attribution-isnt-effective)
- [Last Click Attribution Guide - Ruler Analytics](https://www.ruleranalytics.com/blog/click-attribution/last-click-attribution/)
- [Is Last Click Attribution Dead? - Supermetrics](https://supermetrics.com/blog/last-click-attribution)
- [Pitfalls of Last-Click Attribution - Marketing Evolution](https://www.marketingevolution.com/knowledge-center/pitfalls-of-last-click-attribution)

### GA4 Limitations
- [15 Common GA4 Attribution Challenges - Napkyn](https://www.napkyn.com/blog/15-common-ga4-attribution-challenges-and-how-to-solve-them)
- [14 Best GA4 Alternatives 2024 - HockeyStack](https://www.hockeystack.com/blog-posts/google-analytics-4-alternatives-competitors)
- [GA4 Issues: 8 Questions GA4 Can't Answer - Matomo](https://matomo.org/blog/2024/01/ga4-issues/)
- [Navigating Attribution in GA4 2024 - Cardinal Path](https://www.cardinalpath.com/blog/navigating-attribution-in-ga4-in-2024)
- [GA4 Limitations: Rethinking Attribution - Measured](https://www.measured.com/faq/what-is-the-impact-of-ga4-google-analytics-4/)
- [8 Limitations of Google Analytics 4 - Ruler Analytics](https://www.ruleranalytics.com/blog/analytics/limitations-google-analytics/)

### Server-Side vs Client-Side Tracking
- [Client vs Server-Side Tracking - Segment/Twilio](https://segment.com/academy/collecting-data/when-to-track-on-the-client-vs-server/)
- [Server-side vs Client-side Tracking - Usercentrics](https://usercentrics.com/guides/server-side-tagging/server-side-vs-client-side-tracking/)
- [Server-side vs Client-side Tracking - Matomo](https://matomo.org/blog/2025/07/what-is-server-side-tracking/)
- [Server-Side vs Client-Side: Marketer's Overview - EasyInsights](https://easyinsights.ai/blog/server-side-vs-client-side-tracking/)
- [Ad Blockers and Server-Side Tracking - Medium/Lukas Oldenburg](https://lukas-oldenburg.medium.com/ad-blockers-and-server-side-tracking-part-1-the-ever-more-challenging-world-of-client-side-ace3b1c049b)
- [5 Key Benefits of Server-Side Tracking - Usercentrics](https://usercentrics.com/knowledge-hub/benefits-of-server-side-tracking/)

### UTM Tracking
- [18 UTM Tagging Mistakes & Errors To Avoid - DumbData](https://dumbdata.co/post/costly-utm-tracking-mistakes-that-can-ruin-your-data/)
- [UTM Best Practices Guide - Diffuse Digital](https://diffusedigitalmarketing.com/utm-best-practices/)
- [Common Mistakes with UTM Tracking Codes - ZAG](https://www.zaginteractive.com/insights/articles/february-2021/common-errors-in-utm-tracking)
- [14 Common Mistakes With UTM Tags - Holini](https://holini.com/utm-tags/)
- [10 Critical UTM Mistakes - Usermaven](https://usermaven.com/blog/critical-utm-mistakes)

### Ecommerce Attribution
- [Multi-Channel Attribution: Basics and How to Start - Shopify](https://www.shopify.com/enterprise/blog/multi-channel-attribution)
- [Ecommerce Attribution Models Explained - The Retail Exec](https://theretailexec.com/marketing/marketing-attribution/)
- [Complete Ecommerce Attribution Guide - Klaviyo](https://www.klaviyo.com/products/marketing-analytics/ecommerce-attribution)
- [6 Biggest Challenges in eCommerce Attribution - Graas](https://graas.ai/blog/challenges-in-ecommerce-attribution)
- [Why Is Ecommerce Marketing Attribution Difficult? - Lifesight](https://lifesight.io/blog/difficulties-in-ecommerce-marketing-attribution/)

### Incrementality vs MTA vs MMM
- [What is Incrementality Testing vs MMM vs MTA? - Measured](https://www.measured.com/faq/what-are-the-pros-and-cons-of-incrementality-testing-versus-mmm-or-mta/)
- [Attribution vs Incrementality - Skai](https://skai.io/blog/attribution-vs-incrementality/)
- [Incrementality vs Attribution: What's The Difference? - Haus](https://www.haus.io/blog/incrementality-vs-attribution-whats-the-difference)
- [MTA vs MMM vs Incrementality - CaliberMind](https://calibermind.com/articles/mta-vs-mmm-vs-incrementality-why-attribution-media-mix-modeling-and-incrementality-serve-different-roles-in-b2b-marketing/)
- [How Attribution, Incrementality, and MMM Interact - Adjust](https://www.adjust.com/blog/attribution-incrementality-mmm/)
- [4 Experts on MMM, MTA, and Incrementality - Crealytics](https://www.crealytics.com/blog/4-experts-break-down-3-ways-of-measuring-roi-in-marketing-mmm-mta-and-incrementality-testing)

### MMM vs MTA
- [Multi-touch Attribution vs Marketing Mix Modeling - Funnel.io](https://funnel.io/blog/mta-vs-mmm)
- [MMM vs MTA: Which is Right for You? - Airbridge](https://www.airbridge.io/blog/mmm-vs-mta)
- [MMM vs MTA: Differences - Keen](https://keends.com/blog/marketing-mix-modeling-vs-multi-touch-attribution/)
- [Marketing Mix Modeling vs Attribution - Supermetrics](https://supermetrics.com/blog/marketing-mix-modeling-vs-attribution)
- [MTA vs MMM: Which is Right for You? - Search Engine Land](https://searchengineland.com/mta-vs-mmm-which-marketing-attribution-model-is-right-for-you-452368)

### Cross-Device Attribution
- [Understanding Cross-Device Attribution - Ingest Labs](https://ingestlabs.com/cross-device-attribution-guide/)
- [Cross-Device Attribution - Amplitude](https://amplitude.com/explore/digital-marketing/cross-device-attribution)
- [Multi-Device User Behavior Impact on Attribution - TAGLAB](https://taglab.net/the-impact-of-multi-device-user-behavior-on-marketing-attribution/)
- [Cross-device Marketing Attribution Solution - SegmentStream](https://segmentstream.com/blog/articles/cross-device-attribution-solution)
- [Identity Resolution: Guide to Transparent Attribution - Rockerbox](https://www.rockerbox.com/blog/identity-resolution-the-rockerbox-guide-to-transparent-attribution)
- [Cross-Device Identity Resolution Explained - Customers.ai](https://customers.ai/cross-device-identity-resolution)

### Dark Social
- [Dark Social Explained - Cognism](https://www.cognism.com/blog/inside-out-of-dark-social)
- [What is Dark Social? Why Track It - Hootsuite](https://blog.hootsuite.com/dark-social/)
- [Dark Social: How to Uncover Hidden Traffic - DMEXCO](https://dmexco.com/stories/shining-light-into-the-darkness-what-is-dark-social/)
- [Shining a Light on Dark Social Metrics - Salesforce](https://www.salesforce.com/ca/hub/marketing/shining-light-on-dark-social-metrics/)
- [What is Dark Traffic? - Wolfgang Digital](https://www.wolfgangdigital.com/blog/dark-traffic-find/)

### SaaS & Subscription Attribution
- [LTV/CAC Ratio - Wall Street Prep](https://www.wallstreetprep.com/knowledge/ltv-cac-ratio/)
- [SaaS LTV Formula - Improvado](https://improvado.io/blog/saas-calculating-ltv)
- [Customer Acquisition Cost Benchmarks - Attribution App](https://www.attributionapp.com/blog/saas-calculator-how-much-should-i-spend-to-acquire-a-customer/)
- [Why LTV/CAC is Misleading - ScaleMatters](https://www.scalematters.com/insights/customer-npv)
- [LTV:CAC Misunderstood Metric - Burkland](https://burklandassociates.com/2024/01/02/ltvcac-an-important-but-often-misunderstood-saas-metric/)

### Marketing Attribution Software
- [Best Marketing Attribution Software 2024 - SelectHub](https://www.selecthub.com/c/marketing-attribution-software/)
- [7 Best Marketing Attribution Software 2024 - Matomo](https://matomo.org/blog/2024/02/marketing-attribution-software/)
- [Top 8 Marketing Attribution Tools 2024 - EasyInsights](https://easyinsights.ai/blog/top-8-marketing-attribution-tools-and-software-for-2024/)
- [21 Best Marketing Attribution Software 2025 - The CMO](https://thecmo.com/tools/best-marketing-attribution-software/)
- [14 Marketing Attribution Tools 2024 - Corvidae](https://corvidae.ai/blog/attribution-tools/)
- [Best Attribution Software Tested - G2](https://learn.g2.com/best-attribution-software)

### Customer Retention & Upsell Attribution
- [Enhancing Customer Retention through Upselling - RevPartners](https://blog.revpartners.io/en/revops-articles/boosting-customer-retention-with-upselling-and-cross-selling)
- [Cross-sell and Upsell to Existing Customers - Qlutch](https://qlutch.com/customer-retention/cross-sell-and-up-sell-to-existing-customers)
- [Customer Retention and Cross-selling - Product Marketing Alliance](https://www.productmarketingalliance.com/customer-retention-and-cross-selling-in-product-marketing/)
- [Boost CLV with Personalized Cross-sell - CustomerThink](https://customerthink.com/how-to-boost-retention-loyalty-and-customer-lifetime-value-with-personalized-cross-sell-and-upsell/)

---

## Next Steps

1. **Create hygiene pages** (About, Privacy, Terms, Contact) — P0
2. **Write P0 foundation articles** for launch
3. **Build competitor comparison pages** (Category 3)
4. **Launch landscape survey** for outreach
5. **Continue P1/P2 articles** for SEO growth

---

## Revision History

| Date | Change |
|------|--------|
| 2025-11-29 | Initial TOC created with 134 content items |
| 2025-11-29 | Added Category 0 (Hygiene Pages) and Category 11 (Survey) |
