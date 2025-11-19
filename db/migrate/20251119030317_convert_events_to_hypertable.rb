# frozen_string_literal: true

class ConvertEventsToHypertable < ActiveRecord::Migration[8.0]
  def up
    # Convert events table to hypertable partitioned by occurred_at
    # chunk_time_interval: 1 week (604800000000 microseconds)
    # migrate_data: true to convert existing data
    execute <<-SQL
      SELECT create_hypertable(
        'events',
        'occurred_at',
        chunk_time_interval => INTERVAL '1 week',
        if_not_exists => TRUE,
        migrate_data => TRUE
      );
    SQL
  end

  def down
    # Reverting a hypertable to a regular table is complex and not commonly needed
    # Document manual process if required
    raise ActiveRecord::IrreversibleMigration, "Cannot automatically revert hypertable to regular table"
  end
end
