# frozen_string_literal: true

# One row per (conversion × destination) dispatch attempt. Tracks
# status, payload, platform response, retry count, and the attribution
# model + credit share that decided the dispatch.
#
# attribution_model_id is denormalised at write time so the dispatch row
# records what was used even if the destination's attribution_model
# changes later.
#
# Column choices documented in lib/specs/conversion_feedback_spec.md
# Phase 3.2.
class CreateConversionDispatches < ActiveRecord::Migration[8.0]
  def up
    create_table :conversion_dispatches do |t|
      t.references :conversion, null: false, foreign_key: true
      t.references :conversion_destination, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true   # denormalised for fast admin queries

      # See ConversionDispatch::Statuses constant for the canonical list.
      t.string :status, null: false, default: "pending"

      t.jsonb :payload, null: false, default: {}
      t.jsonb :response, default: {}
      t.text :error
      t.integer :retries_count, null: false, default: 0
      t.datetime :fired_at

      # Snapshot of the model that decided this dispatch
      t.references :attribution_model, foreign_key: true
      t.decimal :platform_credit_share, precision: 5, scale: 4

      t.timestamps
    end

    add_index :conversion_dispatches, [ :conversion_id, :conversion_destination_id ], unique: true,
      name: "idx_conversion_dispatches_unique_per_destination"
    add_index :conversion_dispatches, [ :account_id, :status, :created_at ],
      name: "idx_conversion_dispatches_admin_lookup"
  end

  def down
    drop_table :conversion_dispatches
  end
end
