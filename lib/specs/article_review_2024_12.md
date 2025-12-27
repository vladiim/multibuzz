# MTA Academy Article Review

**Date**: 2024-12-27
**Reviewer**: Claude
**Articles Reviewed**: 13 P0 articles

---

## Research Summary: Real Customer Problems

Based on research from Reddit, Quora, X, and industry publications, these are the **actual problems** customers face with attribution:

### Top Pain Points (Priority Order)

| Problem | Sources | Current Coverage | Gap? |
|---------|---------|------------------|------|
| **"Attribution is broken/dead"** | SparkToro, MarketingWeek, Corvidae | Partially (GA4 article) | Need stronger "what to do instead" content |
| **GA4 removed models, now what?** | Reddit, Napkyn, Piwik Pro | ✅ Covered well | Good |
| **Platform data conflicts** (Google says X, Meta says Y) | Common complaint | Mentioned briefly | Need dedicated article |
| **Privacy/cookie loss breaking tracking** | SparkToro, industry-wide | ✅ Server-side article | Good |
| **Last-touch over-credits closers** | Neil Patel, AdRoll, WhatConverts | ✅ Multiple articles | Very good |
| **"Dark funnel" untrackable touches** | Karmic, SingleGrain | Not addressed | **GAP** |
| **B2B long sales cycles break attribution** | Supermetrics, Quora | Partially (forecasting) | Need B2B-specific article |
| **CMOs cutting analytics teams** | Gartner 2024 | Not addressed | Could add business case |
| **80% of marketers see AdTech bias** | Industry research | GA4 article touches | Could strengthen |
| **Extended attribution windows for Reddit/social** | Karmic, Rockerbox | Lookback article | Add social-specific guidance |

### Quotes from Real Users (Paraphrased)

1. *"It's a difficult topic, and when you look directly at it, managing your marketing becomes harder—and no one wants to hear that."* - Quora
2. *"Customers discuss products in private Slack groups, read reviews on unmonitored forums...30-50% of purchase influences are non-trackable."* - Industry research
3. *"One conversion, three claims"* - on platform attribution conflicts
4. *"Reddit attribution shows 2x higher in post-purchase surveys than tracking tools capture"* - Karmic

---

## Review by Criteria

### 1. COHESION ✅ Strong

**Strengths:**
- Consistent voice and technical depth across all articles
- Related articles are properly cross-linked
- Logical progression: Fundamentals → Models → Forecasting → Implementation
- Unified terminology (ToFU/MoFU/BoFU, tiered attribution)
- All articles follow same structure (TL;DR, content, summary, further reading)

**Issues to Fix:**
| Issue | Location | Fix |
|-------|----------|-----|
| Dead internal link | `what-is-multi-touch-attribution.md.erb` line 18 | Change `attribution-lookback-windows` → `attribution-lookback-window` |
| Missing related article | `ga4-attribution-models-removed.md.erb` | Add link to `mta-vs-mmm` |
| Inconsistent slug | Some reference `linear-attribution` which doesn't exist yet | Create P1 article or remove references |

**Missing Connective Tissue:**
- Need a "Start Here" or "Learning Path" page that sequences articles
- Forecasting section jumps into solution without linking back to "why MTA matters"

---

### 2. UNIQUENESS ⚠️ Needs Work

**What Makes Content Unique (Per Research):**
1. Proprietary data/benchmarks
2. Named frameworks/methodologies
3. Interactive tools
4. Expert quotes/case studies
5. Code examples

**Current Status:**

| Unique Element | Count | Quality |
|---------------|-------|---------|
| **Placeholders for mbuzz data** | 35+ | Good - need to fill |
| **Named frameworks** | 2 (Tiered Attribution, Attribution Death Spiral) | Need more |
| **Code examples** | 8 articles | Good - Ruby, SQL |
| **Interactive calculators** | 0 (all placeholders) | **GAP** |
| **Expert quotes** | 0 | **GAP** |
| **Case studies** | 0 | **GAP** |

**Recommendations:**

