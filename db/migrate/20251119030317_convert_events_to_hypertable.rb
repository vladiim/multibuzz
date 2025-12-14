# frozen_string_literal: true

class ConvertEventsToHypertable < ActiveRecord::Migration[8.0]
  def up
    # Skip hypertable creation in test environment - hypertables don't support
    # disabling triggers which Rails needs for fixture loading
    return if Rails.env.test?

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
    return if Rails.env.test?
    raise ActiveRecord::IrreversibleMigration, "Cannot automatically revert hypertable to regular table"
  end
end
