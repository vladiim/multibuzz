# frozen_string_literal: true

require "test_helper"

module AttributionModels
  class SyncServiceTest < ActiveSupport::TestCase
    setup do
      # Clear all attribution models to start fresh
      AttributionModel.destroy_all
    end

    test "adds preset model to accounts that don't have it" do
      result = SyncService.new(:markov_chain).call

      assert result[:success]
      assert account_one.attribution_models.exists?(algorithm: :markov_chain)
      assert account_two.attribution_models.exists?(algorithm: :markov_chain)
    end

    test "skips accounts that already have the model" do
      account_one.attribution_models.create!(
        name: "Markov Chain",
        algorithm: :markov_chain,
        model_type: :preset,
        is_active: true
      )

      result = SyncService.new(:markov_chain).call

      assert result[:success]
      assert_equal 1, account_one.attribution_models.where(algorithm: :markov_chain).count
    end

    test "sets is_active to true for newly added models" do
      result = SyncService.new(:markov_chain).call

      assert result[:success]
      model = account_one.attribution_models.find_by(algorithm: :markov_chain)
      assert model.is_active
    end

    test "sets model_type to preset" do
      SyncService.new(:markov_chain).call

      model = account_one.attribution_models.find_by(algorithm: :markov_chain)
      assert model.preset?
    end

    test "uses humanized algorithm name" do
      SyncService.new(:markov_chain).call

      model = account_one.attribution_models.find_by(algorithm: :markov_chain)
      assert_equal "Markov Chain", model.name
    end

    test "returns count of accounts updated" do
      result = SyncService.new(:markov_chain).call

      assert result[:success]
      assert_equal Account.count, result[:accounts_updated]
    end

    test "returns zero when all accounts already have the model" do
      Account.find_each do |account|
        account.attribution_models.create!(
          name: "Markov Chain",
          algorithm: :markov_chain,
          model_type: :preset,
          is_active: true
        )
      end

      result = SyncService.new(:markov_chain).call

      assert result[:success]
      assert_equal 0, result[:accounts_updated]
    end

    test "handles string algorithm name" do
      result = SyncService.new("shapley_value").call

      assert result[:success]
      assert account_one.attribution_models.exists?(algorithm: :shapley_value)
    end

    test "returns error for invalid algorithm" do
      result = SyncService.new(:invalid_algorithm).call

      assert_not result[:success]
      assert_includes result[:errors].first, "Invalid algorithm"
    end

    test "sync_all_presets adds all missing preset models to all accounts" do
      # Create one model so we can verify it doesn't duplicate
      account_one.attribution_models.create!(
        name: "First Touch",
        algorithm: :first_touch,
        model_type: :preset,
        is_active: true
      )

      result = SyncService.sync_all_presets

      assert result[:success]

      # Verify account_one has all presets (first_touch existed, others added)
      AttributionAlgorithms::DEFAULTS.each do |algo|
        assert account_one.attribution_models.exists?(algorithm: algo),
          "Account one should have #{algo}"
      end

      # Verify account_two has all presets
      AttributionAlgorithms::DEFAULTS.each do |algo|
        assert account_two.attribution_models.exists?(algorithm: algo),
          "Account two should have #{algo}"
      end
    end

    test "sync_all_presets returns summary of all syncs" do
      result = SyncService.sync_all_presets

      assert result[:success]
      assert result[:results].is_a?(Hash)
      assert_equal AttributionAlgorithms::DEFAULTS.size, result[:results].keys.size
    end

    private

    def account_one
      @account_one ||= accounts(:one)
    end

    def account_two
      @account_two ||= accounts(:two)
    end
  end
end
