# Nested Window Attribution Segments - Spec

## Overview

Extend the AML (Attribution Model Language) DSL to support nested `within_window` blocks that create time-based segments of the customer journey, allowing different attribution rules to apply to different periods.

---

## Problem Statement

Current limitation: `within_window` only sets a single `@lookback_window` value and doesn't support nesting. Users cannot create segment-based attribution models like:
- "60% credit to last 30 days, 40% to 31-60 days"
- "Recency-weighted time decay with distinct segments"

---

## Proposed Syntax

### Basic Nested Windows

```ruby
within_window 90.days do
  within_window 0.days..30.days, weight: 0.6 do
    time_decay half_life: 7.days
  end
  within_window 30.days..60.days, weight: 0.4 do
    time_decay half_life: 7.days
  end
end
```

### Semantics

1. **Outer `within_window`**: Sets the overall lookback period (required)
2. **Inner `within_window` with Range**: Creates a segment filtering touchpoints to that time range
3. **`weight:` parameter**: Allocates a portion of total credit (1.0) to this segment
4. **Range interpretation**: `0.days..30.days` = touchpoints that occurred 0-30 days before conversion

### Alternative Shorthand (Sugar)

```ruby
# Shorthand: single duration means "from 0 to N days"
within_window 30.days, weight: 0.6 do
  time_decay half_life: 7.days
end

# Equivalent to:
within_window 0.days..30.days, weight: 0.6 do
  time_decay half_life: 7.days
end
```

---

## Full Examples

### Example 1: Recency-Weighted Segments

```ruby
within_window 90.days do
  # Last 30 days get 60% of credit
  within_window 30.days, weight: 0.6 do
    time_decay half_life: 7.days
  end
  # 31-60 days get 30% of credit
  within_window 30.days..60.days, weight: 0.3 do
    time_decay half_life: 14.days
  end
  # 61-90 days get 10% of credit
  within_window 60.days..90.days, weight: 0.1 do
    apply 1.0, to: touchpoints, distribute: :equal
  end
end
```

### Example 2: First/Last Touch with Recency Bonus

```ruby
within_window 60.days do
  # Recent touchpoints (last 7 days) get heavier weight
  within_window 7.days, weight: 0.5 do
    apply 0.7, to: touchpoints.last
    apply 0.3, to: touchpoints, distribute: :equal
  end
  # Older touchpoints (8-60 days)
  within_window 7.days..60.days, weight: 0.5 do
    apply 0.6, to: touchpoints.first
    apply 0.4, to: touchpoints, distribute: :equal
  end
end
```

### Example 3: Simple Two-Segment Model

```ruby
within_window 60.days do
  within_window 30.days, weight: 0.7 do
    time_decay half_life: 7.days
  end
  within_window 30.days..60.days, weight: 0.3 do
    time_decay half_life: 14.days
  end
end
```

---

## Behavior Specification

### 1. Touchpoint Filtering

When inside a nested `within_window`, the `touchpoints` collection is filtered to only include touchpoints within that time range:

```ruby
within_window 90.days do
  within_window 30.days do
    # touchpoints here only includes those from 0-30 days before conversion
    apply 1.0, to: touchpoints.first
  end
end
```

### 2. Credit Weighting

- Each segment's `weight:` parameter defines what portion of total credit (1.0) is allocated to that segment
- Credits assigned within the segment are scaled by the weight
- Segment weights must sum to 1.0 (validated)

**Example:**
```ruby
within_window 60.days do
  within_window 30.days, weight: 0.6 do
    # time_decay assigns [0.6, 0.4] (sum=1.0) to 2 touchpoints
    # After weighting: [0.36, 0.24] (sum=0.6)
    time_decay half_life: 7.days
  end
  within_window 30.days..60.days, weight: 0.4 do
    # apply assigns [1.0] to 1 touchpoint
    # After weighting: [0.4] (sum=0.4)
    apply 1.0, to: touchpoints.first
  end
end
# Total: [0.36, 0.24, 0.4] = 1.0
```

### 3. Empty Segments

If a segment contains no touchpoints, its weight is redistributed proportionally to other segments:

```ruby
# If no touchpoints exist in 30-60 day range, the 0.3 weight is redistributed
within_window 60.days do
  within_window 30.days, weight: 0.7 do
    time_decay half_life: 7.days
  end
  within_window 30.days..60.days, weight: 0.3 do  # No touchpoints here
    time_decay half_life: 14.days
  end
end
# Result: 30-day segment gets 100% of credit (weights normalized to 1.0)
```

