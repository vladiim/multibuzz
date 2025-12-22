# frozen_string_literal: true

class AddProbabilisticAttributionModelsToExistingAccounts < ActiveRecord::Migration[8.0]
  def up
    # Add Markov Chain and Shapley Value models to all existing accounts
    # that don't already have them. Uses SyncService which handles duplicates.
    AttributionAlgorithms::PROBABILISTIC.each do |algorithm|
      result = AttributionModels::SyncService.new(algorithm).call
      say "Synced #{algorithm}: #{result[:accounts_updated]} accounts updated"
    end

    # Ensure all probabilistic models are active (matches new account behavior)
    updated = AttributionModel
      .where(algorithm: AttributionAlgorithms::PROBABILISTIC)
      .where(model_type: :preset)
      .where(is_active: false)
      .update_all(is_active: true)
    say "Activated #{updated} probabilistic models"
  end

  def down
    # Remove the probabilistic models added by this migration
    AttributionModel
      .where(algorithm: AttributionAlgorithms::PROBABILISTIC)
      .where(model_type: :preset)
      .delete_all
  end
end
