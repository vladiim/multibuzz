# frozen_string_literal: true

module AttributionModels
  class TestService
    SAMPLE_JOURNEYS = {
      four_touch: [
        { session_id: "sess_1", channel: "organic_search", occurred_at: 30.days.ago },
        { session_id: "sess_2", channel: "email", occurred_at: 14.days.ago },
        { session_id: "sess_3", channel: "paid_search", occurred_at: 7.days.ago },
        { session_id: "sess_4", channel: "direct", occurred_at: 1.day.ago }
      ],
      two_touch: [
        { session_id: "sess_1", channel: "paid_social", occurred_at: 14.days.ago },
        { session_id: "sess_2", channel: "email", occurred_at: 1.day.ago }
      ],
      single_touch: [
        { session_id: "sess_1", channel: "organic_search", occurred_at: 1.day.ago }
      ]
    }.freeze

    CHANNEL_LABELS = {
      "organic_search" => "Organic Search",
      "paid_search" => "Paid Search",
      "paid_social" => "Paid Social",
      "email" => "Email",
      "direct" => "Direct",
      "referral" => "Referral",
      "display" => "Display"
    }.freeze

    def initialize(dsl_code:, journey_type: :four_touch)
      @dsl_code = dsl_code
      @journey_type = journey_type.to_sym
    end

    def call
      credits = execute_model
      build_results(credits)
    rescue AML::SecurityError, AML::ValidationError, AML::SyntaxError, AML::CreditSumError => e
      error_result(e.message)
    rescue StandardError => e
      error_result("Execution error: #{e.message}")
    end

    private

    attr_reader :dsl_code, :journey_type

    def execute_model
      AML::Executor.new(
        dsl_code: dsl_code,
        touchpoints: touchpoints,
        conversion_time: Time.current,
        conversion_value: 100.0
      ).call
    end

    def touchpoints
      SAMPLE_JOURNEYS.fetch(journey_type, SAMPLE_JOURNEYS[:four_touch])
    end

    def build_results(credits)
      {
        success: true,
        results: touchpoints.each_with_index.map do |tp, index|
          {
            position: index + 1,
            channel: tp[:channel],
            channel_label: CHANNEL_LABELS.fetch(tp[:channel], tp[:channel].titleize),
            credit: credits[index].round(4),
            percentage: (credits[index] * 100).round(1)
          }
        end,
        total: credits.sum.round(4)
      }
    end

    def error_result(message)
      { success: false, error: message }
    end
  end
end
