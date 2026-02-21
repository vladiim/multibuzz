# frozen_string_literal: true

class CreateRerunJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :rerun_jobs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :attribution_model, null: false, foreign_key: true
      t.integer :status, default: 0, null: false
      t.integer :total_conversions, null: false
      t.integer :processed_conversions, default: 0, null: false
      t.integer :from_version, null: false
      t.integer :to_version, null: false
      t.integer :overage_blocks, default: 0, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.timestamps

      t.index [ :account_id, :status ]
      t.index [ :attribution_model_id, :status ]
    end
  end
end