1. **Create signature framework names:**
   - "Attribution Death Spiral" ✅ (already used)
   - "Tiered Funnel Attribution" ✅ (already used)
   - ADD: "The Attribution Confidence Score" (quality metric)
   - ADD: "Channel Role Matrix" (introducer/closer/nurturer)
   - ADD: "The 90/10 Rule" (90% of journey ignored by last-touch)

2. **Unique claims that aren't in competitor content:**
   - [ ] "mbuzz data shows X% of conversions have 4+ touchpoints"
   - [ ] "After implementing tiered attribution, customers see Y% forecast improvement"
   - [ ] Specific Shapley vs Markov comparison chart (GA4 article has text, needs visual)

3. **Missing competitor differentiators:**
   - Competitors emphasize "easy setup" - we emphasize accuracy
   - Competitors show dashboards - we show methodology
   - We need BOTH: methodology credibility + "how mbuzz makes it easy"

---

### 3. CUSTOMER FIT ⚠️ Gaps Identified

**Well-Addressed Problems:**
- ✅ GA4 model removal confusion
- ✅ Last-touch over-credits closers
- ✅ How to choose a model
- ✅ Server-side vs client-side
- ✅ Budget reallocation methodology

**NOT Addressed (High Priority):**

| Problem | Search Volume | Competitor Coverage | Priority |
|---------|---------------|--------------------| ---------|
| **"Dark funnel" / untrackable touchpoints** | Growing | SparkToro, Gartner | P0 |
| **Platform data disagrees (Google vs Meta)** | High | Limited | P0 |
| **B2B-specific attribution** (long cycles, multiple stakeholders) | Medium | Supermetrics, Dreamdata | P1 |
| **How to explain attribution to executives** | Medium | None | P1 |
| **Attribution for podcast/influencer/offline** | Growing | Limited | P1 |

**Content Gaps to Create:**

```
PRIORITY NEW ARTICLES:

1. "Why Your Platform Reports Don't Match (And What to Trust)"
   - Google claims X, Meta claims Y, email claims Z
   - How to reconcile conflicting data
   - The "single source of truth" approach

2. "What Attribution Can't Track (The Dark Funnel)"
   - Word of mouth, private channels, Slack, podcasts
   - Survey-based attribution
   - MMM for untrackable channels

3. "Attribution for B2B: Long Sales Cycles and Multiple Decision-Makers"
   - Account-based attribution
   - Influence vs sourcing credit
   - Connecting marketing to sales pipeline
```

---

### 4. SEO ✅ Strong Foundation

**What's Working:**
- Titles are target queries ("What is Multi-Touch Attribution?")
- Meta descriptions are compelling
- H2s contain keywords
- Internal linking structure exists
- FAQ schema is set up

**Issues:**

| Issue | Impact | Fix |
|-------|--------|-----|
| No word count metadata | Can't verify 1500-2500 target | Add to publishing checklist |
| Some H2s are too generic ("How It Works") | Lower keyword density | Make H2s query-specific |
| Missing "People Also Ask" coverage | Lost snippet opportunities | Expand FAQ sections |
| No alt text for future images | Accessibility + SEO | Add to template |

**Keyword Opportunities Not Covered:**

From research, these high-intent queries aren't directly targeted:

| Query | Volume | Current Coverage |
|-------|--------|------------------|
| "attribution is broken" | Growing | Partially (could be title) |
| "GA4 attribution alternative" | 480+/mo | Mentioned, not targeted |
| "marketing attribution for B2B" | 500+/mo | Not covered |
| "attribution without cookies" | Growing | Mentioned in MMM, not dedicated |
| "how to prove marketing ROI" | High | Not covered |

---

### 5. AEO (Answer Engine Optimization) ✅ Good Structure

**What's Working:**
- TL;DR format matches featured snippet requirements
- FAQ structured data ready
- Key takeaways are quotable
- Direct answers in first 100 words

**Improvements Needed:**

