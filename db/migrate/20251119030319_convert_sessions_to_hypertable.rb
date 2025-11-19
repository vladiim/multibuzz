# frozen_string_literal: true

class ConvertSessionsToHypertable < ActiveRecord::Migration[8.0]
  def up
    # Convert sessions table to hypertable partitioned by started_at
    # chunk_time_interval: 1 week
    execute <<-SQL
      SELECT create_hypertable(
        'sessions',
        'started_at',
        chunk_time_interval => INTERVAL '1 week',
        if_not_exists => TRUE,
        migrate_data => TRUE
      );
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot automatically revert hypertable to regular table"
  end
end