### 4. Nesting Depth

- Maximum nesting depth: 2 levels (outer window + one segment level)
- Deeper nesting raises `AML::ValidationError`

### 5. Validation Rules

1. **Segment weights must sum to 1.0** (with 0.0001 tolerance)
2. **Segments cannot overlap** - ranges must be disjoint
3. **Segments must be within outer window** - `30.days..60.days` invalid if outer is `45.days`
4. **Inner windows require `weight:`** when there are multiple segments

---

## Implementation Changes

### 1. Context Class Changes

```ruby
module AML
  module Sandbox
    class Context
      def within_window(duration_or_range, weight: nil, &block)
        if @lookback_window.nil?
          # Outer window - sets overall lookback
          @lookback_window = normalize_duration(duration_or_range)
          safe_eval(&block) if block_given?
        else
          # Inner window - creates segment
          segment = Segment.new(
            range: normalize_range(duration_or_range),
            weight: weight,
            parent_context: self
          )
          segment.execute(&block)
          @segments << segment
        end
      end

      private

      def normalize_range(duration_or_range)
        case duration_or_range
        when Range
          duration_or_range
        when ActiveSupport::Duration, Numeric
          0.seconds..duration_or_range
        end
      end
    end
  end
end
```

### 2. New Segment Class

```ruby
module AML
  module Sandbox
    class Segment
      def initialize(range:, weight:, parent_context:)
        @range = range
        @weight = weight
        @parent_context = parent_context
        @filtered_touchpoints = filter_touchpoints
      end

      def execute(&block)
        # Execute block with filtered touchpoints
        # Scale resulting credits by weight
      end

      private

      def filter_touchpoints
        @parent_context.touchpoints.select do |tp|
          days_before = (conversion_time - tp.occurred_at) / 1.day
          @range.cover?(days_before.days)
        end
      end
    end
  end
end
```

### 3. Credit Ledger Changes

- Add support for segment-scoped credit assignment
- Merge segment credits into main ledger after segment execution
- Apply weight scaling during merge

---

## Edge Cases

### 1. Single Touchpoint Journey

```ruby
within_window 60.days do
  within_window 30.days, weight: 0.6 do
    apply 1.0, to: touchpoints.first
  end
  within_window 30.days..60.days, weight: 0.4 do
    apply 1.0, to: touchpoints.first
  end
end
# If touchpoint is 5 days old: 100% credit to first segment (weight redistributed)
```

### 2. All Touchpoints in One Segment

When all touchpoints fall into a single segment, that segment receives 100% credit regardless of declared weight.

### 3. Backward Compatibility

Existing non-nested usage continues to work:

```ruby
# Still valid - no weight required for single window
within_window 30.days do
  time_decay half_life: 7.days
end
```

---

## Security Considerations

1. **Range objects**: Add Range to whitelist for DSL
2. **Duration arithmetic**: Already supported via whitelist
3. **No new attack surface**: Segments use existing safe_eval mechanism

---

## Test Cases

### Unit Tests

1. `within_window` with range creates filtered touchpoint collection
2. Segment weights scale credits correctly
3. Empty segments redistribute weight
4. Overlapping segments raise validation error
5. Weights not summing to 1.0 raise validation error
6. Nested windows deeper than 2 levels raise error
7. Single duration shorthand (`30.days`) expands to range (`0..30.days`)
8. `touchpoints.first` within segment returns first of filtered collection

### Integration Tests

1. Recency-weighted two-segment model produces correct attribution
2. Three-segment model with time_decay in each segment
3. Mixed algorithms across segments (time_decay + linear + first_touch)
4. Edge case: Journey spans multiple segments correctly

---

## Migration

No database migrations required. This is a DSL enhancement that's backward compatible.

---

## Homepage Example

Update homepage "Custom" model card with this example:

```ruby
within_window 90.days do
  within_window 30.days, weight: 0.6 do
    time_decay half_life: 7.days
  end
  within_window 30.days..60.days, weight: 0.4 do
    time_decay half_life: 14.days
  end
end
```

Caption: "Recency-weighted segments: 60% to last 30 days with fast decay, 40% to 31-60 days with slower decay."
