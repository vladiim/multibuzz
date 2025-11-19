# frozen_string_literal: true

class FixSessionsUniqueIndex < ActiveRecord::Migration[8.0]
  def up
    # Remove the unique index that doesn't include partitioning column
    remove_index :sessions, name: "index_sessions_on_account_id_and_session_id"

    # Add new unique index that includes started_at (partitioning column)
    add_index :sessions,
      [:account_id, :session_id, :started_at],
      unique: true,
      name: "index_sessions_on_account_id_and_session_id"
  end

  def down
    # Revert to original index without partitioning column
    remove_index :sessions, name: "index_sessions_on_account_id_and_session_id"

    add_index :sessions,
      [:account_id, :session_id],
      unique: true,
      name: "index_sessions_on_account_id_and_session_id"
  end
end
