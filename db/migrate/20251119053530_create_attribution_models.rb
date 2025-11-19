# frozen_string_literal: true

class CreateAttributionModels < ActiveRecord::Migration[8.0]
  def change
    create_table :attribution_models do |t|
      t.references :account, null: false, foreign_key: true

      t.string :name, null: false
      t.integer :model_type, null: false, default: 0
      t.integer :algorithm
      t.text :dsl_code
      t.jsonb :compiled_rules, default: {}

      t.boolean :is_active, null: false, default: true
      t.boolean :is_default, null: false, default: false

      t.timestamps
    end

    add_index :attribution_models, [:account_id, :name], unique: true
    add_index :attribution_models, [:account_id, :is_active]
    add_index :attribution_models, [:account_id, :is_default]
  end
end
