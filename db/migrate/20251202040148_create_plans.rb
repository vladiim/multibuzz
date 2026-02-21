# frozen_string_literal: true

class CreatePlans < ActiveRecord::Migration[8.0]
  def change
    create_table :plans do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :monthly_price_cents, null: false, default: 0
      t.integer :events_included, null: false
      t.integer :overage_price_cents  # per 10K events, null for free (hard cap)
      t.string :stripe_product_id
      t.string :stripe_price_id       # base subscription price
      t.string :stripe_meter_id       # for usage-based pricing
      t.boolean :is_active, null: false, default: true
      t.integer :sort_order, null: false, default: 0

      t.timestamps
    end

    add_index :plans, :slug, unique: true
    add_index :plans, :is_active
    add_index :plans, :sort_order
  end
end
