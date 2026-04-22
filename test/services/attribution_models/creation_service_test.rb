# frozen_string_literal: true

require "test_helper"

class AttributionModels::CreationServiceTest < ActiveSupport::TestCase
  test "succeeds for a custom model with valid params" do
    account.update!(plan: starter_plan)

    result = service.call

    assert result[:success], "expected success: #{result[:errors].inspect}"
    assert_predicate result[:model], :persisted?
  end

  test "fires feature_custom_model_created with current model count and limit" do
    account.update!(plan: starter_plan)

    service.call

    assert(tracked_event, "expected feature_custom_model_created to be recorded")
    assert_equal account.attribution_models.where(model_type: :custom).count, tracked_event[:properties][:model_count]
    assert_equal account.custom_model_limit, tracked_event[:properties][:model_limit]
  end

  test "does not fire feature_custom_model_created when over the limit" do
    account.update!(plan: starter_plan)
    over_limit_count.times { |i| account.attribution_models.create!(name: "Custom #{i}", model_type: :custom, dsl_code: "test") }
    Lifecycle::Tracker.reset_recorded_events!

    service.call

    assert_nil tracked_event
  end

  test "does not fire feature_custom_model_created when AML code is invalid" do
    account.update!(plan: starter_plan)

    AttributionModels::CreationService.new(account, name: "Evil", dsl_code: 'system("rm -rf /")').call

    assert_nil tracked_event
  end

  private

  def service = @service ||= AttributionModels::CreationService.new(account, valid_params)
  def account = @account ||= accounts(:one)
  def starter_plan = @starter_plan ||= plans(:starter)
  def tracked_event = Lifecycle::Tracker.recorded_events.find { |e| e[:name] == "feature_custom_model_created" }

  def valid_params
    {
      name: "My Model",
      dsl_code: "within_window 30.days do\n  apply 1.0, to: touchpoints.first\nend",
      lookback_days: 30
    }
  end

  def over_limit_count
    account.custom_model_limit + 1
  end
end
