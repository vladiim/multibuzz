# frozen_string_literal: true

# Account-scoped custom dimensions: user-defined attributes (location, brand,
# region, ...) attached to ad spend. Each dimension is mapped either "by account"
# (one value per connection, via connection.metadata) or "by campaign" (rules in
# dimension_rules). `channel` ships as a built-in dimension.
#
# Column choices documented in lib/specs/custom_dimensions_spec.md Phase 2.
class CreateCustomDimensions < ActiveRecord::Migration[8.0]
  def up
    create_table :custom_dimensions do |t|
      t.references :account, null: false, foreign_key: true
      t.string :key, null: false                                # metadata key, normalised lowercase
      t.string :name, null: false
      t.string :default_value, null: false, default: "Other"    # fallback when no rule matches
      t.string :mapping_mode, null: false, default: "campaign"  # "account" | "campaign"
      t.integer :platform                                       # nil = all platforms; mirrors AdPlatformConnection.platform
      t.integer :position, null: false, default: 0
      t.boolean :is_active, null: false, default: true
      t.string :built_in                                        # "channel" for the built-in; nil = user-defined

      t.timestamps
    end

    add_index :custom_dimensions, [ :account_id, :key ], unique: true
    add_index :custom_dimensions, [ :account_id, :is_active ]
  end

  def down
    drop_table :custom_dimensions
  end
end
