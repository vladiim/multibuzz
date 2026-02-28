# frozen_string_literal: true

class CreateAdSpendRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :ad_spend_records do |t|
      t.references :account, null: false, foreign_key: true
      t.references :ad_platform_connection, null: false, foreign_key: true
      t.date :spend_date, null: false
      t.string :channel, null: false
      t.string :platform_campaign_id, null: false
      t.string :campaign_name, null: false
      t.string :campaign_type
      t.string :network_type
      t.bigint :spend_micros, null: false, default: 0
      t.string :currency, limit: 3, null: false
      t.bigint :impressions, null: false, default: 0
      t.bigint :clicks, null: false, default: 0
      t.bigint :platform_conversions_micros, null: false, default: 0
      t.bigint :platform_conversion_value_micros, null: false, default: 0
      t.boolean :is_test, default: false, null: false
      t.timestamps

      t.index [ :account_id, :spend_date, :channel ], name: "idx_spend_channel_date"
      t.index [ :account_id, :ad_platform_connection_id, :spend_date, :platform_campaign_id ],
        unique: true, name: "idx_spend_unique"
      t.index [ :account_id, :channel, :spend_date ], name: "idx_spend_date_range"
      t.index [ :is_test ], name: "idx_spend_is_test"
    end
  end
end
