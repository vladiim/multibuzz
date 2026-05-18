# frozen_string_literal: true

# Adds the columns the conversion-feedback dispatcher needs to assemble
# Meta CAPI and Google EC for Leads payloads:
#
# - fbp:         _fbp browser cookie value (Meta only). NOT hashed.
# - fbc:         _fbc cookie value, derived from fbclid per Meta's
#                fb.1.{ts_ms}.{fbclid} formula when the cookie is absent.
#                NOT hashed.
# - country:     ISO-2 country code, lowercase. Source: customer-supplied
#                via session create payload (or downstream from CDN headers
#                when wired). NOT hashed at persistence; the dispatcher
#                hashes for Meta and sends raw for Google.
# - postal_code: customer-supplied. Same hashing-at-dispatch story.
# - gclid:       denormalised top-level column from click_ids JSONB so the
#                dispatcher can index-scan rather than JSONB-traverse on
#                every conversion. click_ids JSONB stays the source of
#                truth for all the other click identifiers.
#
# All columns are nullable. SDKs ship Phase 2A separately; until they do,
# columns stay nil and the dispatcher gracefully degrades match keys.
class AddMatchKeysToSessions < ActiveRecord::Migration[8.0]
  def up
    add_column :sessions, :fbp, :string unless column_exists?(:sessions, :fbp)
    add_column :sessions, :fbc, :string unless column_exists?(:sessions, :fbc)
    add_column :sessions, :country, :string, limit: 2 unless column_exists?(:sessions, :country)
    add_column :sessions, :postal_code, :string, limit: 16 unless column_exists?(:sessions, :postal_code)
    add_column :sessions, :gclid, :string unless column_exists?(:sessions, :gclid)

    # TimescaleDB hypertables don't support algorithm: :concurrently.
    safety_assured do
      add_index :sessions, [ :account_id, :gclid ],
        where: "gclid IS NOT NULL",
        name: "index_sessions_on_account_gclid" unless index_exists?(:sessions, [ :account_id, :gclid ], name: "index_sessions_on_account_gclid")

      add_index :sessions, [ :account_id, :fbp ],
        where: "fbp IS NOT NULL",
        name: "index_sessions_on_account_fbp" unless index_exists?(:sessions, [ :account_id, :fbp ], name: "index_sessions_on_account_fbp")
    end
  end

  def down
    remove_index :sessions, name: "index_sessions_on_account_fbp", if_exists: true
    remove_index :sessions, name: "index_sessions_on_account_gclid", if_exists: true
    remove_column :sessions, :gclid, if_exists: true
    remove_column :sessions, :postal_code, if_exists: true
    remove_column :sessions, :country, if_exists: true
    remove_column :sessions, :fbc, if_exists: true
    remove_column :sessions, :fbp, if_exists: true
  end
end
