# Conversion Funnel Analysis Across Channels and Attribution Models

**Status**: Design Standard
**Last Updated**: 2025-11-19
**See also**: `lib/docs/architecture/attribution_methodology.md`

---

## Purpose

This document explains how to analyze conversion funnels across different marketing channels and compare results using different attribution models.

**Key principle**: Funnel analysis and attribution analysis are **separate but complementary** concerns.

---

## 1. Core Concepts

### 1.1 Funnel Analysis vs Attribution Analysis

**Funnel Analysis**:
- **Question**: "How many users progress through steps?"
- **Measures**: Drop-off rates, conversion rates per step
- **Granularity**: Event-level
- **Example**: Homepage → Product → Cart → Checkout → Purchase

**Attribution Analysis**:
- **Question**: "Which channels deserve credit for conversions?"
- **Measures**: Attribution credits, revenue per channel
- **Granularity**: Session-level (touchpoints)
- **Example**: Google → Facebook → Email touchpoints leading to purchase

**Relationship**:
- Funnel analysis identifies WHERE users drop off
- Attribution analysis identifies WHICH CHANNELS brought users who convert

### 1.2 Channel-Segmented Funnels

**Definition**: Funnel analysis filtered by channel exposure.

**Types**:
1. **First-touch channel filter**: Users who first visited via this channel
2. **Any-touch channel filter**: Users who had this channel anywhere in journey
3. **Last-touch channel filter**: Users who converted via this channel

**Purpose**: Understand how different channels perform at converting users through funnel steps.

---

## 2. Funnel Analysis Methodology

### 2.1 Standard Funnel Structure

**Components**:
- **Steps**: Ordered sequence of events (page_view → add_to_cart → purchase)
- **Conversion window**: Time allowed to complete funnel (e.g., 30 days)
- **Drop-off calculation**: Users who completed step N but not step N+1

**Formula**:
```
Overall Conversion Rate =
  Users who completed all steps /
  Users who entered funnel (step 1)

Step-to-Step Conversion Rate =
  Users who completed step N /
  Users who completed step N-1
```

**Example**:
```
Homepage: 10,000 users (100%)
  ↓
Product Page: 4,000 users (40% of homepage)
  ↓
Add to Cart: 1,200 users (30% of product, 12% of homepage)
  ↓
Checkout: 800 users (66.7% of cart, 8% of homepage)
  ↓
Purchase: 600 users (75% of checkout, 6% of homepage)

Overall conversion: 6% (600/10,000)
Biggest drop-off: Product → Cart (70% drop)
```

### 2.2 Channel-Segmented Funnel Analysis

**Three analysis modes**:

#### Mode 1: First-Touch Channel Filter

**Definition**: Analyze funnel for users whose first touchpoint was a specific channel.

**Use case**: "How well does Paid Search acquire users who convert?"

**Query logic**:
```
1. Find all users with first session channel = "paid_search"
2. For these users, analyze their funnel progression
3. Calculate conversion rates
```

**Example results**:
```
Paid Search (First Touch):
- Homepage: 2,000 users (100%)
- Product: 1,000 users (50%)
- Cart: 400 users (20%)
- Checkout: 300 users (15%)
- Purchase: 250 users (12.5%)

Organic Search (First Touch):
- Homepage: 5,000 users (100%)
- Product: 2,000 users (40%)
- Cart: 500 users (10%)
- Checkout: 300 users (6%)
- Purchase: 200 users (4%)

Insight: Paid Search has higher conversion rate (12.5% vs 4%)
```

#### Mode 2: Any-Touch Channel Filter

**Definition**: Analyze funnel for users who had this channel anywhere in their journey.

**Use case**: "Which users who interacted with Email eventually convert?"

**Query logic**:
```
1. Find all users with ANY session channel = "email"
2. For these users, analyze funnel progression
3. Calculate conversion rates
```

**Critical note**: Same user can appear in multiple channel segments if they interacted with multiple channels.

#### Mode 3: Last-Touch Channel Filter

**Definition**: Analyze funnel for users whose last touchpoint before conversion was this channel.

**Use case**: "Which channels are present at point of conversion?"

