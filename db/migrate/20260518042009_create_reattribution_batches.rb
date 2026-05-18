# frozen_string_literal: true

class CreateReattributionBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :reattribution_batches do |t|
      t.references :account, null: false, foreign_key: true
      t.integer :trigger, null: false
      t.integer :status, default: 0, null: false
      t.integer :total, default: 0, null: false
      t.integer :processed, default: 0, null: false
      t.integer :failed, default: 0, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps

      t.index [ :account_id, :status ]
    end
  end
end
