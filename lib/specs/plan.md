# Product

* 1st client UAT - staging + prod
* Dashboard: comp + funnel
  - [x] Conversions tab with KPI cards (conversions, revenue, conversion rate, AOV)
  - [x] KPI cards act as metric tabs (click to switch chart data)
  - [x] Time series line chart (channel performance over time)
  - [x] Bar chart by channel with drill-down to campaigns
  - [x] Model comparison via multi-select (max 2 models)
  - [x] Collapsible filters bar (date range, models, channels)
  - [x] Export dropdown (CSV/PDF)
  - [ ] Journeys tab
  - [ ] Funnel visualization
* Split dash funnel by dimension (properties)
* Event debugging
* $ and plans
* AST for attribution models
  - Create new / edit (up to 20 models applied)
  - New / updates can back calculate at a fixed one-time cost (10k free then $x per 10k)
* Content for subsidiary pages (terms etc)
* Invite users
* Live
* CLV (doesn't work the same as new customer acquisition - think it through)
* Rollout SDKs: python, php, shopify, magento etc
* Other channels: phone, email

## Homepage Update (E1S4)

See `lib/specs/homepage_visualization_spec.md`

- [ ] SDK showcase section (live SDKs + coming soon badges)
- [ ] Attribution flow animation (events → touchpoints → conversion → credit distribution)
- [ ] Dashboard preview/screenshots
- [ ] Social proof section (testimonials, logos when available)
- [ ] Clear CTA flow: View Demo → Try Free → Get Started

***

# Mappings

*  utm_term: "plcid_* -> Google Places

***

# Marketing

* Launch SDK listings + associated newsletters (first being rubygems) - research the best way to get traction in the specific SDK community are there people to engage with?
* CA, Rebel etc (grant), boris clients, audi, others?
* Waitlist for SDK - 1st to implement get 3 months free and priority support
* Reach out: key ICPs, intro LI then email then call
* Content: docs, video demo dropbox style, how to for each SDK, video - what is MTA?, MTA Lenny-style guide, survey potential users w/ LinkedIn / email outreach - compile
* Landing pages: competitor breakdown (very detailed, feature by feature)
* SEO & AEO - lots of FAQs
* Ad Words to competitor breakdowns: GA4 alternative, Segment alternative
* Ad Words targeting US (1-10k multi-touch attribution searches p/m)
* Emails like MKT1
* X relationship grind (Reply to 5-10 niche creators daily (e.g., @lennyrachitsky on growth pains). "Loved your AEO post—here's how AST simplifies MTA for that." DM Looms for collabs.)
* Product Hunt (once several SDKs are live)
*  Reddit value bombs (Post in r/marketing, r/bigquery: "My no-frills MTA setup—free AST template." Story + screenshots, link in comments post-engagement. Reply to all.)
* Get publised in https://www.mi-3.com.au/ or international versions

***

# Content

Educational content strategy: SEO-optimized articles that explain our thinking, can be repurposed across channels, and linked from in-app help.

## Pillar Content (Long-form, High SEO Value)

### 1. MTA Fundamentals
| Article | SEO Target | In-App Link Location | Repurpose |
|---------|------------|---------------------|-----------|
| **"What is Multi-Touch Attribution? The Complete Guide"** | "multi-touch attribution" (2.4k/mo) | Dashboard tooltip, empty state | LinkedIn carousel, email course |
| **"Attribution Models Explained: First Touch to Data-Driven"** | "attribution models" (1.9k/mo) | Model selector dropdown | Comparison infographic |
| **"The 4-Call SDK Pattern: Simplifying Analytics Integration"** | "analytics SDK design" | SDK docs, API reference | Dev.to post, HN discussion |
| **"Cross-Device Attribution: How Identity Resolution Works"** | "cross-device tracking" | Identify method docs | Case study format |

### 2. Technical Deep-Dives
| Article | SEO Target | In-App Link Location | Repurpose |
|---------|------------|---------------------|-----------|
| **"Server-Side vs Client-Side Tracking: Why We Chose Server"** | "server-side tracking" (1.2k/mo) | SDK installation guide | Reddit r/analytics post |
| **"UTM Parameters: The Complete Reference"** | "utm parameters" (14k/mo) | Session/channel docs | Cheat sheet PDF |
| **"Touchpoints vs Events: Understanding the Difference"** | "marketing touchpoints" | Events vs conversions help | Twitter thread |
| **"Lookback Windows: How to Choose the Right Attribution Window"** | "attribution window" | Settings page | Calculator tool |

### 3. Implementation Guides
| Article | SEO Target | In-App Link Location | Repurpose |
|---------|------------|---------------------|-----------|
| **"Rails Attribution Tracking in 5 Minutes"** | "rails analytics" | Ruby SDK quickstart | Screencast video |
| **"Shopify Multi-Touch Attribution Without Code"** | "shopify attribution" | Shopify app listing | YouTube tutorial |
| **"Magento Server-Side Tracking: Complete Setup Guide"** | "magento analytics" | Magento extension docs | Partner webinar |
| **"From GA4 to Multi-Touch: Migration Guide"** | "ga4 attribution" (high intent) | Onboarding flow | Comparison landing page |

### 4. Strategic/Business Content
| Article | SEO Target | In-App Link Location | Repurpose |
|---------|------------|---------------------|-----------|
| **"Why Last-Click Attribution is Costing You Money"** | "last click attribution problems" | First-time dashboard view | LinkedIn article |
| **"The Death of Third-Party Cookies: What Marketers Need to Know"** | "cookieless tracking" | Privacy docs | Email newsletter |
| **"Calculating True Customer Acquisition Cost with MTA"** | "customer acquisition cost" | CAC metric tooltip | Finance team one-pager |
| **"Attribution for B2B: Long Sales Cycles & Multiple Stakeholders"** | "b2b attribution" | B2B use case page | Whitepaper |

## Content Formats & Repurposing Matrix

```
Long-form Article (SEO pillar)
    │
    ├──→ In-app contextual help (tooltip/modal)
    ├──→ Email course module (5-part series)
    ├──→ LinkedIn carousel (key takeaways)
    ├──→ Twitter/X thread (numbered insights)
    ├──→ YouTube explainer (animated diagrams)
    ├──→ Dev.to / HN post (technical angle)
    ├──→ Reddit value post (r/marketing, r/analytics)
    ├──→ Comparison landing page (vs competitors)
    └──→ PDF download (lead magnet)
```

## In-App Help Integration

Link content contextually throughout the app:

| Location | Content Link | Purpose |
|----------|--------------|---------|
| Model selector dropdown | "Attribution Models Explained" | Help users choose |
| Empty conversions state | "What is Multi-Touch Attribution?" | Educate new users |
| Identify method in SDK docs | "Cross-Device Attribution" | Explain the why |
| Channel breakdown chart | "UTM Parameters Reference" | Debug attribution |
| Settings > Lookback window | "Choosing Attribution Windows" | Guide configuration |
| First conversion celebration | "Understanding Your First Attribution" | Reinforce value |

## Content Calendar Priority

### Phase 1: Foundation (Before Launch)
1. "What is Multi-Touch Attribution?" - Core pillar
2. "Attribution Models Explained" - Links from product
3. "UTM Parameters Reference" - High search volume
4. SDK quickstarts (Ruby first)

### Phase 2: SEO Growth (Post-Launch)
5. "Server-Side vs Client-Side Tracking"
6. "From GA4 to Multi-Touch"
7. Platform-specific guides (Shopify, Magento)
8. "Why Last-Click is Costing You Money"

### Phase 3: Authority Building
9. "Cross-Device Attribution Deep-Dive"
10. "B2B Attribution Guide"
11. Case studies with real numbers
12. Comparison pages (vs Segment, vs GA4, vs Mixpanel)

## Glossary / FAQ Hub

Create `/glossary` with SEO-optimized definitions:
- Attribution model
- Touchpoint
- Conversion
- Lookback window
- First touch / Last touch
- Linear attribution
- Time decay
- U-shaped / W-shaped
- Cross-device tracking
- Identity resolution
- Session
- Visitor vs User
- Channel vs Source vs Medium

Each definition:
- 150-300 words
- Links to pillar content
- Schema markup for featured snippets
- "Learn more" CTA to full article

## Measurement

Track per article:
- Organic traffic (GSC)
- Time on page
- Scroll depth
- In-app help clicks
- Conversion to signup
- Backlinks acquired