**Query logic**:
```
1. Find all conversions where last session channel = "paid_search"
2. For these users, trace back their funnel progression
3. Calculate conversion rates
```

### 2.3 Time-Windowed Funnel Analysis

**Conversion windows by business model**:
- **E-commerce checkout**: 30 minutes to 1 hour
- **SaaS trial signup**: 1-7 days
- **B2B lead qualification**: 30-90 days

**Implementation**:
```
Funnel step completion criteria:
1. User completes step 1 (homepage view)
2. User must complete step 2 (product view) within conversion window
3. User must complete step 3 (add to cart) within window from step 1
4. etc.
```

**Flexible windows**:
- Allow configuration per funnel
- Support different windows per step (e.g., quick checkout but slow consideration)

---

## 3. Attribution Model Impact on Channel Funnel Analysis

### 3.1 How Attribution Changes Channel Performance

**Key insight**: Different attribution models will show different channel funnel performance because they credit channels differently.

**Example scenario**:
```
User Journey:
1. Day 1: Google Organic → Homepage view
2. Day 3: Facebook Ad → Product view, Add to cart
3. Day 5: Email → Checkout, Purchase ($100)

Funnel: Homepage → Product → Cart → Checkout → Purchase
Conversion: Purchase ($100)
```

**Under First-Touch Attribution**:
- Google Organic gets 100% credit ($100)
- Channel funnel shows: Google drove homepage → purchase
- Conversion rate: High for Google

**Under Last-Touch Attribution**:
- Email gets 100% credit ($100)
- Channel funnel shows: Email drove checkout → purchase
- Conversion rate: High for Email

**Under Linear Attribution**:
- Google: 33.3% ($33.33)
- Facebook: 33.3% ($33.33)
- Email: 33.3% ($33.33)
- Channel funnels show: All three channels contributed equally

### 3.2 Channel Funnel Conversion Rates by Attribution Model

**Formula**:
```
Channel Funnel Conversion Rate (Channel X, Model Y) =
  Sum of attribution credits to Channel X under Model Y /
  Users who had Channel X in journey
```

**Example with real numbers**:

```
Scenario: 1,000 conversions analyzed

Users with Paid Search touchpoint: 600
Users with Email touchpoint: 400
Users with Organic Search touchpoint: 500

First-Touch Attribution:
- Paid Search total credits: 450
- Email total credits: 50
- Organic Search total credits: 500

Channel conversion rates:
- Paid Search: 450/600 = 75%
- Email: 50/400 = 12.5%
- Organic Search: 500/500 = 100%

Linear Attribution:
- Paid Search total credits: 300
- Email total credits: 200
- Organic Search total credits: 500

Channel conversion rates:
- Paid Search: 300/600 = 50%
- Email: 200/400 = 50%
- Organic Search: 500/500 = 100%

Insight: Attribution model changes perceived channel effectiveness
```

### 3.3 Model Comparison Dashboard

**Side-by-side view**:

```
Channel Funnel Performance Comparison

Channel: Paid Search
Homepage → Product → Cart → Checkout → Purchase

First Touch Model:
- Conversion Rate: 75%
- Revenue Attributed: $45,000
- Funnel Drop-off: Product → Cart (biggest)

U-Shaped Model:
- Conversion Rate: 62%
- Revenue Attributed: $38,000
- Funnel Drop-off: Product → Cart (biggest)

Linear Model:
- Conversion Rate: 50%
- Revenue Attributed: $30,000
- Funnel Drop-off: Product → Cart (biggest)

Insight: Drop-off points same, but conversion rate varies by model
```

---

## 4. Multi-Channel Funnel Analysis

### 4.1 Journey-Based Funnel Segments

**Segment by journey patterns**:

**Single-channel journeys**:
- Users with only one channel touchpoint
- Example: Google → Google → Google → Convert
- Analysis: Pure channel performance

**Multi-channel journeys**:
- Users with multiple channel touchpoints
- Example: Google → Facebook → Email → Convert
- Analysis: Channel collaboration/interaction

