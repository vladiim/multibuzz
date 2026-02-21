# frozen_string_literal: true

class CreateDataIntegrityChecks < ActiveRecord::Migration[8.0]
  def change
    create_table :data_integrity_checks do |t|
      t.references :account, null: false, foreign_key: true
      t.string :check_name, null: false
      t.string :status, null: false
      t.float :value, null: false
      t.float :warning_threshold, null: false
      t.float :critical_threshold, null: false
      t.jsonb :details, default: {}
      t.timestamps
    end

    add_index :data_integrity_checks, [ :account_id, :check_name, :created_at ],
      name: "idx_integrity_checks_account_check_time"
  end
end
