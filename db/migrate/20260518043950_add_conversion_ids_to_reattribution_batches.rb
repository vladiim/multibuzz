# frozen_string_literal: true

class AddConversionIdsToReattributionBatches < ActiveRecord::Migration[8.0]
  def change
    add_column :reattribution_batches, :conversion_ids, :bigint, array: true, default: [], null: false
  end
end