**Common journey patterns**:
```
Pattern 1: Organic → Paid (32% of conversions)
- User discovers via organic search
- Retargeted with paid ad
- Converts via paid

Pattern 2: Paid → Email (25% of conversions)
- User acquires via paid ad
- Nurtures via email
- Converts via email click

Pattern 3: Organic → Organic (18% of conversions)
- Pure organic user
- Multiple visits via organic search
- Converts directly
```

### 4.2 Channel Interaction Analysis

**Question**: "How do channels work together in funnels?"

**Metrics**:
1. **Assisted conversions**: Channel appears in journey but not last touch
2. **Direct conversions**: Channel is last touch
3. **Assisted/Direct ratio**: Measure of channel role (assist vs close)

**Example**:
```
Facebook Ads:
- Direct conversions: 100
- Assisted conversions: 400
- Ratio: 4:1 (primarily assists, rarely closes)

Email:
- Direct conversions: 300
- Assisted conversions: 150
- Ratio: 1:2 (primarily closes deals)

Insight: Facebook acquires, Email converts
```

### 4.3 Cross-Channel Funnel Paths

**Sankey diagram approach**:

```
Step 1 (Homepage):
  - Organic Search: 5,000 users
  - Paid Search: 2,000 users
  - Social: 1,500 users
  ↓
Step 2 (Product Page):
  - Organic → Organic: 2,000 users
  - Organic → Paid: 500 users
  - Paid → Paid: 1,000 users
  - Paid → Email: 300 users
  - Social → Social: 600 users
  ↓
Step 3 (Add to Cart):
  - Organic → Organic → Organic: 800
  - Organic → Paid → Email: 200
  - Paid → Email → Email: 400
  ...

Shows: Which channel combinations lead to conversion
```

---

## 5. Implementation Architecture

### 5.1 Data Models

**Funnel Definition**:
```
Funnel:
- name (e.g., "Purchase Funnel")
- steps (ordered array of event_types)
- conversion_window (duration)
- conversion_event (final step)
```

**Funnel Analysis Result**:
```
FunnelAnalysis:
- funnel_id
- channel_filter (optional: "paid_search", "email", null for all)
- attribution_model_id (optional: for weighted analysis)
- date_range
- results:
  - step_completions (users at each step)
  - step_conversion_rates (step-to-step %)
  - overall_conversion_rate
  - drop_off_analysis
```

**Channel Journey Pattern**:
```
JourneyPattern:
- pattern_signature (e.g., "organic→paid→email")
- occurrence_count
- conversion_rate
- average_revenue
- average_journey_duration
```

### 5.2 Service Architecture

**Query Services**:

**Funnel::AnalysisService**:
- Input: funnel definition, date range, filters
- Output: step completion counts, conversion rates
- Method: `analyze(funnel, date_range, channel_filter: nil)`

**Funnel::ChannelSegmentationService**:
- Input: funnel, channel, segmentation mode (first/any/last)
- Output: funnel results filtered by channel exposure
- Method: `segment_by_channel(funnel, channel, mode: :first_touch)`

**Funnel::AttributionWeightedService**:
- Input: funnel, attribution_model
- Output: funnel results weighted by attribution credits
- Method: `analyze_with_attribution(funnel, model)`

**Journey::PatternAnalysisService**:
- Input: date_range, minimum_occurrences
- Output: common journey patterns with metrics
- Method: `discover_patterns(date_range, min_occurrences: 10)`

**Attribution Model Comparison Services**:

**Attribution::ModelComparisonService**:
- Input: conversion_set, attribution_models (array)
- Output: side-by-side comparison of channel credits
- Method: `compare_models(conversions, models)`

**Attribution::ChannelPerformanceService**:
- Input: channel, attribution_models, date_range
- Output: performance metrics under each model
- Method: `analyze_channel_performance(channel, models, date_range)`

### 5.3 Continuous Aggregates (Performance Optimization)

**Pre-computed views** (TimescaleDB):

**funnel_completion_daily**:
```
Aggregates:
- account_id, funnel_id, step_index, channel_filter, day
- users_entered, users_completed, conversion_rate
Refresh: Hourly
```

**journey_patterns_daily**:
```
Aggregates:
- account_id, pattern_signature, day
- occurrence_count, conversion_count, total_revenue
Refresh: Hourly
```

