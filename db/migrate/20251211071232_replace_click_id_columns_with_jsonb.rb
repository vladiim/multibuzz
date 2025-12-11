class ReplaceClickIdColumnsWithJsonb < ActiveRecord::Migration[8.0]
  def change
    # Remove individual click ID columns (added in 20251211035212 and 20251211064836)
    # These are being replaced with a single JSONB column for extensibility

    # From 20251211035212_add_click_ids_to_sessions
    remove_column :sessions, :gclid, :string, if_exists: true
    remove_column :sessions, :gbraid, :string, if_exists: true
    remove_column :sessions, :wbraid, :string, if_exists: true
    remove_column :sessions, :dclid, :string, if_exists: true
    remove_column :sessions, :msclkid, :string, if_exists: true
    remove_column :sessions, :fbclid, :string, if_exists: true
    remove_column :sessions, :ttclid, :string, if_exists: true
    remove_column :sessions, :li_fat_id, :string, if_exists: true
    remove_column :sessions, :twclid, :string, if_exists: true
    remove_column :sessions, :epik, :string, if_exists: true
    remove_column :sessions, :sclid, :string, if_exists: true

    # From 20251211064836_add_additional_click_ids_to_sessions
    remove_column :sessions, :gclsrc, :string, if_exists: true
    remove_column :sessions, :scclid, :string, if_exists: true
    remove_column :sessions, :rdt_cid, :string, if_exists: true
    remove_column :sessions, :qclid, :string, if_exists: true
    remove_column :sessions, :vmcid, :string, if_exists: true
    remove_column :sessions, :yclid, :string, if_exists: true
    remove_column :sessions, :sznclid, :string, if_exists: true

    # Add single JSONB column for all click identifiers
    # Structure: { "gclid" => "abc123", "fbclid" => "xyz789" }
    add_column :sessions, :click_ids, :jsonb, default: {}, null: false
    add_index :sessions, :click_ids, using: :gin
  end
end
