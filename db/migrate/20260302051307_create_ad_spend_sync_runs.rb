# frozen_string_literal: true

class CreateAdSpendSyncRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :ad_spend_sync_runs do |t|
      t.references :ad_platform_connection, null: false, foreign_key: true
      t.date :sync_date, null: false
      t.integer :status, null: false, default: 0
      t.integer :records_synced, default: 0
      t.string :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps

      t.index [ :ad_platform_connection_id, :sync_date ], name: "idx_sync_runs_connection_date"
    end
  end
end
