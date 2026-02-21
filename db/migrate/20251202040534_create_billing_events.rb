# frozen_string_literal: true

class CreateBillingEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :billing_events do |t|
      t.references :account, null: true, foreign_key: true
      t.string :stripe_event_id, null: false
      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :processed_at

      t.timestamps
    end

    add_index :billing_events, :stripe_event_id, unique: true
    add_index :billing_events, :event_type
    add_index :billing_events, :processed_at
  end
end
