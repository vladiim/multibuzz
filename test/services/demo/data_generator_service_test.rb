# frozen_string_literal: true

require "test_helper"

class Demo::DataGeneratorServiceTest < ActiveSupport::TestCase
  test "returns demo data structure" do
    result = service.call

    assert_kind_of Hash, result
    assert result.key?(:sessions)
    assert result.key?(:conversions)
    assert result.key?(:channel_breakdown)
  end

  test "generates sessions across multiple channels" do
    result = service.call

    channels = result[:sessions].map { |s| s[:channel] }.uniq

    assert_includes channels, Channels::PAID_SEARCH
    assert_includes channels, Channels::ORGANIC_SEARCH
    assert_includes channels, Channels::EMAIL
  end

  test "generates conversions with revenue" do
    result = service.call

    assert_predicate result[:conversions], :any?
    assert result[:conversions].all? { |c| c[:revenue].present? }
  end

  test "generates channel breakdown with attribution" do
    result = service.call

    assert_predicate result[:channel_breakdown], :any?
    result[:channel_breakdown].each do |breakdown|
      assert breakdown.key?(:channel)
      assert breakdown.key?(:credit)
      assert breakdown.key?(:revenue_credit)
    end
  end

  test "generates sample journeys for visualization" do
    result = service.call

    assert result.key?(:sample_journey)
    journey = result[:sample_journey]

    assert_predicate journey[:touchpoints], :any?
    assert_predicate journey[:conversion], :present?
  end

  test "channel breakdown sums to 100 percent" do
    result = service.call

    total_credit = result[:channel_breakdown].sum { |b| b[:credit] }

    assert_in_delta 1.0, total_credit, 0.01
  end

  test "returns consistent data for same seed" do
    result1 = Demo::DataGeneratorService.new(seed: 42).call
    result2 = Demo::DataGeneratorService.new(seed: 42).call

    assert_equal result1[:conversions].size, result2[:conversions].size
    assert_equal result1[:channel_breakdown], result2[:channel_breakdown]
  end

  private

  def service
    @service ||= Demo::DataGeneratorService.new
  end
end
