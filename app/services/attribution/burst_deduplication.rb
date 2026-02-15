# frozen_string_literal: true

module Attribution
  module BurstDeduplication
    BURST_WINDOW = 5.minutes

    private

    def collapse_burst_sessions(touchpoints)
      return touchpoints if touchpoints.size <= 1

      touchpoints.each_with_object([touchpoints.first]) do |touchpoint, collapsed|
        next if touchpoint == touchpoints.first

        previous = collapsed.last
        gap = touchpoint[:occurred_at] - previous[:occurred_at]

        next if gap <= BURST_WINDOW && touchpoint[:channel] == "direct"

        collapsed << touchpoint
      end
    end
  end
end
