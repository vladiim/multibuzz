# frozen_string_literal: true

class AddMetadataToAdSpendRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :ad_spend_records, :metadata, :jsonb, null: false, default: {}
  end
end