**channel_attribution_by_model**:
```
Aggregates:
- account_id, channel, attribution_model_id, day
- total_credits, revenue_credits, conversion_count
Refresh: Hourly
```

**Performance benefit**: Funnel queries <100ms instead of 1-5 seconds for raw event data.

---

## 6. Dashboard Visualizations

### 6.1 Standard Funnel View

**Horizontal funnel chart**:
```
[Homepage]  →  [Product]  →  [Cart]  →  [Checkout]  →  [Purchase]
  10,000      4,000 (40%)   1,200 (30%)  800 (67%)    600 (75%)
              60% drop      70% drop     33% drop     25% drop

Biggest opportunity: Product → Cart (70% drop-off)
```

### 6.2 Channel-Segmented Funnel View

**Stacked funnel comparison**:
```
Paid Search:
[Home] → [Product] → [Cart] → [Checkout] → [Purchase]
2,000    1,000 (50%)  400(40%)  300(75%)     250(83%)

Organic Search:
[Home] → [Product] → [Cart] → [Checkout] → [Purchase]
5,000    2,000(40%)   500(25%)  300(60%)     200(67%)

Comparison:
- Paid Search: Higher conversion at every step
- Organic Search: Bigger volume but lower conversion
```

### 6.3 Multi-Model Attribution Comparison

**Table view**:
```
Channel Performance by Attribution Model

Channel       | First Touch | U-Shaped | Linear | Time Decay
--------------|-------------|----------|--------|------------
Paid Search   | 75% ($45k)  | 62% ($38k)| 50% ($30k) | 58% ($35k)
Organic       | 100% ($50k) | 85% ($42k)| 70% ($35k) | 75% ($38k)
Email         | 12% ($5k)   | 28% ($14k)| 50% ($25k) | 65% ($33k)
Social        | 40% ($20k)  | 42% ($21k)| 45% ($23k) | 48% ($24k)

Insight: Email value increases with later-touch models
```

### 6.4 Journey Pattern Visualization

**Sankey diagram**:
```
Shows flow from first touch → middle touches → last touch → conversion

Width of flow = number of users following that path

Example paths:
- Organic → Organic → Organic: 800 users (thick line)
- Organic → Paid → Email: 200 users (medium line)
- Paid → Email → Email: 400 users (thick line)
- Social → Social: 100 users (thin line)
```

---

## 7. Use Cases and Insights

### 7.1 Optimize Marketing Mix

**Question**: "Which channels should we invest more in?"

**Analysis approach**:
1. Run funnel analysis for each channel (first-touch filter)
2. Compare conversion rates across channels
3. Apply multiple attribution models for validation
4. Consider cost per acquisition (CPA) for ROI

**Example insight**:
```
First-Touch Analysis:
- Paid Search: 12.5% conversion, $50 CPA → ROI: Positive
- Organic Search: 4% conversion, $0 CPA → ROI: Excellent (free)
- Social: 6% conversion, $80 CPA → ROI: Negative

Multi-Touch Analysis (U-Shaped):
- Paid Search: 10% conversion (still good)
- Social: 9% conversion (assists many conversions)

Decision: Increase Social budget (strong assist role revealed by multi-touch)
```

### 7.2 Identify Drop-Off Points by Channel

**Question**: "Where do users from different channels drop off?"

**Analysis approach**:
1. Run channel-segmented funnels
2. Identify step with biggest drop-off per channel
3. Investigate channel-specific UX issues

**Example insight**:
```
Paid Search users:
- Drop-off: Homepage → Product (50%)
- Hypothesis: Landing page mismatch with ad creative

Organic Search users:
- Drop-off: Product → Cart (75%)
- Hypothesis: Price sensitivity (organic users less purchase-intent)

Email users:
- Drop-off: Cart → Checkout (40%)
- Hypothesis: Shipping cost surprise
```

### 7.3 Multi-Touch Journey Optimization

**Question**: "What journey patterns convert best?"

**Analysis approach**:
1. Discover common journey patterns
2. Calculate conversion rate per pattern
3. Optimize marketing to encourage high-converting patterns

