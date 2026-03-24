# frozen_string_literal: true

require "test_helper"

module SpendIntelligence
  class ResponseCurveServiceTest < ActiveSupport::TestCase
    test "returns empty hash when no channels have sufficient weeks" do
      assert_equal({}, service.call)
    end

    test "marginal_roas returns nil for unfitted channel" do
      assert_nil service.marginal_roas(Channels::PAID_SEARCH, 1000)
    end

    private

    def service
      @service ||= ResponseCurveService.new(
        spend_scope: spend_scope,
        credits_scope: credits_scope
      )
    end

    def spend_scope
      @spend_scope ||= Scopes::SpendScope.new(
        account: account,
        date_range: Date.yesterday..Date.current
      ).call
    end

    def credits_scope
      @credits_scope ||= Dashboard::Scopes::CreditsScope.new(
        account: account,
        models: [ attribution_model ],
        date_range: date_range,
        test_mode: false
      ).call
    end

    def account = @account ||= accounts(:one)
    def attribution_model = @attribution_model ||= attribution_models(:last_touch)
    def date_range = @date_range ||= Dashboard::DateRangeParser.new("30d")
  end
end
