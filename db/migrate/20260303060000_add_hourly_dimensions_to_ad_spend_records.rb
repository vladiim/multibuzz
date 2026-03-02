# frozen_string_literal: true

class AddHourlyDimensionsToAdSpendRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :ad_spend_records, :spend_hour, :integer, null: false, default: 0
    add_column :ad_spend_records, :device, :string

    safety_assured do
      remove_index :ad_spend_records, name: "idx_spend_unique"

      add_index :ad_spend_records,
        [ :account_id, :ad_platform_connection_id, :spend_date, :spend_hour,
          :platform_campaign_id, :device, :network_type ],
        unique: true, name: "idx_spend_unique"
    end
  end
end
