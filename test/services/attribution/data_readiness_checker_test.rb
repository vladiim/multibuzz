# frozen_string_literal: true

require "test_helper"

module Attribution
  class DataReadinessCheckerTest < ActiveSupport::TestCase
    # Data requirements from spec:
    # - Markov Chain: 500 conversions, 5+ channels
    # - Shapley Value: 500 conversions, 5-15 channels

    setup do
      account.conversions.destroy_all
      account.sessions.destroy_all
    end

    test "should return ready status for all probabilistic models" do
      result = service.call

      assert result.key?(:markov_chain)
      assert result.key?(:shapley_value)
      assert result[:markov_chain].key?(:ready)
      assert result[:shapley_value].key?(:ready)
    end

    test "should show ready when account has 500+ conversions and 5+ channels" do
      create_conversions(500, channels: 5)

      result = service.call

      assert result[:markov_chain][:ready]
      assert result[:shapley_value][:ready]
    end

    test "should show not ready when account has fewer than 500 conversions" do
      create_conversions(100, channels: 5)

      result = service.call

      assert_not result[:markov_chain][:ready]
      assert_not result[:shapley_value][:ready]
    end

    test "should show not ready when account has fewer than 5 channels" do
      create_conversions(500, channels: 3)

      result = service.call

      assert_not result[:markov_chain][:ready]
    end

    test "should include current conversion count" do
      create_conversions(250, channels: 5)

      result = service.call

      assert_equal 250, result[:markov_chain][:current_conversions]
    end

    test "should include required conversion count" do
      result = service.call

      assert_equal 500, result[:markov_chain][:required_conversions]
      assert_equal 500, result[:shapley_value][:required_conversions]
    end

    test "should include conversions needed" do
      create_conversions(300, channels: 5)

      result = service.call

      assert_equal 200, result[:markov_chain][:conversions_needed]
    end

    test "should show zero conversions needed when ready" do
      create_conversions(600, channels: 5)

      result = service.call

      assert_equal 0, result[:markov_chain][:conversions_needed]
    end

    test "should include current channel count" do
      create_conversions(100, channels: 4)

      result = service.call

      assert_equal 4, result[:markov_chain][:current_channels]
    end

    test "should include required channel count" do
      result = service.call

      assert_equal 5, result[:markov_chain][:required_channels]
      assert_equal 5, result[:shapley_value][:required_channels]
    end

    test "should include channels needed" do
      create_conversions(100, channels: 3)

      result = service.call

      assert_equal 2, result[:markov_chain][:channels_needed]
    end

    test "should show zero channels needed when ready" do
      create_conversions(100, channels: 6)

      result = service.call

      assert_equal 0, result[:markov_chain][:channels_needed]
    end

    test "should include progress percentage" do
      create_conversions(250, channels: 5)

      result = service.call

      assert_equal 50, result[:markov_chain][:progress_percent]
    end

    test "should cap progress at 100" do
      create_conversions(1000, channels: 10)

      result = service.call

      assert_equal 100, result[:markov_chain][:progress_percent]
    end

    test "should count unique channels from sessions with conversions" do
      create_conversions_with_specific_channels(%w[organic_search paid_search email])

      result = service.call

      assert_equal 3, result[:markov_chain][:current_channels]
    end

    test "should handle account with no conversions" do
      result = service.call

      assert_not result[:markov_chain][:ready]
      assert_equal 0, result[:markov_chain][:current_conversions]
      assert_equal 0, result[:markov_chain][:current_channels]
      assert_equal 500, result[:markov_chain][:conversions_needed]
    end

    test "should include model display name" do
      result = service.call

      assert_equal "Markov Chain", result[:markov_chain][:name]
      assert_equal "Shapley Value", result[:shapley_value][:name]
    end

    test "should include model description" do
      result = service.call

      assert result[:markov_chain][:description].present?
      assert result[:shapley_value][:description].present?
    end

    private

    def service
      @service ||= DataReadinessChecker.new(account)
    end

    def account
      @account ||= accounts(:one)
    end

    def create_conversions(count, channels:)
      visitor = account.visitors.first || account.visitors.create!(visitor_id: SecureRandom.hex(16))
      channel_names = %w[organic_search paid_search email referral direct social display affiliate].first(channels)

      count.times do |i|
        session = account.sessions.create!(
          visitor: visitor,
          session_id: SecureRandom.hex(16),
          started_at: i.hours.ago,
          channel: channel_names[i % channel_names.size]
        )
        account.conversions.create!(
          visitor: visitor,
          session_id: session.id,
          conversion_type: "purchase",
          converted_at: i.hours.ago,
          journey_session_ids: [session.id]
        )
      end
    end

    def create_conversions_with_specific_channels(channels)
      visitor = account.visitors.first || account.visitors.create!(visitor_id: SecureRandom.hex(16))

      channels.each_with_index do |channel, i|
        session = account.sessions.create!(
          visitor: visitor,
          session_id: SecureRandom.hex(16),
          started_at: i.hours.ago,
          channel: channel
        )
        account.conversions.create!(
          visitor: visitor,
          session_id: session.id,
          conversion_type: "purchase",
          converted_at: i.hours.ago,
          journey_session_ids: [session.id]
        )
      end
    end
  end
end
