# Channel vs UTM Attribution Analysis

**Status**: Technical Decision Document
**Date**: 2025-11-19
**Decision**: Channel-Primary, UTM-Secondary (CONFIRMED)

---

## Question

Should attribution algorithms use:
- **Option A**: Channel as primary attribution dimension (current approach)
- **Option B**: UTM parameters as primary attribution dimension
- **Option C**: Hybrid approach

---

## Current Implementation Analysis

### What We Have Built

1. **Session Creation** (`app/services/events/processing_service.rb:52-63`):
   ```ruby
   # On first event in session:
   session.update(
     initial_utm: utm_data,        # Raw UTM parameters (jsonb)
     initial_referrer: referrer,   # Referrer URL
     channel: channel              # Classified channel
   )
   ```

2. **Channel Classification** (`app/services/sessions/channel_attribution_service.rb`):
   - **Input**: UTM data (utm_medium, utm_source) + referrer URL
   - **Output**: Standardized channel (one of 11 values)
   - **Logic**:
     - UTM present → classify by utm_medium pattern
     - No UTM but referrer → classify by domain pattern
     - Neither → "direct"

3. **Channel Taxonomy** (`app/constants/channels.rb`):
   ```ruby
   PAID_SEARCH = "paid_search"
   ORGANIC_SEARCH = "organic_search"
   PAID_SOCIAL = "paid_social"
   ORGANIC_SOCIAL = "organic_social"
   EMAIL = "email"
   DISPLAY = "display"
   AFFILIATE = "affiliate"
   REFERRAL = "referral"
   VIDEO = "video"
   DIRECT = "direct"
   OTHER = "other"
   ```

4. **Attribution Credits Table** (`db/schema.rb:49-69`):
   ```ruby
   t.string "channel", null: false     # PRIMARY: Standardized channel
   t.decimal "credit", precision: 5, scale: 4, null: false
   t.string "utm_source"               # SECONDARY: For drill-down
   t.string "utm_medium"               # SECONDARY: For drill-down
   t.string "utm_campaign"             # SECONDARY: For drill-down
   ```

5. **Database Indexes**:
   - Primary index: `["account_id", "attribution_model_id", "channel"]`
   - Secondary index: `["attribution_model_id", "channel"]`
   - **No indexes on UTM fields** (drill-down only)

### Data Flow Summary

```
URL → UTM Extraction → Channel Classification → Session Storage
                                                     ↓
                                            channel (string)
                                            initial_utm (jsonb)
                                                     ↓
                                            Attribution Algorithm
                                                     ↓
                                            Attribution Credits
                                                     ↓
                                            channel (PRIMARY)
                                            utm_* (SECONDARY)
```

---

## Industry Research (2024)

### Key Findings

1. **Channel Grouping is Standard** (Google Analytics, Adobe Analytics, Mixpanel):
   - All major platforms use **channel groupings** as primary attribution dimension
   - UTM parameters feed INTO channel groupings
   - Channel = abstraction layer over raw UTM data

2. **UTM Parameters are Foundation** (CXL, utm.io):
   - "Before implementing MTA, verify UTM parameters are correct - otherwise MTA is waste of time"
   - UTM consistency is critical for accurate attribution
   - Missing/inconsistent UTMs → over-attribution to "Direct"

3. **Two-Level Hierarchy** (GA4, Mixpanel):
   - **Level 1 (Primary)**: Channel grouping - broad categories for strategic decisions
   - **Level 2 (Secondary)**: UTM drill-down - granular campaign performance

4. **Custom Channel Definitions** (Google Analytics):
   - Platforms allow custom channel groupings based on UTM rules
   - Flexibility to match business reporting needs
   - Can retroactively change channel definitions

### Why Channel-Primary Works

1. **Consistency**: UTM tagging varies by team member, campaign, platform
2. **Standardization**: 11 channels vs hundreds/thousands of UTM combinations
3. **Strategic Reporting**: CMOs care about "How much credit does paid search get?" not "How much credit does utm_medium=cpc&utm_source=google&utm_campaign=brand_q4_2024 get?"
4. **Performance**: Aggregating by channel (11 values) is faster than UTM combinations
5. **Historical Flexibility**: Can reclassify channels without changing raw UTM data

---

## Recommended Approach: Channel-Primary, UTM-Secondary

### ✅ CONFIRMED: Current Implementation is Correct

**Primary Attribution Dimension**: `channel`
- Attribution algorithms distribute credit across channels
- Dashboard aggregates by channel
- Channel is dimension for model comparison

**Secondary Drill-Down**: `utm_source`, `utm_medium`, `utm_campaign`
- Stored in attribution_credits for granular analysis
- Users can filter "paid_search" → drill into specific campaigns
- No indexes needed (drill-down is infrequent)

### Data Architecture

```ruby
# Attribution Algorithm Output
{
  session_id: 123,
  channel: "paid_search",           # PRIMARY: Attribution credit goes here
  credit: 0.33,
  utm_source: "google",             # SECONDARY: For drill-down
  utm_medium: "cpc",                # SECONDARY: For drill-down
  utm_campaign: "brand_q4"          # SECONDARY: For drill-down
}
```

### Dashboard UX Flow

