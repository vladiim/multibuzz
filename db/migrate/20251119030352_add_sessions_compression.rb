# frozen_string_literal: true

class AddSessionsCompression < ActiveRecord::Migration[8.0]
  def up
    return if Rails.env.test?

    execute <<-SQL
      ALTER TABLE sessions SET (
        timescaledb.compress,
        timescaledb.compress_segmentby = 'account_id,visitor_id',
        timescaledb.compress_orderby = 'started_at DESC'
      );
    SQL

    # Add compression policy: compress chunks older than 30 days
    # NO retention policy - keep all data forever
    execute <<-SQL
      SELECT add_compression_policy('sessions', INTERVAL '30 days');
    SQL
  end

  def down
    return if Rails.env.test?

    execute <<-SQL
      SELECT remove_compression_policy('sessions');
    SQL
  end
end
