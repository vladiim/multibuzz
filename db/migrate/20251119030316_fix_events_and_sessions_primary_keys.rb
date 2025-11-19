# frozen_string_literal: true

class FixEventsAndSessionsPrimaryKeys < ActiveRecord::Migration[8.0]
  def up
    # Remove foreign keys that depend on primary keys
    remove_foreign_key :events, :sessions

    # Remove existing primary key constraints
    execute "ALTER TABLE events DROP CONSTRAINT events_pkey;"
    execute "ALTER TABLE sessions DROP CONSTRAINT sessions_pkey;"

    # Add composite primary keys that include partitioning columns
    execute "ALTER TABLE events ADD PRIMARY KEY (id, occurred_at);"
    execute "ALTER TABLE sessions ADD PRIMARY KEY (id, started_at);"

    # Note: We don't add unique indexes on just id because:
    # 1. The composite primary key already ensures (id, occurred_at) is unique
    # 2. TimescaleDB doesn't allow unique indexes without the partitioning column
    # 3. We cannot restore the foreign key from events -> sessions because
    #    sessions.id is not uniquely constrained (only sessions(id, started_at) is)
    #
    # The events -> sessions relationship is still enforced at the application level
    # via ActiveRecord associations (belongs_to :session)
  end

  def down
    # Remove foreign keys
    remove_foreign_key :events, :sessions

    # Revert to simple primary keys
    execute "ALTER TABLE events DROP CONSTRAINT events_pkey;"
    execute "ALTER TABLE sessions DROP CONSTRAINT sessions_pkey;"

    execute "ALTER TABLE events ADD PRIMARY KEY (id);"
    execute "ALTER TABLE sessions ADD PRIMARY KEY (id);"

    # Restore foreign keys (explicitly reference id column)
    add_foreign_key :events, :sessions, column: :session_id, primary_key: :id
  end
end
