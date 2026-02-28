# frozen_string_literal: true

class CreateAdPlatformConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :ad_platform_connections do |t|
      t.references :account, null: false, foreign_key: true
      t.integer :platform, null: false
      t.string :platform_account_id, null: false
      t.string :platform_account_name
      t.string :currency, limit: 3, null: false
      t.text :access_token
      t.text :refresh_token
      t.datetime :token_expires_at
      t.integer :status, null: false, default: 0
      t.datetime :last_synced_at
      t.string :last_sync_error
      t.jsonb :settings, default: {}
      t.timestamps

      t.index [ :account_id, :platform, :platform_account_id ], unique: true,
        name: "idx_ad_connections_unique"
    end
  end
end
