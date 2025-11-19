# frozen_string_literal: true

class CreateAttributionCredits < ActiveRecord::Migration[8.0]
  def change
    create_table :attribution_credits do |t|
      t.references :account, null: false, foreign_key: true
      t.references :conversion, null: false, foreign_key: true
      t.references :attribution_model, null: false, foreign_key: true
      t.bigint :session_id, null: false  # No FK due to TimescaleDB composite PK

      t.string :channel, null: false
      t.decimal :credit, precision: 5, scale: 4, null: false
      t.decimal :revenue_credit, precision: 10, scale: 2

      # UTM data for drill-down (not primary attribution dimension)
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_campaign

      t.timestamps
    end

    add_index :attribution_credits, [:conversion_id, :attribution_model_id]
    add_index :attribution_credits, [:attribution_model_id, :channel]
    add_index :attribution_credits, [:account_id, :channel]
    add_index :attribution_credits, [:account_id, :attribution_model_id, :channel],
      name: "index_credits_on_account_model_channel"
  end
end