1. **Top-level view**: Channel performance across attribution models
   ```
   Model: First Touch
   - Paid Search: 40% of conversions
   - Organic Search: 30% of conversions
   - Email: 20% of conversions
   ```

2. **Drill-down**: Click "Paid Search" → see campaign breakdown
   ```
   Paid Search → Campaigns
   - google/cpc/brand: 25%
   - google/cpc/competitor: 10%
   - bing/cpc/brand: 5%
   ```

---

## Implementation Decisions

### ✅ Keep in Attribution Credits Table
- `channel` (not null, indexed)
- `utm_source` (nullable, not indexed)
- `utm_medium` (nullable, not indexed)
- `utm_campaign` (nullable, not indexed)

### ✅ Algorithm Interface
Attribution algorithms should receive touchpoints with:
```ruby
[
  {
    session_id: 100,
    channel: "organic_search",      # Already classified
    occurred_at: Time
  },
  {
    session_id: 101,
    channel: "paid_search",
    occurred_at: Time
  }
]
```

And return credits with:
```ruby
[
  {
    session_id: 100,
    channel: "organic_search",      # From input touchpoint
    credit: 0.5
  },
  {
    session_id: 101,
    channel: "paid_search",
    credit: 0.5
  }
]
```

### ✅ UTM Data Enrichment
Journey Builder should enrich touchpoints with UTM data from sessions:
```ruby
[
  {
    session_id: 100,
    channel: "organic_search",      # From sessions.channel
    utm_source: "google",           # From sessions.initial_utm
    utm_medium: "organic",          # From sessions.initial_utm
    utm_campaign: nil,              # From sessions.initial_utm
    occurred_at: Time
  }
]
```

### ❌ Do NOT Pass UTMs to Attribution Algorithms
Attribution algorithms should NOT receive or process UTM parameters. They only work with:
- `session_id`
- `channel` (already classified)
- `occurred_at` (for time-decay models)

---

## Benefits of This Approach

### 1. Separation of Concerns
- **Channel Classification**: Separate service (`Sessions::ChannelAttributionService`)
- **Attribution Logic**: Only cares about channels, not UTM complexity

### 2. Performance
- Attribution queries: `WHERE channel = 'paid_search'` (indexed, 11 values)
- Drill-down queries: `WHERE utm_campaign = 'brand'` (not indexed, occasional)

### 3. Flexibility
- Change channel classification rules without reprocessing attribution
- Sessions retain raw UTM data (jsonb) for re-classification

### 4. User Experience
- Strategic view: Channels (simple, executive-friendly)
- Tactical view: UTM drill-down (detailed, analyst-friendly)

### 5. Industry Standard
- Matches GA4, Mixpanel, Adobe Analytics patterns
- Familiar mental model for users

---

## Testing Strategy

### Unit Tests for Attribution Algorithms
```ruby
# ✅ CORRECT: Test with channels
touchpoints = [
  { session_id: 1, channel: "organic_search", occurred_at: 5.days.ago },
  { session_id: 2, channel: "email", occurred_at: 2.days.ago },
  { session_id: 3, channel: "paid_search", occurred_at: 1.hour.ago }
]

credits = Attribution::Algorithms::Linear.new(touchpoints).call

assert_equal "organic_search", credits[0][:channel]
assert_equal 0.33, credits[0][:credit]
```

```ruby
# ❌ INCORRECT: Test with UTM parameters
touchpoints = [
  {
    session_id: 1,
    utm_source: "google",
    utm_medium: "organic",
    occurred_at: 5.days.ago
  }
]
# Attribution algorithm should NOT classify channels!
```

---

## Migration Path (None Needed)

Current implementation is already correct. No changes needed to:
- Database schema ✓
- Session channel classification ✓
- Attribution credits table structure ✓
- Indexes ✓

Only need to:
1. Ensure attribution algorithms use `channel` (not UTMs)
2. Journey Builder enriches with UTM data for storage
3. Tests verify channel-based attribution

---

## References

### Internal Documentation
- `lib/docs/architecture/attribution_methodology.md` - Attribution design
- `app/services/sessions/channel_attribution_service.rb` - Channel classification
- `app/constants/channels.rb` - Channel taxonomy

### External Research (2024)
- CXL: "UTM Parameters for Attribution" - UTMs feed channel groupings
- utm.io: "UTMs for MTA" - Verify UTMs before building MTA
- Google Analytics: Channel groupings based on UTM rules
- Mixpanel: Attribution uses channel segments, UTMs for drill-down

---

## Decision Log

**Date**: 2025-11-19
**Decision**: Channel-Primary, UTM-Secondary approach CONFIRMED
**Rationale**:
- Current implementation matches industry best practices
- Performance optimized (indexed channels, not UTMs)
- User experience aligned with GA4/Mixpanel patterns
- Separation of concerns (classification separate from attribution)

**Action Items**:
1. ✅ Update attribution algorithm tests to use `channel` only
2. ✅ Remove UTM parameters from algorithm interfaces
3. ✅ Journey Builder enriches touchpoints with UTM data for storage
4. ✅ Document in CLAUDE.md for future consistency

---

**Last Updated**: 2025-11-19
