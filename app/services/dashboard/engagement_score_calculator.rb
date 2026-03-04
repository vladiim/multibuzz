# frozen_string_literal: true

module Dashboard
  class EngagementScoreCalculator
    # --- Component Bounds ---
    MAX_COMPONENT = 1.0
    MIN_COMPONENT = 0.0

    # --- Recency ---
    RECENCY_DECAY_DAYS = 90

    # --- Frequency ---
    FREQUENCY_SESSION_CAP = 20

    # --- Monetary ---
    REVENUE_PERCENTILE = 0.95
    REVENUE_FLOOR = 1.0

    # --- Breadth ---
    CHANNEL_DIVERSITY_CAP = 5

    # --- Overall Score ---
    COMPONENT_COUNT = 4
    SCORE_SCALE = 100

    # --- Tiers ---
    TIER_HOT = "Hot"
    TIER_WARM = "Warm"
    TIER_ENGAGED = "Engaged"
    TIER_COOL = "Cool"
    TIER_COLD = "Cold"

    HOT_THRESHOLD = 80
    WARM_THRESHOLD = 60
    ENGAGED_THRESHOLD = 40
    COOL_THRESHOLD = 20

    TIERS = [
      { min: HOT_THRESHOLD, label: TIER_HOT },
      { min: WARM_THRESHOLD, label: TIER_WARM },
      { min: ENGAGED_THRESHOLD, label: TIER_ENGAGED },
      { min: COOL_THRESHOLD, label: TIER_COOL },
      { min: MIN_COMPONENT, label: TIER_COLD }
    ].freeze

    def initialize(account, identity)
      @account = account
      @identity = identity
    end

    def call
      compute_components
        .then { |components| score_from(components).merge(components: components) }
    end

    private

    attr_reader :account, :identity

    def compute_components
      {
        recency: recency_score,
        frequency: frequency_score,
        monetary: monetary_score,
        breadth: breadth_score
      }
    end

    def score_from(components)
      score = (components.values.sum / COMPONENT_COUNT.to_f * SCORE_SCALE).round
      { score: score, tier: tier_for(score) }
    end

    def recency_score
      days_ago = (Time.current - identity.last_identified_at) / 1.day
      return MIN_COMPONENT if days_ago >= RECENCY_DECAY_DAYS

      MAX_COMPONENT - (days_ago / RECENCY_DECAY_DAYS)
    end

    def frequency_score
      cap(session_count.to_f / FREQUENCY_SESSION_CAP)
    end

    def monetary_score
      return MIN_COMPONENT if total_revenue.zero? || revenue_cap.zero?

      cap(total_revenue / revenue_cap)
    end

    def breadth_score
      cap(distinct_channels.to_f / CHANNEL_DIVERSITY_CAP)
    end

    def cap(value)
      [ value, MAX_COMPONENT ].min
    end

    def session_count
      @session_count ||= Session.where(visitor_id: visitor_ids).count
    end

    def distinct_channels
      @distinct_channels ||= Session.where(visitor_id: visitor_ids)
        .where.not(channel: nil)
        .distinct
        .count(:channel)
    end

    def total_revenue
      @total_revenue ||= account.conversions
        .where(identity: identity)
        .sum(:revenue)
        .to_f
    end

    def revenue_cap
      @revenue_cap ||= begin
        revenue_scope = account.conversions.where.not(revenue: nil)
        p95_offset = (revenue_scope.count * REVENUE_PERCENTILE).to_i
        p95 = revenue_scope.order(:revenue).offset(p95_offset).pick(:revenue)&.to_f || MIN_COMPONENT

        [ p95, REVENUE_FLOOR ].max
      end
    end

    def visitor_ids
      @visitor_ids ||= account.visitors.where(identity: identity).pluck(:id)
    end

    def tier_for(score)
      TIERS.find { |t| score >= t[:min] }.fetch(:label)
    end
  end
end
