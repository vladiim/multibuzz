# frozen_string_literal: true

# Per-account, per-platform outbound destination config. One row per
# (account, platform, conversion-action-set). The dispatcher reads this
# table to decide where a conversion should be uploaded and under what
# attribution model.
#
# Column choices documented in lib/specs/conversion_feedback_spec.md
# Phase 3.1.
class CreateConversionDestinations < ActiveRecord::Migration[8.0]
  def up
    create_table :conversion_destinations do |t|
      t.references :account, null: false, foreign_key: true
      t.string :platform, null: false                          # "meta_capi" | "google_ec"
      t.string :name, null: false
      t.boolean :enabled, null: false, default: false

      # Attribution model gating
      t.references :attribution_model, null: false, foreign_key: true
      t.string :revenue_mode, null: false, default: "full"     # "full" | "scaled"
      t.decimal :minimum_credit_threshold, precision: 5, scale: 4, null: false, default: 0.0

      # Meta CAPI fields
      t.string :meta_pixel_id
      t.text :meta_access_token                                # encrypted via Rails 7+ encrypts

      # Google EC for Leads fields
      t.string :google_customer_id
      t.string :google_login_customer_id                       # manager link
      t.string :google_conversion_action_resource_name

      # Optional reference to the spend-pull OAuth connection (Google reuses it)
      t.references :ad_platform_connection, null: true, foreign_key: true

      # Mapping of mbuzz conversion_type → platform-specific event/action.
      # Shape: { "Lead" => { "meta_event" => "Lead", "google_resource_name" => "..." } }
      t.jsonb :event_type_mapping, null: false, default: {}

      t.timestamps
    end

    add_index :conversion_destinations, [ :account_id, :platform ]
    add_index :conversion_destinations, [ :account_id, :enabled ]
  end

  def down
    drop_table :conversion_destinations
  end
end