| Element | Current | Optimal |
|---------|---------|---------|
| TL;DR length | 50-80 words | 40-50 words (tighter for AI citation) |
| Key takeaways | 4 per article | Keep 4, make more specific/numeric |
| Definition format | Prose | Add explicit "X is defined as..." for entities |
| Comparison tables | Present | Good - AI loves structured comparisons |

**AEO-Specific Additions:**

For each article, add:
1. **Entity definition box**: "Multi-Touch Attribution (MTA) is..."
2. **Numeric claims**: "MTA typically reveals 30-40% more touchpoints than single-touch"
3. **Comparison snippets**: Clear winner statements when appropriate

---

## Article-by-Article Issues

### Fundamentals Section

| Article | Issues |
|---------|--------|
| what-is-multi-touch-attribution | Dead link (line 18); "6-8 touchpoints" needs source |
| mta-vs-mmm | Good. Add Pearl's Ladder diagram to placeholder |
| server-side-vs-client-side-tracking | Good. Quantify "25-40% more" claim with source |
| ga4-attribution-models-removed | Strong. Could add "GA4 alternative" as secondary keyword |

### Models Section

| Article | Issues |
|---------|--------|
| first-touch-attribution | Good. Missing B2B-specific use case examples |
| last-touch-attribution | Strong. "Death spiral" is memorable framework |
| how-to-choose-attribution-model | Good. Decision tree placeholder is critical to fill |

### Forecasting Section

| Article | Issues |
|---------|--------|
| last-touch-funnel-forecasting-problem | Strong. Core differentiator content |
| funnel-stage-attribution | Good. Needs mbuzz screenshots |
| bottom-up-revenue-forecast | Strong. Calculator placeholder critical |
| forecast-templates-business-model | Good. Downloadable templates critical |

### Implementation Section

| Article | Issues |
|---------|--------|
| budget-reallocation-attribution | Strong. Marginal ROAS is unique angle |
| attribution-lookback-window | Good. Add social-specific guidance |

---

## Priority Actions

### Immediate (Before Launch)

1. **Fix dead internal links** (attribution-lookback-windows → attribution-lookback-window)
2. **Add explicit definitions** to first paragraph of each article for AEO
3. **Tighten TL;DRs** to 40-50 words
4. **Review all "related_articles"** - remove references to non-existent articles

### Short-Term (First Month)

1. **Create "Platform Data Conflicts" article** (addresses #1 user complaint)
2. **Create "Dark Funnel" article** (addresses untrackable touches)
3. **Fill 5 highest-impact placeholders** (decision tree, calculators)
4. **Get 2-3 expert quotes** for outreach (Kevin Hillstrom, Simo Ahava)

### Medium-Term (Quarter 1)

1. **Create B2B attribution guide**
2. **Build interactive calculators** (forecast, window comparison)
3. **Develop "Learning Path" landing page**
4. **Add customer case studies** (1-2 per section)

---

## Competitive Positioning

Based on research, position mbuzz content as:

| Competitor Angle | mbuzz Counter-Position |
|------------------|----------------------|
| "Attribution is dead" (SparkToro) | "Attribution is evolving - here's the modern approach" |
| "Use MMM instead" (Recast) | "MTA + MMM together - here's how" |
| "Just use GA4 DDA" (Google) | "GA4's black box has limits - transparent attribution" |
| "Simple dashboards" (most tools) | "Methodology-first, with tools to implement" |

**Unique mbuzz angle to emphasize:**
- Tiered attribution (first-touch/linear/last-touch by stage)
- Transparency (not black-box like GA4 DDA)
- Technical depth with practical templates
- Forecasting use case (not just reporting)

---

## Summary Scores

| Criteria | Score | Notes |
|----------|-------|-------|
| **Cohesion** | 8/10 | Strong, minor link fixes needed |
| **Uniqueness** | 6/10 | Frameworks good, need data + quotes |
| **Customer Fit** | 7/10 | Core problems covered, gaps in dark funnel/B2B |
| **SEO** | 8/10 | Good foundation, some keyword gaps |
| **AEO** | 7/10 | Structure good, tighten TL;DRs |

**Overall: 7.2/10 - Strong foundation, needs unique content + gap articles**
