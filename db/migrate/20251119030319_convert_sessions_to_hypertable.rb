# frozen_string_literal: true

class ConvertSessionsToHypertable < ActiveRecord::Migration[8.0]
  def up
    return if Rails.env.test?

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
    return if Rails.env.test?
    raise ActiveRecord::IrreversibleMigration, "Cannot automatically revert hypertable to regular table"
  end
end
