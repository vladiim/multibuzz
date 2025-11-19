# frozen_string_literal: true

class AddEventsCompression < ActiveRecord::Migration[8.0]
  def up
    # Enable compression on events hypertable
    # Segment by account_id and visitor_id for better compression
    # Order by occurred_at DESC for efficient time-range queries
    execute <<-SQL
      ALTER TABLE events SET (
        timescaledb.compress,
        timescaledb.compress_segmentby = 'account_id,visitor_id',
        timescaledb.compress_orderby = 'occurred_at DESC'
      );
    SQL

    # Add compression policy: compress chunks older than 7 days
    # NO retention policy - keep all data forever
    execute <<-SQL
      SELECT add_compression_policy('events', INTERVAL '7 days');
    SQL
  end

  def down
    # Remove compression policy
    execute <<-SQL
      SELECT remove_compression_policy('events');
    SQL
  end
end
