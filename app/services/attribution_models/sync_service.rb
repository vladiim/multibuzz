# frozen_string_literal: true

module AttributionModels
  class SyncService
    VALID_ALGORITHMS = AttributionModel.algorithms.keys.freeze

    def initialize(algorithm)
      @algorithm = algorithm.to_s
    end

    def call
      return invalid_algorithm_error unless valid_algorithm?

      { success: true, accounts_updated: sync_to_all_accounts }
    end

    def self.sync_all_presets
      results = AttributionAlgorithms::DEFAULTS.each_with_object({}) do |algorithm, hash|
        hash[algorithm] = new(algorithm).call
      end

      { success: true, results: results }
    end

    private

    attr_reader :algorithm

    def valid_algorithm?
      VALID_ALGORITHMS.include?(algorithm)
    end

    def invalid_algorithm_error
      { success: false, errors: ["Invalid algorithm: #{algorithm}"] }
    end

    def sync_to_all_accounts
      accounts_needing_sync.reduce(0) do |count, account|
        create_preset_for(account)
        count + 1
      end
    end

    def accounts_needing_sync
      Account.where.not(id: accounts_with_algorithm)
    end

    def accounts_with_algorithm
      AttributionModel.where(algorithm: algorithm).select(:account_id)
    end

    def create_preset_for(account)
      account.attribution_models.create!(
        name: algorithm.titleize,
        algorithm: algorithm,
        model_type: :preset,
        is_active: false
      )
    end
  end
end
