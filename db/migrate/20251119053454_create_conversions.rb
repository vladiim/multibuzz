# frozen_string_literal: true

class CreateConversions < ActiveRecord::Migration[8.0]
  def change
    create_table :conversions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :visitor, null: false, foreign_key: true
      t.bigint :session_id, null: false  # No FK due to TimescaleDB composite PK
      t.bigint :event_id, null: false  # No FK due to TimescaleDB composite PK

      t.string :conversion_type, null: false
      t.decimal :revenue, precision: 10, scale: 2
      t.datetime :converted_at, null: false

      # Array of session IDs that make up the attribution journey
      t.bigint :journey_session_ids, array: true, default: []

      t.timestamps
    end

    add_index :conversions, :conversion_type
    add_index :conversions, :converted_at
    add_index :conversions, [:account_id, :converted_at]
    add_index :conversions, [:visitor_id, :converted_at]
  end
end