**Example insight**:
```
High-Converting Patterns:
1. Organic → Email → Email: 25% conversion rate
   → Strategy: Build email list from organic traffic

2. Paid → Organic → Email: 22% conversion rate
   → Strategy: Paid acquisition + SEO + email nurture

Low-Converting Patterns:
1. Social → Social → Social: 3% conversion rate
   → Strategy: Don't rely on social alone, add email nurture
```

### 7.4 Attribution Model Selection

**Question**: "Which attribution model reflects our business reality?"

**Analysis approach**:
1. Compare channel performance under different models
2. Validate against business knowledge (which channels actually drive value?)
3. Select model that aligns with strategy

**Example decision**:
```
Comparison shows:
- First Touch: Over-credits Paid Search (acquisition)
- Last Touch: Over-credits Email (conversion)
- U-Shaped: Balances acquisition + conversion

Business context:
- Paid Search brings new users
- Email nurtures and converts
- Both are critical

Decision: Use U-Shaped as primary model (40/40/20)
Rationale: Credits both acquisition and conversion appropriately
```

---

## 8. Implementation Phases

### Phase 1: Basic Funnel Analysis (Week 1)

**Features**:
- Define funnels (ordered event sequences)
- Calculate overall conversion rates
- Identify drop-off points

**Queries**:
- Standard funnel without channel segmentation
- Simple step-to-step conversion rates

### Phase 2: Channel-Segmented Funnels (Week 2)

**Features**:
- Filter funnels by channel (first/any/last touch)
- Compare channel performance
- Channel-specific drop-off analysis

**Queries**:
- Funnel completion by channel
- Cross-channel funnel comparison

### Phase 3: Attribution-Weighted Analysis (Week 3)

**Features**:
- Apply attribution models to funnel analysis
- Multi-model comparison dashboards
- Attribution-adjusted conversion rates

**Queries**:
- Channel performance under different models
- Side-by-side model comparison

### Phase 4: Journey Pattern Discovery (Week 4)

**Features**:
- Discover common journey patterns
- Pattern conversion rate analysis
- Journey optimization recommendations

**Queries**:
- Pattern frequency and conversion
- Sankey diagram data

---

## 9. Key Formulas

### 9.1 Standard Funnel Metrics

**Overall Conversion Rate**:
```
Users who completed all funnel steps /
Users who entered funnel (step 1)
```

**Step-to-Step Conversion Rate**:
```
Users who completed step N /
Users who completed step N-1
```

**Drop-Off Rate**:
```
1 - (Step-to-step conversion rate)
```

### 9.2 Channel-Segmented Metrics

**Channel Funnel Conversion Rate**:
```
Users who completed funnel with Channel X in journey /
Users who entered funnel with Channel X touchpoint
```

**Channel-Specific Drop-Off**:
```
Users with Channel X who dropped at step N /
Users with Channel X who reached step N-1
```

### 9.3 Attribution-Weighted Metrics

**Attributed Conversion Rate** (Channel X, Model Y):
```
Sum of attribution credits to Channel X under Model Y /
Users who had Channel X touchpoint in journey
```

**Attribution-Weighted Revenue**:
```
Sum(credit × conversion_revenue) for all conversions with Channel X
```

---

## 10. References

**See also**:
- `lib/docs/architecture/attribution_methodology.md` - Core attribution concepts
- `lib/specs/implementation_plan_rest_api_first.md` - Implementation roadmap
- `lib/specs/attribution_dsl_design.md` - Custom model DSL

**Research sources**:
- Amplitude Funnel Analysis Documentation
- Mixpanel Funnel Best Practices
- Google Analytics 4 Funnel Exploration
- Adobe Analytics Path Analysis

---

## 11. Summary

**Key principles**:

1. **Separate concerns**: Funnel analysis (event-level) vs Attribution (session-level)
2. **Channel segmentation**: Filter funnels by channel exposure (first/any/last)
3. **Multi-model comparison**: Different models reveal different channel value
4. **Journey patterns**: Discover high-converting channel combinations
5. **Continuous aggregates**: Pre-compute for <100ms dashboard queries

**Implementation priority**:
1. Basic funnels → Channel segments → Attribution weighting → Journey patterns
2. Start simple, add complexity based on user needs
3. Optimize with continuous aggregates when scale demands it
