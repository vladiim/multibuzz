# frozen_string_literal: true

class AddEventsCompression < ActiveRecord::Migration[8.0]
  def up
    return if Rails.env.test?

    execute <<-SQL
      ALTER TABLE events SET (
        timescaledb.compress,
        timescaledb.compress_segmentby = 'account_id,visitor_id',
        timescaledb.compress_orderby = 'occurred_at DESC'
      );
    SQL

    execute <<-SQL
      SELECT add_compression_policy('events', INTERVAL '7 days');
    SQL
  end

  def down
    return if Rails.env.test?

    execute <<-SQL
      SELECT remove_compression_policy('events');
    SQL
  end
end
