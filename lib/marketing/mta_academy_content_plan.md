# MTA Academy: Comprehensive Content Plan

**Status**: Draft
**Created**: 2025-12-27
**Target ICP**: Technical marketers, data engineers, marketing ops, analysts in e-commerce/SaaS
**Inspiration**: [Recast MMM Academy](https://getrecast.com/mmm-academy/)

---

## Executive Summary

This document outlines a comprehensive content strategy for mbuzz.co's **MTA Academy** - a free educational resource hub that positions mbuzz as the authority on multi-touch attribution for technical users. Unlike generic MTA guides, this academy focuses on:

1. **Technical depth** - Code examples, formulas, and implementation details
2. **Actionable guidance** - When to switch models, how to reallocate funds, integration patterns
3. **Unique methodology** - Our bottom-up funnel forecasting approach with MTA
4. **Verifiable uniqueness** - Original research, proprietary frameworks, and real data
5. **Search + AEO optimization** - Each piece targets a specific niche question

---

## Search & AEO Strategy

### Core Principles

Every piece of content must:

1. **Answer ONE specific question** - The title IS the question users ask
2. **Be the best answer on the internet** - Concise TL;DR + deep explanation
3. **Structure for AI citation** - Clear headings, tables, definitions
4. **Target long-tail queries** - Niche > broad (less competition, higher intent)

### AEO (Answer Engine Optimization) Requirements

Each article includes:

```markdown
## TL;DR (Featured Snippet Target)
[2-3 sentence answer that AI can quote directly]

## Key Takeaways
- Bullet 1: [Specific, quotable insight]
- Bullet 2: [Actionable recommendation]
- Bullet 3: [Unique data point or framework]

## Definitions (Schema.org/FAQPage)
**Term**: [Clear, one-sentence definition]
```

### Content Structure for AI Citation

```markdown
1. Direct Answer (first 100 words)
2. Why This Matters (context)
3. How It Works (technical detail)
4. When to Use / When Not to Use (decision guidance)
5. Example with Real Data (proof/credibility)
6. Related Questions (internal linking)
```

---

## Core Principles for Content Uniqueness

Every piece of content must pass the **"AI Can't Generate This"** test:

### 1. Proprietary Frameworks
- **mbuzz DSL examples** - Real code that only works in mbuzz
- **Decision trees** - Original flowcharts for model selection
- **Calculation templates** - Downloadable Excel/Python tools

### 2. First-Party Data & Research
- **Benchmark data** from mbuzz customers (anonymized)
- **A/B test results** from model comparisons
- **Performance metrics** from server-side vs client-side tracking

### 3. Expert Interviews & Case Studies
- Interview practitioners using different approaches
- Document real implementation stories with metrics
- Include failure cases (what didn't work and why)

### 4. Unique Methodology
- **Bottom-up funnel forecasting with MTA** (detailed below)
- **Tiered model selection framework**
- **Hybrid MTA+MMM integration patterns**

### 5. Interactive Tools
- Live model comparison calculators
- Lookback window optimizer
- Budget reallocation simulator

---

## Academy Structure (7 Sections)

### Section 1: MTA Fundamentals (Entry Point)
*For: Marketing managers new to MTA, analysts transitioning from single-touch*

| # | Title (= Target Question) | Target Query | Monthly Search | AEO Snippet Target | Uniqueness Strategy | Priority |
|---|---------------------------|--------------|----------------|--------------------|--------------------|----------|
| 1.1 | **What is Multi-Touch Attribution?** | "what is multi touch attribution" | 2.4k | Definition + 3 benefits | Include mbuzz methodology diagram; contrast with single-touch | P0 |
| 1.2 | **What's the Difference Between MTA and MMM?** | "mta vs mmm" "multi touch attribution vs media mix modeling" | 720 | Comparison table with use cases | Original framework: Pearl's Ladder applied to measurement | P0 |
| 1.3 | **How Do Attribution Lookback Windows Work?** | "attribution lookback window" "what is lookback window" | 480 | Definition + default recommendations by business model | Original research: optimal windows by vertical with data | P1 |
| 1.4 | **Why Does Server-Side Tracking Capture More Data?** | "server side vs client side tracking" | 1.2k | Capture rate comparison (95% vs 70%) | Benchmark data from mbuzz; before/after screenshots | P0 |
| 1.5 | **What is a Marketing Touchpoint?** | "marketing touchpoint definition" | 1.9k | Clear definition + examples | Use mbuzz's exact schema; include session vs event diagram | P1 |
| 1.6 | **How to Calculate Attribution Credit** | "attribution credit calculation" "how to calculate attribution" | 320 | Formula + worked example | Step-by-step with mbuzz DSL code | P1 |

**Section 1 SEO Cluster:**
- Pillar: "What is Multi-Touch Attribution?"
- Spokes: All other articles link back
- Target: Position 1-3 for "multi touch attribution"

---

### Section 2: Attribution Models Deep Dive
*For: Analysts choosing/tuning models, data engineers implementing attribution*

| # | Title (= Target Question) | Target Query | Monthly Search | AEO Snippet Target | Uniqueness Strategy | Priority |
|---|---------------------------|--------------|----------------|--------------------|--------------------|----------|
| 2.1 | **When Should I Use First-Touch Attribution?** | "first touch attribution" "when to use first touch" | 1.1k | Use case list (brand awareness, ToFU) | Decision tree + mbuzz DSL example | P0 |
| 2.2 | **When Should I Use Last-Touch Attribution?** | "last touch attribution" | 1.3k | Use case list (short cycles, closing) | Comparison with first-touch; common mistakes | P0 |
| 2.3 | **How Does Linear Attribution Work?** | "linear attribution model" "linear attribution formula" | 590 | Formula: credit = 1/n | Worked example with 5 touchpoints; when linear beats ML | P1 |
| 2.4 | **How to Configure Time Decay Half-Life** | "time decay attribution" "attribution half life" | 390 | Formula + recommended half-lives | Interactive calculator; benchmark by vertical | P1 |
| 2.5 | **What is U-Shaped (Position-Based) Attribution?** | "u shaped attribution" "position based attribution" | 480 | 40/40/20 rule explained | Edge cases (1-2 touchpoints); mbuzz implementation | P1 |
| 2.6 | **What is Participation Attribution?** | "participation attribution model" | 110 | Definition: 100% to each channel | When to use sum > 1.0; funnel analysis use case | P1 |
| 2.7 | **How Does Markov Chain Attribution Work?** | "markov chain attribution" "removal effect attribution" | 210 | Algorithm explanation | Python code; minimum data requirements (500+ conversions) | P1 |
| 2.8 | **How Does Shapley Value Attribution Work?** | "shapley value attribution" | 170 | Game theory explanation | Mathematical walkthrough; O(2^n) complexity note | P2 |
| 2.9 | **How to Choose the Right Attribution Model** | "best attribution model" "which attribution model" | 720 | Decision matrix | Original flowchart; A/B testing methodology | P0 |
| 2.10 | **Why Did GA4 Remove Most Attribution Models?** | "ga4 attribution models removed" "ga4 last click only" | 480 | Timeline + Google's reasoning | What to do instead; mbuzz as alternative | P0 |

**Section 2 SEO Cluster:**
- Pillar: "How to Choose the Right Attribution Model"
- Spokes: Each model article links to comparison
- Target: Position 1-3 for "[model] attribution"

---

### Section 3: Integrating MTA with Other Measurement
*For: Marketing ops building measurement stacks, analysts triangulating*

| # | Title (= Target Question) | Target Query | Monthly Search | AEO Snippet Target | Uniqueness Strategy | Priority |
|---|---------------------------|--------------|----------------|--------------------|--------------------|----------|
| 3.1 | **When Should I Use MTA vs MMM?** | "mta vs mmm when to use" | 320 | Decision criteria table | Original: Pearl's Ladder framework for measurement | P0 |
| 3.2 | **How to Run an Incrementality Test** | "incrementality testing marketing" "how to run lift test" | 390 | Step-by-step methodology | Geo-holdout design template; minimum sample sizes | P1 |
| 3.3 | **How to Calibrate MTA with Lift Studies** | "calibrate attribution with lift" | 50 | Workflow diagram | Technical process: adjusting credits with lift coefficients | P1 |
| 3.4 | **How to Combine MTA and MMM Data** | "mta mmm integration" "hybrid measurement" | 90 | Architecture diagram | Integration code examples; API patterns | P1 |
| 3.5 | **What is Marketing Measurement Triangulation?** | "marketing triangulation" "unified measurement" | 70 | Definition + when results conflict | Original framework: resolution methodology | P2 |
| 3.6 | **Can MTA Prove Causation?** | "attribution causation correlation" | 40 | Pearl's Ladder explanation | Deep dive: why MTA is Rung 1 (association) | P2 |

**Section 3 SEO Cluster:**
- Pillar: "When Should I Use MTA vs MMM?"
- Target: Capture "vs" and "comparison" queries

---

### Section 4: Bottom-Up Funnel Forecasting with MTA (Flagship Content)
*For: Marketing ops doing planning, finance teams building forecasts*

**This is mbuzz's unique methodology - not found elsewhere.**

| # | Title (= Target Question) | Target Query | Monthly Search | AEO Snippet Target | Uniqueness Strategy | Priority |
|---|---------------------------|--------------|----------------|--------------------|--------------------|----------|
| 4.1 | **Why Doesn't Last-Touch Work for Funnel Forecasting?** | "funnel attribution problems" "attribution forecasting" | 40 | Problem statement + solution preview | Original framework: tiered attribution | P0 |
| 4.2 | **How to Use Different Attribution Models by Funnel Stage** | "funnel stage attribution" "tofu mofu bofu attribution" | 30 | Tiered model recommendation table | First-touch ToFU, Participation MoFU, Last-touch BoFU | P0 |
| 4.3 | **How to Calculate Channel Overlap with Participation** | "channel overlap attribution" "participation model analysis" | 20 | When sum > 1.0 and what it means | Interpretation guide; Excel template | P1 |
| 4.4 | **How to Build a Bottom-Up Revenue Forecast with MTA** | "bottom up revenue forecast" "channel revenue forecast" | 90 | Workflow summary | Complete Excel template; worked example | P0 |
| 4.5 | **How to Set Lookback Windows by Funnel Stage** | "lookback window by funnel" | 10 | Recommendation table by stage | Original research: optimal windows ToFU/MoFU/BoFU | P1 |
| 4.6 | **How to Validate Forecasts with Attribution Insights** | "validate marketing forecast" | 30 | Validation checklist | Before/after case study with real metrics | P2 |

**Section 4 SEO Cluster:**
- Pillar: "How to Build a Bottom-Up Revenue Forecast with MTA"
- Unique value: Only comprehensive guide on this topic
- Target: Own "attribution forecasting" and "funnel attribution" long-tail

---

### Section 5: Practical Implementation
*For: Developers integrating mbuzz, ops teams tuning models*

| # | Title (= Target Question) | Target Query | Monthly Search | AEO Snippet Target | Uniqueness Strategy | Priority |
|---|---------------------------|--------------|----------------|--------------------|--------------------|----------|
| 5.1 | **How to Change Your Attribution Lookback Window** | "change attribution window" "adjust lookback period" | 110 | Step-by-step + testing approach | A/B test methodology; DSL examples | P0 |
| 5.2 | **How to Reallocate Marketing Budget Using Attribution** | "budget reallocation attribution" "reallocate marketing spend" | 90 | 5-step workflow | Excel template with ROI sensitivity analysis | P0 |
| 5.3 | **How to Debug Attribution Data Issues** | "attribution data issues" "attribution debugging" | 40 | Common issues checklist | Real troubleshooting scenarios from mbuzz | P1 |
| 5.4 | **How to A/B Test Attribution Models** | "test attribution model" "compare attribution models" | 50 | Statistical methodology | Sample size calculator; code examples | P1 |
| 5.5 | **How to Build Custom Attribution Models** | "custom attribution model" "diy attribution" | 70 | mbuzz DSL overview | Tutorial from simple to complex; all syntax | P1 |
| 5.6 | **How to Classify Marketing Channels Correctly** | "marketing channel taxonomy" "channel classification" | 60 | Standard taxonomy table | Edge cases; UTM best practices | P2 |

**Section 5 SEO Cluster:**
- Pillar: "How to Reallocate Marketing Budget Using Attribution"
- Target: High-intent implementation queries

---

### Section 6: Advanced Topics
*For: Data scientists, marketing technologists, analytics leaders*

| # | Title (= Target Question) | Target Query | Monthly Search | AEO Snippet Target | Uniqueness Strategy | Priority |
|---|---------------------------|--------------|----------------|--------------------|--------------------|----------|
| 6.1 | **What is Data-Driven Attribution (DDA)?** | "data driven attribution explained" "google dda" | 390 | Algorithm overview | Comparison with Shapley; when to use | P2 |
| 6.2 | **How to Handle Multicollinearity in Attribution** | "multicollinearity attribution" | 10 | Diagnostic tests + fixes | Technical deep-dive with code | P3 |
| 6.3 | **What is Ordered Shapley Attribution?** | "ordered shapley" "position weighted shapley" | 10 | Definition + use case | Original implementation notes | P3 |
| 6.4 | **How Does Cross-Device Attribution Work Without Cookies?** | "cross device attribution cookieless" | 70 | Identity resolution explanation | mbuzz's approach; privacy-preserving methods | P2 |
| 6.5 | **How to Model Diminishing Returns in Attribution** | "diminishing returns attribution" "saturation modeling" | 30 | Saturation curve explanation | Integration with MMM; advanced formulas | P3 |

---

### Section 7: mbuzz-Specific Guides
*For: mbuzz users getting the most from the platform*

| # | Title (= Target Question) | Target Query | Monthly Search | AEO Snippet Target | Uniqueness Strategy | Priority |
|---|---------------------------|--------------|----------------|--------------------|--------------------|----------|
| 7.1 | **mbuzz vs GA4: Which Attribution Tool is Better?** | "ga4 alternative" "mbuzz vs ga4" | 50 | Feature comparison table | Honest assessment; migration guide | P0 |
| 7.2 | **mbuzz Attribution DSL Reference** | "mbuzz dsl" | - | Complete syntax reference | All commands documented | P0 |
| 7.3 | **How to Set Up mbuzz Server-Side Tracking** | "mbuzz setup" "server side attribution setup" | - | Quick-start checklist | Ruby, Python, Node.js guides | P0 |
| 7.4 | **How to Read the mbuzz Attribution Dashboard** | "mbuzz dashboard guide" | - | Visual tour | Annotated screenshots | P1 |

---

## Detailed Methodology: Bottom-Up Funnel Forecasting with MTA

### The Problem (Article 4.1)

Traditional funnel forecasting uses **last-touch attribution** throughout. This creates:
- Upper-funnel channels get undervalued
- Lower-funnel channels get overvalued
- Channel synergies are invisible
- Forecasts are unreliable for budget allocation

### Our Approach: Tiered Attribution by Funnel Stage (Article 4.2)

**Core Insight**: Different attribution models answer different questions at different funnel stages.

```
┌─────────────────────────────────────────────────────────────────┐
│                   FUNNEL ATTRIBUTION FRAMEWORK                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  TOP OF FUNNEL (Awareness)                                       │
│  ├── Question: "What brings new visitors?"                       │
│  ├── Model: FIRST-TOUCH                                          │
│  ├── Metrics: New visitor volume, discovery channels             │
│  └── Forecast: Lead influx by channel                            │
│                                                                  │
│  MIDDLE OF FUNNEL (Consideration)                                │
│  ├── Question: "What keeps them engaged?"                        │
│  ├── Model: LINEAR / PARTICIPATION                               │
│  ├── Metrics: Engagement depth, channel overlap                  │
│  └── Forecast: Conversion rates by channel combination           │
│                                                                  │
│  BOTTOM OF FUNNEL (Decision)                                     │
│  ├── Question: "What closes the deal?"                           │
│  ├── Model: LAST-TOUCH                                           │
│  └── Metrics: Conversion events, revenue                         │
│  └── Forecast: Revenue by closing channel                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Implementation with mbuzz DSL

```ruby
# ToFU Attribution (First-Touch)
model :tofu_discovery do
  credit first_touch with 1.0
end

# MoFU Attribution (Participation - allows overlap visibility)
model :mofu_engagement do
  credit all_touches equally  # Sum = 1.0 per journey
end

# MoFU Alternative (Participation with over-count)
model :mofu_participation do
  credit participation  # Sum > 1.0, shows channel overlap
end

# BoFU Attribution (Last-Touch)
model :bofu_closing do
  credit last_touch with 1.0
end
```

### The Forecasting Workflow (Article 4.4)

**Step 1: Historical Analysis**
```sql
-- ToFU: First-touch channel distribution
SELECT channel, COUNT(*) as first_touches
FROM attribution_credits
WHERE attribution_model = 'tofu_discovery'
GROUP BY channel;

-- MoFU: Participation overlap
SELECT channel, SUM(credit) as participation_credits
FROM attribution_credits
WHERE attribution_model = 'mofu_participation'
GROUP BY channel;

-- BoFU: Closing channel distribution
SELECT channel, SUM(revenue_credit) as revenue
FROM attribution_credits
WHERE attribution_model = 'bofu_closing'
GROUP BY channel;
```

**Step 2: Calculate Stage Conversion Rates**
```
ToFU → MoFU Conversion Rate (per channel):
  Visitors with channel in MoFU / Visitors with channel as first-touch

MoFU → BoFU Conversion Rate (per channel):
  Conversions with channel in BoFU / Visitors with channel in MoFU
```

**Step 3: Build Bottom-Up Forecast**
```
For each channel:

  Forecasted ToFU Leads =
    Historical first-touch leads × (1 + expected_growth_rate)

  Forecasted MoFU Engaged =
    Forecasted ToFU Leads × ToFU→MoFU conversion rate

  Forecasted BoFU Conversions =
    Forecasted MoFU Engaged × MoFU→BoFU conversion rate

  Forecasted Revenue =
    Forecasted BoFU Conversions × Average Order Value

Total Revenue = Sum of all channel forecasts
```

**Step 4: Validate with Participation Analysis**
```
If Participation Credits (sum) >> 100%:
  → Strong multi-touch journeys
  → Channels are interdependent
  → Reduce individual channel forecasts, increase synergy effect

If Participation Credits (sum) ≈ 100%:
  → Single-touch journeys dominate
  → Channels work independently
  → Individual forecasts are reliable
```

### Lookback Windows by Funnel Stage (Article 4.5)

| Stage | Default Window | Rationale |
|-------|----------------|-----------|
| ToFU | 30-60 days | Discovery can precede engagement |
| MoFU | 14-30 days | Active consideration period |
| BoFU | 7-14 days | Final decision timeframe |

Adjust based on:
- **Sales cycle length**: B2B extends all windows 2-3x
- **Purchase frequency**: Repeat purchases shorten windows
- **Seasonality**: Extend windows during peak planning periods

---

## Content Uniqueness Checklist

Every article must include **AT LEAST 3** of these unique elements:

### Original Research & Data
- [ ] Benchmark data from mbuzz customers
- [ ] A/B test results with sample sizes and confidence intervals
- [ ] Survey data from practitioners
- [ ] Performance comparisons (before/after metrics)

### Proprietary Frameworks
- [ ] Original decision tree or flowchart
- [ ] Named methodology exclusive to mbuzz
- [ ] DSL code examples that work in mbuzz
- [ ] Calculation formulas with worked examples

### Expert Input
- [ ] Practitioner interview/quote
- [ ] Case study with named company (or anonymized with details)
- [ ] Expert review/validation of methodology
- [ ] Failure case with lessons learned

### Interactive/Downloadable Tools
- [ ] Embedded calculator or simulator
- [ ] Excel/Google Sheets template
- [ ] Python/R notebook
- [ ] Decision-support tool

### Visual Content
- [ ] Original diagram (not stock imagery)
- [ ] Annotated screenshot from mbuzz
- [ ] Data visualization from real data
- [ ] Before/after comparison

---

## AEO Optimization Template

Each article follows this structure for AI citation:

```markdown
# [Title as Question]

## TL;DR
[2-3 sentence direct answer. This is what AI will cite.]

## Key Takeaways
- [Specific insight with data if possible]
- [Actionable recommendation]
- [Unique framework or tool mention]

## [Main Content Sections]
### What is [Term]?
[Clear definition - Schema.org compatible]

### Why Does This Matter?
[Context and stakes]

### How Does It Work?
[Technical explanation with formulas/code]

### When Should You Use This?
[Decision criteria - bulleted list]

### Common Mistakes
[What to avoid - numbered list]

### Example
[Worked example with real numbers]

## FAQ
### [Related question 1]?
[Direct answer]

### [Related question 2]?
[Direct answer]

## Related Topics
- [Internal link 1]
- [Internal link 2]
```

---

## Content Production Workflow

### For Each Article

1. **Question Research** (1 hour)
   - Validate search volume (Ahrefs, SEMrush)
   - Check SERP competition
   - Identify featured snippet opportunity
   - Map related questions (People Also Ask)

2. **Uniqueness Planning** (1 hour)
   - Select 3+ unique elements from checklist
   - Plan data/research to gather
   - Identify expert to interview if needed

3. **Framework Creation** (2-3 hours)
   - Original diagrams in Figma/Excalidraw
   - Excel/Python templates
   - DSL code examples tested in mbuzz

4. **Writing** (3-5 hours)
   - Follow AEO template
   - AI assist for structure, human expertise for insights
   - Include all unique elements

5. **Technical Review** (1-2 hours)
   - Dev team accuracy check
   - DSL code verification

6. **SEO Optimization** (1 hour)
   - Keyword placement (title, H2s, meta)
   - Schema markup (FAQPage, HowTo)
   - Internal links (3-5 per article)

---

## Production Phases

### Phase 1: Foundation (P0 Articles) - 12 articles

**Target**: Establish authority on core topics

| Section | Articles | Focus |
|---------|----------|-------|
| 1 | 4 | MTA fundamentals, server-side advantage |
| 2 | 4 | Model selection, GA4 alternative |
| 4 | 2 | Funnel forecasting methodology |
| 5 | 2 | Implementation (lookback, budget) |

### Phase 2: Depth (P1 Articles) - 18 articles

**Target**: Cover all model types and integration patterns

### Phase 3: Authority (P2/P3 Articles) - 12+ articles

**Target**: Advanced topics that establish thought leadership

---

## External Reading List Integration

Curate as "Further Reading" hub:

### Foundational Guides
- [Multi-Touch Attribution: A Complete Guide [2025] - TrueProfit](https://trueprofit.io)
- [Complete Guide To Multi-Touch Attribution - Ruler Analytics](https://ruleranalytics.com)

### Technical Modeling
- [Intelligent attribution modeling for enhanced digital marketing (ScienceDirect)](https://sciencedirect.com)
- [Multi-touch Attribution in Online Advertising with Survival Theory (UCL)](https://ucl.ac.uk)
- [A Probabilistic Multi-Touch Attribution Model (ACM)](https://acm.org)

### MMM & Lift Studies
- [How To Combine Attribution Data With Media Mix Modeling - Branch](https://branch.io)
- [Media Mix Modeling: The Complete Guide for 2025 - Invoca](https://invoca.com)
- [The Value of Calibrating MMM with Lift Experiments - Analytic Edge](https://analyticedge.com)

### Case Studies
- [Multi-Model Attribution Case Study - Choreograph](https://choreograph.com)
- [The Impact of Multi-Touch Attribution on a $2.8B Hospitality Client - Blend360](https://blend360.com)

### Causality & Advanced Theory
- **The Book of Why** by Judea Pearl
- [Shapley Value Methods for Attribution Modeling (arXiv)](https://arxiv.org)
- [A Time To Event Framework For Multi-touch Attribution - Google Research](https://arxiv.org)

---

## Success Metrics

### Search & AEO
- Position 1-3 for target keywords within 6 months
- Featured snippets for 30%+ of articles
- AI citation in ChatGPT/Claude/Perplexity for key questions

### Engagement
- Time on page > 4 minutes
- Scroll depth > 75%
- Tool/template downloads > 5% of visitors

### Business Impact
- Signups from academy pages > 15% of total
- Demo requests mentioning specific articles

---

## Next Steps

1. **Validate funnel methodology**: Review with 2-3 practitioners
2. **Create first P0 article**: "What is Multi-Touch Attribution?" with unique elements
3. **Build forecast template**: Excel downloadable for Section 4
4. **Set up analytics**: Track per-article engagement
5. **Schedule expert interviews**: 3-4 practitioners for case studies

---

## Revision History

| Date | Change |
|------|--------|
| 2025-12-27 | Initial content plan with SEO/AEO optimization |
