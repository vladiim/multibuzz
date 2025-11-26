# frozen_string_literal: true

require "test_helper"

module Conversions
  class AttributionCalculationServiceTest < ActiveSupport::TestCase
    test "calculates credits for all active models" do
      result = service.call

      assert result[:success]
      assert_includes result[:credits_by_model].keys, "First Touch"
      assert_includes result[:credits_by_model].keys, "Last Touch"
    end

    test "stores attribution credits in database" do
      # 2 sessions × 2 models, but First Touch = 1 credit, Last Touch = 1 credit = 2 total
      assert_difference "AttributionCredit.count", 2 do
        service.call
      end
    end

    test "calculates revenue credits when conversion has revenue" do
      conversion_with_revenue = build_conversion(revenue: 100.00)
      revenue_service = build_service(conversion_with_revenue)

      result = revenue_service.call

      assert result[:success]
      credits = result[:credits_by_model]["First Touch"]
      assert credits.all? { |c| c[:revenue_credit].present? }
    end

    test "returns empty credits for visitor with no sessions" do
      empty_conversion = build_conversion(visitor: visitors(:other_account_visitor))
      empty_service = build_service(empty_conversion)

      result = empty_service.call

      assert result[:success]
      assert result[:credits_by_model].values.all?(&:empty?)
    end

    private

    def service
      @service ||= build_service(conversion)
    end

    def build_service(conv)
      Conversions::AttributionCalculationService.new(conv)
    end

    def conversion
      @conversion ||= build_conversion
    end

    def build_conversion(visitor: default_visitor, revenue: nil)
      create_sessions_for_visitor(visitor)

      Conversion.create!(
        account: visitor.account,
        visitor: visitor,
        session_id: 1,
        event_id: 1,
        conversion_type: "purchase",
        revenue: revenue,
        converted_at: Time.current,
        journey_session_ids: []
      )
    end

    def create_sessions_for_visitor(visitor)
      return if visitor == visitors(:other_account_visitor)

      Session.create!(
        account: visitor.account,
        visitor: visitor,
        session_id: SecureRandom.hex(16),
        started_at: 10.days.ago,
        channel: "organic_search",
        initial_utm: { "utm_source" => "google" }
      )

      Session.create!(
        account: visitor.account,
        visitor: visitor,
        session_id: SecureRandom.hex(16),
        started_at: 3.days.ago,
        channel: "email",
        initial_utm: { "utm_source" => "newsletter", "utm_medium" => "email" }
      )
    end

    def default_visitor
      @default_visitor ||= visitors(:two)
    end
  end
end
