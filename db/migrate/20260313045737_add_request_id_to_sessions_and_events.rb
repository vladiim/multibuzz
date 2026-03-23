# frozen_string_literal: true

class AddRequestIdToSessionsAndEvents < ActiveRecord::Migration[8.0]
  def up
    add_column :sessions, :request_id, :string unless column_exists?(:sessions, :request_id)
    add_column :events, :request_id, :string unless column_exists?(:events, :request_id)

    # Non-unique index for lookup performance.
    # Unique constraint not used because sessions/events are TimescaleDB hypertables
    # (unique indexes must include the partition column, which defeats cross-time dedup).
    # Service-layer lookup prevents duplicates instead.
    # TimescaleDB hypertables don't support algorithm: :concurrently.
    safety_assured do
      add_index :sessions, [ :account_id, :request_id ],
        where: "request_id IS NOT NULL",
        name: "index_sessions_on_account_request_id" unless index_exists?(:sessions, [ :account_id, :request_id ], name: "index_sessions_on_account_request_id")

      add_index :events, [ :account_id, :request_id ],
        where: "request_id IS NOT NULL",
        name: "index_events_on_account_request_id" unless index_exists?(:events, [ :account_id, :request_id ], name: "index_events_on_account_request_id")
    end
  end

  def down
    remove_index :events, name: "index_events_on_account_request_id", if_exists: true
    remove_index :sessions, name: "index_sessions_on_account_request_id", if_exists: true
    remove_column :events, :request_id, if_exists: true
    remove_column :sessions, :request_id, if_exists: true
  end
end
