# frozen_string_literal: true

# Ordered match rules for a by-campaign custom dimension. Each rule matches a
# campaign field with an operator and assigns an output value; first match (by
# position) wins. Operators reuse Dashboard::Scopes::Operators (MATCHABLE).
#
# Column choices documented in lib/specs/custom_dimensions_spec.md Phase 2.
class CreateDimensionRules < ActiveRecord::Migration[8.0]
  def up
    create_table :dimension_rules do |t|
      t.references :account, null: false, foreign_key: true             # denormalised for backfill scoping
      t.references :custom_dimension, null: false, foreign_key: true
      t.integer :position, null: false, default: 0                      # lower = evaluated first; first match wins
      t.string :match_field, null: false                                # campaign_name | campaign_id | campaign_type | network_type | device | channel
      t.string :operator, null: false                                   # Dashboard::Scopes::Operators::MATCHABLE
      t.string :value, null: false
      t.string :output_value, null: false

      t.timestamps
    end

    add_index :dimension_rules, [ :custom_dimension_id, :position ]
  end

  def down
    drop_table :dimension_rules
  end
end
