# frozen_string_literal: true

require "test_helper"

module Attribution
  class CrossDeviceCalculatorTest < ActiveSupport::TestCase
    setup do
      account.conversions.destroy_all
      visitor.update!(identity: identity)
    end

    test "should calculate credits for non-probabilistic model" do
      create_sessions!

      credits = build_calculator(model: linear_model).call

      assert_equal 2, credits.size
      assert_in_delta 1.0, credits.sum { |c| c[:credit] }, 0.0001
    end

    test "should calculate credits for markov chain model" do
      create_historical_conversion(%w[organic_search paid_search])
      create_historical_conversion(%w[email paid_search])
      create_sessions!

      credits = build_calculator(model: markov_chain_model).call

      assert_equal 2, credits.size
      assert_in_delta 1.0, credits.sum { |c| c[:credit] }, 0.0001
    end

    test "should calculate credits for shapley value model" do
      create_historical_conversion(%w[organic_search paid_search])
      create_historical_conversion(%w[email paid_search])
      create_sessions!

      credits = build_calculator(model: shapley_value_model).call

      assert_equal 2, credits.size
      assert_in_delta 1.0, credits.sum { |c| c[:credit] }, 0.0001
    end

    test "should enrich markov credits with UTM data" do
      create_historical_conversion(%w[organic_search email])
      create_sessions!

      credits = build_calculator(model: markov_chain_model).call

      assert_equal "google", credits[0][:utm_source]
      assert_equal "newsletter", credits[1][:utm_source]
    end

    test "should return empty array when visitor has no sessions" do
      credits = build_calculator(model: markov_chain_model).call

      assert_empty credits
    end

    test "should use precomputed conversion_paths when provided" do
      create_historical_conversion(%w[organic_search paid_search])
      create_sessions!

      precomputed = Attribution::Markov::ConversionPathsQuery.new(account).call

      calculator = CrossDeviceCalculator.new(
        conversion: conversion,
        identity: identity,
        attribution_model: markov_chain_model,
        conversion_paths: precomputed
      )

      credits = calculator.call

      assert_equal 2, credits.size
      assert_in_delta 1.0, credits.sum { |c| c[:credit] }, 0.0001
    end

    private

    def build_calculator(model:)
      CrossDeviceCalculator.new(
        conversion: conversion,
        identity: identity,
        attribution_model: model
      )
    end

    def create_sessions!
      @session_one = Session.create!(
        account: account,
        visitor: visitor,
        session_id: SecureRandom.hex(16),
        started_at: 10.days.ago,
        channel: "organic_search",
        initial_utm: { "utm_source" => "google", "utm_medium" => "organic" }
      )

      @session_two = Session.create!(
        account: account,
        visitor: visitor,
        session_id: SecureRandom.hex(16),
        started_at: 3.days.ago,
        channel: "email",
        initial_utm: { "utm_source" => "newsletter", "utm_medium" => "email" }
      )
    end

    def create_historical_conversion(channels)
      hist_visitor = Visitor.create!(account: account, visitor_id: SecureRandom.hex(16))
      sessions = channels.each_with_index.map do |channel, index|
        Session.create!(
          account: account,
          visitor: hist_visitor,
          session_id: SecureRandom.hex(16),
          started_at: (channels.size - index).days.ago,
          channel: channel
        )
      end

      Conversion.create!(
        account: account,
        visitor: hist_visitor,
        session_id: sessions.last.id,
        event_id: 1,
        conversion_type: "purchase",
        converted_at: 1.day.ago,
        journey_session_ids: sessions.map(&:id)
      )
    end

    def account
      @account ||= accounts(:one)
    end

    def visitor
      @visitor ||= visitors(:two)
    end

    def identity
      @identity ||= identities(:one)
    end

    def conversion
      @conversion ||= Conversion.create!(
        account: account,
        visitor: visitor,
        session_id: 1,
        event_id: 1,
        conversion_type: "purchase",
        converted_at: Time.current,
        journey_session_ids: []
      )
    end

    def linear_model
      @linear_model ||= attribution_models(:linear)
    end

    def markov_chain_model
      @markov_chain_model ||= AttributionModel.create!(
        account: account,
        name: "Test Markov",
        model_type: :preset,
        algorithm: :markov_chain,
        lookback_days: 30,
        is_active: true
      )
    end

    def shapley_value_model
      @shapley_value_model ||= AttributionModel.create!(
        account: account,
        name: "Test Shapley",
        model_type: :preset,
        algorithm: :shapley_value,
        lookback_days: 30,
        is_active: true
      )
    end
  end
end
