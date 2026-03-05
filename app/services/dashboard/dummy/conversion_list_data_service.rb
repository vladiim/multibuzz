# frozen_string_literal: true

module Dashboard
  module Dummy
    class ConversionListDataService # rubocop:disable Metrics/ClassLength
      CREDIT_MODELS = {
        "first_touch" => ->(n) { [ 1.0 ] + Array.new([ n - 1, 0 ].max, 0.0) },
        "last_touch" => ->(n) { Array.new([ n - 1, 0 ].max, 0.0) + [ 1.0 ] },
        "linear" => ->(n) { Array.new(n) { (1.0 / n).round(2) } },
        "time_decay" => ->(n) {
          raw = Array.new(n) { |i| 2.0**i }
          total = raw.sum
          raw.map { |w| (w / total).round(2) }
        },
        "u_shaped" => ->(n) {
          if n <= 2
            Array.new(n) { (1.0 / n).round(2) }
          else
            middle_share = (0.2 / (n - 2)).round(2)
            [ 0.4 ] + Array.new(n - 2, middle_share) + [ 0.4 ]
          end
        }
      }.freeze

      CONVERSIONS = [
        { id: "conv_demo_001", type: "Purchase", revenue: 249.00, currency: "USD", is_test: false, is_acquisition: true,
          date_offset: 1, channels: %w[paid_search organic_search email], identity: "sarah.chen@acme.co",
          sessions: 3, utm_sources: %w[google google mailchimp] },
        { id: "conv_demo_002", type: "Purchase", revenue: 89.00, currency: "USD", is_test: false, is_acquisition: false,
          date_offset: 1, channels: %w[paid_social direct], identity: "james.wilson@company.io",
          sessions: 2, utm_sources: %w[facebook nil] },
        { id: "conv_demo_003", type: "Signup", revenue: nil, currency: "USD", is_test: false, is_acquisition: true,
          date_offset: 2, channels: %w[organic_search], identity: nil,
          sessions: 1, utm_sources: %w[google] },
        { id: "conv_demo_004", type: "Purchase", revenue: 179.00, currency: "USD", is_test: false, is_acquisition: false,
          date_offset: 3, channels: %w[email paid_search paid_social organic_search], identity: "alex.rivera@startup.com",
          sessions: 4, utm_sources: %w[mailchimp google facebook google] },
        { id: "conv_demo_005", type: "Trial Start", revenue: nil, currency: "USD", is_test: false, is_acquisition: true,
          date_offset: 4, channels: %w[paid_search referral], identity: "m.tanaka@enterprise.jp",
          sessions: 2, utm_sources: %w[google partner-blog] },
        { id: "conv_demo_006", type: "Purchase", revenue: 59.00, currency: "USD", is_test: false, is_acquisition: false,
          date_offset: 5, channels: %w[direct], identity: "taylor.smith@gmail.com",
          sessions: 1, utm_sources: [ nil ] },
        { id: "conv_demo_007", type: "Purchase", revenue: 299.00, currency: "USD", is_test: false, is_acquisition: true,
          date_offset: 6, channels: %w[paid_social organic_search email paid_search], identity: "li.wang@bigcorp.com",
          sessions: 4, utm_sources: %w[instagram google newsletter google] },
        { id: "conv_demo_008", type: "Signup", revenue: nil, currency: "USD", is_test: false, is_acquisition: true,
          date_offset: 7, channels: %w[organic_search referral], identity: nil,
          sessions: 2, utm_sources: %w[bing techcrunch] },
        { id: "conv_demo_009", type: "Purchase", revenue: 149.00, currency: "USD", is_test: false, is_acquisition: false,
          date_offset: 8, channels: %w[email], identity: "priya.patel@agency.co",
          sessions: 1, utm_sources: %w[drip-campaign] },
        { id: "conv_demo_010", type: "Purchase", revenue: 199.00, currency: "USD", is_test: false, is_acquisition: true,
          date_offset: 10, channels: %w[paid_search display organic_search], identity: "carlos.mendez@shop.mx",
          sessions: 3, utm_sources: %w[google display-retarget google] },
        { id: "conv_demo_011", type: "Trial Start", revenue: nil, currency: "USD", is_test: false, is_acquisition: true,
          date_offset: 12, channels: %w[organic_social organic_search], identity: nil,
          sessions: 2, utm_sources: %w[linkedin google] },
        { id: "conv_demo_012", type: "Purchase", revenue: 129.00, currency: "USD", is_test: false, is_acquisition: false,
          date_offset: 14, channels: %w[paid_search], identity: "emma.jones@retail.uk",
          sessions: 1, utm_sources: %w[google] }
      ].freeze

      def call
        { conversions: build_conversions, total_count: CONVERSIONS.size }
      end

      def find(id)
        entry = CONVERSIONS.find { |c| c[:id] == id }
        return nil unless entry

        build_conversion(entry).tap { |conv| enrich_with_journey(conv, entry) }
      end

      private

      def build_conversions
        CONVERSIONS.map { |entry| build_conversion(entry) }
      end

      def build_conversion(entry) # rubocop:disable Metrics/AbcSize
        OpenStruct.new(
          prefix_id: entry[:id],
          converted_at: Time.current - entry[:date_offset].days + rand(1..12).hours,
          conversion_type: entry[:type],
          revenue: entry[:revenue],
          currency: entry[:currency],
          is_test: entry[:is_test],
          is_acquisition: entry[:is_acquisition],
          journey_session_ids: Array.new(entry[:sessions]) { |i| "sess_demo_#{entry[:id][-3..]}_#{i}" },
          identity: entry[:identity] ? OpenStruct.new(prefix_id: "id_#{entry[:id][-3..]}", external_id: entry[:identity]) : nil,
          properties: entry[:type] == "Purchase" ? { "plan" => "pro", "billing" => "annual" } : {},
          funnel: entry[:type] == "Purchase" ? "checkout" : nil,
          visitor: OpenStruct.new(prefix_id: "vis_#{entry[:id][-3..]}"),
          attribution_credits: []
        )
      end

      def enrich_with_journey(conv, entry)
        conv.journey_sessions = build_journey_sessions(conv, entry)
        conv.journey_time_gaps = compute_time_gaps(conv.journey_sessions)
        conv.days_to_convert = compute_days_to_convert(conv)
        conv.attribution_credits = build_credits(entry)
      end

      def build_journey_sessions(conv, entry)
        entry[:channels].each_with_index.map do |channel, i|
          days_before = (entry[:channels].size - i) * rand(1..5)
          OpenStruct.new(
            channel: channel,
            initial_utm: entry[:utm_sources][i] ? { "utm_source" => entry[:utm_sources][i] } : {},
            initial_referrer: nil,
            started_at: conv.converted_at - days_before.days,
            landing_page_host: "mbuzz.co"
          )
        end
      end

      def compute_time_gaps(sessions)
        sessions.each_cons(2).map { |a, b| (b.started_at - a.started_at) / 1.day }
      end

      def compute_days_to_convert(conv)
        return nil unless conv.journey_sessions.any?

        (conv.converted_at - conv.journey_sessions.first.started_at) / 1.day
      end

      def build_credits(entry)
        CREDIT_MODELS.flat_map { |name, fn| credits_for_model(entry, name, fn) }
      end

      def credits_for_model(entry, model_name, weight_fn)
        weights = weight_fn.call(entry[:channels].size)
        model = OpenStruct.new(name: model_name)

        entry[:channels].each_with_index.map do |channel, i|
          OpenStruct.new(
            channel: channel, credit: weights[i],
            revenue_credit: entry[:revenue] ? (entry[:revenue] * weights[i]).round(2) : nil,
            utm_source: entry[:utm_sources][i],
            utm_campaign: channel == "paid_search" ? "brand-awareness" : nil,
            attribution_model: model
          )
        end
      end
    end
  end
end
