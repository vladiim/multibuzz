# frozen_string_literal: true

module Dashboard
  class ConversionDetailQuery
    def initialize(account)
      @account = account
    end

    def call(prefix_id)
      conversion = find_conversion(prefix_id)
      return unless conversion

      attach_journey_sessions(conversion)
      conversion
    end

    private

    attr_reader :account

    def find_conversion(prefix_id)
      account.conversions
        .includes(:visitor, :identity, attribution_credits: :attribution_model)
        .find_by_prefix_id(prefix_id)
    end

    def attach_journey_sessions(conversion)
      sessions = load_journey_sessions(conversion.journey_session_ids)
      ordered = order_by_ids(sessions, conversion.journey_session_ids)

      time_gaps = compute_time_gaps(ordered)
      dtc = compute_days_to_convert(ordered, conversion.converted_at)

      conversion.define_singleton_method(:journey_sessions) { ordered }
      conversion.define_singleton_method(:journey_time_gaps) { time_gaps }
      conversion.define_singleton_method(:days_to_convert) { dtc }
    end

    def load_journey_sessions(session_ids)
      return [] if session_ids.blank?

      Session.where(id: session_ids)
    end

    def order_by_ids(sessions, ids)
      return [] if ids.blank?

      index = sessions.index_by(&:id)
      ids.filter_map { |id| index[id] }
    end

    def compute_time_gaps(sessions)
      sessions.each_cons(2).map do |a, b|
        (b.started_at - a.started_at) / 1.day
      end
    end

    def compute_days_to_convert(sessions, converted_at)
      return nil if sessions.empty?

      (converted_at - sessions.first.started_at) / 1.day
    end
  end
end
