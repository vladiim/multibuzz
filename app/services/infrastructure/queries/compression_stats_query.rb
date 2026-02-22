# frozen_string_literal: true

module Infrastructure
  module Queries
    class CompressionStatsQuery
      HYPERTABLES = %w[events sessions].freeze

      def call
        HYPERTABLES.filter_map { |table| stats_for(table) }
      end

      private

      def stats_for(table)
        row = ActiveRecord::Base.connection.execute(<<-SQL.squish).first
          SELECT
            COALESCE(SUM(before_compression_total_bytes), 0) AS before_bytes,
            COALESCE(SUM(after_compression_total_bytes), 0) AS after_bytes
          FROM hypertable_compression_stats('#{table}')
          WHERE before_compression_total_bytes > 0
        SQL

        return nil if row["before_bytes"].to_i.zero?

        { before_bytes: row["before_bytes"].to_i, after_bytes: row["after_bytes"].to_i }
      rescue ActiveRecord::StatementInvalid
        nil
      end
    end
  end
end
