# frozen_string_literal: true

class CreateGuidedSetups < ActiveRecord::Migration[8.0]
  def change
    create_table :guided_setups do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.integer :status, null: false, default: 0
      t.string :integration_target, null: false, default: "none"
      t.string :specialist_name
      t.text :scheduling_note
      t.text :notes
      t.datetime :accepted_at
      t.datetime :kickoff_call_at
      t.datetime :install_completed_at
      t.datetime :integration_connected_at
      t.datetime :training_call_at
      t.datetime :value_check_at
      t.datetime :completed_at
      t.timestamps

      t.index [ :status, :updated_at ]
    end
  end
end
