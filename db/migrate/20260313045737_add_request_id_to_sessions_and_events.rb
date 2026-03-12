# frozen_string_literal: true

class AddRequestIdToSessionsAndEvents < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :sessions, :request_id, :string
    add_column :events, :request_id, :string

    # Non-unique index for lookup performance.
    # Unique constraint not used because sessions/events are TimescaleDB hypertables
    # (unique indexes must include the partition column, which defeats cross-time dedup).
    # Service-layer lookup prevents duplicates instead.
    add_index :sessions, [ :account_id, :request_id ],
      where: "request_id IS NOT NULL",
      name: "index_sessions_on_account_request_id",
      algorithm: :concurrently

    add_index :events, [ :account_id, :request_id ],
      where: "request_id IS NOT NULL",
      name: "index_events_on_account_request_id",
      algorithm: :concurrently
  end
end
